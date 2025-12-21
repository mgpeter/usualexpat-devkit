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

    # Core settings with sensible defaults
    $content += @'
[core]
    autocrlf = true
    longpaths = true
    editor = code --wait
    excludesfile = ~/.gitignore_global

'@

    # Daily workflow aliases
    $content += @'
[alias]
    yesterday = !"git log --reverse --branches --since='yesterday' --author=$(git config --get user.email) --format=format:'%C(cyan bold ul) %ad %Creset %C(magenta)%h %C(blue bold) %s %Cgreen%d' --date=local"
    recently = !"git log --reverse --branches --since='3 days ago' --author=$(git config --get user.email) --format=format:'%C(cyan bold ul) %ad %Creset %C(magenta)%h %C(blue bold) %s %Cgreen%d' --date=local"
    standup = !"git log --reverse --branches --since='$(if [[ \"Mon\" == \"$(date +%a)\" ]]; then echo \"last friday\"; else echo \"yesterday\"; fi)' --author=$(git config --get user.email) --format=format:'%C(cyan bold ul) %ad %Creset %C(magenta)%h %C(blue bold) %s %Cgreen%d' --date=local"

'@

    # Log formatting aliases
    $content += @'
[alias]
    lg1 = log --graph --abbrev-commit --decorate --date=relative --format=format:'%C(bold blue)%h%C(reset) - %C(bold green)(%ar)%C(reset) %C(white)%s%C(reset) %C(dim white)- %an%C(reset)%C(bold yellow)%d%C(reset)' --all
    lg2 = log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) - %C(bold cyan)%aD%C(reset) %C(bold green)(%ar)%C(reset)%C(bold yellow)%d%C(reset)%n''          %C(white)%s%C(reset) %C(dim white)- %an%C(reset)' --all
    lg = !"git lg1"
    ls = log --pretty=format:'%C(green bold)%h%C(blue bold)  [%cn]  %C(red)%d  %C(cyan bold)%s' --decorate
    la = log --pretty=format:'%C(green bold)%h%C(blue bold)  [%cn]  %C(red)%d  %C(cyan bold)%s' --decorate --all
    ll = log --pretty=format:'%C(green bold)%h%C(blue bold)  [%cn]  %C(red)%d  %C(cyan bold)%s' --decorate --numstat

'@

    # Commit and status aliases
    $content += @'
[alias]
    amend = commit -a --amend
    st = status -s -b -uall
    topcom = shortlog -s -n --since=2017-01-01
    prettydiff = log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr)%Creset' --abbrev-commit --date=relative

'@

    # Utility aliases (hash collision, conflict resolution, new commits)
    $content += @'
[alias]
    abbr = "!sh -c 'git rev-list --all | grep ^$1 | while read commit; do git --no-pager log -n1 --pretty=format:\"%H %ci %an %s%n\" $commit; done' -"
    gitkconflict = !gitk --left-right HEAD...MERGE_HEAD
    new = !sh -c 'git log $1@{1}..$1@{0} "$@"'

'@

    # Push, branch, and help settings
    $content += @'
[push]
    default = simple
    autoSetupRemote = true

[branch]
    autoSetupRebase = always

[help]
    autocorrect = 20

'@

    # Full color configuration
    $content += @'
[color]
    ui = always
    branch = always
    diff = always
    interactive = always
    status = always
    grep = always
    pager = true
    decorate = always
    showbranch = always

'@

    # GPG sections (disabled by default)
    $content += @'
[gpg]
    program = gpg

[commit]
    gpgSign = false

[tag]
    forceSignAnnotated = false
'@

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

#region User Space Installation

function Get-DevkitUserRoot {
    <#
    .SYNOPSIS
        Returns the devkit user installation directory
    .OUTPUTS
        String - Path to ~/.devkit/
    #>
    return Join-Path $env:USERPROFILE ".devkit"
}

