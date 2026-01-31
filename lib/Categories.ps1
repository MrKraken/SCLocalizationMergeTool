##################
# Categories.ps1 — Category definitions for localization keys
# Provides classification of global.ini keys into browsable groups
##################

function Get-CategoryDefinitions {
    <#
    .SYNOPSIS
        Returns an ordered hashtable of known localization key categories.
    #>
    $categories = [ordered]@{
        'vehicle_Name'      = 'Vehicle Names'
        'ui_interactor'     = 'UI Interactors'
        'innerthought'      = 'Inner Thought Prompts'
        'chat_emote'        = 'Chat Emotes'
        'Hints_'            = 'Hints & Tips'
        'ui_error_message'  = 'UI Error Messages'
        'Infractions_'      = 'Infractions'
        'RepStanding_'      = 'Reputation Standing'
        'flightHUD_Label'   = 'Flight HUD Labels'
        'item_NameFood'     = 'Food Items'
        'item_NameDrink'    = 'Drink Items'
        'items_commodities' = 'Commodities'
        'ShipSelector_'     = 'Ship Selector'
        'interaction_'      = 'Interactions'
        'operatorMode'      = 'Operator Modes'
        'RR_'               = 'Reputation Rewards'
        'area_name'         = 'Area Names'
    }
    return $categories
}

function Get-KeyCategory {
    <#
    .SYNOPSIS
        Given a localization key, returns the category prefix it belongs to, or $null.
    .PARAMETER Key
        The INI key to classify.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Key
    )

    $categories = Get-CategoryDefinitions
    foreach ($prefix in $categories.Keys) {
        if ($Key.StartsWith($prefix)) {
            return $prefix
        }
    }
    return $null
}

function Get-DynamicCategories {
    <#
    .SYNOPSIS
        Analyzes a global.ini file to discover all key prefixes dynamically.
    .PARAMETER IniPath
        Path to the global.ini file to analyze.
    .PARAMETER MinKeys
        Minimum number of keys a prefix must have to be included (default: 10).
    .OUTPUTS
        Ordered hashtable of prefix => count, sorted by count descending.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$IniPath,

        [int]$MinKeys = 10
    )

    if (-not (Test-Path $IniPath)) {
        Write-Warning "INI file not found: $IniPath"
        return [ordered]@{}
    }

    $prefixCounts = @{}

    foreach ($line in [System.IO.File]::ReadLines($IniPath)) {
        if ($line -match '^([A-Za-z][A-Za-z0-9]*_)') {
            $prefix = $matches[1]
            if ($prefixCounts.ContainsKey($prefix)) {
                $prefixCounts[$prefix]++
            } else {
                $prefixCounts[$prefix] = 1
            }
        }
    }

    # Filter and sort by count descending
    $sorted = [ordered]@{}
    $prefixCounts.GetEnumerator() |
        Where-Object { $_.Value -ge $MinKeys } |
        Sort-Object -Property Value -Descending |
        ForEach-Object { $sorted[$_.Key] = $_.Value }

    return $sorted
}
