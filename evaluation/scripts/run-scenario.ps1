<#
.SYNOPSIS
    Runs a single evaluation scenario against Copilot CLI.

.DESCRIPTION
    Copies the scenario's 'scenario/' subfolder to a clean temp directory,
    executes Copilot CLI in programmatic mode there, captures output and stats,
    saves results to the results directory, and cleans up the temp copy.

.PARAMETER ScenarioName
    Name of the scenario folder under evaluation/scenarios/.
    Each scenario folder must contain a 'scenario/' subfolder with the test content
    and optionally an 'expected-output.md' for evaluation.

.PARAMETER RunType
    Either "vanilla" (no plugins) or "skilled" (with msbuild-skills plugin).

.PARAMETER ResultsDir
    Path to the results directory for this run.

.PARAMETER TimeoutSeconds
    Maximum time to wait for Copilot CLI to complete (default: 300).

.PARAMETER RepoRoot
    Root directory of the repository. Defaults to two levels up from this script.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ScenarioName,

    [Parameter(Mandatory)]
    [ValidateSet("vanilla", "skilled")]
    [string]$RunType,

    [Parameter(Mandatory)]
    [string]$ResultsDir,

    [int]$TimeoutSeconds = 300,

    [string]$RepoRoot
)

$ErrorActionPreference = "Stop"

# Resolve repo root
if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\")).Path
}

# Import helper functions
. (Join-Path $PSScriptRoot "parse-copilot-stats.ps1")

#region Helper Functions

function Assert-PluginState {
    param(
        [string]$PluginName,
        [bool]$ShouldBeInstalled
    )

    $output = & copilot plugin list 2>&1 | Out-String
    $isInstalled = $output -match $PluginName

    if ($ShouldBeInstalled -and -not $isInstalled) {
        throw "[FAIL] VALIDATION FAILED: Plugin '$PluginName' should be installed but is NOT. Output: $output"
    }
    if (-not $ShouldBeInstalled -and $isInstalled) {
        throw "[FAIL] VALIDATION FAILED: Plugin '$PluginName' should NOT be installed but IS. Output: $output"
    }

    Write-Host "[OK] Plugin state validated: '$PluginName' installed=$isInstalled (expected=$ShouldBeInstalled)"
}

function Copy-ScenarioToTemp {
    param(
        [string]$ScenarioSourceDir,
        [string]$ScenarioName,
        [string]$RunType
    )

    $tempBase = Join-Path ([System.IO.Path]::GetTempPath()) "copilot-eval"
    $tempDir = Join-Path $tempBase "${ScenarioName}-${RunType}-$(Get-Random)"

    Write-Host "[COPY] Copying scenario to temp directory: $tempDir"
    New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
    Copy-Item -Path "$ScenarioSourceDir\*" -Destination $tempDir -Recurse -Force
    Write-Host "[OK] Scenario copied to clean working directory"

    return $tempDir
}

function Invoke-CopilotWithTimeout {
    param(
        [string]$Prompt,
        [string]$WorkingDir,
        [string]$OutputFile,
        [int]$TimeoutSeconds = 300
    )

    Write-Host "[RUN] Running Copilot CLI..."
    Write-Host "   Working directory: $WorkingDir"
    Write-Host "   Timeout: ${TimeoutSeconds}s"
    Write-Host "   Prompt: $Prompt"

    $errorFile = "${OutputFile}.err"

    # Resolve copilot executable - prefer .cmd/.bat/.exe for Process.Start compatibility
    # Use -All to search across all PATH entries, not just the first match
    $copilotCmd = Get-Command copilot -All -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandType -eq 'Application' } |
        Select-Object -First 1 -ExpandProperty Source
    if (-not $copilotCmd) {
        if ($env:OS -match 'Windows') {
            # Windows: use cmd.exe to run copilot (works with .cmd/.bat shims via PATH)
            $copilotCmd = "cmd.exe"
            $copilotArgs = "/c copilot -p `"$Prompt`" --model claude-opus-4.5 --allow-all-tools --allow-all-paths --no-ask-user"
        } else {
            # Linux/macOS: use /usr/bin/env to find copilot
            $copilotCmd = "/usr/bin/env"
            $copilotArgs = "copilot -p `"$Prompt`" --model claude-opus-4.5 --allow-all-tools --allow-all-paths --no-ask-user"
        }
    } else {
        $copilotArgs = "-p `"$Prompt`" --model claude-opus-4.5 --allow-all-tools --allow-all-paths --no-ask-user"
    }

    Write-Host "   Copilot executable: $copilotCmd"

    $processInfo = New-Object System.Diagnostics.ProcessStartInfo
    $processInfo.FileName = $copilotCmd
    $processInfo.Arguments = $copilotArgs
    $processInfo.WorkingDirectory = $WorkingDir
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $processInfo

    # Capture output asynchronously to avoid deadlocks
    $stdoutBuilder = New-Object System.Text.StringBuilder
    $stderrBuilder = New-Object System.Text.StringBuilder

    $stdoutEvent = Register-ObjectEvent -InputObject $process -EventName OutputDataReceived -Action {
        if ($null -ne $EventArgs.Data) {
            $Event.MessageData.AppendLine($EventArgs.Data) | Out-Null
        }
    } -MessageData $stdoutBuilder

    $stderrEvent = Register-ObjectEvent -InputObject $process -EventName ErrorDataReceived -Action {
        if ($null -ne $EventArgs.Data) {
            $Event.MessageData.AppendLine($EventArgs.Data) | Out-Null
        }
    } -MessageData $stderrBuilder

    $startTime = Get-Date
    $process.Start() | Out-Null
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()

    $completed = $process.WaitForExit($TimeoutSeconds * 1000)
    $elapsed = (Get-Date) - $startTime

    # Unregister events
    Unregister-Event -SourceIdentifier $stdoutEvent.Name -ErrorAction SilentlyContinue
    Unregister-Event -SourceIdentifier $stderrEvent.Name -ErrorAction SilentlyContinue

    # Small delay to ensure async output is flushed
    Start-Sleep -Milliseconds 500

    $stdout = $stdoutBuilder.ToString()
    $stderr = $stderrBuilder.ToString()

    # Save outputs
    $stdout | Out-File -FilePath $OutputFile -Encoding utf8
    if ($stderr) {
        $stderr | Out-File -FilePath $errorFile -Encoding utf8
    }

    if (-not $completed) {
        $process.Kill()
        throw "[TIMEOUT] Copilot timed out after $TimeoutSeconds seconds"
    }

    $exitCode = $process.ExitCode
    Write-Host "   Exit code: $exitCode"
    Write-Host "   Elapsed: $([math]::Round($elapsed.TotalSeconds, 1))s"

    if ($exitCode -ne 0) {
        Write-Warning "Copilot CLI exited with code $exitCode"
        Write-Warning "Stderr: $stderr"
        # Don't throw - we still want to capture and evaluate partial output
    }

    # Return combined output (stats are written to stderr by Copilot CLI)
    return ($stdout + "`n" + $stderr)
}

