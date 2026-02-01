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
    .PARAMETER Silent
        When set, skips informational output (used by auto workflow).
    .OUTPUTS
        Path to the installed unp4k.exe.
    #>
    param(
        [switch]$Silent
    )

    # Ensure TLS 1.2 for PS 5.1
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    if (-not $Silent) {
        Write-Host 'Downloading latest unp4k from GitHub...' -ForegroundColor Yellow
    }

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
        if (-not $Silent) {
            Write-Host "Downloading $($zipAsset.name) ($([math]::Round($zipAsset.size / 1MB, 1)) MB)..."
        }

        Invoke-WebRequest -Uri $zipAsset.browser_download_url -OutFile $zipPath -UseBasicParsing

        if (-not $Silent) { Write-Host 'Extracting...' }
        Expand-Archive -Path $zipPath -DestinationPath $toolsDir -Force
        Remove-Item $zipPath -Force

        # Find unp4k.exe in extracted files
        $exe = Get-ChildItem -Path $toolsDir -Filter 'unp4k.exe' -Recurse | Select-Object -First 1
        if ($exe) {
            if (-not $Silent) {
                Write-Host "Installed unp4k to: $($exe.FullName)" -ForegroundColor Green
            }

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

function Select-Environment {
    <#
    .SYNOPSIS
        Prompts for environment selection if multiple are configured.
    .OUTPUTS
        The selected environment string (e.g., LIVE, PTU, EPTU).
    #>
    $config = Read-Config
    if (-not $config) { return 'LIVE' }

    $envList = if ($config.environments) { $config.environments } else { @('LIVE') }

    if ($envList.Count -eq 1) {
        return $envList[0]
    }

    Write-Host 'Select environment:'
    for ($i = 0; $i -lt $envList.Count; $i++) {
        Write-Host "  $($i + 1). $($envList[$i])"
    }
    Write-Host "Selection [1]: " -NoNewline
    $envChoice = Read-Host
    if (-not $envChoice) { $envChoice = '1' }
    $idx = [int]$envChoice - 1
    if ($idx -ge 0 -and $idx -lt $envList.Count) {
        return $envList[$idx]
    }
    return $envList[0]
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

    $selectedEnv = Select-Environment
    Write-Host "Environment: $selectedEnv"
    Write-Host ''
    Invoke-ExtractGlobalIni -Environment $selectedEnv
}

function Invoke-Update {
    <#
    .SYNOPSIS
        Full patch update workflow: extract, version check, diff, backup, swap.
    .DESCRIPTION
        1. Reads current src/global.ini version
        2. Extracts fresh global.ini from Data.p4k
        3. Compares build versions
        4. Diffs old vs new (including conflict detection with target_strings.ini)
        5. Backs up old src/global.ini to cache/
        6. Replaces src/global.ini with the new extract
        7. Offers to re-merge
    .PARAMETER Environment
        The game environment (LIVE, PTU, EPTU).
    #>
    param(
        [string]$Environment = $null
    )

    $config = Read-Config
    if (-not $config -or -not $config.gameInstallPath) {
        Write-Error 'Game install path not configured. Run Settings first.'
        return $false
    }

    Write-Host ''
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host '         Patch Update' -ForegroundColor Cyan
    Write-Host '========================================' -ForegroundColor Cyan
    Write-Host ''

    # Select environment
    if (-not $Environment) {
        $Environment = Select-Environment
    }
    Write-Host "  Environment: $Environment" -ForegroundColor White

    $envPath = Join-Path $config.gameInstallPath $Environment
    $srcGlobalIni = Join-Path $script:ProjectRoot 'src\global.ini'

    # --- Step 1: Current version ---
    $oldVersion = 'unknown'
    if (Test-Path $srcGlobalIni) {
        foreach ($line in [System.IO.File]::ReadLines($srcGlobalIni)) {
            if ($line -match '^Frontend_PU_Version=(.+)$') {
                $oldVersion = $matches[1].Trim()
                break
            }
        }
    }
    Write-Host "  Current   : $oldVersion" -ForegroundColor DarkGray

    # --- Step 2: Check installed build version ---
    $buildVersion = Get-BuildVersion -EnvironmentPath $envPath
    Write-Host "  Installed : $buildVersion" -ForegroundColor White
    Write-Host ''

    # --- Step 3: Extract from Data.p4k ---
    $p4kPath = Join-Path $envPath 'Data.p4k'
    if (-not (Test-Path $p4kPath)) {
        Write-Error "Data.p4k not found at: $p4kPath"
        return $false
    }

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

    Write-Host 'Extracting fresh global.ini from Data.p4k...' -ForegroundColor Yellow

    $tempDir = Join-Path $env:TEMP "sc-merge-update-$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        $originalDir = Get-Location
        Set-Location $tempDir

        $proc = Start-Process -FilePath $unp4k `
            -ArgumentList "`"$p4kPath`" `"Data/Localization/english/global.ini`"" `
            -Wait -PassThru -NoNewWindow

        Set-Location $originalDir

        if ($proc.ExitCode -ne 0) {
            Write-Error "unp4k exited with code $($proc.ExitCode)"
            return $false
        }

        $extracted = Get-ChildItem -Path $tempDir -Filter 'global.ini' -Recurse | Select-Object -First 1
        if (-not $extracted) {
            Write-Error 'global.ini not found in extraction output.'
            return $false
        }

        # Read new version
        $newVersion = 'unknown'
        foreach ($line in [System.IO.File]::ReadLines($extracted.FullName)) {
            if ($line -match '^Frontend_PU_Version=(.+)$') {
                $newVersion = $matches[1].Trim()
                break
            }
        }

        Write-Host ''
        Write-Host "  Extracted : $newVersion" -ForegroundColor Green

        # --- Step 4: Version comparison ---
        if ($oldVersion -eq $newVersion) {
            Write-Host ''
            Write-Host '  Source global.ini is already this version.' -ForegroundColor DarkGray
            Write-Host '  Continue anyway? (y/N): ' -NoNewline
            $cont = Read-Host
            if ($cont -notmatch '^[Yy]') {
                Write-Host '  Update skipped.' -ForegroundColor Yellow
                return $false
            }
        } else {
            Write-Host "  Updating  : $oldVersion -> $newVersion" -ForegroundColor Cyan
        }

        # --- Step 5: Diff ---
        if (Test-Path $srcGlobalIni) {
            Write-Host ''
            Write-Host 'Comparing old and new global.ini...' -ForegroundColor Yellow

            # Load target strings for conflict detection
            $targetPath = Join-Path $script:ProjectRoot 'target_strings.ini'
            $targetKeys = @{}
            if (Test-Path $targetPath) {
                $targetData = Read-TargetStrings -Path $targetPath
                if ($targetData) {
                    $targetKeys = $targetData['Keys']
                }
            }

            $diff = Compare-GlobalIni -OldPath $srcGlobalIni -NewPath $extracted.FullName -TargetKeys $targetKeys

            if ($diff) {
                $addCount = $diff.AddedKeys.Count
                $removeCount = $diff.RemovedKeys.Count
                $changeCount = $diff.ChangedKeys.Count
                $conflictCount = $diff.Conflicts.Count

                Write-Host ''
                Write-Host '  Diff Summary:' -ForegroundColor Cyan
                Write-Host "    Added   : $addCount keys" -ForegroundColor Green
                Write-Host "    Removed : $removeCount keys" -ForegroundColor Red
                Write-Host "    Changed : $changeCount keys" -ForegroundColor Yellow
                if ($conflictCount -gt 0) {
                    Write-Host "    Conflicts: $conflictCount (your custom strings affected)" -ForegroundColor Magenta
                }

                # Show conflicts in detail
                if ($diff.Conflicts.Count -gt 0) {
                    Write-Host ''
                    Write-Host '  CONFLICTS (upstream changed keys you customized):' -ForegroundColor Magenta
                    foreach ($key in $diff.Conflicts.Keys) {
                        Write-Host "    $key" -ForegroundColor Magenta
                        Write-Host "      Was : $($diff.Conflicts[$key].Old)" -ForegroundColor DarkGray
                        Write-Host "      Now : $($diff.Conflicts[$key].New)" -ForegroundColor Yellow
                        Write-Host "      Yours: $($diff.Conflicts[$key].Custom)" -ForegroundColor Cyan
                    }
                }

                # Show removed custom keys
                if ($diff.RemovedCustomKeys.Count -gt 0) {
                    Write-Host ''
                    Write-Host '  REMOVED (these keys no longer exist):' -ForegroundColor Red
                    foreach ($key in $diff.RemovedCustomKeys.Keys) {
                        Write-Host "    $key" -ForegroundColor Red
                    }
                }

                # Offer full diff report
                if ($addCount + $removeCount + $changeCount -gt 0) {
                    Write-Host ''
                    Write-Host '  Show full diff report? (y/N): ' -NoNewline
                    $showFull = Read-Host
                    if ($showFull -match '^[Yy]') {
                        Write-DiffReport -Diff $diff
                    }
                }
            }
        }

        # --- Step 6: Backup old src/global.ini ---
        if (Test-Path $srcGlobalIni) {
            $cacheDir = Join-Path $script:ProjectRoot 'cache'
            if (-not (Test-Path $cacheDir)) {
                New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
            }

            # Name the backup with the old version
            $safeOldVersion = $oldVersion -replace '[^\w\.\-]', '_'
            $backupName = "$safeOldVersion-$Environment.ini"
            $backupPath = Join-Path $cacheDir $backupName

            if (-not (Test-Path $backupPath)) {
                Copy-Item $srcGlobalIni $backupPath -Force
                Write-Host ''
                Write-Host "  Backed up : cache/$backupName" -ForegroundColor Green
            } else {
                Write-Host ''
                Write-Host "  Backup    : cache/$backupName already exists" -ForegroundColor DarkGray
            }
        }

        # --- Step 7: Replace src/global.ini ---
        Copy-Item $extracted.FullName $srcGlobalIni -Force

        # Also cache the new version
        $cacheDir = Join-Path $script:ProjectRoot 'cache'
        if (-not (Test-Path $cacheDir)) {
            New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
        }
        $safeNewVersion = $newVersion -replace '[^\w\.\-]', '_'
        $newCacheName = "$safeNewVersion-$Environment.ini"
        $newCachePath = Join-Path $cacheDir $newCacheName
        Copy-Item $extracted.FullName $newCachePath -Force

        # Update config
        $config.lastBuildVersion = $buildVersion
        Save-Config $config

        Write-Host ''
        Write-Host "  Updated   : src/global.ini -> $newVersion" -ForegroundColor Green
        Write-Host "  Cached    : cache/$newCacheName" -ForegroundColor Green
        Write-Host ''

        # --- Step 8: Offer re-merge ---
        Write-Host '  Run merge now to apply your custom strings? (Y/n): ' -ForegroundColor Yellow -NoNewline
        $doMerge = Read-Host
        if ($doMerge -eq '' -or $doMerge -match '^[Yy]') {
            Invoke-Merge -Environment $Environment
        }

        return $true
    } catch {
        Write-Error "Update failed: $_"
        return $false
    } finally {
        if ($originalDir) { Set-Location $originalDir }
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Show-UpdateMenu {
    <#
    .SYNOPSIS
        Interactive update menu entry point.
    #>
    $config = Read-Config
    if (-not $config) {
        Write-Host 'No configuration found. Please run Settings first.' -ForegroundColor Yellow
        return
    }

    Invoke-Update
}

function Invoke-Auto {
    <#
    .SYNOPSIS
        One-command auto workflow: config, extract, version check, diff, backup, merge.
    .DESCRIPTION
        Non-interactive, always-forward flow. Only prompts if game path cannot
        be auto-detected on first run. Everything else proceeds silently.
    .PARAMETER Environment
        Override the environment (LIVE, PTU, EPTU). Defaults to first configured.
    #>
    param(
        [string]$Environment = $null
    )

    Write-Host ''
    Write-Host '  SC Localization Merge Tool' -ForegroundColor Cyan
    $dash = [char]0x2500  # ─
    Write-Host "  $($dash * 26)" -ForegroundColor Cyan
    Write-Host ''

    # --- Step 1: Config ---
    $config = Read-Config
    if (-not $config) {
        $config = Initialize-AutoConfig
        if (-not $config) {
            return
        }
    }

    if (-not $Environment) {
        $Environment = if ($config.environments -and $config.environments.Count -gt 0) {
            $config.environments[0]
        } else {
            'LIVE'
        }
    }

    $envPath = Join-Path $config.gameInstallPath $Environment
    if (-not (Test-Path $envPath)) {
        Write-Host "  Environment path not found: $envPath" -ForegroundColor Red
        Write-Host '  Run .\merge.ps1 -Settings to fix your game path.' -ForegroundColor Yellow
        return
    }

    Write-Host "  Environment : $Environment" -ForegroundColor White

    # Show installed build version
    $buildVersion = Get-BuildVersion -EnvironmentPath $envPath
    if ($buildVersion -ne 'unknown') {
        Write-Host "  Installed   : $buildVersion" -ForegroundColor White
    }

    # --- Step 2: Find or download unp4k ---
    $unp4k = Find-Unp4k
    if (-not $unp4k) {
        Write-Host ''
        Write-Host '  Downloading unp4k...' -ForegroundColor Yellow
        $unp4k = Install-Unp4k -Silent
        if (-not $unp4k) {
            Write-Host '  Failed to download unp4k. Run .\merge.ps1 -Settings to set the path manually.' -ForegroundColor Red
            return
        }
        Write-Host '  unp4k ready.' -ForegroundColor Green
    }

    # --- Step 3: Extract global.ini from Data.p4k ---
    $p4kPath = Join-Path $envPath 'Data.p4k'
    if (-not (Test-Path $p4kPath)) {
        Write-Host "  Data.p4k not found at: $p4kPath" -ForegroundColor Red
        return
    }

    $srcGlobalIni = Join-Path $script:ProjectRoot 'src\global.ini'

    # Read current version from src/global.ini
    $oldVersion = $null
    if (Test-Path $srcGlobalIni) {
        foreach ($line in [System.IO.File]::ReadLines($srcGlobalIni)) {
            if ($line -match '^Frontend_PU_Version=(.+)$') {
                $oldVersion = $matches[1].Trim()
                break
            }
        }
    }

    Write-Host ''
    Write-Host '  Extracting global.ini from Data.p4k...' -ForegroundColor Yellow

    $tempDir = Join-Path $env:TEMP "sc-merge-auto-$(Get-Date -Format 'yyyyMMddHHmmss')"
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    try {
        $originalDir = Get-Location
        Set-Location $tempDir

        $proc = Start-Process -FilePath $unp4k `
            -ArgumentList "`"$p4kPath`" `"Data/Localization/english/global.ini`"" `
            -Wait -PassThru -NoNewWindow

        Set-Location $originalDir

        if ($proc.ExitCode -ne 0) {
            Write-Host "  unp4k exited with code $($proc.ExitCode)" -ForegroundColor Red
            return
        }

        $extracted = Get-ChildItem -Path $tempDir -Filter 'global.ini' -Recurse | Select-Object -First 1
        if (-not $extracted) {
            Write-Host '  global.ini not found in extraction output.' -ForegroundColor Red
            return
        }

        # --- Step 4: Read extracted version ---
        $newVersion = $null
        foreach ($vLine in [System.IO.File]::ReadLines($extracted.FullName)) {
            if ($vLine -match '^Frontend_PU_Version=(.+)$') {
                $newVersion = $matches[1].Trim()
                break
            }
        }

        if ($newVersion) {
            Write-Host "  Extracted   : $newVersion" -ForegroundColor Green
        } else {
            Write-Host '  Extracted   : (version unknown)' -ForegroundColor Yellow
        }

        # --- Step 5: Version comparison and diff ---
        $isNewVersion = ($oldVersion -ne $newVersion) -and $oldVersion -and $newVersion

        if ($isNewVersion) {
            # Load target strings for conflict detection
            $targetPath = Join-Path $script:ProjectRoot 'target_strings.ini'
            $targetKeys = @{}
            if (Test-Path $targetPath) {
                $targetData = Read-TargetStrings -Path $targetPath
                if ($targetData) {
                    $targetKeys = $targetData['Keys']
                }
            }

            # Diff old vs new
            $diff = Compare-GlobalIni -OldPath $srcGlobalIni -NewPath $extracted.FullName -TargetKeys $targetKeys

            if ($diff) {
                # Extract short version numbers for display
                $oldShort = if ($oldVersion -match '(\d+\.\d+[\.\d]*)') { $matches[1] } else { $oldVersion }
                $newShort = if ($newVersion -match '(\d+\.\d+[\.\d]*)') { $matches[1] } else { $newVersion }

                Write-Host ''
                $arrow = [char]0x2192  # →
                Write-Host "  $([char]0x2500)$([char]0x2500) Patch Changes ($oldShort $arrow $newShort) $([char]0x2500)$([char]0x2500)" -ForegroundColor Cyan
                Write-Host "    Added   : $($diff.AddedKeys.Count.ToString('N0')) keys" -ForegroundColor Green
                Write-Host "    Removed : $($diff.RemovedKeys.Count.ToString('N0')) keys" -ForegroundColor Red
                Write-Host "    Changed : $($diff.ChangedKeys.Count.ToString('N0')) keys" -ForegroundColor Yellow

                # Conflicts with customizations
                Write-Host ''
                Write-Host "  $([char]0x2500)$([char]0x2500) Conflicts with your customizations $([char]0x2500)$([char]0x2500)" -ForegroundColor Cyan
                if ($diff.Conflicts.Count -gt 0) {
                    foreach ($key in $diff.Conflicts.Keys) {
                        Write-Host "    $key" -ForegroundColor Magenta
                        Write-Host "      Was  : $($diff.Conflicts[$key].Old)" -ForegroundColor DarkGray
                        Write-Host "      Now  : $($diff.Conflicts[$key].New)" -ForegroundColor Yellow
                        Write-Host "      Yours: $($diff.Conflicts[$key].Custom)" -ForegroundColor Cyan
                    }
                } else {
                    Write-Host '    (none)' -ForegroundColor DarkGray
                }

                # Orphaned custom keys
                Write-Host ''
                Write-Host "  $([char]0x2500)$([char]0x2500) Orphaned custom keys (removed upstream) $([char]0x2500)$([char]0x2500)" -ForegroundColor Cyan
                if ($diff.RemovedCustomKeys.Count -gt 0) {
                    foreach ($key in $diff.RemovedCustomKeys.Keys) {
                        Write-Host "    $key" -ForegroundColor Red
                    }
                } else {
                    Write-Host '    (none)' -ForegroundColor DarkGray
                }
            }

            # Backup old src/global.ini
            $cacheDir = Join-Path $script:ProjectRoot 'cache'
            if (-not (Test-Path $cacheDir)) {
                New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
            }

            $safeOldVersion = $oldVersion -replace '[^\w\.\-]', '_'
            $backupName = "$safeOldVersion-$Environment.ini"
            $backupPath = Join-Path $cacheDir $backupName

            Write-Host ''
            if (-not (Test-Path $backupPath)) {
                Copy-Item $srcGlobalIni $backupPath -Force
                Write-Host "  Backed up   : cache/$backupName" -ForegroundColor Green
            } else {
                Write-Host "  Backup      : cache/$backupName already exists" -ForegroundColor DarkGray
            }

            # Swap: copy extracted → src/global.ini
            Copy-Item $extracted.FullName $srcGlobalIni -Force

            # Cache the new version too
            $safeNewVersion = $newVersion -replace '[^\w\.\-]', '_'
            $newCacheName = "$safeNewVersion-$Environment.ini"
            $newCachePath = Join-Path $cacheDir $newCacheName
            Copy-Item $extracted.FullName $newCachePath -Force

            # Update config
            $config.lastBuildVersion = $buildVersion
            Save-Config $config

            $newShortDisplay = if ($newVersion -match '(\d+\.\d+[\.\d]*)') { $matches[1] } else { $newVersion }
            Write-Host "  Updated     : src/global.ini $arrow $newShortDisplay" -ForegroundColor Green

        } elseif (-not $oldVersion) {
            # No existing src/global.ini — first extraction
            Copy-Item $extracted.FullName $srcGlobalIni -Force

            $cacheDir = Join-Path $script:ProjectRoot 'cache'
            if (-not (Test-Path $cacheDir)) {
                New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
            }
            if ($newVersion) {
                $safeNewVersion = $newVersion -replace '[^\w\.\-]', '_'
                $newCacheName = "$safeNewVersion-$Environment.ini"
                Copy-Item $extracted.FullName (Join-Path $cacheDir $newCacheName) -Force
            }

            $config.lastBuildVersion = $buildVersion
            Save-Config $config

            Write-Host ''
            Write-Host '  Source      : src/global.ini created' -ForegroundColor Green

        } else {
            # Same version
            Write-Host ''
            Write-Host '  Already up to date.' -ForegroundColor DarkGray
        }

        # --- Step 7: Merge ---
        Write-Host ''
        Write-Host "  $([char]0x2500)$([char]0x2500) Merging translations $([char]0x2500)$([char]0x2500)" -ForegroundColor Cyan

        $targetStringsPath = Join-Path $script:ProjectRoot 'target_strings.ini'
        $globalIniPath = Join-Path $script:ProjectRoot 'src\global.ini'
        $mergedIniPath = Join-Path $script:ProjectRoot 'output\merged.ini'

        if (-not (Test-Path $targetStringsPath)) {
            Write-Host '    No target_strings.ini found. Skipping merge.' -ForegroundColor Yellow
            Write-Host ''
            Write-Host '  Done.' -ForegroundColor Cyan
            return
        }
        if (-not (Test-Path $globalIniPath)) {
            Write-Host '    No src/global.ini found. Skipping merge.' -ForegroundColor Yellow
            Write-Host ''
            Write-Host '  Done.' -ForegroundColor Cyan
            return
        }

        # Ensure output directory
        $outputDir = Split-Path $mergedIniPath -Parent
        if (-not (Test-Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }

        # Load replacements
        $targetData = Read-TargetStrings -Path $targetStringsPath
        $replacements = $targetData['Keys']

        # Process line by line
        $mergedKeys = @{}
        $mergeCount = 0
        $processedLines = [System.Collections.Generic.List[string]]::new()

        foreach ($srcLine in [System.IO.File]::ReadLines($globalIniPath)) {
            if ($srcLine -match '^(.*?)(=)(.*)$') {
                $key = $matches[1].Trim()
                $prefix = $srcLine.Substring(0, $srcLine.IndexOf('=') + 1)
                if ($replacements.Contains($key)) {
                    $processedLines.Add($prefix + $replacements[$key])
                    $mergedKeys[$key] = $true
                    $mergeCount++
                } else {
                    $processedLines.Add($srcLine)
                }
            } else {
                $processedLines.Add($srcLine)
            }
        }

        # Detect orphans
        $orphanedKeys = @()
        foreach ($key in $replacements.Keys) {
            if (-not $mergedKeys.ContainsKey($key)) {
                $orphanedKeys += $key
            }
        }

        # Write output with UTF-8 BOM
        $utf8Bom = [System.Text.UTF8Encoding]::new($true)
        [System.IO.File]::WriteAllLines($mergedIniPath, $processedLines.ToArray(), $utf8Bom)

        Write-Host "    Merged  : $mergeCount / $($replacements.Count) strings" -ForegroundColor Green
        Write-Host "    Output  : output/merged.ini" -ForegroundColor Green

        # Write to game folder if configured
        $language = if ($config.language) { $config.language } else { 'english' }
        if ($config.autoWrite -and $config.gameInstallPath) {
            $gameIniPath = Join-Path $config.gameInstallPath "$Environment\data\Localization\$language\global.ini"
            $gameLocDir = Split-Path $gameIniPath -Parent
            if (-not (Test-Path $gameLocDir)) {
                New-Item -ItemType Directory -Path $gameLocDir -Force | Out-Null
            }
            [System.IO.File]::WriteAllLines($gameIniPath, $processedLines.ToArray(), $utf8Bom)
            Write-Host "    Game    : Written to $Environment/$language folder" -ForegroundColor Green

            # Ensure user.cfg
            $userCfgStatus = Ensure-UserCfg -EnvironmentPath $envPath -Language $language
            if ($userCfgStatus -eq 'created') {
                Write-Host "    Config  : user.cfg created with g_language = $language" -ForegroundColor Green
            } elseif ($userCfgStatus -eq 'updated') {
                Write-Host "    Config  : user.cfg updated with g_language = $language" -ForegroundColor Green
            } elseif ($userCfgStatus -eq 'ok') {
                Write-Host "    Config  : user.cfg already correct" -ForegroundColor DarkGray
            }
        }

        if ($orphanedKeys.Count -gt 0) {
            Write-Host ''
            Write-Host "  Orphaned keys ($($orphanedKeys.Count)):" -ForegroundColor Yellow
            Write-Host '  These keys are in target_strings.ini but not in global.ini.' -ForegroundColor Yellow
            foreach ($key in $orphanedKeys) {
                Write-Host "    - $key" -ForegroundColor Yellow
            }
        }

        Write-Host ''
        Write-Host '  Done.' -ForegroundColor Cyan
        Write-Host ''

    } catch {
        Write-Host "  Auto workflow failed: $_" -ForegroundColor Red
    } finally {
        if ($originalDir) { Set-Location $originalDir }
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
