#Requires -Version 7.0
<#
.SYNOPSIS
    Configuration file generator for Devkit

.DESCRIPTION
    Contains functions to generate .gitconfig, PowerShell profile,
    and variables.ps1 based on wizard configuration.
#>

#region Git Configuration Generation

function New-GitConfig {
    <#
    .SYNOPSIS
        Generates .gitconfig content from configuration
    .PARAMETER Config
        DevkitConfig hashtable with Git settings
    .OUTPUTS
        String - Generated .gitconfig content
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $content = @"
[user]
    name = $($Config.Git.DefaultProfile.Name)
    email = $($Config.Git.DefaultProfile.Email)

"@

    # Add includeIf sections for additional profiles
    foreach ($profile in $Config.Git.AdditionalProfiles) {
        $configFileName = Get-ProfileConfigFileName -Directory $profile.Directory
        $configPath = Join-Path $env:USERPROFILE $configFileName
        # Use forward slashes for git config
        $configPath = $configPath -replace '\\', '/'

        $content += @"
[includeIf "gitdir:$($profile.Directory)"]
    path = $configPath

"@
    }

    # Add standard git configuration
    $content += @"
[core]
    autocrlf = true
    longpaths = true

[alias]
    yesterday = !"git log --reverse --branches --since='yesterday' --author=`$(git config --get user.email) --format=format:'%C(cyan bold ul) %ad %Creset %C(magenta)%h %C(blue bold) %s %Cgreen%d' --date=local"
    recently = !"git log --reverse --branches --since='3 days ago' --author=`$(git config --get user.email) --format=format:'%C(cyan bold ul) %ad %Creset %C(magenta)%h %C(blue bold) %s %Cgreen%d' --date=local"
    lg = log --graph --abbrev-commit --decorate --date=relative --format=format:'%C(bold blue)%h%C(reset) - %C(bold green)(%ar)%C(reset) %C(white)%s%C(reset) %C(dim white)- %an%C(reset)%C(bold yellow)%d%C(reset)' --all
    ls = log --pretty=format:'%C(green bold)%h%C(blue bold)  [%cn]  %C(red)%d  %C(cyan bold)%s' --decorate
    ll = log --pretty=format:'%C(green bold)%h%C(blue bold)  [%cn]  %C(red)%d  %C(cyan bold)%s' --decorate --numstat
    st = status -s -b -uall
    amend = commit -a --amend

[push]
    default = simple
    autoSetupRemote = true

[branch]
    autoSetupRebase = always

[help]
    autocorrect = 20

[color]
    ui = always
"@

    return $content
}

function Get-ProfileConfigFileName {
    <#
    .SYNOPSIS
        Generates a config filename from a directory path
    .PARAMETER Directory
        Directory path for the profile
    .OUTPUTS
        String - Config filename like .gitconfig-repos-work
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Directory
    )

    # Clean up directory to create filename
    $cleanName = $Directory -replace '[:/\\]', '-'
    $cleanName = $cleanName.Trim('-')
    $cleanName = $cleanName -replace '--+', '-'

    return ".gitconfig-$cleanName"
}

function New-GitProfileConfig {
    <#
    .SYNOPSIS
        Generates a profile-specific .gitconfig file
    .PARAMETER Profile
        Profile hashtable with Name, Email, Directory
    .OUTPUTS
        String - Generated config content
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Profile
    )

    return @"
[user]
    name = $($Profile.Name)
    email = $($Profile.Email)
"@
}

function Save-GitConfig {
    <#
    .SYNOPSIS
        Saves the main .gitconfig file
    .PARAMETER Config
        DevkitConfig hashtable
    .PARAMETER Path
        Optional path (defaults to ~/.gitconfig)
    .OUTPUTS
        Boolean - True if successful
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,

        [string]$Path = ""
    )

    if (-not $Path) {
        $Path = Join-Path $env:USERPROFILE ".gitconfig"
    }

    try {
        $content = New-GitConfig -Config $Config
        Set-Content -Path $Path -Value $content -Encoding UTF8 -Force
        return $true
    } catch {
        Write-Warning "Failed to save .gitconfig: $_"
        return $false
    }
}

