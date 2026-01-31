##################
# Merge.ps1 — Conflict-aware merge engine
# Core merge logic: reads INI files, applies replacements, writes output with UTF-8 BOM
##################

function Read-IniFile {
    <#
    .SYNOPSIS
        Loads an INI file into an ordered hashtable.
    .PARAMETER Path
        Path to the INI file.
    .OUTPUTS
        Ordered hashtable of key => value. Keys include the ,P suffix if present.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        Write-Error "File not found: $Path"
        return $null
    }

    $entries = [ordered]@{}
    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        if ($line -match '^(.*?)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2]
            $entries[$key] = $value
        }
    }
    return $entries
}

function Read-TargetStrings {
    <#
    .SYNOPSIS
        Loads target_strings.ini, parsing optional ; @original= metadata.
    .PARAMETER Path
        Path to target_strings.ini.
    .OUTPUTS
        Hashtable with Keys (key => value) and Originals (key => original value).
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        Write-Error "File not found: $Path"
        return $null
    }

    $keys = [ordered]@{}
    $originals = @{}
    $pendingOriginal = $null

    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        # Check for @original metadata comment
        if ($line -match '^\s*;\s*@original=(.*)$') {
            $pendingOriginal = $matches[1]
            continue
        }

        # Skip other comments and blank lines
        if ($line -match '^\s*;' -or $line -match '^\s*$') {
            $pendingOriginal = $null
            continue
        }

        if ($line -match '^(.*?)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2]
            $keys[$key] = $value

            if ($pendingOriginal) {
                $originals[$key] = $pendingOriginal
                $pendingOriginal = $null
            }
        }
    }

    return @{
        Keys      = $keys
        Originals = $originals
    }
}

function Invoke-Merge {
    <#
    .SYNOPSIS
        Merges target_strings.ini translations into global.ini.
    .PARAMETER Environment
        The game environment to write to (if autoWrite is enabled).
    .DESCRIPTION
        Same core logic as the original merge-translations.ps1:
        line-by-line processing, only replaces matching keys.
    #>
    param(
        [string]$Environment = 'LIVE'
    )

    $config = Read-Config

    $targetStringsPath = Join-Path $script:ProjectRoot 'target_strings.ini'
    $globalIniPath = Join-Path $script:ProjectRoot 'src\global.ini'
    $mergedIniPath = Join-Path $script:ProjectRoot 'output\merged.ini'

    # Validate inputs
    if (-not (Test-Path $targetStringsPath)) {
        Write-Error "target_strings.ini not found at: $targetStringsPath"
        return $false
    }
    if (-not (Test-Path $globalIniPath)) {
        Write-Error "global.ini not found at: $globalIniPath"
        return $false
    }

    # Ensure output directory exists
    $outputDir = Split-Path $mergedIniPath -Parent
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    # Load replacements
    $targetData = Read-TargetStrings -Path $targetStringsPath
    $replacements = $targetData['Keys']

    Write-Host ''
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host '          Merging translations' -ForegroundColor Cyan
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host "  Source  : src/global.ini"
    Write-Host "  Targets : $($replacements.Count) custom strings"
    Write-Host ''

    # Track which keys were actually merged
    $mergedKeys = @{}
    $mergeCount = 0

    # Process line by line (same logic as original)
    $processedLines = [System.Collections.Generic.List[string]]::new()
    foreach ($line in [System.IO.File]::ReadLines($globalIniPath)) {
        if ($line -match '^(.*?)(=)(.*)$') {
            $key = $matches[1].Trim()
            $prefix = $line.Substring(0, $line.IndexOf('=') + 1)
            if ($replacements.Contains($key)) {
                $processedLines.Add($prefix + $replacements[$key])
                $mergedKeys[$key] = $true
                $mergeCount++
            } else {
                $processedLines.Add($line)
            }
        } else {
            $processedLines.Add($line)
        }
    }

    # Detect orphaned keys (in targets but not found in source)
    $orphanedKeys = @()
    foreach ($key in $replacements.Keys) {
        if (-not $mergedKeys.ContainsKey($key)) {
            $orphanedKeys += $key
        }
    }

    # Write output with UTF-8 BOM
    $utf8Bom = [System.Text.UTF8Encoding]::new($true)
    [System.IO.File]::WriteAllLines($mergedIniPath, $processedLines.ToArray(), $utf8Bom)

    # Write to game folder if configured
    $gameWritten = $false
    $userCfgStatus = $null
    $language = if ($config -and $config.language) { $config.language } else { 'english' }
    if ($config -and $config.autoWrite -and $config.gameInstallPath) {
        $gameIniPath = Join-Path $config.gameInstallPath "$Environment\data\Localization\$language\global.ini"
        $gameLocDir = Split-Path $gameIniPath -Parent
        if (-not (Test-Path $gameLocDir)) {
            New-Item -ItemType Directory -Path $gameLocDir -Force | Out-Null
        }
        [System.IO.File]::WriteAllLines($gameIniPath, $processedLines.ToArray(), $utf8Bom)
        $gameWritten = $true

        # Ensure user.cfg exists with g_language setting
        $userCfgStatus = Ensure-UserCfg -EnvironmentPath (Join-Path $config.gameInstallPath $Environment) -Language $language
    }

    # Summary
    Write-MergeSummary -MergeCount $mergeCount -TotalTargets $replacements.Count -OrphanedKeys $orphanedKeys -GameWritten $gameWritten -Environment $Environment -UserCfgStatus $userCfgStatus -Language $language

    return $true
}

