# Ensure script is running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Please run this script as Administrator!" -ForegroundColor Red
    exit
}

# Set execution policy to allow module installation
Write-Host "Setting execution policy..." -ForegroundColor Cyan
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

# List of required modules
$requiredModules = @(
    "z",
    "posh-git",
    "Terminal-Icons",
    "PSReadLine"
)

# Function to check and install missing modules
function Install-ModuleIfMissing {
    param (
        [string]$moduleName
    )

    if (-not (Get-Module -ListAvailable -Name $moduleName)) {
        Write-Host "Installing module: $moduleName" -ForegroundColor Yellow
        Install-Module -Name $moduleName -Scope CurrentUser -Force -AllowClobber
    } else {
        Write-Host "Module $moduleName is already installed." -ForegroundColor Green
    }
}

# Ensure PowerShell Gallery is trusted
$gallerySource = Get-PSRepository | Where-Object { $_.Name -eq "PSGallery" }
if ($gallerySource -and $gallerySource.InstallationPolicy -ne "Trusted") {
    Write-Host "Trusting PowerShell Gallery..." -ForegroundColor Cyan
    Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
}

# Install required modules
foreach ($module in $requiredModules) {
    Install-ModuleIfMissing -moduleName $module
}

Write-Host "All necessary modules are installed!" -ForegroundColor Magenta

Write-Host "Installing oh-my-posh" -ForegroundColor Yellow

Set-ExecutionPolicy Bypass -Scope Process -Force;
Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://ohmyposh.dev/install.ps1'))

Write-Host "Oh-my-posh installed!" -ForegroundColor Magenta