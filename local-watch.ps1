# Configuration
$LocalPluginsPath = "C:\Users\Owner\Local Sites\thisismyurlcom\app\public\wp-content\plugins"
$Plugins = @(
    "thisismyurl-avif-support",
    "thisismyurl-heic-support",
    "thisismyurl-svg-support",
    "thisismyurl-webp-support",
    "thisismyurl-link-support"
)


# The Logic
$Watcher = New-Object System.IO.FileSystemWatcher
$Watcher.Path = Get-Location
$Watcher.IncludeSubdirectories = $true
$Watcher.EnableRaisingEvents = $true

Write-Host "Watching for changes in Master Core..." -ForegroundColor Cyan

$Action = {
    $ChangedPath = $Event.SourceEventArgs.FullPath
    
    # Ignore the script itself and .git folder
    if ($ChangedPath -notmatch '\.ps1$' -and $ChangedPath -notmatch '\.git') {
        Write-Host "Change detected in: $($Event.SourceEventArgs.Name)" -ForegroundColor Yellow
        
        foreach ($Plugin in $Plugins) {
            $Destination = Join-Path $LocalPluginsPath "$Plugin\core"
            
            # Create directory if it doesn't exist
            if (!(Test-Path $Destination)) { New-Item -ItemType Directory -Path $Destination }
            
            # Sync files (excluding the script and git)
            Copy-Item -Path ".\*" -Destination $Destination -Recurse -Force -Exclude "*.ps1", ".git*"
        }
        Write-Host "Sync complete to all plugins!" -ForegroundColor Green
    }
}

# Bind the action to Change and Create events
Register-ObjectEvent $Watcher "Changed" -Action $Action
Register-ObjectEvent $Watcher "Created" -Action $Action

# Keep the script running
while ($true) { Start-Sleep 5 }