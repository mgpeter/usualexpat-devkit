#Requires -Version 7.0
<#
.SYNOPSIS
    Test script for backup system

.NOTES
    Run: pwsh -File test-backup.ps1
#>

# Enable UTF-8 encoding
$OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

# Import PwshSpectreConsole
Import-Module PwshSpectreConsole -Force

# Load backup module
. "$PSScriptRoot\lib\backup.ps1"

Write-Host "Testing Backup System..." -ForegroundColor Cyan
Write-Host ""

#region Test 1: Initialize backup directory
Write-Host "=== Test 1: Initialize Backup Directory ===" -ForegroundColor Yellow
$backupDir = Initialize-BackupDirectory
Write-Host "Backup directory: $backupDir"
Write-Host "Exists: $(Test-Path $backupDir)"
Write-Host ""
#endregion

#region Test 2: Backup a single file
Write-Host "=== Test 2: Backup Single File ===" -ForegroundColor Yellow
$gitconfigPath = Join-Path $env:USERPROFILE ".gitconfig"
if (Test-Path $gitconfigPath) {
    $backupPath = Backup-ConfigFile -Path $gitconfigPath -Description "test-gitconfig"
    Write-SpectreHost "[green]Backed up .gitconfig to: $backupPath[/]"
} else {
    Write-SpectreHost "[yellow].gitconfig not found, skipping test[/]"
}
Write-Host ""
#endregion

#region Test 3: Backup all config files
Write-Host "=== Test 3: Backup All Config Files ===" -ForegroundColor Yellow
$results = Backup-AllConfigFiles
Write-Host "Success: $($results.Success)"
Write-Host "Files backed up: $($results.Backups.Count)"
foreach ($backup in $results.Backups) {
    Write-Host "  - $($backup.Original) -> $(Split-Path $backup.Backup -Leaf)"
}
Write-Host ""
#endregion

#region Test 4: List backups
Write-Host "=== Test 4: List Backups ===" -ForegroundColor Yellow
$allBackups = Get-BackupFiles
Write-Host "Total backup files: $($allBackups.Count)"
$allBackups | Select-Object -First 5 | ForEach-Object {
    Write-Host "  - $($_.Name) ($($_.LastWriteTime))"
}
Write-Host ""
#endregion

#region Test 5: Get latest backup
Write-Host "=== Test 5: Get Latest Backup ===" -ForegroundColor Yellow
$latest = Get-LatestBackup -Description "gitconfig"
if ($latest) {
    Write-Host "Latest gitconfig backup: $($latest.Name)"
} else {
    Write-Host "No gitconfig backups found"
}
Write-Host ""
#endregion

Write-Host "=== Backup System Test Complete ===" -ForegroundColor Green
Write-Host ""
Write-Host "Backup directory location: $backupDir"
