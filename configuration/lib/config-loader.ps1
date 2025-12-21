#Requires -Version 7.0
<#
.SYNOPSIS
    Configuration loader for detecting existing Devkit setup

.DESCRIPTION
    Contains functions to detect and parse existing Git configuration,
    PowerShell profile, and Devkit variables to support update mode.
#>

#region Git Configuration Detection

function Get-ExistingGitConfig {
    <#
    .SYNOPSIS
        Parses existing ~/.gitconfig for user settings
    .OUTPUTS
        Hashtable with Name, Email, and AdditionalProfiles
    #>

    $result = @{
        Found = $false
        DefaultProfile = @{
            Name = ""
            Email = ""
        }
        AdditionalProfiles = @()
        IncludeIfPaths = @()
    }

    $gitConfigPath = Join-Path $env:USERPROFILE ".gitconfig"

    if (-not (Test-Path $gitConfigPath)) {
        return $result
    }

    $result.Found = $true

    try {
        $content = Get-Content $gitConfigPath -Raw

        # Parse [user] section for default name/email
        if ($content -match '\[user\]\s*\n\s*name\s*=\s*(.+?)\s*\n') {
            $result.DefaultProfile.Name = $Matches[1].Trim()
        }

        if ($content -match '\[user\]\s*\n.*?email\s*=\s*(.+?)\s*\n') {
            $result.DefaultProfile.Email = $Matches[1].Trim()
        }

        # Alternative: use git config command for more reliable parsing
        $gitName = git config --global user.name 2>$null
        $gitEmail = git config --global user.email 2>$null

        if ($gitName) { $result.DefaultProfile.Name = $gitName }
        if ($gitEmail) { $result.DefaultProfile.Email = $gitEmail }

        # Parse includeIf sections for additional profiles
        $includeIfPattern = '\[includeIf\s+"gitdir:([^"]+)"\]\s*\n\s*path\s*=\s*(.+?)\s*\n'
        $matches = [regex]::Matches($content, $includeIfPattern)

        foreach ($match in $matches) {
            $directory = $match.Groups[1].Value
            $configPath = $match.Groups[2].Value

            $profile = @{
                Directory = $directory
                ConfigPath = $configPath
                Name = ""
                Email = ""
            }

            # Try to read the included config file
            if (Test-Path $configPath) {
                $profileContent = Get-Content $configPath -Raw -ErrorAction SilentlyContinue
                if ($profileContent) {
                    if ($profileContent -match 'name\s*=\s*(.+?)\s*\n') {
                        $profile.Name = $Matches[1].Trim()
                    }
                    if ($profileContent -match 'email\s*=\s*(.+?)\s*\n') {
                        $profile.Email = $Matches[1].Trim()
                    }
                }
            }

            $result.AdditionalProfiles += $profile
            $result.IncludeIfPaths += $directory
        }
    }
    catch {
        Write-Warning "Error parsing git config: $_"
    }

    return $result
}

#endregion

#region PowerShell Profile Detection

function Get-ExistingPowerShellConfig {
    <#
    .SYNOPSIS
        Detects Devkit markers in PowerShell profile
    .OUTPUTS
        Hashtable with Found, DevkitInstalled, ProfilePath, and markers
    #>

    $result = @{
        Found = $false
        DevkitInstalled = $false
        ProfilePath = $PROFILE
        DevkitMarker = $false
        VariablesPath = ""
        OhMyPoshTheme = ""
    }

    if (-not (Test-Path $PROFILE)) {
        return $result
    }

    $result.Found = $true

    try {
        $content = Get-Content $PROFILE -Raw

        # Check for Devkit markers
        if ($content -match 'DevKit Profile Configuration|DEVKIT_ROOT|devkit') {
            $result.DevkitInstalled = $true
            $result.DevkitMarker = $true
        }

        # Try to find variables.ps1 path
        if ($content -match '\.\s*"?([^"]+variables\.ps1)"?') {
            $result.VariablesPath = $Matches[1]
        }

        # Try to find Oh-My-Posh theme
        if ($content -match 'oh-my-posh.*--config\s+"?([^"]+\.omp\.json)"?') {
            $result.OhMyPoshTheme = $Matches[1]
        }
    }
    catch {
        Write-Warning "Error parsing PowerShell profile: $_"
    }

    return $result
}

#endregion

#region Devkit Variables Detection

