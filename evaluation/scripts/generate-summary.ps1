<#
.SYNOPSIS
    Generates a markdown summary of evaluation results.

.DESCRIPTION
    Reads evaluation results from the results directory and produces a markdown
    summary table suitable for GitHub Job Summary or PR comment.

.PARAMETER ResultsDir
    Path to the results directory for this run.

.PARAMETER GitHubRunUrl
    Optional URL to the GitHub Actions workflow run for linking in the footer.

.PARAMETER ArtifactsUrl
    Optional URL to the artifacts download page for linking in the footer.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ResultsDir,

    [Parameter()]
    [string]$GitHubRunUrl,

    [Parameter()]
    [string]$ArtifactsUrl
)

$ErrorActionPreference = "Stop"

#region Helper Functions

function Get-QualityDelta {
    param([float]$Vanilla, [float]$Skilled)
    $delta = $Skilled - $Vanilla
    if ($delta -ge 2) { return "+$delta (much better)" }
    if ($delta -ge 1) { return "+$delta (better)" }
    if ($delta -gt 0) { return "+$delta (slightly better)" }
    if ($delta -eq 0) { return "0 (same)" }
    if ($delta -gt -1) { return "$delta (slightly worse)" }
    if ($delta -gt -2) { return "$delta (worse)" }
    return "$delta (much worse)"
}

function Get-QualityDeltaEmoji {
    param([float]$Delta)
    if ($Delta -ge 2) { return "+++" }
    if ($Delta -ge 1) { return "++" }
    if ($Delta -gt 0) { return "+" }
    if ($Delta -eq 0) { return "=" }
    if ($Delta -gt -1) { return "-" }
    if ($Delta -gt -2) { return "--" }
    return "---"
}

function Get-TimeDelta {
    param([int]$Vanilla, [int]$Skilled)
    if ($null -eq $Vanilla -or $null -eq $Skilled -or $Vanilla -eq 0) {
        return "N/A"
    }
    $ratio = ($Skilled / $Vanilla) * 100
    $pct = [math]::Round($ratio - 100)
    if ($pct -le 0) { return "${pct}%" }
    return "+${pct}%"
}

function Get-Winner {
    param(
        [float]$VanillaScore,
        [float]$SkilledScore,
        [int]$VanillaTime = 0,
        [int]$SkilledTime = 0,
        [int]$VanillaTokens = 0,
        [int]$SkilledTokens = 0
    )
    # Quality is the primary criterion
    if ($SkilledScore -gt $VanillaScore) { return "Skilled" }
    if ($VanillaScore -gt $SkilledScore) { return "Vanilla" }

    # Quality tied - use efficiency (time + tokens) as tiebreaker
    # Score: lower time/tokens = better. Count wins per metric.
    $skilledWins = 0
    $vanillaWins = 0

    if ($VanillaTime -gt 0 -and $SkilledTime -gt 0) {
        if ($SkilledTime -lt $VanillaTime) { $skilledWins++ }
        elseif ($VanillaTime -lt $SkilledTime) { $vanillaWins++ }
    }
    if ($VanillaTokens -gt 0 -and $SkilledTokens -gt 0) {
        if ($SkilledTokens -lt $VanillaTokens) { $skilledWins++ }
        elseif ($VanillaTokens -lt $SkilledTokens) { $vanillaWins++ }
    }

    if ($skilledWins -gt $vanillaWins) { return "Skilled" }
    if ($vanillaWins -gt $skilledWins) { return "Vanilla" }
    return "Tie"
}

function Format-TokenCount {
    param($Value)
    if ($null -eq $Value -or $Value -eq 0) { return "N/A" }
    if ([int]$Value -ge 1000000) {
        return "$([math]::Round([int]$Value / 1000000, 1))M"
    }
    if ([int]$Value -ge 1000) {
        return "$([math]::Round([int]$Value / 1000, 1))k"
    }
    return "$Value"
}

function Get-TokenDelta {
    param([int]$Vanilla, [int]$Skilled)
    if ($null -eq $Vanilla -or $null -eq $Skilled -or $Vanilla -eq 0) {
        return "N/A"
    }
    $ratio = ($Skilled / $Vanilla) * 100
    $pct = [math]::Round($ratio - 100)
    if ($pct -le 0) { return "${pct}%" }
    return "+${pct}%"
}

