##################
# String processing file - Originally from /u/Asphalt_Expert's component stats language pack_ https://github.com/ExoAE/ScCompLangPack/blob/main/merge-process/merge-ini.ps1
# Given a bit of piss and vinegar by MrKraken (https://www.youtube.com/@MrKraken)
# Merges translations from target_strings.ini into global.ini and saves as merged.ini in the same directory as well as the defined global.ini game path
##################

# User config - you can change these values
$gameInstallPath = 'C:\Program Files\Roberts Space Industries\StarCitizen\LIVE' # Set your game installation path here
$gameIniWrite = $false # Set to $true if you want to write directly to the game folder


################## !!!! ##################
# YOU SHOULD NOT NEED TO EDIT BELOW THIS LINE
################## !!!! ##################

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path # Get the script directory
$targetStringsPath = Join-Path $scriptDir 'target_strings.ini' # input file
$globalIniPath = Join-Path $scriptDir 'src\global.ini' # source file from Data.p4k
$mergedIniPath = Join-Path $scriptDir 'output\merged.ini' # Output file

# Check if files exist first, make folders for outpuits if we need them
if (-not (Test-Path $targetStringsPath)) {
    Write-Error "target_strings.ini not found at: $targetStringsPath"
    exit 1
}
if (-not (Test-Path $globalIniPath)) {
    Write-Error "global.ini not found at: $globalIniPath"
    exit 1
}
if (-not (Test-Path $gameInstallPath)) {
    Write-Error "Directory not found: $gameInstallPath"
    exit 1
}
$outputDir = Split-Path $mergedIniPath -Parent
if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    Write-Host "Created output directory: $outputDir"
}
$gameIniPath = Join-Path $gameInstallPath 'data\Localization\english\global.ini' # now we know the install folder is valid we can stitch on the localization path
if ($gameIniWrite) {
    $gameLocalizationDir = Split-Path $gameIniPath -Parent
    if (-not (Test-Path $gameLocalizationDir)) {
        New-Item -ItemType Directory -Path $gameLocalizationDir -Force | Out-Null
        Write-Host "Created game localization directory: $gameLocalizationDir"
    }
}
# Load target_strings.ini into a hashtable (key -> new value)
$replacements = @{}
Get-Content $targetStringsPath | ForEach-Object {
    if ($_ -match '^(.*?)=(.*)$') {
        $key = $matches[1].Trim()
        $value = $matches[2]
        $replacements[$key] = $value
    }
}
# Process global.ini line by line and only replace values for keys found in the hashtable
$processedContent = Get-Content $globalIniPath | ForEach-Object {
    if ($_ -match '^(.*?)(=)(.*)$') {
        $key = $matches[1].Trim()
        $prefix = $_.Substring(0, $_.IndexOf('=') + 1) # Keep everything up to and including '=' (including spaces)
        if ($replacements.ContainsKey($key)) {
            $prefix + $replacements[$key]
        }
        else {
            $_
        }
    }
    else {
        $_  # Blank lines / comments etc. remain untouched
    }
}

# Write to merged.ini and game folder if it's wanted
$processedContent | Set-Content $mergedIniPath -Encoding UTF8
if ($gameIniWrite) {
    $processedContent | Set-Content $gameIniPath -Encoding UTF8
}
