#Requires -Version 7.0
<#
.SYNOPSIS
    Test script for repository locations wizard step

.NOTES
    Run: pwsh -File test-repo-locations.ps1
#>

# Enable UTF-8 encoding
$OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

# Import PwshSpectreConsole
Import-Module PwshSpectreConsole -Force

# Load dependencies
. "$PSScriptRoot\lib\validators.ps1"
. "$PSScriptRoot\lib\config-loader.ps1"
. "$PSScriptRoot\lib\backup.ps1"
. "$PSScriptRoot\lib\config-generator.ps1"
. "$PSScriptRoot\lib\wizard.ps1"

Write-Host "Testing Repository Locations Step..." -ForegroundColor Cyan
Write-Host ""

# Load existing configuration
$existingConfig = Get-ExistingConfiguration

# Determine devkit root
$devkitRoot = $PSScriptRoot | Split-Path

# Start the wizard with existing config
$result = Start-Wizard -Version "1.0.0-test" -ExistingConfig $existingConfig -DevkitRoot $devkitRoot

Write-Host ""
Write-Host "=== Final Wizard State ===" -ForegroundColor Yellow
Write-Host "Mode: $($result.Mode)"
Write-Host "Repo Locations:"
foreach ($loc in $result.Config.RepoLocations) {
    Write-Host "  - $loc"
}
