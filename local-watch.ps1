# Configuration
$LocalPluginsPath = "C:\Users\Owner\Local Sites\thisismyurlcom\app\public\wp-content\plugins"
$Plugins = @(
    "avif-support-thisismyurl",
    "heic-support-thisismyurl",
    "image-support-thisismyurl",
    "link-support-thisismyurl",
    "svg-support-thisismyurl",
    "webp-support-thisismyurl"
)

# The Logic
$Watcher = New-Object System.IO.FileSystemWatcher
$Watcher.Path = Get-Location
$Watcher.IncludeSubdirectories = $true
$Watcher.EnableRaisingEvents = $true

Write-Host "--- Watching for changes in Master Core ---" -ForegroundColor Cyan

$Action = {
    $ChangedPath = $Event.SourceEventArgs.FullPath
    
    # Ignore the script itself and .git folder
    if ($ChangedPath -notmatch '\.ps1$' -and $ChangedPath -notmatch '\.git') {
        $FileName = $Event.SourceEventArgs.Name
        Write-Host "`n[Change Detected]: $FileName" -ForegroundColor Yellow
        
        # Small delay to let the OS release file handles before deletion
        Start-Sleep -Milliseconds 100

        foreach ($Plugin in $Plugins) {
            $Destination = Join-Path $LocalPluginsPath "$Plugin\core"
            
            # Delete the old folder if it exists to ensure a fresh copy
            if (Test-Path $Destination) { 
                Write-Host "  Cleaning -> $Plugin\core" -ForegroundColor Gray
                Remove-Item -Path $Destination -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            # Re-create the clean directory
            New-Item -ItemType Directory -Path $Destination -Force | Out-Null 
            
            # Report and Sync
            Write-Host "  Syncing  -> $Plugin\core" -ForegroundColor Cyan
            Copy-Item -Path ".\*" -Destination $Destination -Recurse -Force -Exclude "*.ps1", ".git*"
        }
        
        Write-Host "Sync complete!" -ForegroundColor Green
    }
}

# Bind the action to Change and Create events
Register-ObjectEvent $Watcher "Changed" -Action $Action
Register-ObjectEvent $Watcher "Created" -Action $Action

# Keep the script running
while ($true) { Start-Sleep 5 }