#endregion

#region Main Logic

Write-Host ""
Write-Host ("=" * 60)
Write-Host "[SUMMARY] Generating Summary"
Write-Host ("=" * 60)

# Find all scenario results
$scenarioDirs = Get-ChildItem -Path $ResultsDir -Directory -ErrorAction SilentlyContinue
if (-not $scenarioDirs) {
    Write-Warning "No scenario results found in $ResultsDir"
    $scenarioDirs = @()
}

$summaryLines = New-Object System.Collections.Generic.List[string]

# Header
$summaryLines.Add("## Copilot Skills Evaluation Results")
$summaryLines.Add("")
$summaryLines.Add("**Run Date**: $(Get-Date -Format 'yyyy-MM-dd HH:mm UTC')")
$summaryLines.Add("**Scenarios Tested**: $($scenarioDirs.Count)")
$summaryLines.Add("")

# Summary table
$summaryLines.Add("### Summary")
$summaryLines.Add("")
$summaryLines.Add("| Scenario | Quality | Time | Tokens (in) | Winner |")
$summaryLines.Add("|----------|---------|------|-------------|--------|")

$overallVanilla = 0.0
$overallSkilled = 0.0
$scenarioCount = 0

foreach ($scenarioDir in $scenarioDirs) {
    $scenarioName = $scenarioDir.Name
    $evalFile = Join-Path $scenarioDir.FullName "evaluation.json"
    $vanillaStatsFile = Join-Path $scenarioDir.FullName "vanilla-stats.json"
    $skilledStatsFile = Join-Path $scenarioDir.FullName "skilled-stats.json"

    # Load evaluation
    $vanillaScore = "N/A"
    $skilledScore = "N/A"
    $qualityDelta = "N/A"
    $winner = "N/A"

    if (Test-Path $evalFile) {
        $evalData = Get-Content $evalFile -Raw | ConvertFrom-Json

        $vanillaEval = $evalData.evaluations.vanilla
        $skilledEval = $evalData.evaluations.skilled

        if ($vanillaEval -and $vanillaEval.score) {
            $vanillaScore = "$($vanillaEval.score)/5"
            $overallVanilla += [float]$vanillaEval.score
        }
        if ($skilledEval -and $skilledEval.score) {
            $skilledScore = "$($skilledEval.score)/5"
            $overallSkilled += [float]$skilledEval.score
        }

        if ($vanillaEval.score -and $skilledEval.score) {
            $delta = [float]$skilledEval.score - [float]$vanillaEval.score
            $deltaEmoji = Get-QualityDeltaEmoji -Delta $delta
            $qualityDelta = "$deltaEmoji $delta"
            $scenarioCount++
        }
    }

    # Load timing stats
    $vanillaTime = "N/A"
    $skilledTime = "N/A"
    $timeDelta = "N/A"
    $vanillaStats = $null
    $skilledStats = $null

    if (Test-Path $vanillaStatsFile) {
        $vanillaStats = Get-Content $vanillaStatsFile -Raw | ConvertFrom-Json
        if ($vanillaStats.TotalTimeSeconds) {
            $vanillaTime = "$($vanillaStats.TotalTimeSeconds)s"
        }
    }
    if (Test-Path $skilledStatsFile) {
        $skilledStats = Get-Content $skilledStatsFile -Raw | ConvertFrom-Json
        if ($skilledStats.TotalTimeSeconds) {
            $skilledTime = "$($skilledStats.TotalTimeSeconds)s"
        }
    }

    if ($vanillaStats -and $vanillaStats.TotalTimeSeconds -and $skilledStats -and $skilledStats.TotalTimeSeconds) {
        $timeDelta = Get-TimeDelta -Vanilla ([int]$vanillaStats.TotalTimeSeconds) -Skilled ([int]$skilledStats.TotalTimeSeconds)
    }

    # Delta stats for summary table
    $tokenDelta = "N/A"

    if ($vanillaStats -and $skilledStats -and $vanillaStats.TokensIn -and $skilledStats.TokensIn) {
        $tokenDelta = Get-TokenDelta -Vanilla ([int]$vanillaStats.TokensIn) -Skilled ([int]$skilledStats.TokensIn)
    }

    # Determine winner: quality first, then time + tokens as tiebreakers
    if ($vanillaEval -and $skilledEval -and $vanillaEval.score -and $skilledEval.score) {
        $winnerParams = @{
            VanillaScore = [float]$vanillaEval.score
            SkilledScore = [float]$skilledEval.score
        }
        if ($vanillaStats -and $skilledStats) {
            if ($vanillaStats.TotalTimeSeconds -and $skilledStats.TotalTimeSeconds) {
                $winnerParams.VanillaTime = [int]$vanillaStats.TotalTimeSeconds
                $winnerParams.SkilledTime = [int]$skilledStats.TotalTimeSeconds
            }
            if ($vanillaStats.TokensIn -and $skilledStats.TokensIn) {
                $winnerParams.VanillaTokens = [int]$vanillaStats.TokensIn
                $winnerParams.SkilledTokens = [int]$skilledStats.TokensIn
            }
        }
        $winner = Get-Winner @winnerParams
    }

    $summaryLines.Add("| $scenarioName | $qualityDelta | $timeDelta | $tokenDelta | $winner |")
}

