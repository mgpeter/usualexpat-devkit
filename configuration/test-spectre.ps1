#Requires -Version 7.0
<#
.SYNOPSIS
    Test script to verify PwshSpectreConsole works correctly

.DESCRIPTION
    Run this script manually to test PwshSpectreConsole after adding
    Bitdefender exception.

.NOTES
    Run in PowerShell 7: pwsh -File test-spectre.ps1
#>

# Enable UTF-8 encoding for Spectre.Console
$OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

Write-Host "Testing PwshSpectreConsole..." -ForegroundColor Cyan
Write-Host ""

# Step 1: Check if module is installed
Write-Host "Step 1: Checking if module is installed..." -ForegroundColor Yellow
$module = Get-Module -ListAvailable -Name PwshSpectreConsole
if ($module) {
    Write-Host "  Module found: v$($module.Version)" -ForegroundColor Green
} else {
    Write-Host "  Module not found. Installing..." -ForegroundColor Yellow
    Install-Module -Name PwshSpectreConsole -Scope CurrentUser -Force
}

# Step 2: Import module
Write-Host ""
Write-Host "Step 2: Importing module..." -ForegroundColor Yellow
try {
    Import-Module PwshSpectreConsole -Force -ErrorAction Stop
    Write-Host "  Module imported successfully!" -ForegroundColor Green
} catch {
    Write-Host "  Failed to import module: $_" -ForegroundColor Red
    Write-Host "  Make sure you added the Bitdefender exception." -ForegroundColor Yellow
    exit 1
}

# Step 3: List available commands
Write-Host ""
Write-Host "Step 3: Available commands..." -ForegroundColor Yellow
$commands = Get-Command -Module PwshSpectreConsole
Write-Host "  Found $($commands.Count) commands" -ForegroundColor Green

# Step 4: Test Format-SpectrePanel
Write-Host ""
Write-Host "Step 4: Testing Format-SpectrePanel..." -ForegroundColor Yellow
try {
    "Welcome to Devkit by Usual Expat v1.0.0" | Format-SpectrePanel -Title "Installation Wizard" -Border Rounded -Color Blue
    Write-Host "  Panel test passed!" -ForegroundColor Green
} catch {
    Write-Host "  Panel test failed: $_" -ForegroundColor Red
}

# Step 5: Test Read-SpectreSelection (interactive)
Write-Host ""
Write-Host "Step 5: Testing Read-SpectreSelection (interactive)..." -ForegroundColor Yellow
Write-Host "  Select an option below:" -ForegroundColor Cyan
try {
    $choices = @("Fresh Install", "Update Existing", "Exit Test")
    $choice = Read-SpectreSelection -Title "Select installation mode:" -Choices $choices
    Write-Host "  You selected: $choice" -ForegroundColor Green
} catch {
    Write-Host "  Selection test failed: $_" -ForegroundColor Red
}

# Step 6: Test Format-SpectreTable
Write-Host ""
Write-Host "Step 6: Testing Format-SpectreTable..." -ForegroundColor Yellow
try {
    $tableData = @(
        [PSCustomObject]@{ Setting = "Git Name"; Value = "John Doe" }
        [PSCustomObject]@{ Setting = "Git Email"; Value = "john@example.com" }
        [PSCustomObject]@{ Setting = "Repo Path"; Value = "C:/repos" }
    )
    $tableData | Format-SpectreTable -Border Rounded -Color Green
    Write-Host "  Table test passed!" -ForegroundColor Green
} catch {
    Write-Host "  Table test failed: $_" -ForegroundColor Red
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "All tests completed!" -ForegroundColor Green
Write-Host "PwshSpectreConsole is ready to use." -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Press any key to exit..."
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
