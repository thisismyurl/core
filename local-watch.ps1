# 1. Configuration
$ParentPath = "C:\Users\Owner\Local Sites\thisismyurlcom\app\public\wp-content\plugins"
$MasterCoreFolderName = "core"
$MasterCorePath = Join-Path $ParentPath $MasterCoreFolderName

# Load Shared List from plugins.json
$PluginListPath = Join-Path $PSScriptRoot "plugins.json"
if (Test-Path $PluginListPath) {
    $Plugins = Get-Content $PluginListPath -Raw | ConvertFrom-Json
} else {
    Write-Host "Error: plugins.json not found!" -ForegroundColor Red; exit
}

# Global variables for background/foreground hand-off
$Global:SyncPending = $false
$Global:PendingData = @{}

# Helper: Local Image Processing using ImageMagick
function Optimize-PluginAssets {
    param ([string]$AssetDir)
    
    $IconSource = Join-Path $AssetDir "icon-512x512.png"
    $BannerSource = Join-Path $AssetDir "banner-1544x500.png"

    # Generate Icons: 256x256, 128x128, 64x64
    if (Test-Path $IconSource) {
        Write-Host "    Processing Icons..." -ForegroundColor Gray
        & magick $IconSource -resize 256x256 $(Join-Path $AssetDir "icon-256x256.png")
        & magick $IconSource -resize 128x128 $(Join-Path $AssetDir "icon-128x128.png")
        & magick $IconSource -resize 64x64 $(Join-Path $AssetDir "icon-64x64.png")
    }

    # Generate Banner: 772x250
    if (Test-Path $BannerSource) {
        Write-Host "    Processing Banner..." -ForegroundColor Gray
        & magick $BannerSource -resize 772x250 $(Join-Path $AssetDir "banner-772x250.png")
    }
}

