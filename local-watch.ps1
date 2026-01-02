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
        
        foreach ($Plugin in $Plugins) {
            $Destination = Join-Path $LocalPluginsPath "$Plugin\core"
            
            # Create directory if it doesn't exist
            if (!(Test-Path $Destination)) { 
                New-Item -ItemType Directory -Path $Destination -Force | Out-Null 
            }
            
            # Report the specific folder being written to
            Write-Host "  Core -> $Plugin" -ForegroundColor Gray
            
            # Sync files
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