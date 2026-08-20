#Requires -Version 7.0
<#
.SYNOPSIS
    Configuration file generator for Devkit

.DESCRIPTION
    Contains functions to generate .gitconfig, PowerShell profile,
    and variables.ps1 based on wizard configuration.
#>

#region Git Configuration Generation

# Section headers that New-GitConfig itself writes. Anything else found in an existing
# .gitconfig is carried over verbatim by Save-GitConfig, so hand-added settings and
# tool-written blocks (git-lfs filters, credential helpers, url rewrites) survive an
# install. Ownership keys on the FULL header: [gpg] is ours, [gpg "ssh"] is not.
$script:DevkitGitSections = @(
    'user', 'core', 'alias', 'push', 'branch', 'help', 'color', 'gpg', 'commit', 'tag', 'init'
)

$script:DevkitGitPreserveMarker = '# --- preserved from your previous .gitconfig (not managed by devkit) ---'

function Get-UnmanagedGitConfigSections {
    <#
    .SYNOPSIS
        Extracts the sections of an existing .gitconfig that the devkit does not author
    .DESCRIPTION
        Splits the file into [header] + body blocks and returns those whose header is not
        in $script:DevkitGitSections (and is not an includeIf, which New-GitConfig rebuilds
        from the configured profiles). A header carrying a subsection - [filter "lfs"],
        [gpg "ssh"] - is never owned, because New-GitConfig only ever writes bare headers.
        Content before the first header, and any previous preserve marker, is dropped.
    .PARAMETER Path
        Path to the .gitconfig to inspect
    .OUTPUTS
        Array of PSCustomObject with Header and Lines
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) { return @() }

    try {
        $lines = @(Get-Content -Path $Path -ErrorAction Stop)
    } catch {
        Write-Warning "Could not read $Path to preserve unmanaged sections: $_"
        return @()
    }

    $sections = [System.Collections.Generic.List[object]]::new()
    $current = $null

    foreach ($line in $lines) {
        # Drop a marker written by an earlier save so re-runs emit exactly one.
        if ($line.Trim() -eq $script:DevkitGitPreserveMarker) { continue }

        if ($line -match '^\s*\[(.+?)\]\s*$') {
            $header = $Matches[1].Trim()
            # 'filter "lfs"' -> name 'filter', subsection present
            $name = ($header -split '\s+', 2)[0].ToLowerInvariant()
            $hasSubsection = $header -match '\s'

            $owned = ($name -eq 'includeif') -or
                     ((-not $hasSubsection) -and ($script:DevkitGitSections -contains $name))

            if ($owned) {
                $current = $null
            } else {
                $current = [PSCustomObject]@{
                    Header = $header
                    Lines  = [System.Collections.Generic.List[string]]::new()
                }
                $current.Lines.Add($line)
                $sections.Add($current)
            }
        }
        elseif ($current) {
            $current.Lines.Add($line)
        }
    }

    # Trim trailing blank lines so the emitted file keeps one blank line between sections.
    foreach ($section in $sections) {
        while ($section.Lines.Count -gt 0 -and
               [string]::IsNullOrWhiteSpace($section.Lines[$section.Lines.Count - 1])) {
            $section.Lines.RemoveAt($section.Lines.Count - 1)
        }
    }

    return $sections.ToArray()
}


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
[includeIf "gitdir/i:$($profile.Directory)"]
    path = $configPath

"@
    }

    # Core settings with sensible defaults
    $editorValue = if ($Config.Git.Editor) { $Config.Git.Editor } else { "code --wait" }
    $content += @"
[core]
    autocrlf = true
    longpaths = true
    editor = $editorValue
    excludesfile = ~/.gitignore_global

"@

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

    # Repository defaults
    $content += @'
[init]
    defaultBranch = main

'@

    # GPG sections (signing disabled by default)
    $content += @'
[gpg]
    program = gpg
    format = openpgp

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
        # Collect what the devkit does not author BEFORE overwriting, so hand-added and
        # tool-written blocks (git-lfs filters, [gpg "ssh"], credential helpers, url
        # rewrites, safe.directory) survive an install or a re-run. Do not regress this
        # back to a plain overwrite - it silently destroys the user's own git settings.
        $preserved = @(Get-UnmanagedGitConfigSections -Path $Path)

        $content = New-GitConfig -Config $Config

        if ($preserved.Count -gt 0) {
            $content += "`r`n" + $script:DevkitGitPreserveMarker + "`r`n"
            foreach ($section in $preserved) {
                $content += "`r`n" + (($section.Lines) -join "`r`n") + "`r`n"
            }
        }

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

