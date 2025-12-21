#Requires -Version 7.0
<#
.SYNOPSIS
    Devkit Interactive Installation Wizard

.DESCRIPTION
    Interactive CLI wizard for configuring your Windows development environment.
    Uses PwshSpectreConsole for a rich console UI experience.

.NOTES
    Requires PowerShell 7.0 or higher
    Requires Administrator privileges for module installation
#>

[CmdletBinding()]
param(
    [switch]$SkipAdminCheck
)

# Enable UTF-8 encoding for Spectre.Console compatibility
$OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$ErrorActionPreference = "Stop"

# Get the root directory of the devkit
$script:DevkitRoot = Split-Path -Parent $PSScriptRoot
$script:ConfigRoot = $PSScriptRoot
$script:LibPath = Join-Path $PSScriptRoot "lib"

# Version info
$script:DevkitVersion = "1.0.0"
$script:DevkitName = "Devkit by Usual Expat"

#region Admin Check
if (-not $SkipAdminCheck) {
    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
    if (-not $isAdmin) {
        Write-Host "This installer requires Administrator privileges for module installation." -ForegroundColor Red
        Write-Host "Please run PowerShell as Administrator and try again." -ForegroundColor Yellow
        exit 1
    }
}
#endregion

#region PwshSpectreConsole Setup
function Install-SpectreConsole {
    <#
    .SYNOPSIS
        Ensures PwshSpectreConsole is installed and loaded
    #>
    $moduleName = "PwshSpectreConsole"

    # Check if module is available
    $module = Get-Module -ListAvailable -Name $moduleName | Select-Object -First 1

    if (-not $module) {
        Write-Host "Installing $moduleName module..." -ForegroundColor Yellow

        # Ensure PSGallery is trusted
        $gallery = Get-PSRepository -Name "PSGallery" -ErrorAction SilentlyContinue
        if ($gallery -and $gallery.InstallationPolicy -ne "Trusted") {
            Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
        }

        try {
            Install-Module -Name $moduleName -Scope CurrentUser -Force -AllowClobber
            Write-Host "$moduleName installed successfully!" -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to install $moduleName : $_" -ForegroundColor Red
            Write-Host "Please install manually: Install-Module -Name $moduleName -Scope CurrentUser" -ForegroundColor Yellow
            exit 1
        }
    }

    # Import the module
    try {
        Import-Module $moduleName -Force -ErrorAction Stop
        return $true
    }
    catch {
        Write-Host "Failed to import $moduleName : $_" -ForegroundColor Red
        return $false
    }
}

function Test-SpectreConsole {
    <#
    .SYNOPSIS
        Tests that PwshSpectreConsole is working correctly
    #>
    try {
        # Test basic Spectre functionality
        $testPanel = Format-SpectrePanel -Data "Welcome to $script:DevkitName v$script:DevkitVersion" -Title "Installation Wizard" -Border Rounded -Color Blue
        Write-SpectreHost $testPanel
        return $true
    }
    catch {
        Write-Host "PwshSpectreConsole test failed: $_" -ForegroundColor Red
        return $false
    }
}
#endregion

#region Main Entry Point
function Start-DevkitInstaller {
    <#
    .SYNOPSIS
        Main entry point for the Devkit installer wizard
    #>

    Clear-Host

    # Install and verify PwshSpectreConsole
    Write-Host "Checking prerequisites..." -ForegroundColor Cyan

    if (-not (Install-SpectreConsole)) {
        Write-Host "Failed to set up PwshSpectreConsole. Exiting." -ForegroundColor Red
        exit 1
    }

    if (-not (Test-SpectreConsole)) {
        Write-Host "PwshSpectreConsole is not working correctly. Exiting." -ForegroundColor Red
        exit 1
    }

    Write-Host ""
    Write-Host "PwshSpectreConsole is ready!" -ForegroundColor Green
    Write-Host ""

    # Load all wizard modules
    . "$script:LibPath\validators.ps1"
    . "$script:LibPath\config-loader.ps1"
    . "$script:LibPath\backup.ps1"
    . "$script:LibPath\config-generator.ps1"
    . "$script:LibPath\wizard.ps1"

    # Load existing configuration
    $existingConfig = Get-ExistingConfiguration -DevkitRoot $script:DevkitRoot

    # Start the wizard
    $result = Start-Wizard -Version $script:DevkitVersion -ExistingConfig $existingConfig -DevkitRoot $script:DevkitRoot

    Write-Host ""
    if ($result.Installed) {
        Write-Host "Installation complete!" -ForegroundColor Green
    }
}
#endregion

# Run the installer
Start-DevkitInstaller
