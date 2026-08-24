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

#region Tool Detection

function Test-NeovimAvailable {
    <#
    .SYNOPSIS
        Detects whether Neovim is installed and on PATH
    .OUTPUTS
        Hashtable with Found (bool), Version (string or $null), Path (string or $null)
    #>

    # Thin wrapper over Test-CommandAvailable. Kept as a named function because the
    # wizard and test-validators.ps1 call it by name. The FallbackPaths entry also lets
    # a just-installed Neovim resolve before the shell's PATH catches up.
    return Test-CommandAvailable -Name 'nvim' `
        -VersionArgs @('--version') `
        -VersionPattern 'NVIM\s+v?([\d\.]+)' `
        -FallbackPaths @('C:\Program Files\Neovim\bin\nvim.exe')
}

function Test-PwshAvailable {
    <#
    .SYNOPSIS
        Detects PowerShell 7 (pwsh) on the machine, preferring the update-surviving shim
    .DESCRIPTION
        Detection order:
          1. The App Execution Alias shim ($env:LOCALAPPDATA\Microsoft\WindowsApps\pwsh.exe)
             - preferred because it survives pwsh version updates, unlike the
             version-stamped WindowsApps package path.
          2. pwsh on PATH (Get-Command).
          3. The running process (the installer requires pwsh 7, so $PSHOME\pwsh.exe
             is a valid last resort).
    .OUTPUTS
        Hashtable with Found (bool), Version (string or $null), Path (string or $null),
        Source (string: 'WindowsApps-alias' | 'PATH' | 'current-process' or $null)
    #>

    $result = @{
        Found = $false
        Version = $null
        Path = $null
        Source = $null
    }

    $shim = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\pwsh.exe"
    if (Test-Path $shim) {
        $result.Found = $true
        $result.Path = $shim
        $result.Source = 'WindowsApps-alias'
    } else {
        $cmd = Get-Command pwsh -ErrorAction SilentlyContinue
        if ($cmd) {
            $result.Found = $true
            $result.Path = $cmd.Source
            $result.Source = 'PATH'
        } else {
            $processPwsh = Join-Path $PSHOME "pwsh.exe"
            if (Test-Path $processPwsh) {
                $result.Found = $true
                $result.Path = $processPwsh
                $result.Source = 'current-process'
                $result.Version = $PSVersionTable.PSVersion.ToString()
            }
        }
    }

    # Probe version when we haven't already taken it from the running process.
    if ($result.Found -and -not $result.Version) {
        try {
            $versionOutput = & $result.Path -NoProfile -Command '$PSVersionTable.PSVersion.ToString()' 2>$null | Select-Object -First 1
            if ($versionOutput) {
                $result.Version = "$versionOutput".Trim()
            }
        } catch {
            # Version probe failed; leave Version as $null but keep Found = true
        }
    }

    return $result
}

function Test-ClaudeCodeAvailable {
    <#
    .SYNOPSIS
        Detects whether the Claude Code CLI is installed and on PATH
    .DESCRIPTION
        Informational only - Claude assets install regardless of whether the CLI
        is present (mirrors the Neovim installer behaviour).
    .OUTPUTS
        Hashtable with Found (bool), Version (string or $null), Path (string or $null)
    #>

    # Thin wrapper over Test-CommandAvailable. No version regex: the CLI prints a bare
    # version line, so the whole first line is taken (unchanged behaviour).
    return Test-CommandAvailable -Name 'claude' `
        -VersionArgs @('--version') `
        -FallbackPaths @('%USERPROFILE%\.local\bin\claude.exe')
}

#endregion


#region Prerequisite Catalogue

function Test-CommandAvailable {
    <#
    .SYNOPSIS
        Generic "is this tool present" probe with a well-known-path fallback
    .DESCRIPTION
        Get-Command first, then each FallbackPaths entry. The fallback matters because
        winget does NOT refresh the calling process's PATH: a tool installed seconds ago
        is invisible to Get-Command until a new shell, but its file is already on disk.
        Without the fallback the wizard would offer to re-install what it just installed.

        Environment variables in FallbackPaths are expanded at call time, not baked in,
        so the test sandbox's redirected USERPROFILE/LOCALAPPDATA are honoured.
    .PARAMETER Name
        Command name to look for (e.g. "nvim")
    .PARAMETER VersionArgs
        Arguments used to probe the version
    .PARAMETER VersionPattern
        Regex with one capture group. When empty, the first non-empty output line is used.
    .PARAMETER FallbackPaths
        Well-known full paths to check when the command is not on PATH
    .OUTPUTS
        Hashtable with Found, Version, Path, Source ('PATH' | 'fallback-path' | $null)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [string[]]$VersionArgs = @('--version'),

        [string]$VersionPattern = '',

        [string[]]$FallbackPaths = @()
    )

    $result = @{
        Found = $false
        Version = $null
        Path = $null
        Source = $null
    }

    $exe = $null
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) {
        $exe = $cmd.Source
        $result.Source = 'PATH'
    } else {
        foreach ($candidate in $FallbackPaths) {
            if (-not $candidate) { continue }
            $expanded = [Environment]::ExpandEnvironmentVariables($candidate)
            if (Test-Path $expanded) {
                $exe = $expanded
                $result.Source = 'fallback-path'
                break
            }
        }
    }

    if (-not $exe) { return $result }

    $result.Found = $true
    $result.Path = $exe

    # No version args means "presence only". Running the binary bare is NOT a safe
    # fallback: glow, nvim and oh-my-posh all launch an interactive UI with no
    # arguments and would hang the caller forever.
    if (-not $VersionArgs -or $VersionArgs.Count -eq 0) { return $result }

    try {
        $output = & $exe @VersionArgs 2>$null | Where-Object { $_ } | Select-Object -First 1
        if ($output) {
            if ($VersionPattern) {
                if ("$output" -match $VersionPattern) { $result.Version = $Matches[1] }
            } else {
                $result.Version = "$output".Trim()
            }
        }
    } catch {
        # Version probe failed; leave Version as $null but keep Found = true
    }

    return $result
}

function Test-WingetAvailable {
    <#
    .SYNOPSIS
        Detects the winget package manager (Windows App Installer)
    .OUTPUTS
        Hashtable with Found, Version, Path
    #>
    return Test-CommandAvailable -Name 'winget' `
        -VersionArgs @('--version') `
        -VersionPattern 'v?([\d\.]+)' `
        -FallbackPaths @('%LOCALAPPDATA%\Microsoft\WindowsApps\winget.exe')
}

