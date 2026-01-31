##################
# Browse.ps1 — Category browser
# Browse global.ini by category, view keys, add to target_strings.ini
##################

function Show-CategoryBrowser {
    <#
    .SYNOPSIS
        Displays categories with key counts and allows drilling into them.
    #>
    $globalIniPath = Join-Path $script:ProjectRoot 'src\global.ini'
    if (-not (Test-Path $globalIniPath)) {
        Write-Error "global.ini not found at: $globalIniPath"
        return
    }

    # Load global.ini keys
    $allKeys = Read-IniFile -Path $globalIniPath
    if (-not $allKeys) { return }

    # Load target_strings to mark customized keys
    $targetPath = Join-Path $script:ProjectRoot 'target_strings.ini'
    $customizedKeys = @{}
    if (Test-Path $targetPath) {
        $targetData = Read-TargetStrings -Path $targetPath
        if ($targetData) {
            $customizedKeys = $targetData['Keys']
        }
    }

    # Build category counts
    $categories = Get-CategoryDefinitions
    $categoryCounts = [ordered]@{}
    $categoryCustomCounts = [ordered]@{}

    foreach ($prefix in $categories.Keys) {
        $count = 0
        $customCount = 0
        foreach ($key in $allKeys.Keys) {
            if ($key.StartsWith($prefix)) {
                $count++
                if ($customizedKeys.Contains($key)) {
                    $customCount++
                }
            }
        }
        $categoryCounts[$prefix] = $count
        $categoryCustomCounts[$prefix] = $customCount
    }

    while ($true) {
        Write-Host ''
        Write-Host '========================================' -ForegroundColor Cyan
        Write-Host '        Category Browser' -ForegroundColor Cyan
        Write-Host '========================================' -ForegroundColor Cyan
        Write-Host ''

        $prefixes = @($categories.Keys)
        for ($i = 0; $i -lt $prefixes.Count; $i++) {
            $prefix = $prefixes[$i]
            $label = $categories[$prefix]
            $count = $categoryCounts[$prefix]
            $customCount = $categoryCustomCounts[$prefix]

            $customTag = ''
            if ($customCount -gt 0) {
                $customTag = " ($customCount customized)"
            }

            Write-Host "  $($i + 1). " -NoNewline -ForegroundColor White
            Write-Host "$label" -NoNewline -ForegroundColor Cyan
            Write-Host " [$count keys]" -NoNewline -ForegroundColor DarkGray
            if ($customTag) {
                Write-Host $customTag -ForegroundColor Green
            } else {
                Write-Host ''
            }
        }

        Write-Host ''
        Write-Host '  D. Discover dynamic categories'
        Write-Host '  Q. Back to main menu'
        Write-Host ''
        Write-Host '  Select category: ' -NoNewline
        $choice = Read-Host

        if ($choice -match '^[Qq]$') { return }

        if ($choice -match '^[Dd]$') {
            Show-DynamicCategories -AllKeys $allKeys -CustomizedKeys $customizedKeys
            continue
        }

        $idx = 0
        if ([int]::TryParse($choice, [ref]$idx)) {
            $idx--
            if ($idx -ge 0 -and $idx -lt $prefixes.Count) {
                $selectedPrefix = $prefixes[$idx]
                Show-CategoryKeys -AllKeys $allKeys -CustomizedKeys $customizedKeys -Prefix $selectedPrefix -Label $categories[$selectedPrefix]
            }
        }
    }
}

function Show-DynamicCategories {
    <#
    .SYNOPSIS
        Shows dynamically discovered categories from global.ini.
    #>
    param(
        [Parameter(Mandatory)]
        $AllKeys,

        [Parameter(Mandatory)]
        $CustomizedKeys
    )

    $globalIniPath = Join-Path $script:ProjectRoot 'src\global.ini'
    Write-Host ''
    Write-Host 'Discovering categories from global.ini...' -ForegroundColor Yellow

    $dynamic = Get-DynamicCategories -IniPath $globalIniPath -MinKeys 20

    Write-Host ''
    Write-Host "Found $($dynamic.Count) categories with 20+ keys:" -ForegroundColor Cyan
    Write-Host ''

    $prefixes = @($dynamic.Keys)
    for ($i = 0; $i -lt [Math]::Min($prefixes.Count, 40); $i++) {
        $prefix = $prefixes[$i]
        $count = $dynamic[$prefix]
        Write-Host "  $($i + 1). $prefix ($count keys)" -ForegroundColor White
    }

    if ($prefixes.Count -gt 40) {
        Write-Host "  ... and $($prefixes.Count - 40) more" -ForegroundColor DarkGray
    }

    Write-Host ''
    Write-Host '  Select number to browse, or Q to go back: ' -NoNewline
    $choice = Read-Host

    if ($choice -match '^[Qq]$') { return }

    $idx = 0
    if ([int]::TryParse($choice, [ref]$idx)) {
        $idx--
        if ($idx -ge 0 -and $idx -lt $prefixes.Count) {
            Show-CategoryKeys -AllKeys $AllKeys -CustomizedKeys $CustomizedKeys -Prefix $prefixes[$idx] -Label $prefixes[$idx]
        }
    }
}

