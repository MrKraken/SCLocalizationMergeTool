##################
# Extract.ps1 — Data.p4k extraction pipeline
# Finds/installs unp4k, extracts global.ini, manages cached versions
##################

function Find-Unp4k {
    <#
    .SYNOPSIS
        Locates unp4k.exe using multiple search strategies.
    .OUTPUTS
        Path to unp4k.exe, or $null if not found.
    #>
    $config = Read-Config

    # 1. Config path
    if ($config -and $config.unp4kPath -and (Test-Path $config.unp4kPath)) {
        return $config.unp4kPath
    }

    # 2. tools/ folder in project
    $toolsPath = Join-Path $script:ProjectRoot 'tools'
    $candidates = @(
        (Join-Path $toolsPath 'unp4k.exe'),
        (Join-Path $toolsPath 'unp4k\unp4k.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }

    # 3. System PATH
    $inPath = Get-Command 'unp4k.exe' -ErrorAction SilentlyContinue
    if ($inPath) { return $inPath.Source }

    # 4. Common locations
    $commonPaths = @(
        (Join-Path $env:USERPROFILE 'Downloads\unp4k.exe'),
        (Join-Path $env:USERPROFILE 'Downloads\unp4k\unp4k.exe'),
        (Join-Path $env:USERPROFILE 'Desktop\unp4k.exe'),
        (Join-Path $env:USERPROFILE 'Desktop\unp4k\unp4k.exe'),
        'C:\Program Files\unp4k\unp4k.exe',
        'C:\Tools\unp4k\unp4k.exe'
    )
    foreach ($path in $commonPaths) {
        if (Test-Path $path) { return $path }
    }

    return $null
}

function Install-Unp4k {
    <#
    .SYNOPSIS
        Downloads the latest unp4k release from GitHub to tools/.
    .OUTPUTS
        Path to the installed unp4k.exe.
    #>
    # Ensure TLS 1.2 for PS 5.1
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    Write-Host 'Downloading latest unp4k from GitHub...' -ForegroundColor Yellow

    try {
        $releaseUrl = 'https://api.github.com/repos/dolkensp/unp4k/releases/latest'
        $release = Invoke-RestMethod -Uri $releaseUrl -Headers @{ 'User-Agent' = 'SCLocalizationMergeTool' }

        # Find the zip asset
        $zipAsset = $release.assets | Where-Object { $_.name -match '\.zip$' } | Select-Object -First 1
        if (-not $zipAsset) {
            Write-Error 'No zip asset found in latest unp4k release.'
            return $null
        }

        $toolsDir = Join-Path $script:ProjectRoot 'tools'
        if (-not (Test-Path $toolsDir)) {
            New-Item -ItemType Directory -Path $toolsDir -Force | Out-Null
        }

        $zipPath = Join-Path $toolsDir 'unp4k.zip'
        Write-Host "Downloading $($zipAsset.name) ($([math]::Round($zipAsset.size / 1MB, 1)) MB)..."

        Invoke-WebRequest -Uri $zipAsset.browser_download_url -OutFile $zipPath -UseBasicParsing

        Write-Host 'Extracting...'
        Expand-Archive -Path $zipPath -DestinationPath $toolsDir -Force
        Remove-Item $zipPath -Force

        # Find unp4k.exe in extracted files
        $exe = Get-ChildItem -Path $toolsDir -Filter 'unp4k.exe' -Recurse | Select-Object -First 1
        if ($exe) {
            Write-Host "Installed unp4k to: $($exe.FullName)" -ForegroundColor Green

            # Save to config
            $config = Read-Config
            if ($config) {
                $config.unp4kPath = $exe.FullName
                Save-Config $config
            }

            return $exe.FullName
        }

        Write-Error 'unp4k.exe not found in downloaded archive.'
        return $null
    } catch {
        Write-Error "Failed to download unp4k: $_"
        return $null
    }
}

function Get-BuildVersion {
    <#
    .SYNOPSIS
        Determines the current Star Citizen build version.
    .PARAMETER EnvironmentPath
        Path to the environment folder (e.g., LIVE, PTU).
    .OUTPUTS
        Version string, or 'unknown'.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$EnvironmentPath
    )

    # 1. build_manifest.id
    $manifestPath = Join-Path $EnvironmentPath 'build_manifest.id'
    if (Test-Path $manifestPath) {
        try {
            $manifest = [System.IO.File]::ReadAllText($manifestPath) | ConvertFrom-Json
            if ($manifest.Data -and $manifest.Data.BuildId) {
                return $manifest.Data.BuildId
            }
            if ($manifest.BuildId) {
                return $manifest.BuildId
            }
        } catch {
            # Try plain text
            $text = [System.IO.File]::ReadAllText($manifestPath).Trim()
            if ($text -match '\d+\.\d+') {
                return $text
            }
        }
    }

    # 2. Game.log regex
    $gameLog = Join-Path $EnvironmentPath 'Game.log'
    if (Test-Path $gameLog) {
        try {
            $logHead = [System.IO.File]::ReadLines($gameLog) |
                Select-Object -First 50 |
                Out-String
            if ($logHead -match 'Branch\s*:\s*sc-alpha-(\S+)') {
                return $matches[1]
            }
            if ($logHead -match 'Version\s*:\s*(\S+)') {
                return $matches[1]
            }
        } catch { }
    }

    # 3. Frontend_PU_Version from global.ini in src/
    $srcIni = Join-Path $script:ProjectRoot 'src\global.ini'
    if (Test-Path $srcIni) {
        foreach ($line in [System.IO.File]::ReadLines($srcIni)) {
            if ($line -match '^Frontend_PU_Version=(.+)$') {
                $ver = $matches[1].Trim()
                # Extract version number if it contains extra text
                if ($ver -match '(\d+\.\d+[\.\d]*)') {
                    return $matches[1]
                }
                return $ver
            }
        }
    }

    return 'unknown'
}

function Invoke-ExtractGlobalIni {
    <#
    .SYNOPSIS
        Extracts global.ini from Data.p4k using unp4k.
    .PARAMETER Environment
        The environment to extract from (LIVE, PTU, EPTU).
    #>
    param(
        [string]$Environment = 'LIVE'
    )

    $config = Read-Config
    if (-not $config -or -not $config.gameInstallPath) {
        Write-Error 'Game install path not configured. Run Settings first.'
        return $false
    }

    $envPath = Join-Path $config.gameInstallPath $Environment
    if (-not (Test-Path $envPath)) {
        Write-Error "Environment path not found: $envPath"
        return $false
    }

    $p4kPath = Join-Path $envPath 'Data.p4k'
    if (-not (Test-Path $p4kPath)) {
        Write-Error "Data.p4k not found at: $p4kPath"
        return $false
    }

    # Find or install unp4k
    $unp4k = Find-Unp4k
    if (-not $unp4k) {
        Write-Host 'unp4k not found on your system.' -ForegroundColor Yellow
        Write-Host 'Would you like to download it? (Y/n): ' -NoNewline
        $confirm = Read-Host
        if ($confirm -eq '' -or $confirm -match '^[Yy]') {
            $unp4k = Install-Unp4k
        }
        if (-not $unp4k) {
            Write-Error 'Cannot extract without unp4k. Please install it manually.'
            return $false
        }
    }

    # Extract to temp directory
    $tempDir = Join-Path $env:TEMP "sc-merge-extract-$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    Write-Host "Extracting global.ini from $Environment Data.p4k..." -ForegroundColor Yellow
    Write-Host "Using unp4k: $unp4k"

    try {
        $originalDir = Get-Location
        Set-Location $tempDir

        $proc = Start-Process -FilePath $unp4k `
            -ArgumentList "`"$p4kPath`" `"Data/Localization/english/global.ini`"" `
            -Wait -PassThru -NoNewWindow

        Set-Location $originalDir

        if ($proc.ExitCode -ne 0) {
            Write-Error "unp4k exited with code $($proc.ExitCode)"
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            return $false
        }

        # Find the extracted file
        $extracted = Get-ChildItem -Path $tempDir -Filter 'global.ini' -Recurse | Select-Object -First 1
        if (-not $extracted) {
            Write-Error 'global.ini not found in extraction output.'
            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            return $false
        }

        # Get build version
        $version = Get-BuildVersion -EnvironmentPath $envPath

        # Cache the file
        $cacheDir = Join-Path $script:ProjectRoot 'cache'
        if (-not (Test-Path $cacheDir)) {
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
        }
        $cacheName = "$version-$Environment.ini"
        $cachePath = Join-Path $cacheDir $cacheName
        Copy-Item $extracted.FullName $cachePath -Force

        # Also copy to src/global.ini
        $srcPath = Join-Path $script:ProjectRoot 'src\global.ini'
        Copy-Item $extracted.FullName $srcPath -Force

        # Update config
        $config.lastBuildVersion = $version
        Save-Config $config

        Write-Host ''
        Write-Host "Extraction complete!" -ForegroundColor Green
        Write-Host "  Version : $version"
        Write-Host "  Cached  : cache/$cacheName"
        Write-Host "  Source  : src/global.ini (updated)"
        Write-Host ''

        return $true
    } catch {
        Write-Error "Extraction failed: $_"
        return $false
    } finally {
        if ($originalDir) { Set-Location $originalDir }
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-CachedVersions {
    <#
    .SYNOPSIS
        Lists cached global.ini versions from the cache/ directory.
    .OUTPUTS
        Array of objects with Name, Version, Environment, Path, and LastWriteTime.
    #>
    $cacheDir = Join-Path $script:ProjectRoot 'cache'
    if (-not (Test-Path $cacheDir)) {
        return @()
    }

    $files = Get-ChildItem -Path $cacheDir -Filter '*.ini' | Sort-Object LastWriteTime -Descending
    $versions = @()

    foreach ($file in $files) {
        $name = [System.IO.Path]::GetFileNameWithoutExtension($file.Name)
        $parts = $name -split '-', 2
        $version = if ($parts.Count -ge 1) { $parts[0] } else { 'unknown' }
        $env = if ($parts.Count -ge 2) { $parts[1] } else { 'unknown' }

        $versions += [PSCustomObject]@{
            Name          = $file.Name
            Version       = $version
            Environment   = $env
            Path          = $file.FullName
            LastWriteTime = $file.LastWriteTime
        }
    }

    return $versions
}

function Show-ExtractMenu {
    <#
    .SYNOPSIS
        Interactive extraction menu.
    #>
    $config = Read-Config
    if (-not $config) {
        Write-Host 'No configuration found. Please run Settings first.' -ForegroundColor Yellow
        return
    }

    Write-Host ''
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host '        Extract global.ini' -ForegroundColor Cyan
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host ''

    # Show cached versions
    $cached = Get-CachedVersions
    if ($cached.Count -gt 0) {
        Write-Host 'Cached versions:' -ForegroundColor DarkGray
        foreach ($v in $cached) {
            Write-Host "  $($v.Name) - $($v.LastWriteTime.ToString('yyyy-MM-dd HH:mm'))" -ForegroundColor DarkGray
        }
        Write-Host ''
    }

    # List available environments
    if ($config.environments) {
        $envList = $config.environments
    } else {
        $envList = @('LIVE')
    }

    if ($envList.Count -eq 1) {
        $selectedEnv = $envList[0]
        Write-Host "Environment: $selectedEnv"
    } else {
        Write-Host 'Select environment:'
        for ($i = 0; $i -lt $envList.Count; $i++) {
            Write-Host "  $($i + 1). $($envList[$i])"
        }
        Write-Host "Selection [1]: " -NoNewline
        $envChoice = Read-Host
        if (-not $envChoice) { $envChoice = '1' }
        $idx = [int]$envChoice - 1
        if ($idx -ge 0 -and $idx -lt $envList.Count) {
            $selectedEnv = $envList[$idx]
        } else {
            $selectedEnv = $envList[0]
        }
    }

    Write-Host ''
    Invoke-ExtractGlobalIni -Environment $selectedEnv
}