function Initialize-DevkitUserSpace {
    <#
    .SYNOPSIS
        Creates the devkit user space directory structure
    .OUTPUTS
        Boolean - True if successful
    #>
    $userRoot = Get-DevkitUserRoot

    try {
        # Create main devkit directory
        if (-not (Test-Path $userRoot)) {
            New-Item -Path $userRoot -ItemType Directory -Force | Out-Null
        }

        # Create themes subdirectory
        $themesDir = Join-Path $userRoot "themes"
        if (-not (Test-Path $themesDir)) {
            New-Item -Path $themesDir -ItemType Directory -Force | Out-Null
        }

        # Create backups subdirectory
        $backupsDir = Join-Path $userRoot "backups"
        if (-not (Test-Path $backupsDir)) {
            New-Item -Path $backupsDir -ItemType Directory -Force | Out-Null
        }

        return $true
    } catch {
        Write-Warning "Failed to initialize devkit user space: $_"
        return $false
    }
}

function Copy-DevkitProfile {
    <#
    .SYNOPSIS
        Copies the PowerShell profile template to user space
    .PARAMETER SourceRoot
        Root path of the source devkit repo
    .OUTPUTS
        String - Path to copied profile, or empty string on failure
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot
    )

    $userRoot = Get-DevkitUserRoot
    $sourcePath = Join-Path $SourceRoot "configuration/powershell/Microsoft.PowerShell_profile.ps1"
    $destPath = Join-Path $userRoot "profile.ps1"

    try {
        if (-not (Test-Path $sourcePath)) {
            Write-Warning "Source profile not found: $sourcePath"
            return ""
        }

        Copy-Item -Path $sourcePath -Destination $destPath -Force
        return $destPath
    } catch {
        Write-Warning "Failed to copy profile: $_"
        return ""
    }
}

function Copy-DevkitTheme {
    <#
    .SYNOPSIS
        Copies the selected Oh-My-Posh theme to user space
    .PARAMETER SourceThemePath
        Full path to the source theme file
    .OUTPUTS
        String - Path to copied theme, or empty string on failure
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SourceThemePath
    )

    $userRoot = Get-DevkitUserRoot
    $themesDir = Join-Path $userRoot "themes"
    $themeName = Split-Path $SourceThemePath -Leaf
    $destPath = Join-Path $themesDir $themeName

    try {
        if (-not (Test-Path $SourceThemePath)) {
            Write-Warning "Source theme not found: $SourceThemePath"
            return ""
        }

        # Ensure themes directory exists
        if (-not (Test-Path $themesDir)) {
            New-Item -Path $themesDir -ItemType Directory -Force | Out-Null
        }

        Copy-Item -Path $SourceThemePath -Destination $destPath -Force
        return $destPath
    } catch {
        Write-Warning "Failed to copy theme: $_"
        return ""
    }
}

#endregion

#region PowerShell Configuration Generation

function New-VariablesPs1 {
    <#
    .SYNOPSIS
        Generates variables.ps1 content for user space installation
    .PARAMETER ThemePath
        Path to the copied Oh-My-Posh theme file in user space
    .OUTPUTS
        String - Generated variables.ps1 content
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ThemePath
    )

    # Normalize theme path to forward slashes
    $themePath = $ThemePath -replace '\\', '/'

    return @"
# Devkit Environment Variables
# Generated by Devkit Installation Wizard