function Show-CategoryKeys {
    <#
    .SYNOPSIS
        Shows paginated keys for a given category prefix.
    .PARAMETER AllKeys
        Ordered hashtable of all global.ini keys.
    .PARAMETER CustomizedKeys
        Hashtable of keys already in target_strings.ini.
    .PARAMETER Prefix
        The category prefix to filter by.
    .PARAMETER Label
        Display label for the category.
    #>
    param(
        [Parameter(Mandatory)]
        $AllKeys,

        [Parameter(Mandatory)]
        $CustomizedKeys,

        [Parameter(Mandatory)]
        [string]$Prefix,

        [string]$Label = $Prefix
    )

    # Collect matching keys
    $matchingKeys = [System.Collections.Generic.List[string]]::new()
    foreach ($key in $AllKeys.Keys) {
        if ($key.StartsWith($Prefix)) {
            $matchingKeys.Add($key)
        }
    }

    if ($matchingKeys.Count -eq 0) {
        Write-Host "No keys found for prefix: $Prefix" -ForegroundColor Yellow
        return
    }

    $pageSize = 20
    $page = 0
    $totalPages = [Math]::Ceiling($matchingKeys.Count / $pageSize)

    while ($true) {
        $start = $page * $pageSize
        $end = [Math]::Min($start + $pageSize, $matchingKeys.Count)

        Write-Host ''
        Write-Host "  $Label - Page $($page + 1)/$totalPages ($($matchingKeys.Count) keys)" -ForegroundColor Cyan
        Write-Host '  ----------------------------------------' -ForegroundColor DarkGray
        Write-Host ''

        for ($i = $start; $i -lt $end; $i++) {
            $key = $matchingKeys[$i]
            $value = $AllKeys[$key]
            $displayNum = $i + 1

            # Truncate long values for display
            $displayValue = $value
            if ($displayValue.Length -gt 60) {
                $displayValue = $displayValue.Substring(0, 57) + '...'
            }

            $customMark = '   '
            if ($CustomizedKeys.Contains($key)) {
                $customMark = '[*]'
            }

            Write-Host "  $customMark " -NoNewline
            if ($CustomizedKeys.Contains($key)) {
                Write-Host "$displayNum. " -NoNewline -ForegroundColor Green
            } else {
                Write-Host "$displayNum. " -NoNewline -ForegroundColor White
            }
            Write-Host "$key" -NoNewline -ForegroundColor Yellow
            Write-Host " = $displayValue" -ForegroundColor DarkGray
        }

        Write-Host ''
        Write-Host '  [*] = already in target_strings.ini' -ForegroundColor Green
        Write-Host ''

        # Navigation
        $nav = @()
        if ($page -gt 0) { $nav += 'P=Previous' }
        if ($page -lt $totalPages - 1) { $nav += 'N=Next' }
        $nav += 'A=Add keys'
        $nav += 'Q=Back'

        Write-Host "  $($nav -join '  |  ')" -ForegroundColor DarkGray
        Write-Host '  Choice: ' -NoNewline
        $choice = Read-Host

        switch -Regex ($choice.Trim()) {
            '^[Nn]$' {
                if ($page -lt $totalPages - 1) { $page++ }
            }
            '^[Pp]$' {
                if ($page -gt 0) { $page-- }
            }
            '^[Aa]$' {
                Add-KeysToTargetStrings -AllKeys $AllKeys -MatchingKeys $matchingKeys
            }
            '^[Qq]$' { return }
            '^\d' {
                # Direct key number - show full value
                $num = [int]$choice - 1
                if ($num -ge 0 -and $num -lt $matchingKeys.Count) {
                    $key = $matchingKeys[$num]
                    Write-Host ''
                    Write-Host "  Key  : $key" -ForegroundColor Yellow
                    Write-Host "  Value: $($AllKeys[$key])" -ForegroundColor White
                    if ($CustomizedKeys.Contains($key)) {
                        Write-Host "  Custom: $($CustomizedKeys[$key])" -ForegroundColor Green
                    }
                }
            }
        }
    }
}

function Add-KeysToTargetStrings {
    <#
    .SYNOPSIS
        Prompts for key numbers and appends selected keys to target_strings.ini.
    .PARAMETER AllKeys
        Full global.ini hashtable.
    .PARAMETER MatchingKeys
        List of keys in current category.
    #>
    param(
        [Parameter(Mandatory)]
        $AllKeys,

        [Parameter(Mandatory)]
        $MatchingKeys
    )

    Write-Host ''
    Write-Host '  Enter key numbers to add (comma-separated, e.g., 1,3,5): ' -NoNewline
    $input_str = Read-Host

    if (-not $input_str) { return }

    $targetPath = Join-Path $script:ProjectRoot 'target_strings.ini'
    $keysToAdd = [System.Collections.Generic.List[string]]::new()

    foreach ($num in ($input_str -split ',')) {
        $num = $num.Trim()
        $idx = 0
        if ([int]::TryParse($num, [ref]$idx)) {
            $idx-- # Convert to 0-based
            if ($idx -ge 0 -and $idx -lt $MatchingKeys.Count) {
                $keysToAdd.Add($MatchingKeys[$idx])
            }
        }
    }

    if ($keysToAdd.Count -eq 0) {
        Write-Host '  No valid keys selected.' -ForegroundColor Yellow
        return
    }

    # Append to target_strings.ini
    $linesToAdd = [System.Collections.Generic.List[string]]::new()
    $linesToAdd.Add('')  # Blank separator line

    foreach ($key in $keysToAdd) {
        $originalValue = $AllKeys[$key]
        $linesToAdd.Add("; @original=$originalValue")
        $linesToAdd.Add("$key=$originalValue")
    }

    # Use AppendAllText to avoid encoding issues
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    $appendText = [string]::Join([Environment]::NewLine, $linesToAdd.ToArray()) + [Environment]::NewLine
    [System.IO.File]::AppendAllText($targetPath, $appendText, $utf8NoBom)

    Write-Host "  Added $($keysToAdd.Count) key(s) to target_strings.ini" -ForegroundColor Green
    Write-Host '  Edit the file to customize the values.' -ForegroundColor Yellow
}
