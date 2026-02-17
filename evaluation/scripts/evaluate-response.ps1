<#
.SYNOPSIS
    Evaluates a Copilot CLI response against expected output using Copilot as evaluator.

.DESCRIPTION
    Takes the actual Copilot output and compares it against the expected output file
    using a separate Copilot CLI invocation (vanilla, no plugins) as the evaluator.
    Files are written to a temp directory so Copilot can read them with file tools.

.PARAMETER ScenarioName
    Name of the scenario to evaluate.

.PARAMETER ResultsDir
    Path to the results directory for this run.

.PARAMETER TimeoutSeconds
    Maximum time to wait for evaluation Copilot CLI to complete.

.PARAMETER RepoRoot
    Root directory of the repository.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ScenarioName,

    [Parameter(Mandatory)]
    [string]$ResultsDir,

[int]$TimeoutSeconds = 300,

    [string]$RepoRoot
)

$ErrorActionPreference = "Stop"

if (-not $RepoRoot) {
    $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..\")).Path
}

#region Helper Functions

function Invoke-EvaluationCopilot {
    param(
        [string]$Prompt,
        [string]$WorkingDir,
        [int]$TimeoutSeconds = 300
    )

# Resolve copilot executable - prefer .cmd/.bat/.exe for Process.Start compatibility
    # Use -All to search across all PATH entries, not just the first match
    $copilotCmd = Get-Command copilot -All -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandType -eq 'Application' } |
        Select-Object -First 1 -ExpandProperty Source
    if (-not $copilotCmd) {
        if ($env:OS -match 'Windows') {
            $copilotCmd = "cmd.exe"
            $copilotArgs = "/c copilot -p `"$Prompt`" --model claude-opus-4.5 --no-ask-user --allow-all-tools --allow-all-paths"
        } else {
            $copilotCmd = "/usr/bin/env"
            $copilotArgs = "copilot -p `"$Prompt`" --model claude-opus-4.5 --no-ask-user --allow-all-tools --allow-all-paths"
        }
    } else {
        $copilotArgs = "-p `"$Prompt`" --model claude-opus-4.5 --no-ask-user --allow-all-tools --allow-all-paths"
    }

    Write-Host "   Copilot executable: $copilotCmd"
    Write-Host "   Working dir: $WorkingDir"

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

    $process.Start() | Out-Null
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()

    $completed = $process.WaitForExit($TimeoutSeconds * 1000)

    Unregister-Event -SourceIdentifier $stdoutEvent.Name -ErrorAction SilentlyContinue
    Unregister-Event -SourceIdentifier $stderrEvent.Name -ErrorAction SilentlyContinue

    Start-Sleep -Milliseconds 500

    if (-not $completed) {
        $process.Kill()
        throw "Evaluation Copilot timed out after $TimeoutSeconds seconds"
    }

    return $stdoutBuilder.ToString()
}

function Parse-EvaluationJson {
    param([string]$Output)

    # Try to extract JSON from the output - it may be wrapped in markdown code blocks
    # Use a pattern that can match across lines for multi-line JSON
    $lines = $Output -split "`n"
    $jsonStartIdx = -1
    $jsonEndIdx = -1

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\{' -and $lines[$i] -match '"score"') {
            # Single-line JSON
            $jsonCandidate = $lines[$i].Trim()
            try {
                $json = $jsonCandidate | ConvertFrom-Json
                return $json
            } catch { }
        }
        if ($lines[$i] -match '^\s*\{' -and $jsonStartIdx -eq -1) {
            $jsonStartIdx = $i
        }
        if ($jsonStartIdx -ge 0 -and $lines[$i] -match '^\s*\}') {
            $jsonEndIdx = $i
            $jsonCandidate = ($lines[$jsonStartIdx..$jsonEndIdx] -join "`n").Trim()
            if ($jsonCandidate -match '"score"') {
                try {
                    $json = $jsonCandidate | ConvertFrom-Json
                    return $json
                } catch {
                    $jsonStartIdx = -1
                    $jsonEndIdx = -1
                }
            }
        }
    }

    # Fallback: regex extraction
    if ($Output -match '(?s)\{[^{}]*"score"\s*:\s*\d[^{}]*\}') {
        try {
            $json = $Matches[0] | ConvertFrom-Json
            return $json
        } catch {
            Write-Warning "Failed to parse extracted JSON: $_"
        }
    }

    # Return a default failure evaluation
    Write-Warning "Could not parse evaluation output."
    return [PSCustomObject]@{
        score         = 0
        accuracy      = 0
        completeness  = 0
        actionability = 0
        clarity       = 0
        reasoning     = "Failed to parse evaluation response from Copilot"
    }
}

#endregion

#region Main Logic

