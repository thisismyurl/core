# 1. Configuration
$ParentPath = "C:\Users\Owner\Local Sites\thisismyurlcom\app\public\wp-content\plugins"
$MasterCoreFolderName = "core" 
$MasterCorePath = Join-Path $ParentPath $MasterCoreFolderName
$GitCmd = "C:\Users\Owner\AppData\Local\GitHubDesktop\app-3.5.4\resources\app\git\cmd\git.exe"

$Plugins = @(
    "avif-support-thisismyurl",
    "heic-support-thisismyurl",
    "media-support-thisismyurl",
    "link-support-thisismyurl",
    "svg-support-thisismyurl",
    "webp-support-thisismyurl"
)

# Global variables to handle the hand-off from background to foreground
$Global:SyncPending = $false
$Global:PendingData = @{}

# 2. Reusable Sync Function
function Sync-CoreAssets {
    param (
        [string]$TriggerFile = "Manual Startup",
        [bool]$IsMasterCoreChange = $true,
        [array]$ActiveTargets = @()
    )

    $NewVersion = "1." + (Get-Date).ToString("yyMMddHH")
    Write-Host "`n[Processing]: $TriggerFile" -ForegroundColor Yellow
    
    # Update internal Master Core headers recursively
    if ($IsMasterCoreChange) {
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
        $Destination = Join-Path $PluginDir "core"
        $MainPhpFile = Join-Path $PluginDir "$Plugin.php"
        $ReadmeFile = Join-Path $PluginDir "readme.txt"

        if (Test-Path $PluginDir) {
            # Sync Core folder
            if ($IsMasterCoreChange) {
                if (Test-Path $Destination) { Remove-Item $Destination -Recurse -Force -ErrorAction SilentlyContinue }
                New-Item -ItemType Directory -Path $Destination -Force | Out-Null
                Copy-Item -Path "$MasterCorePath\*" -Destination $Destination -Recurse -Force -Exclude ".git*", "*.ps1"
            }

            # Update Plugin Version and Readme
            if (Test-Path $MainPhpFile) {
                (Get-Content $MainPhpFile) -replace '(Version:\s+)([0-9.]+)', "`${1}$NewVersion" | Set-Content $MainPhpFile
            }
            if (Test-Path $ReadmeFile) {
                $ReadmeContent = Get-Content $ReadmeFile
                $ReadmeContent = $ReadmeContent -replace '(Stable tag:\s+)([0-9.]+)', "`${1}$NewVersion"
                $Entry = "`n= $NewVersion =`n* Core hierarchy updated via $TriggerFile"
                $ReadmeContent = $ReadmeContent -replace '(== Changelog ==)', "`$1`n$Entry"
                $ReadmeContent | Set-Content $ReadmeFile
            }
        }
    }

    # --- TIMED COMMIT PROMPT (3s) ---
    # This now runs in the main thread, so it won't jam.
    Write-Host "`nSync Complete. Commit all changes? (y/N) [3s timeout]: " -NoNewline -ForegroundColor White
    $timeout = 3
    $CommitDecision = $false
    
    while ($timeout -gt 0 -and -not [Console]::KeyAvailable) {
        Start-Sleep -Seconds 1
        $timeout--
    }

    if ([Console]::KeyAvailable) {
        $Key = [Console]::ReadKey($true)
        if ($Key.KeyChar -eq 'y') { $CommitDecision = $true }
    }

    if ($CommitDecision) {
        Write-Host "`nCommitting updates..." -ForegroundColor Cyan
        foreach ($Plugin in $ActiveTargets) {
            $PluginDir = Join-Path $ParentPath $Plugin
            if (Test-Path (Join-Path $PluginDir ".git")) {
                Push-Location $PluginDir
                if (& $GitCmd status --porcelain) {
                    & $GitCmd add .
                    & $GitCmd commit -m "Build ${NewVersion}: Update via ${TriggerFile}" --quiet
                    Write-Host "  ${Plugin}: Changes committed locally." -ForegroundColor Cyan
                }
                Pop-Location
            }
        }

        # --- PUSH PROMPT (Only if committed) ---
        Write-Host "Push all changes to GitHub? (y/N): " -NoNewline -ForegroundColor White
        $PushResponse = Read-Host
        if ($PushResponse -eq 'y') {
            Write-Host "Pushing updates..." -ForegroundColor Magenta
            foreach ($Plugin in $ActiveTargets) {
                $PluginDir = Join-Path $ParentPath $Plugin
                if (Test-Path (Join-Path $PluginDir ".git")) {
                    Push-Location $PluginDir
                    & $GitCmd push origin main --quiet
                    Pop-Location
                    Write-Host "  ${Plugin}: Pushed successfully." -ForegroundColor Gray
                }
            }
        }
    } else {
        Write-Host "`nSkipping Git operations. Resuming monitor..." -ForegroundColor Gray
    }
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
    # Ignore git and script files
    if ($ChangedPath -match '\.git' -or $ChangedPath -match '\.ps1$') { return }

    $IsMasterCoreChange = $ChangedPath.StartsWith($MasterCorePath + "\") -or ($ChangedPath -eq $MasterCorePath)
    $Targets = if ($IsMasterCoreChange) { $Plugins } else { $Plugins | Where-Object { $ChangedPath -like "*\$_*" } }

    # Instead of running logic here, we signal the main loop
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
    # Check if the background watcher flagged a change
    if ($Global:SyncPending) {
        Sync-CoreAssets -TriggerFile $Global:PendingData.Trigger `
                        -IsMasterCoreChange $Global:PendingData.Master `
                        -ActiveTargets $Global:PendingData.Targets
        # Reset flag
        $Global:SyncPending = $false
    }
    
    # Small sleep to keep CPU usage low while waiting for flags
    Start-Sleep -Milliseconds 500
}