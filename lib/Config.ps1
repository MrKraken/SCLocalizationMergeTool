##################
# Config.ps1 — Configuration system
# JSON-based config with first-run wizard and auto-detection
##################

function Get-ConfigPath {
    return Join-Path $script:ProjectRoot 'config.json'
}

function Read-Config {
    <#
    .SYNOPSIS
        Loads configuration from config.json. Returns $null if not found.
    #>
    $configPath = Get-ConfigPath
    if (-not (Test-Path $configPath)) {
        return $null
    }

    try {
        $json = [System.IO.File]::ReadAllText($configPath)
        $config = $json | ConvertFrom-Json
        return $config
    } catch {
        Write-Warning "Failed to read config.json: $_"
        return $null
    }
}

function Save-Config {
    <#
    .SYNOPSIS
        Saves configuration to config.json (PS 5.1 safe, no BOM).
    .PARAMETER Config
        The configuration object to save.
    #>
    param(
        [Parameter(Mandatory)]
        $Config
    )

    $configPath = Get-ConfigPath
    $json = $Config | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText($configPath, $json)
}

function Find-GameInstallPath {
    <#
    .SYNOPSIS
        Attempts to auto-detect the Star Citizen install path.
    .DESCRIPTION
        Search order:
        1. RSI Launcher log file (installDir / libraryFolder)
        2. Default C:\Program Files path
        3. Scan all fixed drive roots for Roberts Space Industries\StarCitizen
        4. Common install patterns per drive ({drive}:\Games\StarCitizen, etc.)
    .OUTPUTS
        The detected path, or $null if not found.
    #>

    # 1. Try RSI Launcher log
    $logPath = Join-Path $env:APPDATA 'rsilauncher\logs\log.log'
    if (Test-Path $logPath) {
        try {
            $logContent = [System.IO.File]::ReadAllText($logPath)
            # Look for install path references in the log
            if ($logContent -match '"installDir"\s*:\s*"([^"]+)"') {
                $installDir = $matches[1] -replace '\\\\', '\'
                if (Test-Path $installDir) {
                    return $installDir
                }
            }
            # Alternative pattern
            if ($logContent -match '"libraryFolder"\s*:\s*"([^"]+)"') {
                $libraryFolder = $matches[1] -replace '\\\\', '\'
                $scPath = Join-Path $libraryFolder 'StarCitizen'
                if (Test-Path $scPath) {
                    return $scPath
                }
            }
        } catch {
            # Silently continue to next detection method
        }
    }

    # 2. Try default path
    $defaultPath = 'C:\Program Files\Roberts Space Industries\StarCitizen'
    if (Test-Path $defaultPath) {
        return $defaultPath
    }

    # 3. Scan all fixed drives for Roberts Space Industries\StarCitizen
    $fixedDrives = @()
    try {
        $fixedDrives = [System.IO.DriveInfo]::GetDrives() |
            Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } |
            ForEach-Object { $_.RootDirectory.FullName }
    } catch { }

    foreach ($root in $fixedDrives) {
        $candidate = Join-Path $root 'Roberts Space Industries\StarCitizen'
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    # 4. Common install patterns per drive
    foreach ($root in $fixedDrives) {
        $patterns = @(
            (Join-Path $root 'Games\StarCitizen'),
            (Join-Path $root 'Games\Roberts Space Industries\StarCitizen'),
            (Join-Path $root 'Program Files\Roberts Space Industries\StarCitizen')
        )
        foreach ($candidate in $patterns) {
            if (Test-Path $candidate) {
                return $candidate
            }
        }
    }

    return $null
}

function Initialize-AutoConfig {
    <#
    .SYNOPSIS
        Silent auto-configuration for the one-command workflow.
    .DESCRIPTION
        Detects game path automatically, applies sensible defaults
        (LIVE, english, autoWrite=true). Only prompts if the game
        path cannot be found.
    .OUTPUTS
        The newly created configuration object.
    #>
    $detectedPath = Find-GameInstallPath

    if (-not $detectedPath) {
        Write-Host ''
        Write-Host '  Game install path could not be detected.' -ForegroundColor Yellow
        Write-Host '  Enter your Star Citizen installation path' -ForegroundColor Yellow
        Write-Host '  (e.g., C:\Program Files\Roberts Space Industries\StarCitizen): ' -NoNewline
        $detectedPath = Read-Host
        $detectedPath = $detectedPath.Trim('"', "'", ' ')

        if (-not $detectedPath -or -not (Test-Path $detectedPath)) {
            Write-Warning "Path not found: $detectedPath"
            Write-Host '  Run .\merge.ps1 -Settings to configure manually.' -ForegroundColor Yellow
            return $null
        }
    }

    $config = [PSCustomObject]@{
        gameInstallPath  = $detectedPath
        environments     = @('LIVE')
        language         = 'english'
        unp4kPath        = $null
        lastBuildVersion = $null
        autoWrite        = $true
        createdAt        = (Get-Date -Format 'o')
    }

    Save-Config $config
    return $config
}