# 2. Reusable Sync Function
function Sync-CoreAssets {
    param (
        [string]$TriggerFile = "Manual Startup",
        [bool]$IsMasterCoreChange = $true,
        [array]$ActiveTargets = @()
    )

    $NewVersion = "1." + (Get-Date).ToString("yyMMddHH")
    Write-Host "`n[Syncing Files]: $TriggerFile" -ForegroundColor Yellow
    
    # Update internal Master Core headers recursively
    if ($IsMasterCoreChange) {
        Write-Host "  Updating Master Core version headers..." -ForegroundColor Gray
        Get-ChildItem -Path $MasterCorePath -Filter *.php -Recurse | ForEach-Object {
            $C = Get-Content $_.FullName
            if ($C -match '\$version\s*=\s*[''"][0-9.]+[''"]') {
                $C -replace '(\$version\s*=\s*[''"])([0-9.]+)([''"])', "`${1}$NewVersion`${3}" | Set-Content $_.FullName
            }
        }
        Get-ChildItem -Path $MasterCorePath -Include *.js, *.css -Recurse | ForEach-Object {
            $C = Get-Content $_.FullName
            if ($C -match '\*\s*Version:\s*[0-9.]+') {
                $C -replace '(\*\s*Version:\s*)([0-9.]+)', "`${1}$NewVersion" | Set-Content $_.FullName
            }
        }
    }

    foreach ($Plugin in $ActiveTargets) {
        $PluginDir = Join-Path $ParentPath $Plugin
        $CoreDest = Join-Path $PluginDir "core"
        $GithubSource = Join-Path $MasterCorePath ".github"
        $GithubDest = Join-Path $PluginDir ".github"
        $MainPhpFile = Join-Path $PluginDir "$Plugin.php"
        $ReadmeFile = Join-Path $PluginDir "readme.txt"
        $AssetDir = Join-Path $PluginDir "assets"

        if (Test-Path $PluginDir) {
            Write-Host "  Syncing: $Plugin" -ForegroundColor Cyan
            
            # --- 1. Sync Core folder ---
            if ($IsMasterCoreChange) {
                if (![string]::IsNullOrWhiteSpace($CoreDest) -and (Test-Path -LiteralPath $CoreDest)) { 
                    Remove-Item -LiteralPath $CoreDest -Recurse -Force -ErrorAction SilentlyContinue 
                }
                New-Item -ItemType Directory -Path $CoreDest -Force | Out-Null
                Copy-Item -Path "$MasterCorePath\*" -Destination $CoreDest -Recurse -Force -Exclude ".git*", ".github*", "*.ps1"
            }

            # --- 2. Sync and Personalize .github folder ---
            if ($IsMasterCoreChange -and (Test-Path $GithubSource)) {
                if (Test-Path $GithubDest) { Remove-Item $GithubDest -Recurse -Force -ErrorAction SilentlyContinue }
                Copy-Item -Path $GithubSource -Destination $GithubDest -Recurse -Force
                
                # Update foldername and name inside the .github files
                Get-ChildItem -Path $GithubDest -File -Recurse | ForEach-Object {
                    (Get-Content $_.FullName) `
                        -replace '{{PLUGIN_SLUG}}', $Plugin `
                        -replace '{{PLUGIN_NAME}}', ($Plugin -replace '-', ' ' | ForEach-Object { (Get-Culture).TextInfo.ToTitleCase($_) }) `
                        | Set-Content $_.FullName
                }
            }

            # --- 3. Process Images locally ---
            if (Test-Path $AssetDir) {
                Optimize-PluginAssets -AssetDir $AssetDir
            }

            # --- 4. Update Versioning (Readme Changelog update removed) ---
            if (Test-Path $MainPhpFile) {
                (Get-Content $MainPhpFile) -replace '(Version:\s+)([0-9.]+)', "`${1}$NewVersion" | Set-Content $MainPhpFile
            }
            if (Test-Path $ReadmeFile) {
                # Only update the Stable tag; do not append to Changelog
                (Get-Content $ReadmeFile) -replace '(Stable tag:\s+)([0-9.]+)', "`${1}$NewVersion" | Set-Content $ReadmeFile
            }
        }
    }
    Write-Host "`nSync Complete. Local files updated to v$NewVersion." -ForegroundColor Green
}

# 3. BOOTSTRAP
Write-Host "--- Initializing Script: Performing Startup Sync ---" -ForegroundColor Cyan
Sync-CoreAssets -TriggerFile "Initial Launch" -ActiveTargets $Plugins

# 4. Watcher Setup
$Watcher = New-Object System.IO.FileSystemWatcher
$Watcher.Path = $ParentPath
$Watcher.IncludeSubdirectories = $true
$Watcher.EnableRaisingEvents = $true

$Action = {
    $ChangedPath = $Event.SourceEventArgs.FullPath
    if ($ChangedPath -match '\.git' -or $ChangedPath -match '\.ps1$') { return }

    $IsMasterCoreChange = $ChangedPath.StartsWith($MasterCorePath + "\") -or ($ChangedPath -eq $MasterCorePath)
    $Targets = if ($IsMasterCoreChange) { $Plugins } else { $Plugins | Where-Object { $ChangedPath -like "*\$_*" } }

    if ($Targets) {
        $Global:PendingData = @{
            Trigger = $Event.SourceEventArgs.Name
            Master  = $IsMasterCoreChange
            Targets = $Targets
        }
        $Global:SyncPending = $true
    }
}

Register-ObjectEvent $Watcher "Changed" -Action $Action

Write-Host "`n--- Monitoring Active (Main Loop Control) ---" -ForegroundColor Cyan
while ($true) {
    if ($Global:SyncPending) {
        Sync-CoreAssets -TriggerFile $Global:PendingData.Trigger `
                        -IsMasterCoreChange $Global:PendingData.Master `
                        -ActiveTargets $Global:PendingData.Targets
        $Global:SyncPending = $false
    }
    Start-Sleep -Milliseconds 500
}