function Test-NerdFontInstalled {
    <#
    .SYNOPSIS
        Detects whether any Nerd Font (or a specific family) is installed
    .DESCRIPTION
        ANY Nerd Font satisfies the devkit's requirement - the prompt, Terminal-Icons and
        the Claude statusline need the glyph ranges, not one particular family. Pass
        -Family only when a caller genuinely cares about a specific one.

        Files are checked before the registry because a font file on disk is the more
        reliable signal; stale registry entries for uninstalled fonts are common.

        Naming varies a lot between families and oh-my-posh versions - "MesloLGS NF",
        "CaskaydiaCove NFM", "FiraCode Nerd Font Propo" - so both the spelled-out
        "Nerd Font" form and the bare NF/NFM/NFP suffixes must be matched. Dropping the
        bare-suffix alternative silently misses every Caskaydia install.
    .PARAMETER Family
        Optional family prefix to require (e.g. "Meslo")
    .OUTPUTS
        Hashtable with Found, Confidence ('strong'|'weak'|'none'), Families, Source, Paths
    #>
    param(
        [string]$Family = ''
    )

    $result = @{
        Found = $false
        Confidence = 'none'
        Families = @()
        Source = $null
        Paths = @()
    }

    $nerdPattern = if ($Family) {
        "$([regex]::Escape($Family)).*(NerdFont|Nerd\s*Font|\bNF[MP]?\b)"
    } else {
        '(NerdFont|Nerd\s*Font|\bNF[MP]?\b)'
    }
    # File names have no spaces: "CaskaydiaCoveNerdFont-Regular.ttf", "MesloLGS NF Regular.ttf"
    $filePattern = if ($Family) {
        "^$([regex]::Escape($Family)).*(NerdFont|NF[MP]?[-_ ])"
    } else {
        '(NerdFont|NerdFontMono|NerdFontPropo|NF[MP]?[-_ ])'
    }

    try {
        # 1. Font files (strong signal). The per-user directory is where
        #    `oh-my-posh font install` writes when not elevated.
        $fontDirs = @(
            (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts')
            (Join-Path $env:WINDIR 'Fonts')
        )
        foreach ($dir in $fontDirs) {
            if (-not $dir -or -not (Test-Path $dir)) { continue }
            $hits = Get-ChildItem -Path $dir -Include '*.ttf', '*.otf' -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match $filePattern }
            if ($hits) {
                $result.Found = $true
                $result.Confidence = 'strong'
                $result.Source = 'font-file'
                $result.Paths += @($hits | Select-Object -First 5 -ExpandProperty FullName)
                $result.Families += @($hits | ForEach-Object { $_.BaseName } | Select-Object -First 5)
                break
            }
        }

        # 2. Registry value NAMES (weaker - entries outlive uninstalls).
        #    HKCU first: oh-my-posh installs per-user, so that is where these land.
        if (-not $result.Found) {
            foreach ($hive in @('HKCU:', 'HKLM:')) {
                $key = "$hive\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts"
                if (-not (Test-Path $key)) { continue }
                $props = Get-ItemProperty -Path $key -ErrorAction SilentlyContinue
                if (-not $props) { continue }
                $matched = $props.PSObject.Properties |
                    Where-Object { $_.Name -notmatch '^PS' -and $_.Name -match $nerdPattern }
                if ($matched) {
                    $result.Found = $true
                    $result.Source = "registry:$hive"
                    $result.Families += @($matched | Select-Object -First 5 -ExpandProperty Name)

                    # A registry entry can outlive the font file, so confirm one of the
                    # referenced files actually exists before calling this a strong hit.
                    # Values are either a bare file name (resolved against the font dirs)
                    # or a full path.
                    $confirmed = $false
                    foreach ($prop in $matched) {
                        $value = "$($prop.Value)"
                        if (-not $value) { continue }
                        $candidates = @(
                            $value
                            (Join-Path $env:WINDIR "Fonts\$value")
                            (Join-Path $env:LOCALAPPDATA "Microsoft\Windows\Fonts\$value")
                        )
                        foreach ($candidate in $candidates) {
                            if (Test-Path $candidate -ErrorAction SilentlyContinue) {
                                $result.Paths += $candidate
                                $confirmed = $true
                                break
                            }
                        }
                        if ($confirmed) { break }
                    }
                    $result.Confidence = if ($confirmed) { 'strong' } else { 'weak' }
                    break
                }
            }
        }
    } catch {
        # Detection is best-effort; an unreadable hive must not break the wizard.
    }

    return $result
}