function Ensure-UserCfg {
    <#
    .SYNOPSIS
        Ensures user.cfg exists in the environment folder with the g_language line.
    .PARAMETER EnvironmentPath
        Path to the environment folder (e.g., StarCitizen/LIVE).
    .PARAMETER Language
        The language to set. Defaults to 'english'.
    .OUTPUTS
        String status: 'created', 'updated', 'ok', or $null on error.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$EnvironmentPath,

        [string]$Language = 'english'
    )

    $userCfgPath = Join-Path $EnvironmentPath 'user.cfg'
    $requiredLine = "g_language = $Language"

    try {
        if (-not (Test-Path $userCfgPath)) {
            # Create new user.cfg
            [System.IO.File]::WriteAllText($userCfgPath, "$requiredLine`r`n")
            return 'created'
        }

        # File exists — check if it already contains the setting
        $content = [System.IO.File]::ReadAllText($userCfgPath)
        $lines = $content -split '\r?\n'

        # Look for existing g_language line (any value)
        $found = $false
        $correct = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*g_language\s*=') {
                $found = $true
                if ($lines[$i] -match "^\s*g_language\s*=\s*$Language\s*$") {
                    $correct = $true
                } else {
                    # Wrong language value — update it
                    $lines[$i] = $requiredLine
                }
                break
            }
        }

        if ($correct) {
            return 'ok'
        }

        if ($found) {
            # Had wrong value, write back with corrected line
            $newContent = ($lines -join "`r`n")
            [System.IO.File]::WriteAllText($userCfgPath, $newContent)
            return 'updated'
        }

        # Line not present — append it
        $appendText = "`r`n$requiredLine`r`n"
        [System.IO.File]::AppendAllText($userCfgPath, $appendText)
        return 'updated'
    } catch {
        Write-Warning "Could not manage user.cfg: $_"
        return $null
    }
}

function Write-MergeSummary {
    <#
    .SYNOPSIS
        Displays a color-coded merge summary.
    #>
    param(
        [int]$MergeCount,
        [int]$TotalTargets,
        [string[]]$OrphanedKeys,
        [bool]$GameWritten,
        [string]$Environment,
        [string]$UserCfgStatus = $null,
        [string]$Language = 'english'
    )

    Write-Host '  Results:' -ForegroundColor Cyan
    Write-Host "    Merged: $MergeCount / $TotalTargets strings" -ForegroundColor Green
    Write-Host "    Output: output/merged.ini" -ForegroundColor Green

    if ($GameWritten) {
        Write-Host "    Game  : Written to $Environment/$Language folder" -ForegroundColor Green
    }

    if ($UserCfgStatus -eq 'created') {
        Write-Host "    Config: user.cfg created with g_language = $Language" -ForegroundColor Green
    } elseif ($UserCfgStatus -eq 'updated') {
        Write-Host "    Config: user.cfg updated with g_language = $Language" -ForegroundColor Green
    } elseif ($UserCfgStatus -eq 'ok') {
        Write-Host "    Config: user.cfg already correct" -ForegroundColor DarkGray
    }

    if ($OrphanedKeys.Count -gt 0) {
        Write-Host ''
        Write-Host "  Orphaned keys ($($OrphanedKeys.Count)):" -ForegroundColor Yellow
        Write-Host '  These keys are in target_strings.ini but not in global.ini.' -ForegroundColor Yellow
        Write-Host '  They may have been renamed or removed in a patch.' -ForegroundColor Yellow
        foreach ($key in $OrphanedKeys) {
            Write-Host "    - $key" -ForegroundColor Yellow
        }
    }

    Write-Host ''
}