function New-GlobalGitIgnore {
    <#
    .SYNOPSIS
        Creates ~/.gitignore_global when it does not already exist
    .DESCRIPTION
        New-GitConfig points core.excludesfile at ~/.gitignore_global. Git ignores a
        missing excludesfile silently, so without this the setting is dead on a fresh
        machine. An existing file is never touched - the user's own rules win.
    .PARAMETER Path
        Optional path (defaults to ~/.gitignore_global)
    .OUTPUTS
        String - path to the file, or empty string on failure
    #>
    param(
        [string]$Path = ""
    )

    if (-not $Path) {
        $Path = Join-Path $env:USERPROFILE ".gitignore_global"
    }

    if (Test-Path $Path) { return $Path }

    $content = @'
# Global gitignore - applies to every repository on this machine.
# Created by devkit because .gitconfig sets core.excludesfile to this path.
# Add your own entries freely; devkit never overwrites an existing file.

# Windows shell cruft
Thumbs.db
ehthumbs.db
desktop.ini

# Editor / IDE local state
*.user
*.suo
.vs/
.idea/
'@

    try {
        Set-Content -Path $Path -Value $content -Encoding UTF8 -Force
        return $Path
    } catch {
        Write-Warning "Failed to create ${Path}: $_"
        return ""
    }
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

function Copy-DevkitCli {
    <#
    .SYNOPSIS
        Copies the devkit CLI script to user space
    .PARAMETER SourceRoot
        Root path of the source devkit repo
    .OUTPUTS
        String - Path to copied devkit.ps1, or empty string on failure
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot
    )

    $userRoot = Get-DevkitUserRoot
    $sourcePath = Join-Path $SourceRoot "configuration/powershell/devkit.ps1"
    $destPath = Join-Path $userRoot "devkit.ps1"

    try {
        if (-not (Test-Path $sourcePath)) {
            Write-Warning "Source devkit CLI not found: $sourcePath"
            return ""
        }

        Copy-Item -Path $sourcePath -Destination $destPath -Force
        return $destPath
    } catch {
        Write-Warning "Failed to copy devkit CLI: $_"
        return ""
    }
}

function Get-NvimUserRoot {
    <#
    .SYNOPSIS
        Returns the standard Neovim config directory on Windows
    .OUTPUTS
        String - Path to $env:LOCALAPPDATA\nvim
    #>
    return Join-Path $env:LOCALAPPDATA "nvim"
}

function Copy-DevkitNvimConfig {
    <#
    .SYNOPSIS
        Copies the bundled Neovim config template into the user's nvim directory
    .DESCRIPTION
        Lays down init.lua and lua/ from configuration/nvim/ to $env:LOCALAPPDATA\nvim\.
        Does NOT touch lazy-lock.json (lazy.nvim regenerates it on first launch)
        or nvim-data/ (plugin sources, cache, etc.). Idempotent; overwrites
        the source files on every run.
    .PARAMETER SourceRoot
        Root path of the source devkit repo
    .OUTPUTS
        String - Path to the nvim config root, or empty string on failure
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot
    )

    $sourceDir = Join-Path $SourceRoot "configuration/nvim"
    $destDir = Get-NvimUserRoot

    if (-not (Test-Path $sourceDir)) {
        Write-Warning "Source nvim template not found: $sourceDir"
        return ""
    }

    try {
        if (-not (Test-Path $destDir)) {
            New-Item -Path $destDir -ItemType Directory -Force | Out-Null
        }

        # Copy init.lua at the root
        $sourceInit = Join-Path $sourceDir "init.lua"
        if (Test-Path $sourceInit) {
            Copy-Item -Path $sourceInit -Destination (Join-Path $destDir "init.lua") -Force
        }

        # Copy lua/ tree recursively. Use the trailing wildcard form so we
        # merge into an existing lua/ rather than nesting a duplicate.
        $sourceLua = Join-Path $sourceDir "lua"
        if (Test-Path $sourceLua) {
            $destLua = Join-Path $destDir "lua"
            if (-not (Test-Path $destLua)) {
                New-Item -Path $destLua -ItemType Directory -Force | Out-Null
            }
            Copy-Item -Path (Join-Path $sourceLua "*") -Destination $destLua -Recurse -Force
        }

        return $destDir
    } catch {
        Write-Warning "Failed to copy Neovim config: $_"
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
    .PARAMETER SourceRoot
        Optional path to the source devkit repo (recorded as DEVKIT_REPO_ROOT)
    .OUTPUTS
        String - Generated variables.ps1 content
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ThemePath,

        [string]$SourceRoot = ""
    )

    # Normalize paths to forward slashes
    $themePath = $ThemePath -replace '\\', '/'

    $repoLine = ""
    if ($SourceRoot) {
        $repoPath = $SourceRoot -replace '\\', '/'
        $repoLine = "`$env:DEVKIT_REPO_ROOT = `"$repoPath`"`n"
    }

    return @"
# Devkit Environment Variables
# Generated by Devkit Installation Wizard