function Get-DevkitPrerequisites {
    <#
    .SYNOPSIS
        THE catalogue of prerequisite tools the devkit can detect and install
    .DESCRIPTION
        Single source of truth, consumed by Show-PrerequisitesStep, Install-Prerequisites,
        `devkit prereqs` and `devkit doctor`. Adding a tool is one row.

        Mechanism:
          winget         - installed with `winget install --id <WingetId>`
          remote-script  - the vendor's own installer, downloaded and run in a child pwsh
          omp-font       - `oh-my-posh font install <name> --headless`
          psgallery      - Install-Module (reporting only here; install.ps1 owns the prompt)

        InstallHint strings mirror README.md's prerequisite tables; FallbackPaths mirror
        README.md's "A note on PATH" table. Keep all three in sync.

        PreSelect controls ORDERING AND EMPHASIS, not a tick - Read-SpectreMultiSelection
        cannot pre-select choices. Rows with PreSelect = $false (Node.js, Claude Code,
        Herdr) sort last and are never part of any default install set; they must be
        ticked in the wizard or named explicitly on the CLI.
    .OUTPUTS
        Array of hashtables
    #>

    return @(
        @{
            Key = 'pwsh'; Name = 'PowerShell 7'; Description = 'The wizard and generated profile require it'
            Mechanism = 'winget'; WingetId = 'Microsoft.PowerShell'
            Command = 'pwsh'; VersionArgs = @('--version'); VersionPattern = 'PowerShell ([\d\.]+)'
            FallbackPaths = @('%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe')
            # Detection order is deliberately inverted vs the generic helper - see Test-PwshAvailable.
            DetectOverride = 'Test-PwshAvailable'
            ModuleName = $null; Fonts = @(); DependsOn = @()
            Tier = 'Required'; PreSelect = $true; HandledBy = 'prereqs'
            InstallHint = 'winget install --id Microsoft.PowerShell -e'; HelpUrl = ''
        }
        @{
            Key = 'git'; Name = 'Git'; Description = 'Git config generation and aliases'
            Mechanism = 'winget'; WingetId = 'Git.Git'
            Command = 'git'; VersionArgs = @('--version'); VersionPattern = 'git version (\d+\.\d+\.\d+)'
            FallbackPaths = @('C:\Program Files\Git\cmd\git.exe')
            DetectOverride = $null; ModuleName = $null; Fonts = @(); DependsOn = @()
            Tier = 'Required'; PreSelect = $true; HandledBy = 'prereqs'
            InstallHint = 'winget install --id Git.Git -e'; HelpUrl = ''
        }
        @{
            Key = 'oh-my-posh'; Name = 'Oh My Posh'; Description = 'Renders the prompt when selected, and installs Nerd Fonts for either engine'
            Mechanism = 'winget'; WingetId = 'JanDeDobbeleer.OhMyPosh'
            Command = 'oh-my-posh'; VersionArgs = @('--version'); VersionPattern = '([\d\.]+)'
            FallbackPaths = @('%LOCALAPPDATA%\Programs\oh-my-posh\bin\oh-my-posh.exe')
            DetectOverride = $null; ModuleName = $null; Fonts = @(); DependsOn = @()
            Tier = 'Required'; PreSelect = $true; HandledBy = 'prereqs'
            InstallHint = 'winget install --id JanDeDobbeleer.OhMyPosh -e'; HelpUrl = ''
        }
        @{
            # The other prompt engine. Optional because Oh My Posh stays the default, but
            # the wizard promotes whichever engine the user picked in step 2.
            Key = 'starship'; Name = 'Starship'; Description = 'Alternative prompt engine - the profile calls starship by name when selected'
            Mechanism = 'winget'; WingetId = 'Starship.Starship'
            Command = 'starship'; VersionArgs = @('--version'); VersionPattern = '([\d\.]+)'
            FallbackPaths = @('%LOCALAPPDATA%\Microsoft\WinGet\Links\starship.exe', '%ProgramFiles%\starship\bin\starship.exe')
            DetectOverride = $null; ModuleName = $null; Fonts = @(); DependsOn = @()
            Tier = 'Optional'; PreSelect = $false; HandledBy = 'prereqs'
            InstallHint = 'winget install --id Starship.Starship -e'; HelpUrl = ''
        }
        @{
            Key = 'nerd-font'; Name = 'Nerd Font'; Description = 'Glyphs for the prompt, Terminal-Icons and the Claude statusline'
            Mechanism = 'omp-font'; WingetId = $null
            Command = $null; VersionArgs = @(); VersionPattern = ''
            FallbackPaths = @()
            DetectOverride = $null; ModuleName = $null
            Fonts = @('meslo')          # default; the wizard offers a multi-select
            DependsOn = @('oh-my-posh') # installed BY oh-my-posh, so it must exist first
            Tier = 'Required'; PreSelect = $true; HandledBy = 'prereqs'
            InstallHint = 'oh-my-posh font install meslo --headless'; HelpUrl = ''
        }
        @{
            Key = 'neovim'; Name = 'Neovim'; Description = 'The bundled Neovim config, or Neovim as the Git editor'
            Mechanism = 'winget'; WingetId = 'Neovim.Neovim'
            Command = 'nvim'; VersionArgs = @('--version'); VersionPattern = 'NVIM\s+v?([\d\.]+)'
            FallbackPaths = @('C:\Program Files\Neovim\bin\nvim.exe')
            DetectOverride = $null; ModuleName = $null; Fonts = @(); DependsOn = @()
            Tier = 'Optional'; PreSelect = $true; HandledBy = 'prereqs'
            InstallHint = 'winget install --id Neovim.Neovim -e'; HelpUrl = ''
        }
        @{
            Key = 'glow'; Name = 'glow'; Description = 'Rendering markdown in the terminal'
            Mechanism = 'winget'; WingetId = 'charmbracelet.glow'
            Command = 'glow'; VersionArgs = @('--version'); VersionPattern = '([\d\.]+)'
            FallbackPaths = @('%LOCALAPPDATA%\Microsoft\WinGet\Links\glow.exe')
            DetectOverride = $null; ModuleName = $null; Fonts = @(); DependsOn = @()
            Tier = 'Optional'; PreSelect = $true; HandledBy = 'prereqs'
            InstallHint = 'winget install --id charmbracelet.glow -e'; HelpUrl = ''
        }
        @{
            Key = 'nodejs'; Name = 'Node.js LTS'; Description = 'General dev workflows (and the npm-based Claude Code install)'
            Mechanism = 'winget'; WingetId = 'OpenJS.NodeJS.LTS'
            Command = 'node'; VersionArgs = @('--version'); VersionPattern = 'v?([\d\.]+)'
            FallbackPaths = @('C:\Program Files\nodejs\node.exe')
            DetectOverride = $null; ModuleName = $null; Fonts = @(); DependsOn = @()
            Tier = 'Optional'; PreSelect = $false; HandledBy = 'prereqs'
            InstallHint = 'winget install --id OpenJS.NodeJS.LTS -e'; HelpUrl = ''
        }
        @{
            Key = 'claude-code'; Name = 'Claude Code CLI'; Description = 'Using the Claude agents/skills/commands installed into ~/.claude'
            Mechanism = 'remote-script'; WingetId = $null
            ScriptUrl = 'https://claude.ai/install.ps1'
            Command = 'claude'; VersionArgs = @('--version'); VersionPattern = ''
            FallbackPaths = @('%USERPROFILE%\.local\bin\claude.exe')
            DetectOverride = $null; ModuleName = $null; Fonts = @(); DependsOn = @()
            # Never pre-selected: this downloads and runs a script from the internet.
            Tier = 'Optional'; PreSelect = $false; HandledBy = 'prereqs'
            InstallHint = 'irm https://claude.ai/install.ps1 | iex'; HelpUrl = 'https://claude.ai'
        }
        @{
            Key = 'herdr'; Name = 'Herdr'; Description = 'The herdr terminal multiplexer configured by the devkit'
            # Preview is the ONLY published channel (there is no Herdr.Herdr), and the
            # devkit's own herdr config.toml pins channel = "preview", so this matches.
            Mechanism = 'winget'; WingetId = 'Herdr.Herdr.Preview'
            Command = 'herdr'; VersionArgs = @('--version'); VersionPattern = '([\d\.]+)'
            FallbackPaths = @('%LOCALAPPDATA%\Programs\Herdr\bin\herdr.exe')
            DetectOverride = $null; ModuleName = $null; Fonts = @(); DependsOn = @()
            Tier = 'Optional'; PreSelect = $false; HandledBy = 'prereqs'
            InstallHint = 'winget install --id Herdr.Herdr.Preview -e'; HelpUrl = 'https://herdr.dev'
        }
        @{
            Key = 'pwshspectreconsole'; Name = 'PwshSpectreConsole'; Description = 'The wizard UI itself'
            Mechanism = 'psgallery'; WingetId = $null
            Command = $null; VersionArgs = @(); VersionPattern = ''
            FallbackPaths = @()
            DetectOverride = $null; ModuleName = 'PwshSpectreConsole'; Fonts = @(); DependsOn = @()
            Tier = 'Required'; PreSelect = $true
            # install.ps1 prompts for this before lib/ is dot-sourced - the wizard UI
            # cannot render without it, so it can never be a wizard step. Reporting only.
            HandledBy = 'installer-bootstrap'
            InstallHint = 'Install-Module -Name PwshSpectreConsole -Scope CurrentUser'; HelpUrl = ''
        }
    )
}

