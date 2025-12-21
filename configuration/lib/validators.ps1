#Requires -Version 7.0
<#
.SYNOPSIS
    Input validation functions for Devkit wizard

.DESCRIPTION
    Contains validation functions for email, directory paths, names,
    and other user inputs collected by the wizard.
#>

#region Email Validation

function Test-EmailAddress {
    <#
    .SYNOPSIS
        Validates an email address format
    .PARAMETER Email
        The email address to validate
    .OUTPUTS
        Boolean - True if valid, False otherwise
    .EXAMPLE
        Test-EmailAddress -Email "user@example.com"  # Returns $true
        Test-EmailAddress -Email "invalid"           # Returns $false
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Email
    )

    if ([string]::IsNullOrWhiteSpace($Email)) {
        return $false
    }

    $emailPattern = '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    return $Email -match $emailPattern
}

function Read-ValidatedEmail {
    <#
    .SYNOPSIS
        Prompts for an email address with validation
    .PARAMETER Prompt
        The prompt message to display
    .PARAMETER DefaultValue
        Optional default value
    .OUTPUTS
        String - Valid email address
    #>
    param(
        [string]$Prompt = "Enter email address",
        [string]$DefaultValue = ""
    )

    do {
        if ($DefaultValue) {
            $email = Read-SpectreText -Prompt $Prompt -DefaultAnswer $DefaultValue
        } else {
            $email = Read-SpectreText -Prompt $Prompt
        }

        if (Test-EmailAddress -Email $email) {
            return $email
        }

        Write-SpectreHost "[red]Invalid email format. Please enter a valid email address.[/]"
    } while ($true)
}

#endregion

#region Directory Path Validation

function Test-DirectoryPath {
    <#
    .SYNOPSIS
        Validates a Windows directory path format
    .PARAMETER Path
        The directory path to validate
    .PARAMETER MustExist
        If true, the directory must exist
    .OUTPUTS
        Hashtable with IsValid (bool) and Exists (bool)
    .EXAMPLE
        Test-DirectoryPath -Path "C:/repos"
        Test-DirectoryPath -Path "C:/repos" -MustExist
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Path,

        [switch]$MustExist
    )

    $result = @{
        IsValid = $false
        Exists = $false
        NormalizedPath = ""
    }

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $result
    }

    # Check for valid Windows path pattern
    # Supports: C:\path, C:/path, D:\repos\work, etc.
    $pathPattern = '^[a-zA-Z]:[/\\]'

    if (-not ($Path -match $pathPattern)) {
        return $result
    }

    # Normalize path (convert forward slashes to backslashes)
    $normalizedPath = $Path -replace '/', '\'

    # Ensure trailing backslash for directory paths
    if (-not $normalizedPath.EndsWith('\')) {
        $normalizedPath += '\'
    }

    $result.NormalizedPath = $normalizedPath
    $result.IsValid = $true
    $result.Exists = Test-Path -Path $normalizedPath -PathType Container

    if ($MustExist -and -not $result.Exists) {
        $result.IsValid = $false
    }

    return $result
}

function Read-ValidatedPath {
    <#
    .SYNOPSIS
        Prompts for a directory path with validation and optional creation
    .PARAMETER Prompt
        The prompt message to display
    .PARAMETER DefaultValue
        Optional default value
    .PARAMETER AllowCreate
        If true, offer to create missing directories
    .OUTPUTS
        String - Valid directory path (normalized)
    #>
    param(
        [string]$Prompt = "Enter directory path",
        [string]$DefaultValue = "",
        [switch]$AllowCreate
    )

    do {
        if ($DefaultValue) {
            $path = Read-SpectreText -Prompt $Prompt -DefaultAnswer $DefaultValue
        } else {
            $path = Read-SpectreText -Prompt $Prompt
        }

        $validation = Test-DirectoryPath -Path $path

        if (-not $validation.IsValid) {
            Write-SpectreHost "[red]Invalid path format. Please enter a valid Windows path (e.g., C:\repos)[/]"
            continue
        }

        if (-not $validation.Exists) {
            if ($AllowCreate) {
                $create = Read-SpectreConfirm -Prompt "Directory doesn't exist. Create it?" -DefaultAnswer "y"
                if ($create) {
                    try {
                        New-Item -Path $validation.NormalizedPath -ItemType Directory -Force | Out-Null
                        Write-SpectreHost "[green]Directory created: $($validation.NormalizedPath)[/]"
                        return $validation.NormalizedPath
                    } catch {
                        Write-SpectreHost "[red]Failed to create directory: $_[/]"
                        continue
                    }
                } else {
                    continue
                }
            } else {
                Write-SpectreHost "[yellow]Warning: Directory doesn't exist: $($validation.NormalizedPath)[/]"
            }
        }

        return $validation.NormalizedPath
    } while ($true)
}

