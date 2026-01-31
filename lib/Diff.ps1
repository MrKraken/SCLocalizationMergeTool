##################
# Diff.ps1 — Patch change detection
# Compares cached global.ini versions to detect added/removed/changed keys
##################

function Compare-GlobalIni {
    <#
    .SYNOPSIS
        Compares two global.ini files and returns categorized differences.
    .PARAMETER OldPath
        Path to the older global.ini.
    .PARAMETER NewPath
        Path to the newer global.ini.
    .PARAMETER TargetKeys
        Optional hashtable of user-customized keys to detect conflicts.
    .OUTPUTS
        Object with AddedKeys, RemovedKeys, ChangedKeys, Conflicts, RemovedCustomKeys.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$OldPath,

        [Parameter(Mandatory)]
        [string]$NewPath,

        [hashtable]$TargetKeys = @{}
    )

    $oldData = Read-IniFile -Path $OldPath
    $newData = Read-IniFile -Path $NewPath

    if (-not $oldData -or -not $newData) {
        Write-Error 'Failed to read one or both INI files.'
        return $null
    }

    $added = [ordered]@{}
    $removed = [ordered]@{}
    $changed = [ordered]@{}
    $conflicts = [ordered]@{}
    $removedCustom = [ordered]@{}

    # Find added and changed keys
    foreach ($key in $newData.Keys) {
        if (-not $oldData.Contains($key)) {
            $added[$key] = $newData[$key]
        } elseif ($newData[$key] -ne $oldData[$key]) {
            $changed[$key] = @{
                Old = $oldData[$key]
                New = $newData[$key]
            }

            # Check if this is a conflict with user customizations
            if ($TargetKeys.ContainsKey($key)) {
                $conflicts[$key] = @{
                    Old    = $oldData[$key]
                    New    = $newData[$key]
                    Custom = $TargetKeys[$key]
                }
            }
        }
    }

    # Find removed keys
    foreach ($key in $oldData.Keys) {
        if (-not $newData.Contains($key)) {
            $removed[$key] = $oldData[$key]

            # Check if user had customized a removed key
            if ($TargetKeys.ContainsKey($key)) {
                $removedCustom[$key] = $TargetKeys[$key]
            }
        }
    }

    return [PSCustomObject]@{
        AddedKeys         = $added
        RemovedKeys       = $removed
        ChangedKeys       = $changed
        Conflicts         = $conflicts
        RemovedCustomKeys = $removedCustom
    }
}

function Write-DiffReport {
    <#
    .SYNOPSIS
        Displays a color-coded diff report.
    .PARAMETER Diff
        The diff result from Compare-GlobalIni.
    .PARAMETER CategoryFilter
        Optional category prefix to filter results.
    .PARAMETER MaxItems
        Maximum items to display per section (default: 20).
    #>
    param(
        [Parameter(Mandatory)]
        $Diff,

        [string]$CategoryFilter = $null,

        [int]$MaxItems = 20
    )

    Write-Host ''
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host '         Patch Diff Report' -ForegroundColor Cyan
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host ''

    # Summary line
    $addCount = $Diff.AddedKeys.Count
    $removeCount = $Diff.RemovedKeys.Count
    $changeCount = $Diff.ChangedKeys.Count
    $conflictCount = $Diff.Conflicts.Count
    $removedCustomCount = $Diff.RemovedCustomKeys.Count

    Write-Host "  Added: $addCount  |  Removed: $removeCount  |  Changed: $changeCount" -ForegroundColor White
    if ($conflictCount -gt 0 -or $removedCustomCount -gt 0) {
        Write-Host "  Conflicts: $conflictCount  |  Removed custom: $removedCustomCount" -ForegroundColor Magenta
    }
    Write-Host ''

    # Conflicts (most important, show first)
    if ($Diff.Conflicts.Count -gt 0) {
        Write-Host '  CONFLICTS (your customized keys were changed upstream):' -ForegroundColor Magenta
        $shown = 0
        foreach ($key in $Diff.Conflicts.Keys) {
            if ($CategoryFilter -and -not $key.StartsWith($CategoryFilter)) { continue }
            if ($shown -ge $MaxItems) {
                Write-Host "    ... and $($Diff.Conflicts.Count - $shown) more" -ForegroundColor DarkGray
                break
            }
            Write-Host "    $key" -ForegroundColor Magenta
            Write-Host "      Old source : $($Diff.Conflicts[$key].Old)" -ForegroundColor DarkGray
            Write-Host "      New source : $($Diff.Conflicts[$key].New)" -ForegroundColor Yellow
            Write-Host "      Your custom: $($Diff.Conflicts[$key].Custom)" -ForegroundColor Cyan
            $shown++
        }
        Write-Host ''
    }

    # Removed custom keys
    if ($Diff.RemovedCustomKeys.Count -gt 0) {
        Write-Host '  REMOVED CUSTOM KEYS (you customized these but they no longer exist):' -ForegroundColor Magenta
        foreach ($key in $Diff.RemovedCustomKeys.Keys) {
            if ($CategoryFilter -and -not $key.StartsWith($CategoryFilter)) { continue }
            Write-Host "    $key = $($Diff.RemovedCustomKeys[$key])" -ForegroundColor Magenta
        }
        Write-Host ''
    }

    # Changed keys
    if ($Diff.ChangedKeys.Count -gt 0) {
        Write-Host "  Changed keys ($changeCount):" -ForegroundColor Yellow
        $shown = 0
        foreach ($key in $Diff.ChangedKeys.Keys) {
            if ($CategoryFilter -and -not $key.StartsWith($CategoryFilter)) { continue }
            if ($Diff.Conflicts.Contains($key)) { continue } # Already shown above
            if ($shown -ge $MaxItems) {
                $remaining = $Diff.ChangedKeys.Count - $Diff.Conflicts.Count - $shown
                if ($remaining -gt 0) {
                    Write-Host "    ... and $remaining more" -ForegroundColor DarkGray
                }
                break
            }
            Write-Host "    $key" -ForegroundColor Yellow
            $shown++
        }
        Write-Host ''
    }

    # Added keys
    if ($Diff.AddedKeys.Count -gt 0) {
        Write-Host "  Added keys ($addCount):" -ForegroundColor Green
        $shown = 0
        foreach ($key in $Diff.AddedKeys.Keys) {
            if ($CategoryFilter -and -not $key.StartsWith($CategoryFilter)) { continue }
            if ($shown -ge $MaxItems) {
                Write-Host "    ... and $($Diff.AddedKeys.Count - $shown) more" -ForegroundColor DarkGray
                break
            }
            Write-Host "    + $key" -ForegroundColor Green
            $shown++
        }
        Write-Host ''
    }

    # Removed keys
    if ($Diff.RemovedKeys.Count -gt 0) {
        Write-Host "  Removed keys ($removeCount):" -ForegroundColor Red
        $shown = 0
        foreach ($key in $Diff.RemovedKeys.Keys) {
            if ($CategoryFilter -and -not $key.StartsWith($CategoryFilter)) { continue }
            if ($Diff.RemovedCustomKeys.Contains($key)) { continue } # Already shown above
            if ($shown -ge $MaxItems) {
                $remaining = $Diff.RemovedKeys.Count - $Diff.RemovedCustomKeys.Count - $shown
                if ($remaining -gt 0) {
                    Write-Host "    ... and $remaining more" -ForegroundColor DarkGray
                }
                break
            }
            Write-Host "    - $key" -ForegroundColor Red
            $shown++
        }
        Write-Host ''
    }
}