`$env:DEVKIT_ROOT = "`$HOME/.devkit"
`$env:DEVKIT_OMP_THEME = "$themePath"
"@
}

function Save-VariablesPs1 {
    <#
    .SYNOPSIS
        Saves the variables.ps1 file to user space
    .PARAMETER ThemePath
        Path to the copied Oh-My-Posh theme file in user space
    .OUTPUTS
        Boolean - True if successful
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ThemePath
    )

    $userRoot = Get-DevkitUserRoot
    $variablesPath = Join-Path $userRoot "variables.ps1"

    try {
        $content = New-VariablesPs1 -ThemePath $ThemePath

        # Ensure directory exists
        if (-not (Test-Path $userRoot)) {
            New-Item -Path $userRoot -ItemType Directory -Force | Out-Null
        }

        Set-Content -Path $variablesPath -Value $content -Encoding UTF8 -Force
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
    .DESCRIPTION
        Creates a snippet that sources files from user space (~/.devkit/)
        This makes the installation independent of the source repo location
    .OUTPUTS
        String - Profile snippet to add
    #>

    return @'

# ===== DevKit Profile Configuration =====
# Load devkit variables and profile from user space
. "$HOME/.devkit/variables.ps1"
. "$HOME/.devkit/profile.ps1"
# ===== End DevKit Configuration =====
'@
}

function Update-PowerShellProfile {
    <#
    .SYNOPSIS
        Updates the PowerShell profile to include devkit
    .DESCRIPTION
        Adds a snippet to the user's PowerShell profile that sources
        devkit files from user space (~/.devkit/)
    .PARAMETER ProfilePath
        Optional profile path (defaults to $PROFILE)
    .OUTPUTS
        Boolean - True if successful
    #>
    param(
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
        $snippet = New-ProfileSnippet
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
    .DESCRIPTION
        Installs devkit to user space (~/.devkit/) by:
        1. Creating user space directory structure
        2. Copying profile template from source repo
        3. Copying selected theme to user space
        4. Generating variables.ps1 in user space
        5. Generating .gitconfig files
        6. Updating user's PowerShell profile
    .PARAMETER Config
        DevkitConfig hashtable
    .PARAMETER SourceRoot
        Root path of the source devkit repo (for copying templates)
    .OUTPUTS
        Hashtable with generation results
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,

        [Parameter(Mandatory)]
        [string]$SourceRoot
    )

    $results = @{
        Success = $true
        UserSpaceInit = $false
        ProfileCopied = ""
        ThemeCopied = ""
        GitConfig = $false
        ProfileConfigs = @()
        Variables = $false
        Profile = $false
        Errors = @()
    }

    # Step 1: Initialize user space directory structure
    try {
        $results.UserSpaceInit = Initialize-DevkitUserSpace
        if (-not $results.UserSpaceInit) {
            $results.Errors += "Failed to initialize user space"
            $results.Success = $false
            return $results
        }
    } catch {
        $results.Errors += "UserSpaceInit: $_"
        $results.Success = $false
        return $results
    }

    # Step 2: Copy profile template to user space
    try {
        $results.ProfileCopied = Copy-DevkitProfile -SourceRoot $SourceRoot
        if (-not $results.ProfileCopied) {
            $results.Errors += "Failed to copy profile template"
            $results.Success = $false
        }
    } catch {
        $results.Errors += "ProfileCopy: $_"
        $results.Success = $false
    }

    # Step 3: Copy theme to user space
    try {
        $results.ThemeCopied = Copy-DevkitTheme -SourceThemePath $Config.PowerShell.OhMyPoshTheme
        if (-not $results.ThemeCopied) {
            $results.Errors += "Failed to copy theme"
            $results.Success = $false
        }
    } catch {
        $results.Errors += "ThemeCopy: $_"
        $results.Success = $false
    }

    # Step 4: Generate variables.ps1 in user space
    try {
        if ($results.ThemeCopied) {
            $results.Variables = Save-VariablesPs1 -ThemePath $results.ThemeCopied
        }
    } catch {
        $results.Errors += "Variables: $_"
        $results.Success = $false
    }

    # Step 5: Generate .gitconfig
    try {
        $results.GitConfig = Save-GitConfig -Config $Config
    } catch {
        $results.Errors += "GitConfig: $_"
        $results.Success = $false
    }

    # Step 6: Generate profile-specific git configs
    try {
        $results.ProfileConfigs = Save-GitProfileConfigs -Config $Config
    } catch {
        $results.Errors += "ProfileConfigs: $_"
        $results.Success = $false
    }

    # Step 7: Update PowerShell profile to source from user space
    try {
        $results.Profile = Update-PowerShellProfile
    } catch {
        $results.Errors += "Profile: $_"
        $results.Success = $false
    }

    return $results
}

#endregion

# Functions exported when dot-sourced:
# User Space:
# - Get-DevkitUserRoot, Initialize-DevkitUserSpace
# - Copy-DevkitProfile, Copy-DevkitTheme
# Git:
# - New-GitConfig, Save-GitConfig
# - Get-ProfileConfigFileName, New-GitProfileConfig, Save-GitProfileConfigs
# PowerShell:
# - New-VariablesPs1, Save-VariablesPs1
# - New-ProfileSnippet, Update-PowerShellProfile
# Modules:
# - Install-RequiredModules
# Full Installation:
# - Invoke-ConfigGeneration
