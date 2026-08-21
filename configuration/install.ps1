#Requires -Version 7.0
<#
.SYNOPSIS
    Devkit Interactive Installation Wizard

.DESCRIPTION
    Interactive CLI wizard for configuring your Windows development environment.
    Uses PwshSpectreConsole for a rich console UI experience.

.NOTES
    Requires PowerShell 7.0 or higher
    Administrator privileges are recommended: the prerequisites step can install
    system-wide packages with winget. Use -SkipAdminCheck to run without them
    (individual package installs may then raise their own elevation prompts).
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
        Write-Host "This installer requires Administrator privileges." -ForegroundColor Red
        Write-Host "The prerequisites step installs system-wide packages with winget." -ForegroundColor Yellow
        Write-Host "Run PowerShell as Administrator, or re-run with -SkipAdminCheck." -ForegroundColor Yellow
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
        # This runs BEFORE lib/ is dot-sourced and before any Spectre call - the wizard
        # UI is what we are about to install - so plain Write-Host/Read-Host only.
        Write-Host ""
        Write-Host "$moduleName is required for the wizard's interactive UI." -ForegroundColor Yellow
        Write-Host "It is installed from the PowerShell Gallery for the current user only:" -ForegroundColor Gray
        Write-Host "  Install-Module -Name $moduleName -Scope CurrentUser" -ForegroundColor Gray

        # PowerShellGet v2 and PSResourceGet have different cmdlets. Probing rather than
        # assuming avoids the silent no-op where Get-PSRepository returns nothing on a
        # PSResourceGet-only host and the trust step quietly does nothing.
        $useResourceGet = [bool](Get-Command Install-PSResource -ErrorAction SilentlyContinue)
        $useModule = [bool](Get-Command Install-Module -ErrorAction SilentlyContinue)

        if (-not $useResourceGet -and -not $useModule) {
            Write-Host "Neither Install-PSResource nor Install-Module is available on this host." -ForegroundColor Red
            Write-Host "Install PowerShellGet or PSResourceGet, then re-run the installer." -ForegroundColor Yellow
            exit 1
        }

        # Surface the machine-wide side effect instead of doing it silently.
        $needsTrust = $false
        if ($useResourceGet) {
            $repo = Get-PSResourceRepository -Name "PSGallery" -ErrorAction SilentlyContinue
            $needsTrust = ($repo -and -not $repo.Trusted)
        } else {
            $gallery = Get-PSRepository -Name "PSGallery" -ErrorAction SilentlyContinue
            $needsTrust = ($gallery -and $gallery.InstallationPolicy -ne "Trusted")
        }
        if ($needsTrust) {
            Write-Host "Note: PSGallery is not currently trusted. Continuing marks it Trusted so the" -ForegroundColor Yellow
            Write-Host "      install runs without a per-package confirmation. That is a machine-wide" -ForegroundColor Yellow
            Write-Host "      setting and it is not reverted afterwards." -ForegroundColor Yellow
        }

        Write-Host ""
        $answer = Read-Host "Install $moduleName now? [y/N]"
        if ("$answer".Trim() -notmatch '^(y|yes)$') {
            # Declining is a choice, not a failure.
            Write-Host ""
            Write-Host "Skipped. Install it yourself with:" -ForegroundColor Yellow
            Write-Host "  Install-Module -Name $moduleName -Scope CurrentUser" -ForegroundColor Gray
            Write-Host "then re-run: . ./configuration/install.ps1" -ForegroundColor Gray
            exit 0
        }

        Write-Host "Installing $moduleName module..." -ForegroundColor Yellow

        try {
            if ($useResourceGet) {
                if ($needsTrust) {
                    Write-Host "Setting PSGallery to Trusted..." -ForegroundColor Gray
                    Set-PSResourceRepository -Name "PSGallery" -Trusted -ErrorAction SilentlyContinue
                }
                Install-PSResource -Name $moduleName -Scope CurrentUser -TrustRepository -Reinstall:$false -ErrorAction Stop
            } else {
                if ($needsTrust) {
                    Write-Host "Setting PSGallery InstallationPolicy to Trusted..." -ForegroundColor Gray
                    Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted
                }
                Install-Module -Name $moduleName -Scope CurrentUser -Force -AllowClobber
            }
            Write-Host "$moduleName installed successfully!" -ForegroundColor Green
        }
        catch {
            Write-Host "Failed to install $moduleName : $_" -ForegroundColor Red
            Write-Host "If you are offline, install it on a connected machine or from a local" -ForegroundColor Yellow
            Write-Host "repository, then re-run the installer." -ForegroundColor Yellow
            Write-Host "Manual install: Install-Module -Name $moduleName -Scope CurrentUser" -ForegroundColor Yellow
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