#endregion

#region Main Logic

Write-Host ""
Write-Host ("=" * 60)
Write-Host "[SCENARIO] Running: $ScenarioName ($RunType)"
Write-Host ("=" * 60)

$scenarioBaseDir = Join-Path $RepoRoot "evaluation\scenarios\$ScenarioName"
$scenarioSourceDir = Join-Path $scenarioBaseDir "scenario"
$scenarioResultsDir = Join-Path $ResultsDir $ScenarioName

if (-not (Test-Path $scenarioSourceDir)) {
    throw "Scenario source directory not found: $scenarioSourceDir"
}

# Create results directory
New-Item -ItemType Directory -Force -Path $scenarioResultsDir | Out-Null

# Step 1: Copy scenario to a clean temp directory
$workingDir = Copy-ScenarioToTemp -ScenarioSourceDir $scenarioSourceDir -ScenarioName $ScenarioName -RunType $RunType

# Step 2: Configure plugin state
$pluginName = "msbuild-skills"
$pluginPath = Join-Path $RepoRoot "msbuild-skills"

if ($RunType -eq "vanilla") {
    Write-Host ""
    Write-Host "[PLUGIN] Uninstalling plugin for vanilla run..."
    $prevPref = $ErrorActionPreference
    $ErrorActionPreference = "SilentlyContinue"
    & copilot plugin uninstall $pluginName 2>&1 | Out-Null
    $ErrorActionPreference = $prevPref
    # Swallow error if not installed - that's the desired state
    Assert-PluginState -PluginName $pluginName -ShouldBeInstalled $false
} elseif ($RunType -eq "skilled") {
    Write-Host ""
    Write-Host "[PLUGIN] Installing plugin for skilled run..."
    & copilot plugin install $pluginPath 2>&1 | Write-Host
    Assert-PluginState -PluginName $pluginName -ShouldBeInstalled $true
}

# Step 3: Build the prompt
$promptFile = Join-Path $workingDir "prompt.txt"
if (Test-Path $promptFile) {
    $prompt = (Get-Content $promptFile -Raw).Trim()
    Write-Host "[PROMPT] Loaded from: $promptFile"
} else {
    $prompt = "Analyze the build issues in this scenario and provide required fixes and their explanations. The fixes should not alter logic of the code (e.g. by suggesting to delete code files)."
    Write-Host "[PROMPT] Using default prompt (no prompt.txt found)"
}

# Step 4: Run Copilot CLI
$outputFile = Join-Path $scenarioResultsDir "${RunType}-output.txt"

$output = Invoke-CopilotWithTimeout `
    -Prompt $prompt `
    -WorkingDir $workingDir `
    -OutputFile $outputFile `
    -TimeoutSeconds $TimeoutSeconds

# Step 5: Parse stats
Write-Host ""
Write-Host "[STATS] Parsing stats..."
$stats = Parse-CopilotStats -Output $output

# Add metadata
$stats.RunType = $RunType
$stats.ScenarioName = $ScenarioName
$stats.Timestamp = (Get-Date -Format "o")

$statsFile = Join-Path $scenarioResultsDir "${RunType}-stats.json"
$stats | ConvertTo-Json -Depth 5 | Out-File -FilePath $statsFile -Encoding utf8

Write-Host "   Premium Requests: $($stats.PremiumRequests)"
Write-Host "   API Time: $($stats.ApiTimeSeconds)s"
Write-Host "   Total Time: $($stats.TotalTimeSeconds)s"
Write-Host "   Model: $($stats.Model)"
Write-Host "   Tokens In: $($stats.TokensIn)"
Write-Host "   Tokens Out: $($stats.TokensOut)"

# Step 6: Clean up temp directory
Write-Host ""
Write-Host "[CLEAN] Removing temp working directory: $workingDir"
Remove-Item -Path $workingDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "[OK] Scenario $ScenarioName ($RunType) completed"
Write-Host "   Output: $outputFile"
Write-Host "   Stats: $statsFile"

#endregion