#endregion

#region Name Validation

function Test-NonEmptyString {
    <#
    .SYNOPSIS
        Validates that a string is not empty or whitespace
    .PARAMETER Value
        The string to validate
    .PARAMETER MinLength
        Optional minimum length
    .OUTPUTS
        Boolean
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Value,

        [int]$MinLength = 1
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    return $Value.Trim().Length -ge $MinLength
}

function Read-ValidatedName {
    <#
    .SYNOPSIS
        Prompts for a name with validation
    .PARAMETER Prompt
        The prompt message to display
    .PARAMETER DefaultValue
        Optional default value
    .OUTPUTS
        String - Non-empty name
    #>
    param(
        [string]$Prompt = "Enter name",
        [string]$DefaultValue = ""
    )

    do {
        if ($DefaultValue) {
            $name = Read-SpectreText -Prompt $Prompt -DefaultAnswer $DefaultValue
        } else {
            $name = Read-SpectreText -Prompt $Prompt
        }

        if (Test-NonEmptyString -Value $name) {
            return $name.Trim()
        }

        Write-SpectreHost "[red]Name cannot be empty. Please enter a valid name.[/]"
    } while ($true)
}

#endregion

#region Configuration Data Model

function New-DevkitConfig {
    <#
    .SYNOPSIS
        Creates a new empty DevkitConfig hashtable
    .OUTPUTS
        Hashtable - Empty configuration structure
    #>

    return @{
        Mode = "Fresh"  # "Fresh" or "Update"
        RepoLocations = @()
        Git = @{
            DefaultProfile = @{
                Name = ""
                Email = ""
            }
            AdditionalProfiles = @()
        }
        PowerShell = @{
            Modules = @()
            OhMyPoshTheme = ""
        }
        InstallPath = ""
        BackupPath = ""
    }
}

function Test-DevkitConfig {
    <#
    .SYNOPSIS
        Validates a DevkitConfig hashtable has required fields
    .PARAMETER Config
        The configuration to validate
    .OUTPUTS
        Hashtable with IsValid (bool) and Errors (array)
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $result = @{
        IsValid = $true
        Errors = @()
    }

    # Check Git default profile
    if (-not (Test-NonEmptyString -Value $Config.Git.DefaultProfile.Name)) {
        $result.IsValid = $false
        $result.Errors += "Git name is required"
    }

    if (-not (Test-EmailAddress -Email $Config.Git.DefaultProfile.Email)) {
        $result.IsValid = $false
        $result.Errors += "Valid Git email is required"
    }

    # Check repo locations
    if ($Config.RepoLocations.Count -eq 0) {
        $result.IsValid = $false
        $result.Errors += "At least one repository location is required"
    }

    # Check PowerShell modules
    if ($Config.PowerShell.Modules.Count -eq 0) {
        $result.IsValid = $false
        $result.Errors += "At least one PowerShell module must be selected"
    }

    # Check Oh-My-Posh theme
    if (-not (Test-NonEmptyString -Value $Config.PowerShell.OhMyPoshTheme)) {
        $result.IsValid = $false
        $result.Errors += "Oh-My-Posh theme is required"
    }

    return $result
}

#endregion

# Functions exported when dot-sourced:
# - Test-EmailAddress, Read-ValidatedEmail
# - Test-DirectoryPath, Read-ValidatedPath
# - Test-NonEmptyString, Read-ValidatedName
# - New-DevkitConfig, Test-DevkitConfig
