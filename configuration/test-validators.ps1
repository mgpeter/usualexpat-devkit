#Requires -Version 7.0
<#
.SYNOPSIS
    Test script for validators

.NOTES
    Run: pwsh -File test-validators.ps1
#>

# Enable UTF-8 encoding
$OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

# Import PwshSpectreConsole
Import-Module PwshSpectreConsole -Force

# Load validators
. "$PSScriptRoot\lib\validators.ps1"

Write-Host "Testing Validators..." -ForegroundColor Cyan
Write-Host ""

#region Email Validation Tests
Write-Host "=== Email Validation ===" -ForegroundColor Yellow

$emailTests = @(
    @{ Email = "user@example.com"; Expected = $true }
    @{ Email = "john.doe@company.co.uk"; Expected = $true }
    @{ Email = "test+label@gmail.com"; Expected = $true }
    @{ Email = "invalid"; Expected = $false }
    @{ Email = "@nodomain.com"; Expected = $false }
    @{ Email = "spaces in@email.com"; Expected = $false }
    @{ Email = ""; Expected = $false }
)

foreach ($test in $emailTests) {
    $result = Test-EmailAddress -Email $test.Email
    $status = if ($result -eq $test.Expected) { "[green]PASS[/]" } else { "[red]FAIL[/]" }
    Write-SpectreHost "  $status - '$($test.Email)' -> $result (expected: $($test.Expected))"
}
#endregion

Write-Host ""

#region Directory Path Validation Tests
Write-Host "=== Directory Path Validation ===" -ForegroundColor Yellow

$pathTests = @(
    @{ Path = "C:\repos"; ExpectedValid = $true }
    @{ Path = "C:/repos"; ExpectedValid = $true }
    @{ Path = "D:\repos\work\"; ExpectedValid = $true }
    @{ Path = "repos"; ExpectedValid = $false }
    @{ Path = "/unix/path"; ExpectedValid = $false }
    @{ Path = ""; ExpectedValid = $false }
)

foreach ($test in $pathTests) {
    $result = Test-DirectoryPath -Path $test.Path
    $status = if ($result.IsValid -eq $test.ExpectedValid) { "[green]PASS[/]" } else { "[red]FAIL[/]" }
    Write-SpectreHost "  $status - '$($test.Path)' -> Valid: $($result.IsValid), Exists: $($result.Exists)"
}
#endregion

Write-Host ""

#region Name Validation Tests
Write-Host "=== Name Validation ===" -ForegroundColor Yellow

$nameTests = @(
    @{ Name = "John Doe"; Expected = $true }
    @{ Name = "A"; Expected = $true }
    @{ Name = "  spaces  "; Expected = $true }  # Has content after trim
    @{ Name = ""; Expected = $false }
    @{ Name = "   "; Expected = $false }  # Only whitespace
)

foreach ($test in $nameTests) {
    $result = Test-NonEmptyString -Value $test.Name
    $status = if ($result -eq $test.Expected) { "[green]PASS[/]" } else { "[red]FAIL[/]" }
    Write-SpectreHost "  $status - '$($test.Name)' -> $result (expected: $($test.Expected))"
}
#endregion

Write-Host ""

#region Config Validation Tests
Write-Host "=== Config Validation ===" -ForegroundColor Yellow

# Valid config
$validConfig = New-DevkitConfig
$validConfig.Git.DefaultProfile.Name = "John Doe"
$validConfig.Git.DefaultProfile.Email = "john@example.com"
$validConfig.RepoLocations = @("C:\repos")
$validConfig.PowerShell.Modules = @("z", "posh-git")
$validConfig.PowerShell.OhMyPoshTheme = ".mytheme-new.omp.json"

$result = Test-DevkitConfig -Config $validConfig
$status = if ($result.IsValid) { "[green]PASS[/]" } else { "[red]FAIL[/]" }
Write-SpectreHost "  $status - Valid config -> IsValid: $($result.IsValid)"

# Invalid config (missing email)
$invalidConfig = New-DevkitConfig
$invalidConfig.Git.DefaultProfile.Name = "John Doe"
$invalidConfig.Git.DefaultProfile.Email = "invalid"

$result = Test-DevkitConfig -Config $invalidConfig
$status = if (-not $result.IsValid) { "[green]PASS[/]" } else { "[red]FAIL[/]" }
Write-SpectreHost "  $status - Invalid config -> IsValid: $($result.IsValid), Errors: $($result.Errors.Count)"
if ($result.Errors.Count -gt 0) {
    foreach ($error in $result.Errors) {
        Write-SpectreHost "    [dim]- $error[/]"
    }
}
#endregion

Write-Host ""
Write-Host "=== All Tests Complete ===" -ForegroundColor Green