function Save-GitProfileConfigs {
    <#
    .SYNOPSIS
        Saves all additional profile .gitconfig files
    .PARAMETER Config
        DevkitConfig hashtable
    .OUTPUTS
        Array of saved file paths
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    $savedFiles = @()

    foreach ($profile in $Config.Git.AdditionalProfiles) {
        $fileName = Get-ProfileConfigFileName -Directory $profile.Directory
        $filePath = Join-Path $env:USERPROFILE $fileName

        try {
            $content = New-GitProfileConfig -Profile $profile
            Set-Content -Path $filePath -Value $content -Encoding UTF8 -Force
            $savedFiles += $filePath
        } catch {
            Write-Warning "Failed to save profile config $fileName : $_"
        }
    }

    return $savedFiles
}

#endregion

#region PowerShell Configuration Generation

function New-VariablesPs1 {
    <#
    .SYNOPSIS
        Generates variables.ps1 content
    .PARAMETER DevkitRoot
        Root path of the devkit installation
    .PARAMETER OhMyPoshTheme
        Path to Oh-My-Posh theme file
    .OUTPUTS
        String - Generated variables.ps1 content
    #>
    param(
        [Parameter(Mandatory)]
        [string]$DevkitRoot,

        [Parameter(Mandatory)]
        [string]$OhMyPoshTheme
    )

    # Normalize paths
    $devkitRoot = $DevkitRoot -replace '\\', '/'
    $themePath = $OhMyPoshTheme -replace '\\', '/'

    return @"
# Devkit Environment Variables
# Generated by Devkit Installation Wizard

`$env:DEVKIT_ROOT = "$devkitRoot"
`$env:DEVKIT_POWERSHELL_CONFIG = "`$env:DEVKIT_ROOT/configuration/powershell"
`$env:DEVKIT_OMP_THEME = "$themePath"
"@
}

function Save-VariablesPs1 {
    <#
    .SYNOPSIS
        Saves the variables.ps1 file
    .PARAMETER DevkitRoot
        Root path of the devkit installation
    .PARAMETER OhMyPoshTheme
        Path to Oh-My-Posh theme file
    .PARAMETER Path
        Optional output path
    .OUTPUTS
        Boolean - True if successful
    #>
    param(
        [Parameter(Mandatory)]
        [string]$DevkitRoot,

        [Parameter(Mandatory)]
        [string]$OhMyPoshTheme,

        [string]$Path = ""
    )

    if (-not $Path) {
        $Path = Join-Path $DevkitRoot "configuration/powershell/variables.ps1"
    }

    try {
        $content = New-VariablesPs1 -DevkitRoot $DevkitRoot -OhMyPoshTheme $OhMyPoshTheme

        # Ensure directory exists
        $dir = Split-Path $Path -Parent
        if (-not (Test-Path $dir)) {
            New-Item -Path $dir -ItemType Directory -Force | Out-Null
        }

        Set-Content -Path $Path -Value $content -Encoding UTF8 -Force
        return $true
    } catch {
        Write-Warning "Failed to save variables.ps1: $_"
        return $false
    }
}

function New-ProfileSnippet {
    <#
    .SYNOPSIS
        Generates the PowerShell profile snippet for devkit
    .PARAMETER DevkitRoot
        Root path of the devkit installation
    .OUTPUTS
        String - Profile snippet to add
    #>
    param(
        [Parameter(Mandatory)]
        [string]$DevkitRoot
    )

    $variablesPath = Join-Path $DevkitRoot "configuration/powershell/variables.ps1"
    $profilePath = Join-Path $DevkitRoot "configuration/powershell/Microsoft.PowerShell_profile.ps1"

    # Normalize to forward slashes
    $variablesPath = $variablesPath -replace '\\', '/'
    $profilePath = $profilePath -replace '\\', '/'

    return @"

# ===== DevKit Profile Configuration =====
# Load devkit variables
. "$variablesPath"

# Load devkit profile
. "$profilePath"
# ===== End DevKit Configuration =====
"@
}

function Update-PowerShellProfile {
    <#
    .SYNOPSIS
        Updates the PowerShell profile to include devkit
    .PARAMETER DevkitRoot
        Root path of the devkit installation
    .PARAMETER ProfilePath
        Optional profile path (defaults to $PROFILE)
    .OUTPUTS
        Boolean - True if successful
    #>
    param(
        [Parameter(Mandatory)]
        [string]$DevkitRoot,

        [string]$ProfilePath = ""
    )

    if (-not $ProfilePath) {
        $ProfilePath = $PROFILE
    }

    try {
        # Create profile if it doesn't exist
        if (-not (Test-Path $ProfilePath)) {
            $dir = Split-Path $ProfilePath -Parent
            if (-not (Test-Path $dir)) {
                New-Item -Path $dir -ItemType Directory -Force | Out-Null
            }
            New-Item -Path $ProfilePath -ItemType File -Force | Out-Null
        }

        $content = Get-Content $ProfilePath -Raw -ErrorAction SilentlyContinue
        if (-not $content) { $content = "" }

        # Check if devkit is already configured
        if ($content -match "DevKit Profile Configuration") {
            # Remove existing devkit configuration
            $content = $content -replace '(?s)# ===== DevKit Profile Configuration =====.*?# ===== End DevKit Configuration =====\r?\n?', ''
        }

        # Add new snippet
        $snippet = New-ProfileSnippet -DevkitRoot $DevkitRoot
        $content = $content.TrimEnd() + $snippet

        Set-Content -Path $ProfilePath -Value $content -Encoding UTF8 -Force
        return $true
    } catch {
        Write-Warning "Failed to update PowerShell profile: $_"
        return $false
    }
}

#endregion

#region Module Installation

function Install-RequiredModules {
    <#
    .SYNOPSIS
        Installs selected PowerShell modules
    .PARAMETER Modules
        Array of module names to install
    .OUTPUTS
        Hashtable with installation results
    #>
    param(
        [Parameter(Mandatory)]
        [array]$Modules
    )

    $results = @{
        Installed = @()
        AlreadyInstalled = @()
        Failed = @()
    }

    foreach ($moduleName in $Modules) {
        try {
            $existing = Get-Module -ListAvailable -Name $moduleName -ErrorAction SilentlyContinue

            if ($existing) {
                $results.AlreadyInstalled += $moduleName
            } else {
                Install-Module -Name $moduleName -Scope CurrentUser -Force -AllowClobber
                $results.Installed += $moduleName
            }
        } catch {
            $results.Failed += @{ Name = $moduleName; Error = $_.ToString() }
        }
    }

    return $results
}

#endregion

#region Full Installation

function Invoke-ConfigGeneration {
    <#
    .SYNOPSIS
        Generates all configuration files from wizard config
    .PARAMETER Config
        DevkitConfig hashtable
    .PARAMETER DevkitRoot
        Root path of the devkit installation
    .OUTPUTS
        Hashtable with generation results
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,

        [Parameter(Mandatory)]
        [string]$DevkitRoot
    )

    $results = @{
        Success = $true
        GitConfig = $false
        ProfileConfigs = @()
        Variables = $false
        Profile = $false
        Errors = @()
    }

    # Generate .gitconfig
    try {
        $results.GitConfig = Save-GitConfig -Config $Config
    } catch {
        $results.Errors += "GitConfig: $_"
        $results.Success = $false
    }

    # Generate profile-specific configs
    try {
        $results.ProfileConfigs = Save-GitProfileConfigs -Config $Config
    } catch {
        $results.Errors += "ProfileConfigs: $_"
        $results.Success = $false
    }

    # Generate variables.ps1
    try {
        $results.Variables = Save-VariablesPs1 -DevkitRoot $DevkitRoot -OhMyPoshTheme $Config.PowerShell.OhMyPoshTheme
    } catch {
        $results.Errors += "Variables: $_"
        $results.Success = $false
    }

    # Update PowerShell profile
    try {
        $results.Profile = Update-PowerShellProfile -DevkitRoot $DevkitRoot
    } catch {
        $results.Errors += "Profile: $_"
        $results.Success = $false
    }

    return $results
}

#endregion

# Functions exported when dot-sourced:
# - New-GitConfig, Save-GitConfig
# - Get-ProfileConfigFileName, New-GitProfileConfig, Save-GitProfileConfigs
# - New-VariablesPs1, Save-VariablesPs1
# - New-ProfileSnippet, Update-PowerShellProfile
# - Install-RequiredModules
# - Invoke-ConfigGeneration
