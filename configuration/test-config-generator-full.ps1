#Requires -Version 7.0
<#
.SYNOPSIS
    Test script for verifying the enhanced config-generator produces full feature set

.NOTES
    Run: pwsh -File test-config-generator-full.ps1
#>

# Load the config generator
. "$PSScriptRoot\lib\config-generator.ps1"

Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "Testing Enhanced Config Generator" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host ""

# Test configuration
$testConfig = @{
    Git = @{
        DefaultProfile = @{
            Name = 'Test User'
            Email = 'test@example.com'
        }
        AdditionalProfiles = @(
            @{
                Directory = 'C:/repos/work/'
                Name = 'Work User'
                Email = 'test@work.com'
            }
        )
    }
}

# Generate the config
$result = New-GitConfig -Config $testConfig

Write-Host "=== Generated .gitconfig ===" -ForegroundColor Yellow
Write-Host ""
Write-Host $result
Write-Host ""

# Verify all expected aliases are present
$expectedAliases = @(
    'yesterday', 'recently', 'standup',
    'lg1', 'lg2', 'lg', 'ls', 'la', 'll',
    'amend', 'st', 'topcom', 'prettydiff',
    'abbr', 'gitkconflict', 'new'
)

Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "Verifying Aliases" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host ""

$missingAliases = @()
foreach ($alias in $expectedAliases) {
    # Use simple contains check - the alias followed by =
    if ($result -match "\s+$alias\s*=") {
        Write-Host "[OK] $alias" -ForegroundColor Green
    } else {
        Write-Host "[MISSING] $alias" -ForegroundColor Red
        $missingAliases += $alias
    }
}

Write-Host ""

# Verify color settings
$expectedColors = @('ui', 'branch', 'diff', 'interactive', 'status', 'grep', 'pager', 'decorate', 'showbranch')

Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "Verifying Color Settings" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host ""

$missingColors = @()
foreach ($color in $expectedColors) {
    if ($result -match "\s+$color\s*=") {
        Write-Host "[OK] color.$color" -ForegroundColor Green
    } else {
        Write-Host "[MISSING] color.$color" -ForegroundColor Red
        $missingColors += $color
    }
}

Write-Host ""

# Verify core settings
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "Verifying Core Settings" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host ""

$coreSettings = @('autocrlf', 'longpaths', 'editor', 'excludesfile')
foreach ($setting in $coreSettings) {
    if ($result -match "\s+$setting\s*=") {
        Write-Host "[OK] core.$setting" -ForegroundColor Green
    } else {
        Write-Host "[MISSING] core.$setting" -ForegroundColor Red
    }
}

Write-Host ""

# Verify GPG sections
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "Verifying GPG Sections" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host ""

$gpgSections = @('\[gpg\]', '\[commit\]', '\[tag\]', 'gpgSign', 'forceSignAnnotated')
foreach ($section in $gpgSections) {
    if ($result -match $section) {
        Write-Host "[OK] $($section -replace '\\', '')" -ForegroundColor Green
    } else {
        Write-Host "[MISSING] $($section -replace '\\', '')" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "Summary" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host ""

if ($missingAliases.Count -eq 0 -and $missingColors.Count -eq 0) {
    Write-Host "All checks passed!" -ForegroundColor Green
} else {
    Write-Host "Some checks failed:" -ForegroundColor Red
    if ($missingAliases.Count -gt 0) {
        Write-Host "  Missing aliases: $($missingAliases -join ', ')" -ForegroundColor Red
    }
    if ($missingColors.Count -gt 0) {
        Write-Host "  Missing colors: $($missingColors -join ', ')" -ForegroundColor Red
    }
}