function Select-CacheVersions {
    <#
    .SYNOPSIS
        Interactive picker for selecting two cached versions to compare.
    .OUTPUTS
        Object with OldPath and NewPath, or $null if cancelled.
    #>
    $cached = Get-CachedVersions
    if ($cached.Count -lt 2) {
        Write-Host 'Need at least 2 cached versions to compare.' -ForegroundColor Yellow
        Write-Host 'Run Extract to cache a version, then extract again after a patch.' -ForegroundColor Yellow
        return $null
    }

    Write-Host ''
    Write-Host 'Available cached versions:' -ForegroundColor Cyan
    for ($i = 0; $i -lt $cached.Count; $i++) {
        $v = $cached[$i]
        Write-Host "  $($i + 1). $($v.Name) ($($v.LastWriteTime.ToString('yyyy-MM-dd HH:mm')))"
    }

    Write-Host ''
    Write-Host 'Select OLDER version number: ' -NoNewline
    $oldChoice = Read-Host
    $oldIdx = [int]$oldChoice - 1

    Write-Host 'Select NEWER version number: ' -NoNewline
    $newChoice = Read-Host
    $newIdx = [int]$newChoice - 1

    if ($oldIdx -lt 0 -or $oldIdx -ge $cached.Count -or $newIdx -lt 0 -or $newIdx -ge $cached.Count) {
        Write-Host 'Invalid selection.' -ForegroundColor Red
        return $null
    }

    if ($oldIdx -eq $newIdx) {
        Write-Host 'Please select two different versions.' -ForegroundColor Red
        return $null
    }

    return [PSCustomObject]@{
        OldPath    = $cached[$oldIdx].Path
        NewPath    = $cached[$newIdx].Path
        OldVersion = $cached[$oldIdx].Version
        NewVersion = $cached[$newIdx].Version
    }
}

function Show-DiffMenu {
    <#
    .SYNOPSIS
        Interactive diff menu: select versions and view report.
    #>
    Write-Host ''
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host '          Patch Diff' -ForegroundColor Cyan
    Write-Host '========================================' -ForegroundColor Cyan

    $selection = Select-CacheVersions
    if (-not $selection) { return }

    Write-Host ''
    Write-Host "Comparing: $($selection.OldVersion) -> $($selection.NewVersion)" -ForegroundColor Yellow

    # Load user's target strings to detect conflicts
    $targetPath = Join-Path $script:ProjectRoot 'target_strings.ini'
    $targetKeys = @{}
    if (Test-Path $targetPath) {
        $targetData = Read-TargetStrings -Path $targetPath
        if ($targetData) {
            $targetKeys = $targetData['Keys']
        }
    }

    $diff = Compare-GlobalIni -OldPath $selection.OldPath -NewPath $selection.NewPath -TargetKeys $targetKeys

    if ($diff) {
        # Ask for optional category filter
        Write-Host ''
        Write-Host 'Filter by category prefix? (blank for all): ' -NoNewline
        $filter = Read-Host
        if (-not $filter) { $filter = $null }

        Write-DiffReport -Diff $diff -CategoryFilter $filter
    }
}
