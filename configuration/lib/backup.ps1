#Requires -Version 7.0
<#
.SYNOPSIS
    Backup system for Devkit configuration files

.DESCRIPTION
    Contains functions to backup existing configuration files before
    modification, with automatic cleanup of old backups.
#>

# Default backup directory
$script:BackupRoot = Join-Path $env:USERPROFILE ".devkit-backups"

#region Backup Directory Management

function Initialize-BackupDirectory {
    <#
    .SYNOPSIS
        Creates the backup directory if it doesn't exist
    .OUTPUTS
        String - Path to backup directory
    #>

    if (-not (Test-Path $script:BackupRoot)) {
        New-Item -Path $script:BackupRoot -ItemType Directory -Force | Out-Null
        Write-Verbose "Created backup directory: $script:BackupRoot"
    }

    return $script:BackupRoot
}

function Get-BackupDirectory {
    <#
    .SYNOPSIS
        Returns the backup directory path
    #>
    return $script:BackupRoot
}

#endregion

#region Backup Functions

function Backup-ConfigFile {
    <#
    .SYNOPSIS
        Creates a timestamped backup of a configuration file
    .PARAMETER Path
        Path to the file to backup
    .PARAMETER Description
        Optional description for the backup (used in filename)
    .OUTPUTS
        String - Path to the backup file, or $null if source doesn't exist
    .EXAMPLE
        Backup-ConfigFile -Path "$env:USERPROFILE\.gitconfig" -Description "gitconfig"
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [string]$Description = ""
    )

    # Check if source file exists
    if (-not (Test-Path $Path)) {
        Write-Verbose "File does not exist, skipping backup: $Path"
        return $null
    }

    # Ensure backup directory exists
    $backupDir = Initialize-BackupDirectory

    # Generate backup filename with timestamp
    $timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
    $originalName = Split-Path $Path -Leaf

    if ($Description) {
        $backupName = "${Description}_${timestamp}_${originalName}"
    } else {
        $backupName = "${timestamp}_${originalName}"
    }

    $backupPath = Join-Path $backupDir $backupName

    # Copy file to backup location
    try {
        Copy-Item -Path $Path -Destination $backupPath -Force
        Write-Verbose "Backed up: $Path -> $backupPath"
        return $backupPath
    } catch {
        Write-Warning "Failed to backup file: $_"
        return $null
    }
}

function Backup-AllConfigFiles {
    <#
    .SYNOPSIS
        Backs up all standard configuration files
    .OUTPUTS
        Hashtable with backup results
    #>

    $results = @{
        Success = $true
        Backups = @()
        Errors = @()
    }

    # Files to backup
    $filesToBackup = @(
        @{ Path = (Join-Path $env:USERPROFILE ".gitconfig"); Description = "gitconfig" }
        @{ Path = $PROFILE; Description = "powershell-profile" }
    )

    # Also backup any .gitconfig-* files (additional profiles)
    $additionalGitConfigs = Get-ChildItem -Path $env:USERPROFILE -Filter ".gitconfig-*" -ErrorAction SilentlyContinue
    foreach ($config in $additionalGitConfigs) {
        $filesToBackup += @{ Path = $config.FullName; Description = "gitconfig-profile" }
    }

    foreach ($file in $filesToBackup) {
        $backupPath = Backup-ConfigFile -Path $file.Path -Description $file.Description
        if ($backupPath) {
            $results.Backups += @{
                Original = $file.Path
                Backup = $backupPath
            }
        }
    }

    return $results
}

#endregion

#region Cleanup Functions

function Get-BackupFiles {
    <#
    .SYNOPSIS
        Lists all backup files, optionally filtered by description
    .PARAMETER Description
        Optional filter for backup description
    .OUTPUTS
        Array of FileInfo objects
    #>
    param(
        [string]$Description = ""
    )

    $backupDir = Get-BackupDirectory

    if (-not (Test-Path $backupDir)) {
        return @()
    }

    if ($Description) {
        return Get-ChildItem -Path $backupDir -Filter "${Description}_*" | Sort-Object LastWriteTime -Descending
    } else {
        return Get-ChildItem -Path $backupDir | Sort-Object LastWriteTime -Descending
    }
}

function Remove-OldBackups {
    <#
    .SYNOPSIS
        Removes old backups, keeping only the most recent ones
    .PARAMETER KeepCount
        Number of most recent backups to keep (default: 5)
    .PARAMETER Description
        Optional filter to only clean up specific backup types
    .OUTPUTS
        Number of files removed
    #>
    param(
        [int]$KeepCount = 5,
        [string]$Description = ""
    )

    $backups = Get-BackupFiles -Description $Description
    $removedCount = 0

    if ($backups.Count -gt $KeepCount) {
        $toRemove = $backups | Select-Object -Skip $KeepCount

        foreach ($file in $toRemove) {
            try {
                Remove-Item -Path $file.FullName -Force
                $removedCount++
                Write-Verbose "Removed old backup: $($file.Name)"
            } catch {
                Write-Warning "Failed to remove backup: $($file.Name)"
            }
        }
    }

    return $removedCount
}

function Invoke-BackupCleanup {
    <#
    .SYNOPSIS
        Cleans up old backups for all backup types
    .PARAMETER KeepCount
        Number of backups to keep per type (default: 5)
    #>
    param(
        [int]$KeepCount = 5
    )

    $backupTypes = @("gitconfig", "powershell-profile", "gitconfig-profile")

    $totalRemoved = 0
    foreach ($type in $backupTypes) {
        $removed = Remove-OldBackups -KeepCount $KeepCount -Description $type
        $totalRemoved += $removed
    }

    if ($totalRemoved -gt 0) {
        Write-Verbose "Cleaned up $totalRemoved old backup files"
    }

    return $totalRemoved
}

#endregion

#region Restore Functions

function Restore-ConfigFile {
    <#
    .SYNOPSIS
        Restores a configuration file from backup
    .PARAMETER BackupPath
        Path to the backup file
    .PARAMETER DestinationPath
        Path where to restore the file
    .OUTPUTS
        Boolean - True if restore succeeded
    #>
    param(
        [Parameter(Mandatory)]
        [string]$BackupPath,

        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    if (-not (Test-Path $BackupPath)) {
        Write-Warning "Backup file not found: $BackupPath"
        return $false
    }

    try {
        Copy-Item -Path $BackupPath -Destination $DestinationPath -Force
        Write-Verbose "Restored: $BackupPath -> $DestinationPath"
        return $true
    } catch {
        Write-Warning "Failed to restore file: $_"
        return $false
    }
}

function Get-LatestBackup {
    <#
    .SYNOPSIS
        Gets the most recent backup for a specific type
    .PARAMETER Description
        Backup type description (e.g., "gitconfig")
    .OUTPUTS
        FileInfo object or $null
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Description
    )

    $backups = Get-BackupFiles -Description $Description
    return $backups | Select-Object -First 1
}

#endregion

# Functions exported when dot-sourced:
# - Initialize-BackupDirectory, Get-BackupDirectory
# - Backup-ConfigFile, Backup-AllConfigFiles
# - Get-BackupFiles, Remove-OldBackups, Invoke-BackupCleanup
# - Restore-ConfigFile, Get-LatestBackup