function Initialize-Config {
    <#
    .SYNOPSIS
        First-run configuration wizard. Prompts the user for settings.
    .OUTPUTS
        The newly created configuration object.
    #>
    Write-Host ''
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host '  SC Localization Merge Tool - Setup' -ForegroundColor Cyan
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'Welcome! This appears to be your first time running the tool.'
    Write-Host 'Let''s get you set up.' -ForegroundColor Yellow
    Write-Host ''

    # Detect game install path
    $detectedPath = Find-GameInstallPath
    $gameInstallPath = $null

    if ($detectedPath) {
        Write-Host "Detected Star Citizen installation: $detectedPath" -ForegroundColor Green
        Write-Host 'Use this path? (Y/n): ' -ForegroundColor Yellow -NoNewline
        $confirm = Read-Host
        if ($confirm -eq '' -or $confirm -match '^[Yy]') {
            $gameInstallPath = $detectedPath
        }
    }

    if (-not $gameInstallPath) {
        Write-Host 'Enter your Star Citizen installation path' -ForegroundColor Yellow
        Write-Host '(e.g., C:\Program Files\Roberts Space Industries\StarCitizen): ' -NoNewline
        $gameInstallPath = Read-Host
        $gameInstallPath = $gameInstallPath.Trim('"', "'", ' ')
    }

    if (-not $gameInstallPath -or -not (Test-Path $gameInstallPath)) {
        Write-Warning "Path not found: $gameInstallPath"
        Write-Host 'You can update this later in Settings.' -ForegroundColor Yellow
    }

    # Select environments
    Write-Host ''
    Write-Host 'Which environments do you use? (comma-separated, e.g., 1,2)' -ForegroundColor Yellow
    Write-Host '  1. LIVE'
    Write-Host '  2. PTU'
    Write-Host '  3. EPTU'
    Write-Host 'Selection [1]: ' -NoNewline
    $envInput = Read-Host
    if (-not $envInput) { $envInput = '1' }

    $envMap = @{ '1' = 'LIVE'; '2' = 'PTU'; '3' = 'EPTU' }
    $environments = @()
    foreach ($num in ($envInput -split ',')) {
        $num = $num.Trim()
        if ($envMap.ContainsKey($num)) {
            $environments += $envMap[$num]
        }
    }
    if ($environments.Count -eq 0) {
        $environments = @('LIVE')
    }

    # Language selection
    Write-Host ''
    Write-Host 'Which language should the game use?' -ForegroundColor Yellow
    Write-Host '  1. english (default)'
    Write-Host '  2. french'
    Write-Host '  3. german'
    Write-Host '  4. spanish'
    Write-Host '  5. italian'
    Write-Host '  6. portuguese'
    Write-Host '  7. chinese_(simplified)'
    Write-Host '  8. chinese_(traditional)'
    Write-Host '  9. korean'
    Write-Host '  10. japanese'
    Write-Host 'Selection [1]: ' -NoNewline
    $langInput = Read-Host
    if (-not $langInput) { $langInput = '1' }

    $langMap = @{
        '1' = 'english'; '2' = 'french'; '3' = 'german'; '4' = 'spanish'
        '5' = 'italian'; '6' = 'portuguese'; '7' = 'chinese_(simplified)'
        '8' = 'chinese_(traditional)'; '9' = 'korean'; '10' = 'japanese'
    }
    $language = if ($langMap.ContainsKey($langInput.Trim())) { $langMap[$langInput.Trim()] } else { 'english' }

    # Auto-write preference
    Write-Host ''
    Write-Host 'Automatically write merged.ini to game folder after merge? (y/N): ' -ForegroundColor Yellow -NoNewline
    $autoWrite = Read-Host
    $autoWriteBool = $autoWrite -match '^[Yy]'

    $config = [PSCustomObject]@{
        gameInstallPath  = $gameInstallPath
        environments     = $environments
        language         = $language
        unp4kPath        = $null
        lastBuildVersion = $null
        autoWrite        = $autoWriteBool
        createdAt        = (Get-Date -Format 'o')
    }

    Save-Config $config

    Write-Host ''
    Write-Host 'Configuration saved!' -ForegroundColor Green
    Write-Host ''

    return $config
}

