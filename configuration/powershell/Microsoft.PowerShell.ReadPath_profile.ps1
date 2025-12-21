# Check if DevKit variables are loaded
if (-not $env:DEVKIT_ROOT) {
    Write-Host "DevKit environment variables not found. Please run the install script first:" -ForegroundColor Red
    Write-Host "1. Open PowerShell as Administrator" -ForegroundColor Yellow
    Write-Host "2. Navigate to the DevKit directory" -ForegroundColor Yellow
    Write-Host "3. Run: .\configuration\powershell\install.ps1" -ForegroundColor Yellow
    return
}

# Set oh-my-posh theme path
$env:ohMyPoshConfig = $env:DEVKIT_OMP_THEME

# Execute the main profile script
$mainProfilePath = Join-Path $env:DEVKIT_POWERSHELL_CONFIG "Microsoft.PowerShell_profile.ps1"
if (Test-Path $mainProfilePath) {
    . $mainProfilePath
} else {
    Write-Host "Main profile script not found at: $mainProfilePath" -ForegroundColor Red
}