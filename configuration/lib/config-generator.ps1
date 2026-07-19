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

function Copy-DevkitClaudeMd {
    <#
    .SYNOPSIS
        Installs the bundled global CLAUDE.md into ~/.claude/CLAUDE.md
    .DESCRIPTION
        Backs up any existing ~/.claude/CLAUDE.md before overwriting.
    .PARAMETER SourceRoot
        Root path of the source devkit repo
    .OUTPUTS
        Boolean - True if successful
    #>
    param(
        [Parameter(Mandatory)]
        [string]$SourceRoot
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

# Functions exported when dot-sourced:
# User Space:
# - Get-DevkitUserRoot, Initialize-DevkitUserSpace
# - Copy-DevkitProfile, Copy-DevkitTheme
# - Get-NvimUserRoot, Copy-DevkitNvimConfig
# Claude Code & Herdr:
# - Get-ClaudeUserRoot, Get-HerdrConfigRoot
# - Copy-DevkitClaudeAgents, Copy-DevkitClaudeSkills, Copy-DevkitClaudeCommands, Copy-DevkitClaudeMd
# - Install-HerdrHookAndSettings, Save-HerdrConfig
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