Write-Host ""
Write-Host ("=" * 60)
Write-Host "[EVAL] Evaluating Scenario: $ScenarioName"
Write-Host ("=" * 60)

$scenarioResultsDir = Join-Path $ResultsDir $ScenarioName

# Read expected output from scenario folder
$scenarioBaseDir = Join-Path $RepoRoot "evaluation\scenarios\$ScenarioName"
$expectedFile = Join-Path $scenarioBaseDir "expected-output.md"
if (-not (Test-Path $expectedFile)) {
    throw "Expected output file not found: $expectedFile"
}
Write-Host "[INFO] Expected output loaded from: $expectedFile"

# Process each run type
$runTypes = @("vanilla", "skilled")
$evaluations = @{}

foreach ($runType in $runTypes) {
    $outputFile = Join-Path $scenarioResultsDir "${runType}-output.txt"

    if (-not (Test-Path $outputFile)) {
        Write-Warning "[WARN] Output file not found for $runType run: $outputFile"
        $evaluations[$runType] = [PSCustomObject]@{
            score         = 0
            accuracy      = 0
            completeness  = 0
            actionability = 0
            clarity       = 0
            reasoning     = "Output file not found - run may have failed or was skipped"
        }
        continue
    }

    $actualOutput = Get-Content $outputFile -Raw
    Write-Host ""
    Write-Host "[EVAL] Evaluating $runType response ($($actualOutput.Length) chars)..."

    # Create a temp evaluation directory with the files Copilot needs to read
    $evalDir = Join-Path ([System.IO.Path]::GetTempPath()) "copilot-eval-${runType}-$(Get-Random)"
    New-Item -ItemType Directory -Force -Path $evalDir | Out-Null

    try {
        # Write the expected output and actual response as files in the eval directory
        Copy-Item -Path $expectedFile -Destination (Join-Path $evalDir "expected-output.md")
        Copy-Item -Path $outputFile -Destination (Join-Path $evalDir "actual-response.txt")

        # Write the evaluation instructions
        $instructions = @"
# Evaluation Task

Read the two files in this directory:
1. **expected-output.md** - The ground truth / expected findings
2. **actual-response.txt** - The AI assistant's actual response

Rate the actual response from 1-5 based on:
1. **Accuracy** - Did it correctly identify the problems?
2. **Completeness** - Did it find all issues mentioned in expected output?
3. **Actionability** - Are the suggested solutions practical and correct?
4. **Clarity** - Is the explanation clear and well-organized?

After reading both files, respond with ONLY a JSON object (no markdown code fences, no extra text):
{"score": <1-5>, "accuracy": <1-5>, "completeness": <1-5>, "actionability": <1-5>, "clarity": <1-5>, "reasoning": "<brief explanation>"}
"@
        $instructions | Out-File -FilePath (Join-Path $evalDir "INSTRUCTIONS.md") -Encoding utf8

        # Build a short prompt that tells Copilot to read the files
        $evalPrompt = "Read the files in this directory: INSTRUCTIONS.md, expected-output.md, and actual-response.txt. Follow the instructions in INSTRUCTIONS.md to evaluate the actual response against the expected output. Respond with ONLY a JSON object as specified in the instructions."

        # Run evaluation with Copilot (vanilla - no plugins)
        Write-Host "[EVAL] Running Copilot evaluator for $runType..."
        $evalOutput = Invoke-EvaluationCopilot `
            -Prompt $evalPrompt `
            -WorkingDir $evalDir `
            -TimeoutSeconds $TimeoutSeconds

        # Save raw evaluation output
        $evalRawFile = Join-Path $scenarioResultsDir "${runType}-eval-raw.txt"
        $evalOutput | Out-File -FilePath $evalRawFile -Encoding utf8

        # Parse evaluation
        $evaluation = Parse-EvaluationJson -Output $evalOutput
        $evaluations[$runType] = $evaluation

        Write-Host "   Score: $($evaluation.score)/5"
        Write-Host "   Accuracy: $($evaluation.accuracy)/5"
        Write-Host "   Completeness: $($evaluation.completeness)/5"
        Write-Host "   Actionability: $($evaluation.actionability)/5"
        Write-Host "   Clarity: $($evaluation.clarity)/5"
        Write-Host "   Reasoning: $($evaluation.reasoning)"
    }
    finally {
        Remove-Item -Path $evalDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# Save combined evaluation results
$evalResult = @{
    scenario    = $ScenarioName
    timestamp   = (Get-Date -Format "o")
    evaluations = $evaluations
}

$evalFile = Join-Path $scenarioResultsDir "evaluation.json"
$evalResult | ConvertTo-Json -Depth 10 | Out-File -FilePath $evalFile -Encoding utf8

Write-Host ""
Write-Host "[OK] Evaluation complete for $ScenarioName"
Write-Host "   Results saved to: $evalFile"

#endregion