function Get-ExistingDevkitVariables {
    <#
    .SYNOPSIS
        Loads existing variables.ps1 if present
    .PARAMETER DevkitRoot
        Root path of the devkit installation
    .OUTPUTS
        Hashtable with variable values
    #>
    param(
        [string]$DevkitRoot = ""
    )

    $result = @{
        Found = $false
        DevkitRoot = ""
        PowerShellConfig = ""
        OhMyPoshTheme = ""
    }

    # Try common locations
    $possiblePaths = @()

    if ($DevkitRoot) {
        $possiblePaths += Join-Path $DevkitRoot "configuration\powershell\variables.ps1"
    }

    # Check environment variable
    if ($env:DEVKIT_ROOT) {
        $possiblePaths += Join-Path $env:DEVKIT_ROOT "configuration\powershell\variables.ps1"
    }

    # Check common repo locations
    $possiblePaths += "C:\repos\usualexpat-devkit\configuration\powershell\variables.ps1"
    $possiblePaths += "D:\repos\usualexpat-devkit\configuration\powershell\variables.ps1"

    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $result.Found = $true

            try {
                $content = Get-Content $path -Raw

                if ($content -match '\$env:DEVKIT_ROOT\s*=\s*"([^"]+)"') {
                    $result.DevkitRoot = $Matches[1]
                }

                if ($content -match '\$env:DEVKIT_POWERSHELL_CONFIG\s*=\s*"([^"]+)"') {
                    $result.PowerShellConfig = $Matches[1]
                }

                if ($content -match '\$env:DEVKIT_OMP_THEME\s*=\s*"([^"]+)"') {
                    $result.OhMyPoshTheme = $Matches[1]
                }
            }
            catch {
                Write-Warning "Error parsing variables.ps1: $_"
            }

            break
        }
    }

    return $result
}

#endregion

#region Repo Locations Detection

function Get-CommonRepoLocations {
    <#
    .SYNOPSIS
        Detects common repository locations on the system
    .OUTPUTS
        Array of existing repo directories
    #>

    $commonPaths = @(
        "C:\repos",
        "D:\repos",
        "C:\src",
        "D:\src",
        "C:\projects",
        "D:\projects",
        (Join-Path $env:USERPROFILE "source\repos"),
        (Join-Path $env:USERPROFILE "repos"),
        (Join-Path $env:USERPROFILE "projects")
    )

    $existingPaths = @()

    foreach ($path in $commonPaths) {
        if (Test-Path $path -PathType Container) {
            $existingPaths += $path
        }
    }

    return $existingPaths
}

#endregion

#region Combined Config Loader

function Get-ExistingConfiguration {
    <#
    .SYNOPSIS
        Loads all existing configuration into a DevkitConfig structure
    .PARAMETER DevkitRoot
        Optional root path of devkit installation
    .OUTPUTS
        Hashtable matching DevkitConfig structure with detected values
    #>
    param(
        [string]$DevkitRoot = ""
    )

    # Start with empty config
    $config = @{
        Mode = "Update"
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
        _Detection = @{
            GitConfigFound = $false
            ProfileFound = $false
            DevkitInstalled = $false
            VariablesFound = $false
        }
    }

    # Load Git configuration
    $gitConfig = Get-ExistingGitConfig
    $config._Detection.GitConfigFound = $gitConfig.Found

    if ($gitConfig.Found) {
        $config.Git.DefaultProfile.Name = $gitConfig.DefaultProfile.Name
        $config.Git.DefaultProfile.Email = $gitConfig.DefaultProfile.Email
        $config.Git.AdditionalProfiles = $gitConfig.AdditionalProfiles
    }

    # Load PowerShell profile info
    $psConfig = Get-ExistingPowerShellConfig
    $config._Detection.ProfileFound = $psConfig.Found
    $config._Detection.DevkitInstalled = $psConfig.DevkitInstalled

    if ($psConfig.OhMyPoshTheme) {
        $config.PowerShell.OhMyPoshTheme = $psConfig.OhMyPoshTheme
    }

    # Load Devkit variables
    $devkitVars = Get-ExistingDevkitVariables -DevkitRoot $DevkitRoot
    $config._Detection.VariablesFound = $devkitVars.Found

    if ($devkitVars.OhMyPoshTheme -and -not $config.PowerShell.OhMyPoshTheme) {
        $config.PowerShell.OhMyPoshTheme = $devkitVars.OhMyPoshTheme
    }

    # Detect repo locations
    $config.RepoLocations = Get-CommonRepoLocations

    # Detect installed modules
    $moduleNames = @("z", "posh-git", "Terminal-Icons", "PSReadLine", "PwshSpectreConsole")
    foreach ($moduleName in $moduleNames) {
        if (Get-Module -ListAvailable -Name $moduleName) {
            $config.PowerShell.Modules += $moduleName
        }
    }

    return $config
}

#endregion

# Functions exported when dot-sourced:
# - Get-ExistingGitConfig
# - Get-ExistingPowerShellConfig
# - Get-ExistingDevkitVariables
# - Get-CommonRepoLocations
# - Get-ExistingConfiguration
