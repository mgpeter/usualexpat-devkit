#Requires -Version 7.0
<#
.SYNOPSIS
    Sandboxed test script for the backup system

.DESCRIPTION
    Redirects USERPROFILE / APPDATA / LOCALAPPDATA to a scratch sandbox BEFORE
    dot-sourcing backup.ps1, so the real ~/.devkit/backups, ~/.gitconfig and ~/.claude
    are never touched.

    IT ALSO OVERRIDES $PROFILE, and that is not optional. $PROFILE is an automatic
    variable PowerShell resolves at startup from the Documents folder (often
    OneDrive-redirected) - it is NOT derived from $env:USERPROFILE, so redirecting the
    environment does not contain anything that reads or writes it. Backup-AllConfigFiles
    and Update-PowerShellProfile both use $PROFILE directly. Without this override this
    file snapshots the developer's real ~/.claude into their real ~/.devkit/backups on
    every run - which is exactly what it used to do.

    Test 6 is the regression guard: it records the real profile's hash before the
    override and fails if anything in this run touched it.

.NOTES
    Run: pwsh -File test-backup.ps1
    Exits non-zero if any assertion fails.
#>

# Enable UTF-8 encoding
$OutputEncoding = [console]::InputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$script:Failures = 0
function Assert($Condition, $Message) {
    if ($Condition) {
        Write-Host "  [PASS] $Message" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $Message" -ForegroundColor Red
        $script:Failures++
    }
}

# --- Record the REAL user paths before we redirect anything -------------------
$realProfilePath = $PROFILE
$realProfileHash = if (Test-Path $realProfilePath) { (Get-FileHash $realProfilePath).Hash } else { $null }
$realBackupDir = Join-Path $env:USERPROFILE ".devkit\backups"
$realBackupCount = if (Test-Path $realBackupDir) { @(Get-ChildItem $realBackupDir -Force).Count } else { 0 }

# --- Sandbox setup: redirect BEFORE dot-sourcing ------------------------------
$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("devkit-backup-test-" + [guid]::NewGuid().ToString('N').Substring(0,8))
$env:USERPROFILE = Join-Path $sandbox "home"
$env:APPDATA = Join-Path $sandbox "appdata"
$env:LOCALAPPDATA = Join-Path $sandbox "localappdata"
New-Item -Path $env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA -ItemType Directory -Force | Out-Null

# $PROFILE does not follow USERPROFILE - see the .DESCRIPTION above.
$global:PROFILE = Join-Path $env:USERPROFILE "Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
New-Item -Path (Split-Path $global:PROFILE -Parent) -ItemType Directory -Force | Out-Null
Set-Content -Path $global:PROFILE -Value "# sandbox profile" -Encoding UTF8 -Force

# Give the sandbox something to find, so the tests exercise real code paths.
Set-Content -Path (Join-Path $env:USERPROFILE ".gitconfig") -Value "[user]`n`tname = Sandbox User" -Encoding UTF8 -Force

Write-Host "Sandbox: $sandbox" -ForegroundColor Cyan
Write-Host ""

# Load backup module (AFTER the redirect - $script:BackupRoot is computed at file scope)
. "$PSScriptRoot\lib\backup.ps1"

Write-Host "Testing Backup System..." -ForegroundColor Cyan
Write-Host ""

#region Test 1: Initialize backup directory
Write-Host "=== Test 1: Initialize Backup Directory ===" -ForegroundColor Yellow
$backupDir = Initialize-BackupDirectory
Assert (Test-Path $backupDir) "backup directory created"
Assert ($backupDir -like "$sandbox*") "backup directory is inside the sandbox, not the real ~/.devkit"
Write-Host ""
#endregion

#region Test 2: Backup a single file
Write-Host "=== Test 2: Backup Single File ===" -ForegroundColor Yellow
$gitconfigPath = Join-Path $env:USERPROFILE ".gitconfig"
$backupPath = Backup-ConfigFile -Path $gitconfigPath -Description "test-gitconfig"
Assert ($null -ne $backupPath) "Backup-ConfigFile returned a path"
Assert (Test-Path $backupPath) "the backup file exists"
Assert ((Split-Path $backupPath -Leaf) -like "test-gitconfig_*_.gitconfig") "the backup is named <description>_<timestamp>_<original>"
Write-Host ""
#endregion

#region Test 3: Backup all config files
Write-Host "=== Test 3: Backup All Config Files ===" -ForegroundColor Yellow
$results = Backup-AllConfigFiles
Assert $results.Success "Backup-AllConfigFiles succeeded"
Assert ($results.Backups.Count -ge 1) "at least one file was backed up"
foreach ($backup in $results.Backups) {
    Write-Host "    $($backup.Original) -> $(Split-Path $backup.Backup -Leaf)" -ForegroundColor DarkGray
}
Assert (-not (@($results.Backups | Where-Object { $_.Backup -notlike "$sandbox*" }))) "every backup landed inside the sandbox"
Write-Host ""
#endregion

#region Test 4: List backups
Write-Host "=== Test 4: List Backups ===" -ForegroundColor Yellow
$allBackups = Get-BackupFiles
Assert ($allBackups.Count -ge 1) "Get-BackupFiles found the backups just written"
Write-Host ""
#endregion

#region Test 5: Get latest backup
Write-Host "=== Test 5: Get Latest Backup ===" -ForegroundColor Yellow
$latest = Get-LatestBackup -Description "gitconfig"
Assert ($null -ne $latest) "Get-LatestBackup found a gitconfig backup"
Write-Host ""
#endregion

#region Test 6: the sandbox actually held
# The whole point of this file's preamble. If someone removes the $PROFILE override or
# moves the dot-source above the redirect, this is what fails instead of quietly
# snapshotting the developer's home directory.
Write-Host "=== Test 6: Nothing escaped to the real user profile ===" -ForegroundColor Yellow
$nowHash = if (Test-Path $realProfilePath) { (Get-FileHash $realProfilePath).Hash } else { $null }
Assert ($nowHash -eq $realProfileHash) "the real `$PROFILE was not modified"

$nowCount = if (Test-Path $realBackupDir) { @(Get-ChildItem $realBackupDir -Force).Count } else { 0 }
Assert ($nowCount -eq $realBackupCount) "no new entries were written to the real ~/.devkit/backups"
Write-Host ""
#endregion

# --- Cleanup ------------------------------------------------------------------
Remove-Item -Path $sandbox -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
if ($script:Failures -eq 0) {
    Write-Host "All backup tests passed." -ForegroundColor Green
    exit 0
} else {
    Write-Host "$script:Failures assertion(s) failed." -ForegroundColor Red
    exit 1
}