`$env:DEVKIT_ROOT = "`$HOME/.devkit"
`$env:DEVKIT_OMP_THEME = "$themePath"
$repoLine
"@
}

function Save-VariablesPs1 {
    <#
    .SYNOPSIS
        Saves the variables.ps1 file to user space
    .PARAMETER ThemePath
        Path to the copied Oh-My-Posh theme file in user space
    .PARAMETER SourceRoot
        Optional path to the source devkit repo (recorded as DEVKIT_REPO_ROOT)
    .OUTPUTS
        Boolean - True if successful
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ThemePath,

        [string]$SourceRoot = ""
    )

    $userRoot = Get-DevkitUserRoot
    $variablesPath = Join-Path $userRoot "variables.ps1"

    try {
        $content = New-VariablesPs1 -ThemePath $ThemePath -SourceRoot $SourceRoot

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
            $results.Variables = Save-VariablesPs1 -ThemePath $results.ThemeCopied -SourceRoot $SourceRoot
        }
    } catch {
        $results.Errors += "Variables: $_"
        $results.Success = $false
    }

    # Step 5: Generate .gitconfig
    try {
        $results.GitConfig = Save-GitConfig -Config $Config
        New-GlobalGitIgnore | Out-Null
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

#region Claude Code & Herdr

function Get-ClaudeUserRoot {
    <#
    .SYNOPSIS
        Returns the standard Claude Code config directory (~/.claude)
    .OUTPUTS
        String - Path to $env:USERPROFILE\.claude
    #>
    return Join-Path $env:USERPROFILE ".claude"
}

function Get-HerdrConfigRoot {
    <#
    .SYNOPSIS
        Returns the herdr app config directory (%APPDATA%\herdr)
    .OUTPUTS
        String - Path to $env:APPDATA\herdr
    #>
    return Join-Path $env:APPDATA "herdr"
}

function Copy-DevkitClaudeArea {
    <#
    .SYNOPSIS
        Merge-copies one Claude asset subdirectory into ~/.claude
    .DESCRIPTION
        Shared helper for the agents/skills/commands installers. Uses the
        trailing-wildcard form so existing user content in the target area is
        merged rather than nested (same approach as Copy-DevkitNvimConfig).
        Byte-verbatim copy preserves LF line endings (e.g. herd.sh).
    .PARAMETER SourceRoot
        Root path of the source devkit repo
    .PARAMETER Area
        Subdirectory name under configuration/claude/ and ~/.claude/ (e.g. "agents")
    .OUTPUTS
        String - Path to the installed area, or empty string on failure
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot,

        [Parameter(Mandatory)]
        [string]$Area
    )

    $sourceDir = Join-Path $SourceRoot "configuration/claude/$Area"
    $destDir = Join-Path (Get-ClaudeUserRoot) $Area

    if (-not (Test-Path $sourceDir)) {
        Write-Warning "Source Claude $Area not found: $sourceDir"
        return ""
    }

    try {
        if (-not (Test-Path $destDir)) {
            New-Item -Path $destDir -ItemType Directory -Force | Out-Null
        }

        # Trailing-wildcard form merges into an existing area rather than nesting.
        Copy-Item -Path (Join-Path $sourceDir "*") -Destination $destDir -Recurse -Force
        return $destDir
    } catch {
        Write-Warning "Failed to copy Claude ${Area}: $_"
        return ""
    }
}

function Copy-DevkitClaudeAgents {
    <#
    .SYNOPSIS
        Installs the bundled Claude subagents into ~/.claude/agents
    .PARAMETER SourceRoot
        Root path of the source devkit repo
    .OUTPUTS
        String - Path to the agents directory, or empty string on failure
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot
    )
    return Copy-DevkitClaudeArea -SourceRoot $SourceRoot -Area "agents"
}

function Copy-DevkitClaudeSkills {
    <#
    .SYNOPSIS
        Installs the bundled Claude skills (herdr, spin-up-herd) into ~/.claude/skills
    .PARAMETER SourceRoot
        Root path of the source devkit repo
    .OUTPUTS
        String - Path to the skills directory, or empty string on failure
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot
    )
    return Copy-DevkitClaudeArea -SourceRoot $SourceRoot -Area "skills"
}

function Copy-DevkitClaudeCommands {
    <#
    .SYNOPSIS
        Installs the bundled Claude slash commands into ~/.claude/commands
    .PARAMETER SourceRoot
        Root path of the source devkit repo
    .OUTPUTS
        String - Path to the commands directory, or empty string on failure
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot
    )
    return Copy-DevkitClaudeArea -SourceRoot $SourceRoot -Area "commands"
}

function Test-DevkitClaudeMdDrift {
    <#
    .SYNOPSIS
        Reports whether ~/.claude/CLAUDE.md has diverged from the bundled copy
    .DESCRIPTION
        The live file is where personal global instructions accumulate, so it regularly
        runs ahead of the repo. Callers use this to prompt instead of overwriting.
    .PARAMETER SourceRoot
        Root path of the source devkit repo
    .OUTPUTS
        Boolean - True when a local file exists and its content differs from the bundle
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot
    )

    $sourcePath = Join-Path $SourceRoot "configuration/claude/CLAUDE.md"
    $destPath = Join-Path (Get-ClaudeUserRoot) "CLAUDE.md"

    if (-not (Test-Path $sourcePath)) { return $false }
    if (-not (Test-Path $destPath)) { return $false }

    try {
        return ((Get-Content $sourcePath -Raw) -ne (Get-Content $destPath -Raw))
    } catch {
        # If it cannot be compared, treat it as drifted - refusing to overwrite is the
        # safe failure here.
        return $true
    }
}

function Copy-DevkitClaudeMd {
    <#
    .SYNOPSIS
        Installs the bundled global CLAUDE.md into ~/.claude/CLAUDE.md
    .DESCRIPTION
        Backs up any existing ~/.claude/CLAUDE.md before overwriting. If the live file
        has diverged from the bundled one it is left alone unless -Force is given, so a
        refresh cannot silently discard instructions added since the last install.
    .PARAMETER SourceRoot
        Root path of the source devkit repo
    .PARAMETER Force
        Overwrite even when the live file differs from the bundled copy
    .OUTPUTS
        Boolean - True if the file was installed or already matched
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot,

        [switch]$Force
    )

    $sourcePath = Join-Path $SourceRoot "configuration/claude/CLAUDE.md"
    $destDir = Get-ClaudeUserRoot
    $destPath = Join-Path $destDir "CLAUDE.md"

    if (-not (Test-Path $sourcePath)) {
        Write-Warning "Source CLAUDE.md not found: $sourcePath"
        return $false
    }

    try {
        if (-not (Test-Path $destDir)) {
            New-Item -Path $destDir -ItemType Directory -Force | Out-Null
        }

        if (-not $Force -and (Test-DevkitClaudeMdDrift -SourceRoot $SourceRoot)) {
            Write-Warning "$destPath differs from the bundled CLAUDE.md - leaving it in place. Re-run with -Force to overwrite (the existing file is backed up first)."
            return $false
        }

        # Back up an existing global instructions file before replacing it.
        Backup-ConfigFile -Path $destPath -Description "claude-md" | Out-Null

        Copy-Item -Path $sourcePath -Destination $destPath -Force
        return $true
    } catch {
        Write-Warning "Failed to copy CLAUDE.md: $_"
        return $false
    }
}

function Install-HerdrHookAndSettings {
    <#
    .SYNOPSIS
        Installs the herdr SessionStart hook file and merges its wiring into settings.json
    .DESCRIPTION
        Copies the portable herdr-agent-state.ps1 hook into ~/.claude/hooks, then
        performs a TARGETED merge of only hooks.SessionStart in ~/.claude/settings.json.
        All other settings (model, env, enabledPlugins, ...) are preserved untouched.
        Idempotent: any pre-existing herdr SessionStart entry (matched on the hook
        script name, which also heals a stale path from another machine) is replaced
        rather than duplicated. Backs up settings.json before writing.
    .PARAMETER SourceRoot
        Root path of the source devkit repo
    .OUTPUTS
        Boolean - True if successful
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot
    )

    $claudeRoot = Get-ClaudeUserRoot
    $hooksDir = Join-Path $claudeRoot "hooks"
    $sourceHook = Join-Path $SourceRoot "configuration/claude/hooks/herdr-agent-state.ps1"
    $destHook = Join-Path $hooksDir "herdr-agent-state.ps1"
    $settingsPath = Join-Path $claudeRoot "settings.json"

    try {
        # 1. Install the hook file
        if (-not (Test-Path $sourceHook)) {
            Write-Warning "Source herdr hook not found: $sourceHook"
            return $false
        }
        if (-not (Test-Path $hooksDir)) {
            New-Item -Path $hooksDir -ItemType Directory -Force | Out-Null
        }
        Copy-Item -Path $sourceHook -Destination $destHook -Force

        # 2. Back up settings.json before touching it
        Backup-ConfigFile -Path $settingsPath -Description "claude-settings" | Out-Null

        # 3. Load existing settings (mutable hashtables) or start fresh
        $settings = @{}
        if (Test-Path $settingsPath) {
            $raw = Get-Content -Path $settingsPath -Raw
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $settings = $raw | ConvertFrom-Json -AsHashtable -Depth 20
            }
        }

        # 4. Build the SessionStart command against the CURRENT user's ~/.claude
        $command = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$destHook`" session"

        # 5. Ensure structure without clobbering other keys
        if (-not $settings.ContainsKey('hooks')) { $settings['hooks'] = @{} }
        if (-not $settings['hooks'].ContainsKey('SessionStart')) { $settings['hooks']['SessionStart'] = @() }

        # 6. Idempotent de-dup: drop any existing herdr group, keep everything else
        $kept = foreach ($grp in @($settings['hooks']['SessionStart'])) {
            $isHerdr = $false
            foreach ($h in @($grp.hooks)) {
                if ("$($h.command)" -match 'herdr-agent-state\.ps1') { $isHerdr = $true }
            }
            if (-not $isHerdr) { $grp }
        }
        $herdrGroup = @{
            matcher = '*'
            hooks = @(@{ type = 'command'; command = $command; timeout = 10 })
        }
        $settings['hooks']['SessionStart'] = @($kept) + $herdrGroup

        # 7. Write back (Depth 20 avoids silent nested truncation; UTF8 = no BOM)
        $json = $settings | ConvertTo-Json -Depth 20
        Set-Content -Path $settingsPath -Value $json -Encoding UTF8 -Force
        return $true
    } catch {
        Write-Warning "Failed to install herdr hook/settings: $_"
        return $false
    }
}