$summaryLines.Add("")

# Overall result
if ($scenarioCount -gt 0) {
    $avgVanilla = [math]::Round($overallVanilla / $scenarioCount, 1)
    $avgSkilled = [math]::Round($overallSkilled / $scenarioCount, 1)

    if ($avgSkilled -gt $avgVanilla) {
        $summaryLines.Add("### Overall Result: **Skills Improved Response Quality**")
    } elseif ($avgSkilled -eq $avgVanilla) {
        $summaryLines.Add("### Overall Result: **No Significant Difference**")
    } else {
        $summaryLines.Add("### Overall Result: **Skills Degraded Response Quality**")
    }
    $summaryLines.Add("")
    $summaryLines.Add("**Average Scores**: Vanilla $avgVanilla/5 | Skilled $avgSkilled/5")
} else {
    $summaryLines.Add("### Overall Result: **No scenarios evaluated**")
}

$summaryLines.Add("")

# Per-scenario comparison tables
$summaryLines.Add("### Scenario Details")
$summaryLines.Add("")

foreach ($scenarioDir in $scenarioDirs) {
    $scenarioName = $scenarioDir.Name
    $evalFile = Join-Path $scenarioDir.FullName "evaluation.json"
    $vanillaStatsFile = Join-Path $scenarioDir.FullName "vanilla-stats.json"
    $skilledStatsFile = Join-Path $scenarioDir.FullName "skilled-stats.json"

    $vanillaStats = $null
    $skilledStats = $null
    $vanillaEval = $null
    $skilledEval = $null

    if (Test-Path $evalFile) {
        $evalData = Get-Content $evalFile -Raw | ConvertFrom-Json
        $vanillaEval = $evalData.evaluations.vanilla
        $skilledEval = $evalData.evaluations.skilled
    }
    if (Test-Path $vanillaStatsFile) {
        $vanillaStats = Get-Content $vanillaStatsFile -Raw | ConvertFrom-Json
    }
    if (Test-Path $skilledStatsFile) {
        $skilledStats = Get-Content $skilledStatsFile -Raw | ConvertFrom-Json
    }

    $summaryLines.Add("#### $scenarioName")
    $summaryLines.Add("")
    $summaryLines.Add("| Metric | Vanilla | Skilled | Delta |")
    $summaryLines.Add("|--------|---------|---------|-------|")

    # Quality row
    $vScore = if ($vanillaEval -and $vanillaEval.score) { "$($vanillaEval.score)/5" } else { "N/A" }
    $sScore = if ($skilledEval -and $skilledEval.score) { "$($skilledEval.score)/5" } else { "N/A" }
    $qDelta = "N/A"
    if ($vanillaEval -and $vanillaEval.score -and $skilledEval -and $skilledEval.score) {
        $d = [float]$skilledEval.score - [float]$vanillaEval.score
        $emoji = Get-QualityDeltaEmoji -Delta $d
        $qDelta = "$emoji $d"
    }
    $summaryLines.Add("| Quality | $vScore | $sScore | $qDelta |")

    # Time row
    $vTime = if ($vanillaStats -and $vanillaStats.TotalTimeSeconds) { "$($vanillaStats.TotalTimeSeconds)s" } else { "N/A" }
    $sTime = if ($skilledStats -and $skilledStats.TotalTimeSeconds) { "$($skilledStats.TotalTimeSeconds)s" } else { "N/A" }
    $tDelta = "N/A"
    if ($vanillaStats -and $skilledStats -and $vanillaStats.TotalTimeSeconds -and $skilledStats.TotalTimeSeconds) {
        $tDelta = Get-TimeDelta -Vanilla ([int]$vanillaStats.TotalTimeSeconds) -Skilled ([int]$skilledStats.TotalTimeSeconds)
    }
    $summaryLines.Add("| Time | $vTime | $sTime | $tDelta |")

    # Tokens row
    $vTokens = "N/A"
    $sTokens = "N/A"
    $tkDelta = "N/A"
    if ($vanillaStats -and $vanillaStats.TokensIn) {
        $vIn = Format-TokenCount $vanillaStats.TokensIn
        $vOut = Format-TokenCount $vanillaStats.TokensOut
        $vTokens = "$vIn / $vOut"
    }
    if ($skilledStats -and $skilledStats.TokensIn) {
        $sIn = Format-TokenCount $skilledStats.TokensIn
        $sOut = Format-TokenCount $skilledStats.TokensOut
        $sTokens = "$sIn / $sOut"
    }
    if ($vanillaStats -and $skilledStats -and $vanillaStats.TokensIn -and $skilledStats.TokensIn) {
        $tkDelta = Get-TokenDelta -Vanilla ([int]$vanillaStats.TokensIn) -Skilled ([int]$skilledStats.TokensIn)
    }
    $summaryLines.Add("| Tokens (in/out) | $vTokens | $sTokens | $tkDelta |")

    $summaryLines.Add("")

    # Model verification
    if ($vanillaStats -and $skilledStats -and $vanillaStats.Model -and $skilledStats.Model) {
        if ($vanillaStats.Model -eq $skilledStats.Model) {
            $summaryLines.Add("**Model**: $($vanillaStats.Model) (consistent)")
        } else {
            $summaryLines.Add("**WARNING - Model Mismatch**: Vanilla=$($vanillaStats.Model), Skilled=$($skilledStats.Model)")
        }
        $summaryLines.Add("")
    }

    # Evaluation details in collapsible section
    if ($vanillaEval -or $skilledEval) {
        $summaryLines.Add("<details>")
        $summaryLines.Add("<summary>Evaluation Details</summary>")
        $summaryLines.Add("")

        foreach ($runType in @("vanilla", "skilled")) {
            $eval = if ($runType -eq "vanilla") { $vanillaEval } else { $skilledEval }
            if ($eval) {
                $label = $runType.Substring(0,1).ToUpper() + $runType.Substring(1)
                $summaryLines.Add("**$label** ($($eval.score)/5): Accuracy $($eval.accuracy)/5, Completeness $($eval.completeness)/5, Actionability $($eval.actionability)/5, Clarity $($eval.clarity)/5")
                if ($eval.reasoning) {
                    $summaryLines.Add("> $($eval.reasoning)")
                }
                $summaryLines.Add("")
            }
        }

        $summaryLines.Add("</details>")
        $summaryLines.Add("")
    }
}

# Footer
$summaryLines.Add("---")
$footerParts = @("*Generated by Copilot Skills Evaluation Pipeline")
if ($GitHubRunUrl) {
    $footerParts += " | [View workflow run]($GitHubRunUrl)"
}
if ($ArtifactsUrl) {
    $footerParts += " | [Download artifacts]($ArtifactsUrl)"
}
$footerParts += "*"
$summaryLines.Add($footerParts -join "")

# Write summary
$summaryContent = $summaryLines -join "`n"
$summaryFile = Join-Path $ResultsDir "summary.md"
$summaryContent | Out-File -FilePath $summaryFile -Encoding utf8

Write-Host ""
Write-Host "[OK] Summary generated: $summaryFile"
Write-Host ""
Write-Host "--- Summary Preview ---"
Write-Host $summaryContent
Write-Host "--- End Preview ---"

#endregion
