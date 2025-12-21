#Requires -Version 7.0
<#
.SYNOPSIS
    Test script for verifying the user-space installation architecture

.DESCRIPTION
    Tests that the devkit installs to ~/.devkit/ instead of the repo,
    making the installation independent of the source repo location.

.NOTES
    Run: pwsh -File test-user-space-architecture.ps1
#>

# Load the config generator
. "$PSScriptRoot\lib\config-generator.ps1"

$testDir = Join-Path $env:TEMP "devkit-test-$(Get-Random)"
$originalUserProfile = $env:USERPROFILE

Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "Testing User-Space Installation Architecture" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host ""
Write-Host "Test directory: $testDir"
Write-Host ""

# Override USERPROFILE for testing
$env:USERPROFILE = $testDir
New-Item -Path $testDir -ItemType Directory -Force | Out-Null

try {
    # Test 1: Get-DevkitUserRoot
    Write-Host "=== Test 1: Get-DevkitUserRoot ===" -ForegroundColor Yellow
    $userRoot = Get-DevkitUserRoot
    $expectedRoot = Join-Path $testDir ".devkit"
    if ($userRoot -eq $expectedRoot) {
        Write-Host "[OK] Returns correct path: $userRoot" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] Expected: $expectedRoot, Got: $userRoot" -ForegroundColor Red
    }
    Write-Host ""

    # Test 2: Initialize-DevkitUserSpace
    Write-Host "=== Test 2: Initialize-DevkitUserSpace ===" -ForegroundColor Yellow
    $initResult = Initialize-DevkitUserSpace
    if ($initResult) {
        Write-Host "[OK] Initialization returned true" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] Initialization returned false" -ForegroundColor Red
    }

    # Check directories were created
    $dirsToCheck = @(
        (Join-Path $userRoot ""),
        (Join-Path $userRoot "themes"),
        (Join-Path $userRoot "backups")
    )
    foreach ($dir in $dirsToCheck) {
        if (Test-Path $dir) {
            Write-Host "[OK] Directory exists: $dir" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] Directory missing: $dir" -ForegroundColor Red
        }
    }
    Write-Host ""

    # Test 3: Copy-DevkitProfile
    Write-Host "=== Test 3: Copy-DevkitProfile ===" -ForegroundColor Yellow
    $sourceRoot = Split-Path $PSScriptRoot -Parent
    $copiedProfile = Copy-DevkitProfile -SourceRoot $sourceRoot
    $expectedProfile = Join-Path $userRoot "profile.ps1"
    if ($copiedProfile -eq $expectedProfile -and (Test-Path $expectedProfile)) {
        Write-Host "[OK] Profile copied to: $copiedProfile" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] Profile copy failed. Expected: $expectedProfile, Got: $copiedProfile" -ForegroundColor Red
    }
    Write-Host ""

    # Test 4: Copy-DevkitTheme
    Write-Host "=== Test 4: Copy-DevkitTheme ===" -ForegroundColor Yellow
    $sourceTheme = Join-Path $sourceRoot "configuration/powershell/.mytheme-new.omp.json"
    if (Test-Path $sourceTheme) {
        $copiedTheme = Copy-DevkitTheme -SourceThemePath $sourceTheme
        $expectedTheme = Join-Path $userRoot "themes/.mytheme-new.omp.json"
        if ($copiedTheme -eq $expectedTheme -and (Test-Path $expectedTheme)) {
            Write-Host "[OK] Theme copied to: $copiedTheme" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] Theme copy failed. Expected: $expectedTheme, Got: $copiedTheme" -ForegroundColor Red
        }
    } else {
        Write-Host "[SKIP] Source theme not found: $sourceTheme" -ForegroundColor Yellow
    }
    Write-Host ""

    # Test 5: Save-VariablesPs1
    Write-Host "=== Test 5: Save-VariablesPs1 ===" -ForegroundColor Yellow
    $themePath = Join-Path $userRoot "themes/test-theme.omp.json"
    $varsResult = Save-VariablesPs1 -ThemePath $themePath
    $varsPath = Join-Path $userRoot "variables.ps1"
    if ($varsResult -and (Test-Path $varsPath)) {
        Write-Host "[OK] variables.ps1 created at: $varsPath" -ForegroundColor Green

        # Check content
        $varsContent = Get-Content $varsPath -Raw
        if ($varsContent -match '\$HOME/\.devkit') {
            Write-Host "[OK] variables.ps1 uses `$HOME/.devkit path" -ForegroundColor Green
        } else {
            Write-Host "[FAIL] variables.ps1 doesn't use `$HOME/.devkit path" -ForegroundColor Red
        }
    } else {
        Write-Host "[FAIL] variables.ps1 not created" -ForegroundColor Red
    }
    Write-Host ""

    # Test 6: New-ProfileSnippet
    Write-Host "=== Test 6: New-ProfileSnippet ===" -ForegroundColor Yellow
    $snippet = New-ProfileSnippet
    if ($snippet -match '\$HOME/\.devkit/variables\.ps1' -and $snippet -match '\$HOME/\.devkit/profile\.ps1') {
        Write-Host "[OK] Profile snippet uses `$HOME/.devkit paths" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] Profile snippet doesn't use `$HOME/.devkit paths" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "Generated snippet:" -ForegroundColor Cyan
    Write-Host $snippet
    Write-Host ""

    # Summary
    Write-Host "=" * 60 -ForegroundColor Cyan
    Write-Host "Architecture Verification Complete" -ForegroundColor Cyan
    Write-Host "=" * 60 -ForegroundColor Cyan
    Write-Host ""
    Write-Host "User space directory: $userRoot"
    Write-Host ""
    Write-Host "Files created:"
    Get-ChildItem -Path $userRoot -Recurse -File | ForEach-Object {
        Write-Host "  - $($_.FullName.Replace($testDir, '~'))"
    }

} finally {
    # Restore USERPROFILE
    $env:USERPROFILE = $originalUserProfile

    # Cleanup
    if (Test-Path $testDir) {
        Remove-Item -Path $testDir -Recurse -Force
        Write-Host ""
        Write-Host "Test directory cleaned up." -ForegroundColor Gray
    }
}