function Save-HerdrConfig {
    <#
    .SYNOPSIS
        Writes %APPDATA%\herdr\config.toml with a discovered pwsh path
    .DESCRIPTION
        Reads the bundled config.toml template and replaces the tokenized
        default_shell with the pwsh path discovered by Test-PwshAvailable
        (preferring the update-surviving App Execution Alias shim). If pwsh is
        not found, the default_shell line is omitted so herdr falls back to its
        own default rather than a broken path. Backs up any existing config.toml.
    .PARAMETER SourceRoot
        Root path of the source devkit repo
    .OUTPUTS
        Boolean - True if successful
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot
    )

    $templatePath = Join-Path $SourceRoot "configuration/herdr/config.toml"
    $destDir = Get-HerdrConfigRoot
    $destPath = Join-Path $destDir "config.toml"

    if (-not (Test-Path $templatePath)) {
        Write-Warning "Source herdr config.toml not found: $templatePath"
        return $false
    }

    try {
        $text = Get-Content -Path $templatePath -Raw

        $pwsh = Test-PwshAvailable
        if ($pwsh.Found -and $pwsh.Path) {
            # Single-quoted TOML literal: backslashes in the Windows path are literal.
            $text = $text -replace '__PWSH_PATH__', $pwsh.Path
        } else {
            Write-Warning "pwsh not detected; leaving herdr default_shell unset."
            $text = $text -replace "(?m)^\s*default_shell\s*=.*$", "# default_shell not set (pwsh not detected)"
        }

        if (-not (Test-Path $destDir)) {
            New-Item -Path $destDir -ItemType Directory -Force | Out-Null
        }

        # Back up any existing herdr config before overwriting
        Backup-ConfigFile -Path $destPath -Description "herdr-config" | Out-Null

        Set-Content -Path $destPath -Value $text -Encoding UTF8 -Force
        return $true
    } catch {
        Write-Warning "Failed to save herdr config: $_"
        return $false
    }
}

