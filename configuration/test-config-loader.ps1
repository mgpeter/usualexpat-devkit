#Requires -Version 7.0
<#
.SYNOPSIS
    Test script for config-loader

.NOTES
    Run: pwsh -File test-config-loader.ps1
#>

# Enable UTF-8 encoding
$OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

# Import PwshSpectreConsole
Import-Module PwshSpectreConsole -Force

# Load config loader
. "$PSScriptRoot\lib\config-loader.ps1"

Write-Host "Testing Config Loader..." -ForegroundColor Cyan
Write-Host ""

#region Git Config Detection
Write-Host "=== Git Configuration ===" -ForegroundColor Yellow
$gitConfig = Get-ExistingGitConfig

if ($gitConfig.Found) {
    Write-SpectreHost "[green]Git config found![/]"
    Write-Host "  Name: $($gitConfig.DefaultProfile.Name)"
    Write-Host "  Email: $($gitConfig.DefaultProfile.Email)"

    if ($gitConfig.AdditionalProfiles.Count -gt 0) {
        Write-Host "  Additional Profiles: $($gitConfig.AdditionalProfiles.Count)"
        foreach ($profile in $gitConfig.AdditionalProfiles) {
            Write-Host "    - $($profile.Directory) -> $($profile.Email)"
        }
    }
} else {
    Write-SpectreHost "[yellow]No git config found[/]"
}
#endregion

Write-Host ""

#region PowerShell Profile Detection
Write-Host "=== PowerShell Profile ===" -ForegroundColor Yellow
$psConfig = Get-ExistingPowerShellConfig

if ($psConfig.Found) {
    Write-SpectreHost "[green]PowerShell profile found![/]"
    Write-Host "  Path: $($psConfig.ProfilePath)"
    Write-Host "  Devkit Installed: $($psConfig.DevkitInstalled)"
    if ($psConfig.OhMyPoshTheme) {
        Write-Host "  Oh-My-Posh Theme: $($psConfig.OhMyPoshTheme)"
    }
} else {
    Write-SpectreHost "[yellow]No PowerShell profile found[/]"
}
#endregion

Write-Host ""

#region Devkit Variables Detection
Write-Host "=== Devkit Variables ===" -ForegroundColor Yellow
$devkitVars = Get-ExistingDevkitVariables

if ($devkitVars.Found) {
    Write-SpectreHost "[green]Devkit variables found![/]"
    Write-Host "  DEVKIT_ROOT: $($devkitVars.DevkitRoot)"
    Write-Host "  OMP Theme: $($devkitVars.OhMyPoshTheme)"
} else {
    Write-SpectreHost "[yellow]No devkit variables found[/]"
}
#endregion

Write-Host ""

#region Repo Locations Detection
Write-Host "=== Repository Locations ===" -ForegroundColor Yellow
$repoLocations = Get-CommonRepoLocations

if ($repoLocations.Count -gt 0) {
    Write-SpectreHost "[green]Found $($repoLocations.Count) repo location(s):[/]"
    foreach ($loc in $repoLocations) {
        Write-Host "  - $loc"
    }
} else {
    Write-SpectreHost "[yellow]No common repo locations found[/]"
}
#endregion

Write-Host ""

#region Full Configuration Load
Write-Host "=== Full Configuration ===" -ForegroundColor Yellow
$fullConfig = Get-ExistingConfiguration

Write-SpectreHost "[blue]Detection Summary:[/]"
Write-Host "  Git Config Found: $($fullConfig._Detection.GitConfigFound)"
Write-Host "  Profile Found: $($fullConfig._Detection.ProfileFound)"
Write-Host "  Devkit Installed: $($fullConfig._Detection.DevkitInstalled)"
Write-Host "  Variables Found: $($fullConfig._Detection.VariablesFound)"

Write-Host ""
Write-SpectreHost "[blue]Loaded Values:[/]"
Write-Host "  Git Name: $($fullConfig.Git.DefaultProfile.Name)"
Write-Host "  Git Email: $($fullConfig.Git.DefaultProfile.Email)"
Write-Host "  Repo Locations: $($fullConfig.RepoLocations.Count)"
Write-Host "  Installed Modules: $($fullConfig.PowerShell.Modules -join ', ')"
Write-Host "  OMP Theme: $($fullConfig.PowerShell.OhMyPoshTheme)"
#endregion

Write-Host ""
Write-Host "=== Config Loader Test Complete ===" -ForegroundColor Green