function Show-Settings {
    <#
    .SYNOPSIS
        Displays current settings and allows editing.
    #>
    $config = Read-Config
    if (-not $config) {
        Write-Host 'No configuration found. Running setup...' -ForegroundColor Yellow
        $config = Initialize-Config
        return
    }

    while ($true) {
        Write-Host ''
        Write-Host '========================================' -ForegroundColor Cyan
        Write-Host '           Settings' -ForegroundColor Cyan
        Write-Host '========================================' -ForegroundColor Cyan
        Write-Host ''
        $displayLang = if ($config.language) { $config.language } else { 'english' }
        Write-Host "  1. Game Install Path : $($config.gameInstallPath)"
        Write-Host "  2. Environments      : $($config.environments -join ', ')"
        Write-Host "  3. Language          : $displayLang"
        Write-Host "  4. unp4k Path        : $(if ($config.unp4kPath) { $config.unp4kPath } else { '(auto-detect)' })"
        Write-Host "  5. Auto-write to game: $(if ($config.autoWrite) { 'Yes' } else { 'No' })"
        Write-Host "  6. Last Build Version: $(if ($config.lastBuildVersion) { $config.lastBuildVersion } else { '(none)' })"
        Write-Host ''
        Write-Host '  Enter number to edit, or Q to go back: ' -NoNewline
        $choice = Read-Host

        switch ($choice.Trim().ToUpper()) {
            '1' {
                Write-Host "Current: $($config.gameInstallPath)" -ForegroundColor DarkGray
                Write-Host 'New path: ' -NoNewline
                $newPath = Read-Host
                $newPath = $newPath.Trim('"', "'", ' ')
                if ($newPath -and (Test-Path $newPath)) {
                    $config.gameInstallPath = $newPath
                    Save-Config $config
                    Write-Host 'Updated.' -ForegroundColor Green
                } elseif ($newPath) {
                    Write-Warning "Path not found: $newPath"
                }
            }
            '2' {
                Write-Host 'Select environments (comma-separated):' -ForegroundColor Yellow
                Write-Host '  1. LIVE  2. PTU  3. EPTU'
                Write-Host 'Selection: ' -NoNewline
                $envInput = Read-Host
                $envMap = @{ '1' = 'LIVE'; '2' = 'PTU'; '3' = 'EPTU' }
                $environments = @()
                foreach ($num in ($envInput -split ',')) {
                    $num = $num.Trim()
                    if ($envMap.ContainsKey($num)) {
                        $environments += $envMap[$num]
                    }
                }
                if ($environments.Count -gt 0) {
                    $config.environments = $environments
                    Save-Config $config
                    Write-Host 'Updated.' -ForegroundColor Green
                }
            }
            '3' {
                $currentLang = if ($config.language) { $config.language } else { 'english' }
                Write-Host "Current: $currentLang" -ForegroundColor DarkGray
                Write-Host '  1. english  2. french  3. german  4. spanish  5. italian'
                Write-Host '  6. portuguese  7. chinese_(simplified)  8. chinese_(traditional)'
                Write-Host '  9. korean  10. japanese'
                Write-Host 'Selection: ' -NoNewline
                $langInput = Read-Host
                $langMap = @{
                    '1' = 'english'; '2' = 'french'; '3' = 'german'; '4' = 'spanish'
                    '5' = 'italian'; '6' = 'portuguese'; '7' = 'chinese_(simplified)'
                    '8' = 'chinese_(traditional)'; '9' = 'korean'; '10' = 'japanese'
                }
                if ($langMap.ContainsKey($langInput.Trim())) {
                    $config.language = $langMap[$langInput.Trim()]
                    Save-Config $config
                    Write-Host "Language set to: $($config.language)" -ForegroundColor Green
                }
            }
            '4' {
                Write-Host "Current: $(if ($config.unp4kPath) { $config.unp4kPath } else { '(auto-detect)' })" -ForegroundColor DarkGray
                Write-Host 'New unp4k path (blank for auto-detect): ' -NoNewline
                $newPath = Read-Host
                $newPath = $newPath.Trim('"', "'", ' ')
                if (-not $newPath) {
                    $config.unp4kPath = $null
                } else {
                    $config.unp4kPath = $newPath
                }
                Save-Config $config
                Write-Host 'Updated.' -ForegroundColor Green
            }
            '5' {
                $config.autoWrite = -not $config.autoWrite
                Save-Config $config
                Write-Host "Auto-write set to: $(if ($config.autoWrite) { 'Yes' } else { 'No' })" -ForegroundColor Green
            }
            'Q' { return }
            default { }
        }
    }
}