#endregion

#region Claude Statusline

# Awesome Statusline (AwesomeJun/CC-statusline, MIT) is third-party code fetched
# from GitHub at install time. It is deliberately NOT vendored into this repo:
# the user asked for a fresh upstream copy, and vendoring would create a
# permanent drift-maintenance surface plus an attribution obligation.
$script:AwesomeStatusLineFileName   = 'awesome-statusline.ps1'
$script:AwesomeStatusLineRepoRaw    = 'https://raw.githubusercontent.com/AwesomeJun/CC-statusline'
$script:AwesomeStatusLineScriptPath = 'scripts/awesome-statusline-windows.ps1'
$script:AwesomeStatusLineSizes      = @('xsmall', 'small', 'medium', 'large', 'xlarge')

function Get-ClaudeStatusLinePath {
    <#
    .SYNOPSIS
        Returns the installed path of the Awesome Statusline renderer
    .OUTPUTS
        String - Path to ~/.claude/awesome-statusline.ps1
    #>
    return Join-Path (Get-ClaudeUserRoot) $script:AwesomeStatusLineFileName
}

function Remove-Utf8BomChar {
    <#
    .SYNOPSIS
        Strips a leading U+FEFF character from text
    .DESCRIPTION
        Upstream ships the renderer as UTF-8 WITH a BOM, and Invoke-WebRequest hands
        that BOM back as a literal U+FEFF CHARACTER rather than consuming it (likewise
        Get-Content -Raw on some hosts). Since the installer writes the file with a BOM
        of its own, the character has to go or the file lands with a DOUBLE BOM -
        three stray bytes plus a stray U+FEFF at the top of the script.
    .PARAMETER Text
        Text that may begin with a BOM character
    .OUTPUTS
        String - Text without a leading U+FEFF
    #>
    param([string]$Text)

    if ($Text -and $Text[0] -eq [char]0xFEFF) { return $Text.Substring(1) }
    return $Text
}

