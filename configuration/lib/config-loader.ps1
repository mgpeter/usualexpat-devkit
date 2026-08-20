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
    .PARAMETER Path
        Optional path to a .gitconfig (defaults to ~/.gitconfig). When supplied, the
        `git config --global` fallback is skipped so the file is parsed in isolation -
        this is what makes the parser testable without touching the real config.
    .OUTPUTS
        Hashtable with Name, Email, and AdditionalProfiles
    #>
    param(
        [string]$Path = ""
    )

    $result = @{
        Found = $false
        DefaultProfile = @{
            Name = ""
            Email = ""
        }
        AdditionalProfiles = @()
        IncludeIfPaths = @()
        Editor = ""
    }

    $useGlobalFallback = -not $Path
    $gitConfigPath = if ($Path) { $Path } else { Join-Path $env:USERPROFILE ".gitconfig" }

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

        # Alternative: use git config command for more reliable parsing. Only when reading
        # the real global config - an explicit -Path must be parsed on its own.
        if ($useGlobalFallback) {
            $gitName = git config --global user.name 2>$null
            $gitEmail = git config --global user.email 2>$null
            $gitEditor = git config --global core.editor 2>$null

            if ($gitName) { $result.DefaultProfile.Name = $gitName }
            if ($gitEmail) { $result.DefaultProfile.Email = $gitEmail }
            if ($gitEditor) { $result.Editor = $gitEditor }
        }

        # Parse includeIf sections for additional profiles
        # New-GitConfig writes the case-insensitive "gitdir/i:" form; older hand-written
        # configs use plain "gitdir:". Accept both, or a re-run silently drops every
        # includeIf block and orphans the .gitconfig-* files.
        $includeIfPattern = '\[includeIf\s+"gitdir(?:/i)?:([^"]+)"\]\s*\n\s*path\s*=\s*(.+?)\s*\n'
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

#region Neovim Configuration Detection

function Get-ExistingNvimConfig {
    <#
    .SYNOPSIS
        Detects existing Neovim configuration in the standard Windows location
    .OUTPUTS
        Hashtable with Found, ConfigRoot, PluginManager, IsDevkitManaged
    #>

    $result = @{
        Found = $false
        ConfigRoot = ""
        PluginManager = $null  # 'lazy', 'packer', 'plug', or $null
        IsDevkitManaged = $false
    }

    $configRoot = Join-Path $env:LOCALAPPDATA "nvim"
    $initLua = Join-Path $configRoot "init.lua"
    $initVim = Join-Path $configRoot "init.vim"

    $initPath = $null
    if (Test-Path $initLua) { $initPath = $initLua }
    elseif (Test-Path $initVim) { $initPath = $initVim }

    if (-not $initPath) {
        return $result
    }

    $result.Found = $true
    $result.ConfigRoot = $configRoot

    try {
        $content = Get-Content $initPath -Raw -ErrorAction SilentlyContinue
        if ($content) {
            # Marker placed by Copy-DevkitNvimConfig at the top of init.lua
            if ($content -match '(?m)^\s*--\s*devkit-managed') {
                $result.IsDevkitManaged = $true
            }

            if ($content -match 'require\(["'']lazy["'']\)|folke/lazy\.nvim') {
                $result.PluginManager = 'lazy'
            } elseif ($content -match 'require\(["'']packer["'']\)|wbthomason/packer\.nvim') {
                $result.PluginManager = 'packer'
            } elseif ($content -match '\bPlug\s+["'']') {
                $result.PluginManager = 'plug'
            }
        }
    } catch {
        Write-Warning "Error parsing Neovim config: $_"
    }

    return $result
}

#endregion

#region Claude Code Detection

