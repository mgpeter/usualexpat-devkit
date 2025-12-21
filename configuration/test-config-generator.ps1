#Requires -Version 7.0
<#
.SYNOPSIS
    Test script for config-generator (preview only - no files written)

.NOTES
    Run: pwsh -File test-config-generator.ps1
#>

# Enable UTF-8 encoding
$OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

# Import PwshSpectreConsole
Import-Module PwshSpectreConsole -Force

# Load modules
. "$PSScriptRoot\lib\validators.ps1"
. "$PSScriptRoot\lib\config-generator.ps1"

Write-Host "Testing Config Generator (Preview Mode)..." -ForegroundColor Cyan
Write-Host ""

# Create test configuration
$testConfig = @{
    Mode = "Fresh"
    RepoLocations = @("C:\repos", "D:\projects")
    Git = @{
        DefaultProfile = @{
            Name = "Test User"
            Email = "test@example.com"
        }
        AdditionalProfiles = @(
            @{
                Directory = "C:/repos/work/"
                Name = "Test User"
                Email = "test@work.com"
            }
            @{
                Directory = "D:/projects/client/"
                Name = "Test User"
                Email = "test@client.com"
            }
        )
    }
    PowerShell = @{
        Modules = @("z", "posh-git", "Terminal-Icons")
        OhMyPoshTheme = "C:/repos/devkit/themes/mytheme.omp.json"
    }
}

$devkitRoot = "C:/repos/usualexpat-devkit"

#region Test 1: Generate .gitconfig content
Write-Host "=== Test 1: Generated .gitconfig ===" -ForegroundColor Yellow
$gitconfigContent = New-GitConfig -Config $testConfig
Write-Host $gitconfigContent
Write-Host ""
#endregion

#region Test 2: Generate profile config filename
Write-Host "=== Test 2: Profile Config Filenames ===" -ForegroundColor Yellow
foreach ($profile in $testConfig.Git.AdditionalProfiles) {
    $filename = Get-ProfileConfigFileName -Directory $profile.Directory
    Write-Host "  $($profile.Directory) -> $filename"
}
Write-Host ""
#endregion

#region Test 3: Generate profile-specific config
Write-Host "=== Test 3: Profile-specific .gitconfig ===" -ForegroundColor Yellow
$profileConfig = New-GitProfileConfig -Profile $testConfig.Git.AdditionalProfiles[0]
Write-Host $profileConfig
Write-Host ""
#endregion

#region Test 4: Generate variables.ps1 content
Write-Host "=== Test 4: Generated variables.ps1 ===" -ForegroundColor Yellow
$variablesContent = New-VariablesPs1 -DevkitRoot $devkitRoot -OhMyPoshTheme $testConfig.PowerShell.OhMyPoshTheme
Write-Host $variablesContent
Write-Host ""
#endregion

#region Test 5: Generate profile snippet
Write-Host "=== Test 5: PowerShell Profile Snippet ===" -ForegroundColor Yellow
$snippet = New-ProfileSnippet -DevkitRoot $devkitRoot
Write-Host $snippet
Write-Host ""
#endregion

Write-Host "=== Config Generator Test Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Note: This was preview mode - no files were actually written."
Write-Host "The actual installation will use these generators to create real files."
