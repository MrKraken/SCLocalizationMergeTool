##################
# merge.ps1 — SC Localization Merge Tool
# Main entry point: interactive menu, parameter dispatch, module loader
#
# Originally from /u/Asphalt_Expert's component stats language pack
# https://github.com/ExoAE/ScCompLangPack/blob/main/merge-process/merge-ini.ps1
# Rebuilt into a modular workbench by MrKraken (https://www.youtube.com/@MrKraken)
##################

[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(ParameterSetName = 'Merge')]
    [switch]$Merge,

    [Parameter(ParameterSetName = 'Extract')]
    [switch]$Extract,

    [Parameter(ParameterSetName = 'Diff')]
    [switch]$Diff,

    [Parameter(ParameterSetName = 'Browse')]
    [switch]$Browse,

    [Parameter(ParameterSetName = 'Settings')]
    [switch]$Settings,

    [string]$Environment = $null
)

# Set project root so lib files can reference it
$script:ProjectRoot = $PSScriptRoot

# Dot-source all library modules
. (Join-Path $PSScriptRoot 'lib\Categories.ps1')
. (Join-Path $PSScriptRoot 'lib\Config.ps1')
. (Join-Path $PSScriptRoot 'lib\Extract.ps1')
. (Join-Path $PSScriptRoot 'lib\Merge.ps1')
. (Join-Path $PSScriptRoot 'lib\Diff.ps1')
. (Join-Path $PSScriptRoot 'lib\Browse.ps1')

function Show-Banner {
    Write-Host ''
    Write-Host '  ____   ____   _                    _ _          _   _' -ForegroundColor Cyan
    Write-Host ' / ___| / ___| | |    ___   ___ __ _| (_)______ _| |_(_) ___  _ __' -ForegroundColor Cyan
    Write-Host ' \___ \| |     | |   / _ \ / __/ _` | | |_  / _` | __| |/ _ \| `_ \' -ForegroundColor Cyan
    Write-Host '  ___) | |___  | |__| (_) | (_| (_| | | |/ / (_| | |_| | (_) | | | |' -ForegroundColor Cyan
    Write-Host ' |____/ \____| |_____\___/ \___\__,_|_|_/___\__,_|\__|_|\___/|_| |_|' -ForegroundColor Cyan
    Write-Host '                     Merge Tool' -ForegroundColor Yellow
    Write-Host ''
}

function Show-MainMenu {
    <#
    .SYNOPSIS
        Interactive menu loop — the default when no parameters are passed.
    #>
    Show-Banner

    # First-run detection
    $config = Read-Config
    if (-not $config) {
        $config = Initialize-Config
    }

    while ($true) {
        Write-Host '========================================' -ForegroundColor Cyan
        Write-Host '             Main Menu' -ForegroundColor Cyan
        Write-Host '========================================' -ForegroundColor Cyan
        Write-Host ''
        Write-Host '  1. Merge translations'
        Write-Host '  2. Browse categories'
        Write-Host '  3. Diff patch versions'
        Write-Host '  4. Extract from Data.p4k'
        Write-Host '  5. Settings'
        Write-Host '  Q. Quit'
        Write-Host ''
        Write-Host '  Select: ' -NoNewline
        $choice = Read-Host

        switch ($choice.Trim().ToUpper()) {
            '1' {
                $env = if ($Environment) { $Environment } else { Get-DefaultEnvironment }
                Invoke-Merge -Environment $env
            }
            '2' { Show-CategoryBrowser }
            '3' { Show-DiffMenu }
            '4' { Show-ExtractMenu }
            '5' { Show-Settings }
            'Q' {
                Write-Host 'Goodbye!' -ForegroundColor Cyan
                return
            }
            default {
                Write-Host 'Invalid selection.' -ForegroundColor Yellow
            }
        }

        Write-Host ''
    }
}

function Get-DefaultEnvironment {
    <#
    .SYNOPSIS
        Returns the first configured environment, or 'LIVE' as fallback.
    #>
    $config = Read-Config
    if ($config -and $config.environments -and $config.environments.Count -gt 0) {
        return $config.environments[0]
    }
    return 'LIVE'
}

# Parameter dispatch
if ($Merge) {
    $env = if ($Environment) { $Environment } else { Get-DefaultEnvironment }
    Invoke-Merge -Environment $env
} elseif ($Extract) {
    Show-ExtractMenu
} elseif ($Diff) {
    Show-DiffMenu
} elseif ($Browse) {
    Show-CategoryBrowser
} elseif ($Settings) {
    Show-Settings
} else {
    # Interactive mode
    Show-MainMenu
}