function Get-PrerequisiteState {
    <#
    .SYNOPSIS
        Resolves the live installed/missing state of the prerequisite catalogue
    .DESCRIPTION
        One call site for the wizard step, `devkit prereqs check` and `devkit doctor`.
        Dispatches on each row's Mechanism. Never throws.
    .PARAMETER Catalog
        Catalogue rows (defaults to Get-DevkitPrerequisites)
    .PARAMETER Keys
        Optional subset of Keys to resolve
    .PARAMETER Fast
        Skip version probes. Each probe spawns a process, which is measurable when this
        runs at wizard startup from Get-ExistingConfiguration.
    .OUTPUTS
        Ordered hashtable: Key -> @{ Key; Name; Tier; Found; Version; Path; Source;
                                     Confidence; Mechanism; InstallHint }
    #>
    param(
        [array]$Catalog = @(),
        [string[]]$Keys = @(),
        [switch]$Fast
    )

    if (-not $Catalog -or $Catalog.Count -eq 0) { $Catalog = Get-DevkitPrerequisites }

    $state = [ordered]@{}

    foreach ($row in $Catalog) {
        if ($Keys.Count -gt 0 -and $Keys -notcontains $row.Key) { continue }

        $entry = @{
            Key = $row.Key; Name = $row.Name; Tier = $row.Tier
            Mechanism = $row.Mechanism; InstallHint = $row.InstallHint
            Found = $false; Version = $null; Path = $null; Source = $null
            Confidence = $null
        }

        try {
            switch ($row.Mechanism) {
                'omp-font' {
                    $font = Test-NerdFontInstalled
                    $entry.Found = $font.Found
                    $entry.Confidence = $font.Confidence
                    $entry.Source = $font.Source
                    if ($font.Families) { $entry.Version = ($font.Families | Select-Object -First 1) }
                }
                'psgallery' {
                    $mod = Get-Module -ListAvailable -Name $row.ModuleName -ErrorAction SilentlyContinue |
                        Select-Object -First 1
                    if ($mod) {
                        $entry.Found = $true
                        $entry.Version = "$($mod.Version)"
                        $entry.Path = $mod.ModuleBase
                        $entry.Source = 'psgallery'
                    }
                }
                default {
                    # A row may pin a bespoke detector (pwsh), otherwise use the generic probe.
                    if ($row.DetectOverride -and (Get-Command $row.DetectOverride -ErrorAction SilentlyContinue)) {
                        $probe = & $row.DetectOverride
                    } else {
                        $versionArgs = if ($Fast) { @() } else { $row.VersionArgs }
                        $probe = Test-CommandAvailable -Name $row.Command `
                            -VersionArgs $versionArgs `
                            -VersionPattern $row.VersionPattern `
                            -FallbackPaths $row.FallbackPaths
                    }
                    $entry.Found = [bool]$probe.Found
                    $entry.Version = $probe.Version
                    $entry.Path = $probe.Path
                    if ($probe.ContainsKey('Source')) { $entry.Source = $probe.Source }
                }
            }
        } catch {
            # Leave the row as not-found rather than breaking the whole report.
        }

        $state[$row.Key] = $entry
    }

    return $state
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
            Editor = ""
        }
        PowerShell = @{
            Modules = @()
            PromptEngine = "oh-my-posh"  # or "starship"
            OhMyPoshTheme = ""
            # Empty means "let Starship find its own ~/.config/starship.toml".
            StarshipConfig = ""
            StarshipPreset = ""
            StarshipMode = "Fresh"       # Fresh | Keep | Custom
            StarshipGitPanel = $true     # branch coloured by repo state + posh-git counts
        }
        Nvim = @{
            Install = $false
        }
        Claude = @{
            Install         = $true   # parent gate for all Claude/herdr areas
            InstallAgents   = $true
            InstallSkills   = $true
            InstallCommands = $true
            InstallClaudeMd = $true
            InstallHerdr    = $true   # settings.json hook merge + config.toml
            # Set by the wizard only when the user agrees to replace a drifted
            # ~/.claude/CLAUDE.md - see Test-DevkitClaudeMdDrift.
            ForceClaudeMd   = $false
            # Opt-in by default, unlike its siblings: the statusline is the only area
            # that downloads third-party code over the network.
            InstallStatusLine = $false
            StatusLineSize    = 'small'
            StatusLineMode    = 'Fresh'
        }
        Prerequisites = @{
            Install          = $false   # parent gate; true only when the user opts in
            Selected         = @()      # catalogue Keys the user ticked
            Fonts            = @()      # Nerd Font names to install (multi-select)
            Installed        = @()
            AlreadyInstalled = @()
            Failed           = @()      # @{ Name; Error } - mirrors Install-RequiredModules
            Skipped          = @()      # @{ Name; Reason }
            NeedsNewShell    = @()      # installed, but not resolvable in this process
            WingetAvailable  = $false
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

    # Check the prompt engine, then whatever that engine needs. A Starship config path
    # is deliberately NOT required: "Keep" mode leaves it empty so Starship falls back to
    # its own ~/.config/starship.toml.
    $engine = $Config.PowerShell.PromptEngine
    if (-not $engine) { $engine = 'oh-my-posh' }  # pre-PromptEngine configs default to OMP

    if ($engine -notin @('oh-my-posh', 'starship')) {
        $result.IsValid = $false
        $result.Errors += "Unknown prompt engine: $engine"
    }

    if ($engine -eq 'oh-my-posh' -and -not (Test-NonEmptyString -Value $Config.PowerShell.OhMyPoshTheme)) {
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
# - Test-NeovimAvailable, Test-PwshAvailable, Test-ClaudeCodeAvailable
# Prerequisites:
# - Test-CommandAvailable, Test-WingetAvailable, Test-NerdFontInstalled
# - Get-DevkitPrerequisites, Get-PrerequisiteState
# - New-DevkitConfig, Test-DevkitConfig