function Get-AwesomeStatusLineSource {
    <#
    .SYNOPSIS
        Fetches the Awesome Statusline renderer source text
    .DESCRIPTION
        THE SINGLE NETWORK SEAM for the statusline feature. Install-ClaudeStatusLine
        calls this BY NAME so the test harness can shadow it and run offline - do not
        inline Invoke-WebRequest into the caller.

        Resolution order:
          1. $env:DEVKIT_STATUSLINE_SOURCE pointing at an existing file (offline/proxy escape hatch)
          2. -RawBaseUrl, else $env:AWESOME_STATUSLINE_RAW (upstream's own variable), else the repo raw URL
    .PARAMETER RawBaseUrl
        Overrides the raw base URL (without the trailing script path)
    .PARAMETER Ref
        Git ref to fetch from. Defaults to main; set to a tag such as v3.3.2 to pin.
    .OUTPUTS
        Hashtable - @{ Success; Content; Source; Error }. Never throws.
    #>
    param(
        [string]$RawBaseUrl = '',
        [string]$Ref = 'main'
    )

    $result = @{ Success = $false; Content = ''; Source = ''; Error = '' }

    # 1. Local override wins, so an offline or proxied machine can still install.
    if ($env:DEVKIT_STATUSLINE_SOURCE -and (Test-Path $env:DEVKIT_STATUSLINE_SOURCE)) {
        try {
            $result.Content = Remove-Utf8BomChar (Get-Content -Path $env:DEVKIT_STATUSLINE_SOURCE -Raw)
            $result.Source = 'local-override'
            $result.Success = $true
            return $result
        } catch {
            $result.Error = "Failed to read DEVKIT_STATUSLINE_SOURCE: $_"
            return $result
        }
    }

    # 2. Resolve the base URL
    $base = $RawBaseUrl
    if (-not $base) { $base = $env:AWESOME_STATUSLINE_RAW }
    if (-not $base) { $base = "$script:AwesomeStatusLineRepoRaw/$Ref" }
    $uri = "$($base.TrimEnd('/'))/$script:AwesomeStatusLineScriptPath"

    try {
        $response = Invoke-WebRequest -Uri $uri -UseBasicParsing -TimeoutSec 20 -ErrorAction Stop
        $content = Remove-Utf8BomChar ([string]$response.Content)

        # Sanity gate: a captive portal or GitHub error page can arrive as HTTP 200.
        if ($content.Length -le 1000 -or $content -match '^\s*<(!DOCTYPE|html)') {
            $result.Error = "Downloaded content from $uri does not look like the renderer script."
            return $result
        }
        if ($content -notmatch 'param\(') {
            # Soft warning only: an upstream refactor should not hard-block the install.
            Write-Warning "Statusline renderer from $uri has no param() block; upstream may have changed."
        }

        $result.Content = $content
        $result.Source = $uri
        $result.Success = $true
        return $result
    } catch {
        $result.Error = "$_"
        return $result
    }
}

function Set-ClaudeStatusLineSetting {
    <#
    .SYNOPSIS
        Merges the statusLine key into ~/.claude/settings.json
    .DESCRIPTION
        Uses the same targeted-merge pattern as Install-HerdrHookAndSettings: the whole
        document is loaded as mutable hashtables and exactly one key is reassigned, so
        model, env, enabledPlugins, hooks and every other sibling survive untouched.

        statusLine is a single object rather than an array, so plain assignment IS the
        idempotent replacement - no de-dup loop is needed here.

        The wired host is Windows PowerShell (powershell, not pwsh) on purpose: it is
        what upstream targets, the renderer's UTF-8 BOM exists so 5.1 decodes its block
        glyphs, and 5.1 cold-starts faster for something that runs on every render.
    .PARAMETER RendererPath
        Full path to the installed renderer script
    .PARAMETER Size
        Statusline size mode passed to the renderer
    .OUTPUTS
        Boolean - True if successful
    #>
    param(
        [Parameter(Mandatory)]
        [string]$RendererPath,

        [Parameter(Mandatory)]
        [ValidateSet('xsmall', 'small', 'medium', 'large', 'xlarge')]
        [string]$Size
    )

    $claudeRoot = Get-ClaudeUserRoot
    $settingsPath = Join-Path $claudeRoot "settings.json"

    try {
        if (-not (Test-Path $claudeRoot)) {
            New-Item -Path $claudeRoot -ItemType Directory -Force | Out-Null
        }

        # Back up settings.json before touching it
        Backup-ConfigFile -Path $settingsPath -Description "claude-settings" | Out-Null

        # Load existing settings (mutable hashtables) or start fresh
        $settings = @{}
        if (Test-Path $settingsPath) {
            $raw = Get-Content -Path $settingsPath -Raw
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $settings = $raw | ConvertFrom-Json -AsHashtable -Depth 20
            }
        }

        # Forward slashes match what upstream writes and avoid backslash-escape noise in JSON.
        $forward = $RendererPath -replace '\\', '/'
        $settings['statusLine'] = @{
            type    = 'command'
            command = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$forward`" -Size $Size"
        }

        $json = $settings | ConvertTo-Json -Depth 20
        Set-Content -Path $settingsPath -Value $json -Encoding UTF8 -Force
        return $true
    } catch {
        Write-Warning "Failed to set statusLine in settings.json: $_"
        return $false
    }
}

function Install-ClaudeStatusLine {
    <#
    .SYNOPSIS
        Installs the Awesome Statusline renderer and wires it into settings.json
    .DESCRIPTION
        Unlike its siblings in this file there is no -SourceRoot parameter, and that
        asymmetry is deliberate: nothing is copied out of the devkit repo. Mode Fresh
        downloads the renderer from upstream; Mode Keep reuses a renderer already on
        disk (so a locally customized one is not clobbered) and only re-wires settings.

        NEVER THROWS. Every path returns a boolean, because Invoke-Installation only
        aborts the run on a thrown exception - a returned $false degrades to a warning.
        An offline machine with no renderer deliberately leaves statusLine unwritten:
        pointing Claude Code at a nonexistent file is worse than having no statusline.
    .PARAMETER Size
        Statusline size mode
    .PARAMETER Mode
        Fresh downloads from upstream; Keep reuses the renderer already installed
    .PARAMETER RawBaseUrl
        Overrides the raw base URL (passed through to Get-AwesomeStatusLineSource)
    .PARAMETER Ref
        Git ref to fetch from. Defaults to main; set to a tag such as v3.3.2 to pin.
    .OUTPUTS
        Boolean - True if the statusline ended up installed and wired
    #>
    param(
        [ValidateSet('xsmall', 'small', 'medium', 'large', 'xlarge')]
        [string]$Size = 'small',

        [ValidateSet('Fresh', 'Keep')]
        [string]$Mode = 'Fresh',

        [string]$RawBaseUrl = '',

        [string]$Ref = 'main'
    )

    try {
        $claudeRoot = Get-ClaudeUserRoot
        $rendererPath = Get-ClaudeStatusLinePath

        if (-not (Test-Path $claudeRoot)) {
            New-Item -Path $claudeRoot -ItemType Directory -Force | Out-Null
        }

        if ($Mode -eq 'Keep') {
            if (-not (Test-Path $rendererPath)) {
                Write-Warning "Keep requested but no renderer at $rendererPath. Run with -Mode Fresh to download one."
                return $false
            }
            return (Set-ClaudeStatusLineSetting -RendererPath $rendererPath -Size $Size)
        }

        # Mode Fresh: fetch from upstream via the single network seam.
        $src = Get-AwesomeStatusLineSource -RawBaseUrl $RawBaseUrl -Ref $Ref
        if (-not $src.Success) {
            if (Test-Path $rendererPath) {
                Write-Warning "Could not download the statusline renderer ($($src.Error)). Keeping the existing $rendererPath."
                return (Set-ClaudeStatusLineSetting -RendererPath $rendererPath -Size $Size)
            }
            Write-Warning "Could not download the statusline renderer ($($src.Error)). Skipping - settings.json left unchanged."
            Write-Warning "Workaround: point DEVKIT_STATUSLINE_SOURCE at a local copy, then run 'devkit statusline install'."
            return $false
        }

        $priorContent = $null
        if (Test-Path $rendererPath) {
            $priorContent = Get-Content -Path $rendererPath -Raw
        }

        $backupPath = Backup-ConfigFile -Path $rendererPath -Description "claude-statusline"

        # This function owns the on-disk format, so strip again here: the single-BOM
        # invariant has to hold whatever the source handed back. The BOM itself is
        # deliberate - without it Windows PowerShell mis-decodes the block/emoji glyphs
        # under non-UTF-8 locales. Do NOT simplify this to Set-Content -Encoding UTF8.
        $body = Remove-Utf8BomChar $src.Content
        [System.IO.File]::WriteAllText($rendererPath, $body, (New-Object System.Text.UTF8Encoding($true)))

        if ($null -ne $priorContent -and (Remove-Utf8BomChar $priorContent) -cne $body) {
            if ($backupPath) {
                Write-Warning "Your previous statusline renderer differed from upstream; the old copy is at $backupPath."
            } else {
                Write-Warning "Your previous statusline renderer differed from upstream and was replaced."
            }
        }

        return (Set-ClaudeStatusLineSetting -RendererPath $rendererPath -Size $Size)
    } catch {
        Write-Warning "Failed to install the Claude statusline: $_"
        return $false
    }
}

function Test-ClaudeStatusLinePresent {
    <#
    .SYNOPSIS
        Reports the live state of the Claude Code statusline install
    .DESCRIPTION
        Uses a cheap raw-text regex over settings.json rather than a full JSON parse,
        matching the HerdrHookPresent convention in config-loader.ps1.
    .OUTPUTS
        Hashtable - @{ ScriptFound; SettingWired; Size; Command; ScriptPathResolves }
    #>
    $claudeRoot = Get-ClaudeUserRoot
    $result = @{
        ScriptFound        = $false
        SettingWired       = $false
        Size               = ''
        Command            = ''
        ScriptPathResolves = $false
    }

    try {
        $result.ScriptFound = Test-Path (Get-ClaudeStatusLinePath)

        $settingsPath = Join-Path $claudeRoot "settings.json"
        if (Test-Path $settingsPath) {
            $raw = Get-Content -Path $settingsPath -Raw -ErrorAction SilentlyContinue
            if ($raw -and $raw -match 'awesome-statusline\.ps1') {
                $result.SettingWired = $true
                if ($raw -match '-Size\s+([a-z]+)') { $result.Size = $Matches[1] }
                # settings.json is JSON, so the embedded quotes arrive backslash-escaped.
                if ($raw -match '-File\s+\\?"([^"\\]+awesome-statusline\.ps1)') {
                    $result.Command = $Matches[1]
                    $result.ScriptPathResolves = Test-Path $Matches[1]
                }
            }
        }
    } catch {
        Write-Warning "Failed to inspect statusline state: $_"
    }

    return $result
}

function Remove-ClaudeStatusLine {
    <#
    .SYNOPSIS
        Removes the statusLine wiring and (optionally) the renderer
    .DESCRIPTION
        Upstream ships no uninstall, so the devkit provides one. Both the settings file
        and the renderer are backed up before anything is removed.
    .PARAMETER KeepRenderer
        Leave ~/.claude/awesome-statusline.ps1 on disk; only unwire settings.json
    .OUTPUTS
        Boolean - True if successful
    #>
    param(
        [switch]$KeepRenderer
    )

    $claudeRoot = Get-ClaudeUserRoot
    $settingsPath = Join-Path $claudeRoot "settings.json"
    $rendererPath = Get-ClaudeStatusLinePath

    try {
        if (Test-Path $settingsPath) {
            Backup-ConfigFile -Path $settingsPath -Description "claude-settings" | Out-Null

            $raw = Get-Content -Path $settingsPath -Raw
            if (-not [string]::IsNullOrWhiteSpace($raw)) {
                $settings = $raw | ConvertFrom-Json -AsHashtable -Depth 20
                if ($settings.ContainsKey('statusLine')) {
                    $settings.Remove('statusLine')
                    $json = $settings | ConvertTo-Json -Depth 20
                    Set-Content -Path $settingsPath -Value $json -Encoding UTF8 -Force
                }
            }
        }

        if (-not $KeepRenderer -and (Test-Path $rendererPath)) {
            Backup-ConfigFile -Path $rendererPath -Description "claude-statusline" | Out-Null
            Remove-Item -Path $rendererPath -Force
        }

        return $true
    } catch {
        Write-Warning "Failed to remove the Claude statusline: $_"
        return $false
    }
}

#endregion

# Functions exported when dot-sourced:
# User Space:
# - Get-DevkitUserRoot, Initialize-DevkitUserSpace
# - Copy-DevkitProfile, Copy-DevkitCli, Copy-DevkitTheme
# - Get-NvimUserRoot, Copy-DevkitNvimConfig
# Claude Code & Herdr:
# - Get-ClaudeUserRoot, Get-HerdrConfigRoot
# - Copy-DevkitClaudeAgents, Copy-DevkitClaudeSkills, Copy-DevkitClaudeCommands, Copy-DevkitClaudeMd
# - Test-DevkitClaudeMdDrift
# - Install-HerdrHookAndSettings, Save-HerdrConfig
# Claude Statusline:
# - Get-ClaudeStatusLinePath, Remove-Utf8BomChar, Get-AwesomeStatusLineSource
# - Install-ClaudeStatusLine, Set-ClaudeStatusLineSetting
# - Test-ClaudeStatusLinePresent, Remove-ClaudeStatusLine
# Git:
# - New-GitConfig, Save-GitConfig, Get-UnmanagedGitConfigSections, New-GlobalGitIgnore
# - Get-ProfileConfigFileName, New-GitProfileConfig, Save-GitProfileConfigs
# PowerShell:
# - New-VariablesPs1, Save-VariablesPs1
# - New-ProfileSnippet, Update-PowerShellProfile
# Modules:
# - Install-RequiredModules
# Full Installation:
# - Invoke-ConfigGeneration