function Get-ExistingClaudeConfig {
    <#
    .SYNOPSIS
        Detects existing Claude Code / herdr configuration
    .OUTPUTS
        Hashtable with Found, ClaudeMdFound, SettingsFound, HerdrHookPresent,
        HerdrConfigFound, ClaudeInstalled
    #>

    $result = @{
        Found = $false
        ClaudeMdFound = $false
        SettingsFound = $false
        HerdrHookPresent = $false
        HerdrConfigFound = $false
        ClaudeInstalled = $false
    }

    $claudeRoot = Join-Path $env:USERPROFILE ".claude"
    $result.Found = Test-Path $claudeRoot
    $result.ClaudeMdFound = Test-Path (Join-Path $claudeRoot "CLAUDE.md")
    $result.HerdrConfigFound = Test-Path (Join-Path $env:APPDATA "herdr\config.toml")

    $settingsPath = Join-Path $claudeRoot "settings.json"
    if (Test-Path $settingsPath) {
        $result.SettingsFound = $true
        try {
            $raw = Get-Content $settingsPath -Raw -ErrorAction SilentlyContinue
            if ($raw -and $raw -match 'herdr-agent-state\.ps1') {
                $result.HerdrHookPresent = $true
            }
        } catch {
            Write-Warning "Error parsing Claude settings.json: $_"
        }
    }

    # Claude CLI on PATH (informational)
    if (Get-Command Test-ClaudeCodeAvailable -ErrorAction SilentlyContinue) {
        $result.ClaudeInstalled = (Test-ClaudeCodeAvailable).Found
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
            Editor = ""
        }
        PowerShell = @{
            Modules = @()
            OhMyPoshTheme = ""
        }
        Nvim = @{
            Install = $false
            ExistingPluginManager = $null
            ExistingIsDevkitManaged = $false
        }
        Claude = @{
            Install         = $true
            InstallAgents   = $true
            InstallSkills   = $true
            InstallCommands = $true
            InstallClaudeMd = $true
            InstallHerdr    = $true
            # Set by the wizard only when the user agrees to replace a drifted
            # ~/.claude/CLAUDE.md - see Test-DevkitClaudeMdDrift.
            ForceClaudeMd   = $false
        }
        _Detection = @{
            GitConfigFound = $false
            ProfileFound = $false
            DevkitInstalled = $false
            VariablesFound = $false
            NvimConfigFound = $false
            ClaudeFound = $false
            ClaudeInstalled = $false
            ClaudeMdFound = $false
            ClaudeSettingsFound = $false
            HerdrHookPresent = $false
            HerdrConfigFound = $false
        }
    }

    # Load Git configuration
    $gitConfig = Get-ExistingGitConfig
    $config._Detection.GitConfigFound = $gitConfig.Found

    if ($gitConfig.Found) {
        $config.Git.DefaultProfile.Name = $gitConfig.DefaultProfile.Name
        $config.Git.DefaultProfile.Email = $gitConfig.DefaultProfile.Email
        $config.Git.AdditionalProfiles = $gitConfig.AdditionalProfiles
        $config.Git.Editor = $gitConfig.Editor
    }

    # Load PowerShell profile info
    $psConfig = Get-ExistingPowerShellConfig
    $config._Detection.ProfileFound = $psConfig.Found
    $config._Detection.DevkitInstalled = $psConfig.DevkitInstalled

    if ($psConfig.OhMyPoshTheme) {
        $config.PowerShell.OhMyPoshTheme = $psConfig.OhMyPoshTheme
    }

    # Load Neovim config info
    $nvimConfig = Get-ExistingNvimConfig
    $config._Detection.NvimConfigFound = $nvimConfig.Found
    if ($nvimConfig.Found) {
        $config.Nvim.ExistingPluginManager = $nvimConfig.PluginManager
        $config.Nvim.ExistingIsDevkitManaged = $nvimConfig.IsDevkitManaged
    }

    # Load Claude Code / herdr detection
    $claudeConfig = Get-ExistingClaudeConfig
    $config._Detection.ClaudeFound = $claudeConfig.Found
    $config._Detection.ClaudeInstalled = $claudeConfig.ClaudeInstalled
    $config._Detection.ClaudeMdFound = $claudeConfig.ClaudeMdFound
    $config._Detection.ClaudeSettingsFound = $claudeConfig.SettingsFound
    $config._Detection.HerdrHookPresent = $claudeConfig.HerdrHookPresent
    $config._Detection.HerdrConfigFound = $claudeConfig.HerdrConfigFound

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
# - Get-ExistingNvimConfig
# - Get-ExistingClaudeConfig
# - Get-ExistingDevkitVariables
# - Get-CommonRepoLocations
# - Get-ExistingConfiguration
