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

# The preset used when something needs a Starship config and nobody picked one -
# `devkit prompt use starship` on a box that has never had one. Nerd Font powerline,
# to match what the bundled Oh My Posh theme expects of the terminal font.
$script:DevkitDefaultStarshipPreset = 'gruvbox-rainbow'

function Get-DevkitStarshipConfigPath {
    <#
    .SYNOPSIS
        Returns the path of the devkit-managed starship.toml in user space
    #>
    return Join-Path (Join-Path (Get-DevkitUserRoot) "themes") "starship.toml"
}

#region Starship git panel

# Starship gives each module exactly one style, so `git_branch` cannot change colour
# with what the repo is doing. The panel works around that: `git_branch` is disabled and
# four `env_var` modules take its slot in the format string, one per state. An env_var
# module renders only when its variable is set, and Invoke-Starship-PreCommand in the
# profile sets exactly one of them per prompt - so exactly one branch segment appears.
#
# The alternative - four `custom` modules with mutually exclusive `when` conditions - is
# what the Starship docs suggest and is wrong on Windows: every `when` spawns its own
# shell, so it costs four pwsh launches per prompt instead of one `git status`.
$script:DevkitStarshipPanelStates = [ordered]@{
    'DEVKIT_GIT_CONFLICT' = 'red'
    'DEVKIT_GIT_DIRTY'    = 'yellow'
    'DEVKIT_GIT_DIVERGED' = 'purple'
    'DEVKIT_GIT_CLEAN'    = 'green'
}

$script:DevkitStarshipPanelBegin = '# --- devkit git panel BEGIN (managed: devkit prompt gitpanel) ---'
$script:DevkitStarshipPanelEnd   = '# --- devkit git panel END ---'

# `gitpanel off` has to hand back the preset the user actually chose, and the panel
# overwrites [git_branch] / [git_status] to get there. The originals are archived inside
# the panel block behind this prefix so removal can put them back verbatim.
$script:DevkitStarshipArchiveMark = '#!devkit-orig!'

# Starship's own default git_branch.format. A preset that only overrides `symbol` - which
# is most of them, nerd-font-symbols included - inherits this, and it is where the "on "
# before the branch comes from. Rebuilding the branch without it silently restyles a
# prompt the user chose, so the panel reuses this rather than inventing its own wrapper.
$script:DevkitStarshipDefaultBranchFormat = 'on [$symbol$branch]($style) '

function Split-StarshipToml {
    <#
    .SYNOPSIS
        Splits a starship.toml into its preamble and its [section] blocks
    .DESCRIPTION
        Section headers are only recognised outside triple-quoted strings. That matters:
        every powerline preset writes its top-level format as a """ block whose lines
        start with things like [](fg:color_aqua), which a naive line scan reads as a
        section header and truncates the format at.
    .PARAMETER Text
        Full text of a starship.toml
    .OUTPUTS
        Hashtable - Preamble (string) and Sections (array of @{ Name; Text })
    #>
    param([string]$Text)

    $lines = $Text -split "`r?`n"
    $preamble = [System.Collections.Generic.List[string]]::new()
    $sections = [System.Collections.Generic.List[object]]::new()
    $current = $null
    $inTriple = ''

    foreach ($line in $lines) {
        if (-not $inTriple -and $line -match '^\s*\[\[?([A-Za-z0-9_\-\."'']+)\]\]?\s*(#.*)?$') {
            $current = @{ Name = $Matches[1].Trim('"', "'"); Lines = [System.Collections.Generic.List[string]]::new() }
            $current.Lines.Add($line)
            $sections.Add($current)
        } elseif ($current) {
            $current.Lines.Add($line)
        } else {
            $preamble.Add($line)
        }

        # Track triple-quote state left to right; a line may open and close one.
        $idx = 0
        while ($idx -lt $line.Length) {
            if ($inTriple) {
                $j = $line.IndexOf($inTriple, $idx)
                if ($j -lt 0) { break }
                $idx = $j + 3
                $inTriple = ''
            } else {
                $d1 = $line.IndexOf('"""', $idx)
                $d2 = $line.IndexOf("'''", $idx)
                $j = if ($d1 -lt 0) { $d2 } elseif ($d2 -lt 0) { $d1 } else { [Math]::Min($d1, $d2) }
                if ($j -lt 0) { break }
                $inTriple = $line.Substring($j, 3)
                $idx = $j + 3
            }
        }
    }

    return @{
        Preamble = ($preamble -join "`n")
        Sections = @($sections | ForEach-Object { @{ Name = $_.Name; Text = ($_.Lines -join "`n") } })
    }
}

function Get-StarshipStyleBackground {
    <#
    .SYNOPSIS
        Extracts the first bg: token from a starship.toml section
    .DESCRIPTION
        Powerline presets carry the segment background on both `style` and the inner
        (fg:x bg:y) of their format. Reusing it is what keeps the panel from punching a
        transparent hole in the middle of the prompt.
    .OUTPUTS
        String - e.g. "bg:color_aqua", or "" when the preset uses no background
    #>
    param([string]$SectionText)

    $match = [regex]::Match($SectionText, 'bg:([A-Za-z0-9_#\-]+)')
    if ($match.Success) { return "bg:$($match.Groups[1].Value)" }
    return ''
}

function Get-StarshipSectionValue {
    <#
    .SYNOPSIS
        Reads one quoted scalar key out of a starship.toml section
    .OUTPUTS
        String - the value, or "" when the key is absent
    #>
    param([string]$SectionText, [string]$Key)

    # Group 1 is the opening quote and group 2 the value, so the backreference that closes
    # the literal is \1. Pointing it at \2 matches the value against itself, always fails,
    # and silently costs the panel its branch glyph.
    $pattern = "(?m)^\s*$([regex]::Escape($Key))\s*=\s*([`"'])(.*?)\1\s*(#.*)?$"
    $match = [regex]::Match($SectionText, $pattern)
    if ($match.Success) { return $match.Groups[2].Value }
    return ''
}

function Convert-StarshipBranchFormat {
    <#
    .SYNOPSIS
        Turns a git_branch format string into one an env_var module can render
    .DESCRIPTION
        Two substitutions, both needed to keep the preset looking like itself:

          $branch    -> $env_value   (env_var modules expose the value under that name)
          ](fg:... ) -> ]($style)    (powerline presets hard-code the segment colour
                                      INSIDE the format; left alone it wins over the
                                      module style and every state renders identically)

        Everything else survives verbatim, which is what preserves the literal "on "
        prefix, the surrounding spaces, and any powerline padding.
    .PARAMETER Format
        The preset's git_branch format, or "" to use Starship's default
    .OUTPUTS
        String
    #>
    param([string]$Format = '')

    $source = if ($Format) { $Format } else { $script:DevkitStarshipDefaultBranchFormat }
    $converted = [regex]::Replace($source, '\$\{?branch\}?', '$env_value')
    # Only style groups that set a foreground: a bare ($style) reference must survive.
    return [regex]::Replace($converted, '\]\((?<s>[^)]*fg:[^)]*)\)', ']($style)')
}

function Test-DevkitStarshipGitPanel {
    <#
    .SYNOPSIS
        True when the given starship.toml already carries the devkit git panel
    #>
    param([string]$Path)

    if (-not $Path -or -not (Test-Path $Path)) { return $false }
    try {
        return ((Get-Content -LiteralPath $Path -Raw) -like "*$($script:DevkitStarshipPanelBegin)*")
    } catch {
        return $false
    }
}

function New-DevkitStarshipPanelBlock {
    <#
    .SYNOPSIS
        Renders the devkit git panel block for one starship.toml
    .PARAMETER Symbol
        Branch symbol lifted from the preset's [git_branch], so the panel keeps its glyph
    .PARAMETER Background
        bg: token lifted from the preset, or "" for presets that use no background
    .PARAMETER BranchFormat
        The preset's git_branch format, reused so the branch keeps its wrapper text
    .PARAMETER StatusFormat
        The preset's git_status format, re-emitted verbatim. Empty means the preset never
        overrode it, and the key is then omitted so Starship's default applies - that
        default is what draws the [ ] around the status and orders it via $all_status.
    .PARAMETER StatusStyle
        The preset's git_status style, re-emitted verbatim. Empty omits the key.
    .PARAMETER Archive
        Original [git_branch] / [git_status] text, stored commented out so `gitpanel off`
        can restore the preset rather than leaving it degraded
    .OUTPUTS
        String - the block, marker to marker
    #>
    param(
        [string]$Symbol = '',
        [string]$Background = '',
        [string]$BranchFormat = '',
        [string]$StatusFormat = '',
        [string]$StatusStyle = '',
        [string]$Archive = ''
    )

    $bgSuffix = if ($Background) { " $Background" } else { '' }
    $branchFormatOut = Convert-StarshipBranchFormat -Format $BranchFormat
    $lines = [System.Collections.Generic.List[string]]::new()

    $lines.Add($script:DevkitStarshipPanelBegin)
    $lines.Add('# git_branch cannot change colour per repo state, so it is disabled and four')
    $lines.Add('# env_var modules stand in for it. Invoke-Starship-PreCommand in the devkit')
    $lines.Add('# profile sets exactly one of DEVKIT_GIT_CONFLICT/DIRTY/DIVERGED/CLEAN per')
    $lines.Add('# prompt; without it no branch renders at all.')
    $lines.Add('#   red = conflict or rebase/merge in progress   yellow = local changes')
    $lines.Add('#   purple = ahead of or behind upstream         green = clean')
    $lines.Add('# Regenerate with: devkit prompt gitpanel on     Undo with: gitpanel off')

    if ($Archive) {
        $lines.Add('')
        $lines.Add('# Preset sections this panel replaced, kept verbatim for `gitpanel off`:')
        foreach ($archLine in ($Archive -split "`r?`n")) {
            $lines.Add("$($script:DevkitStarshipArchiveMark)$archLine")
        }
    }

    $lines.Add('')
    $lines.Add('[git_branch]')
    $lines.Add('disabled = true')

    foreach ($varName in $script:DevkitStarshipPanelStates.Keys) {
        $colour = $script:DevkitStarshipPanelStates[$varName]
        $lines.Add('')
        $lines.Add("[env_var.$varName]")
        if ($Symbol) { $lines.Add("symbol = `"$Symbol`"") }
        $lines.Add("style = `"bold fg:$colour$bgSuffix`"")
        $lines.Add("format = '$branchFormatOut'")
    }

    # posh-git's counts, one colour per category. ${count} is the whole point of the
    # rewrite - the presets ship these as bare symbols with no number attached.
    $counts = [ordered]@{
        conflicted = @('!', 'red')
        untracked  = @('?', 'purple')
        modified   = @('~', 'yellow')
        staged     = @('+', 'green')
        renamed    = @([string][char]0x00BB, 'cyan')
        deleted    = @('-', 'red')
        stashed    = @([string][char]0x2261, 'blue')
    }

    # The preset's own format and style are re-emitted untouched, and omitted entirely
    # when it never set them. Overriding them was the bug that cost nerd-font-symbols the
    # [ ] around its status and reordered the categories: $all_status in Starship's
    # default format already orders these, and only the per-category symbols need
    # rewriting to carry a number.
    $lines.Add('')
    $lines.Add('[git_status]')
    if ($StatusStyle) { $lines.Add("style = '$StatusStyle'") }
    if ($StatusFormat) { $lines.Add("format = '$StatusFormat'") }
    foreach ($key in $counts.Keys) {
        $symbol = $counts[$key][0]
        $colour = $counts[$key][1]
        $lines.Add("$($key.PadRight(10)) = `"[$symbol`${count}](bold fg:$colour$bgSuffix) `"")
    }

    $up   = [string][char]0x21E1
    $down = [string][char]0x21E3
    $both = [string][char]0x21D5
    $lines.Add("ahead      = `"[$up`${count}](bold fg:purple$bgSuffix) `"")
    $lines.Add("behind     = `"[$down`${count}](bold fg:purple$bgSuffix) `"")
    $lines.Add("diverged   = `"[$both$up`${ahead_count}$down`${behind_count}](bold fg:purple$bgSuffix) `"")

    $lines.Add('')
    $lines.Add($script:DevkitStarshipPanelEnd)

    return ($lines -join "`n")
}

function Update-StarshipFormatForPanel {
    <#
    .SYNOPSIS
        Puts the four env_var refs where $git_branch used to be in a top-level format
    .OUTPUTS
        String - the rewritten preamble, or $null when the format cannot be placed
    #>
    param([string]$Preamble)

    $refs = (($script:DevkitStarshipPanelStates.Keys | ForEach-Object { "`${env_var.$_}" }) -join '')

    if ($Preamble -like '*${env_var.DEVKIT_GIT_*') {
        return $Preamble
    }

    if ($Preamble -match '\$\{?git_branch\}?') {
        return ([regex]::Replace($Preamble, '\$\{?git_branch\}?', $refs))
    }

    if ($Preamble -notmatch '(?m)^\s*format\s*=') {
        # No top-level format means Starship's "$all", which orders env_var modules
        # nowhere near the git segment. Name only the modules needed to position the
        # branch and let $all render everything else in its usual order.
        return ($Preamble.TrimEnd() + "`n" + "format = `"`$username`$hostname`$directory$refs`$all`"")
    }

    if ($Preamble -match '\$\{?git_status\}?') {
        return ([regex]::Replace($Preamble, '(\$\{?git_status\}?)', "$refs`$1", 1))
    }

    Write-Warning "Starship config has a top-level format with no git segment; the git panel was not applied."
    return $null
}

function Remove-DevkitStarshipPanelText {
    <#
    .SYNOPSIS
        Reverses Add-DevkitStarshipGitPanel on a config's text
    .DESCRIPTION
        Restores the archived [git_branch] / [git_status], puts $git_branch back in the
        format, and drops the block. A config that never had a panel comes back unchanged.
    .OUTPUTS
        String - the restored text
    #>
    param([string]$Text)

    $beginIdx = $Text.IndexOf($script:DevkitStarshipPanelBegin)
    if ($beginIdx -lt 0) { return $Text }

    $endIdx = $Text.IndexOf($script:DevkitStarshipPanelEnd, $beginIdx)
    $blockEnd = if ($endIdx -lt 0) { $Text.Length } else { $endIdx + $script:DevkitStarshipPanelEnd.Length }
    $block = $Text.Substring($beginIdx, $blockEnd - $beginIdx)
    $rest = ($Text.Substring(0, $beginIdx).TrimEnd() + "`n" + $Text.Substring($blockEnd)).TrimEnd()

    $archive = @()
    foreach ($line in ($block -split "`r?`n")) {
        if ($line.StartsWith($script:DevkitStarshipArchiveMark)) {
            $archive += $line.Substring($script:DevkitStarshipArchiveMark.Length)
        }
    }

    $refs = (($script:DevkitStarshipPanelStates.Keys | ForEach-Object { "`${env_var.$_}" }) -join '')
    if ($rest.Contains($refs)) {
        $rest = $rest.Replace($refs, '$git_branch')
    }

    # The synthesised format is ours alone; leaving it behind would pin a config that
    # had no top-level format to today's module list.
    $rest = (($rest -split "`r?`n") | Where-Object {
        $_ -notmatch '^\s*format\s*=\s*"\$username\$hostname\$directory\$git_branch\$all"\s*$'
    }) -join "`n"

    if ($archive.Count -gt 0) {
        $rest = $rest.TrimEnd() + "`n`n" + (($archive -join "`n").Trim("`n"))
    }

    return ($rest.TrimEnd() + "`n")
}

function Add-DevkitStarshipGitPanel {
    <#
    .SYNOPSIS
        Rewrites a starship.toml so the branch is coloured by repo state and git_status
        reports posh-git style counts
    .DESCRIPTION
        Three edits, all of which have to happen together or the prompt loses its branch:
          1. [git_branch] and [git_status] are REPLACED, not appended to. TOML rejects a
             duplicate table outright and Starship then falls back to its default config,
             so the preset's own sections have to go. They are archived inside the block.
          2. $git_branch in the top-level format is swapped for the four env_var refs.
             A config with no top-level format is on Starship's $all, where env_var sits
             far from the git segment - so one is written naming only enough modules to
             put the branch back in the right place, leaving $all to order the rest.
          3. The panel block is appended.

        MUST NEVER THROW - same contract as Install-DevkitStarshipConfig, whose result
        this decorates. A failure here degrades to a warning and an unpanelled prompt.
    .PARAMETER Path
        The starship.toml to rewrite, in place
    .OUTPUTS
        Boolean - True when the panel is present afterwards
    #>
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        if (-not (Test-Path $Path)) {
            Write-Warning "Starship config not found: $Path"
            return $false
        }

        $text = Get-Content -LiteralPath $Path -Raw
        if (Test-DevkitStarshipGitPanel -Path $Path) {
            # Re-applying: drop the old panel and restore the archive first, so the symbol
            # and background are read off the preset rather than off our own last output.
            $text = Remove-DevkitStarshipPanelText -Text $text
        }

        $parsed = Split-StarshipToml -Text $text
        $branchSection = @($parsed.Sections | Where-Object { $_.Name -eq 'git_branch' })[0]
        $statusSection = @($parsed.Sections | Where-Object { $_.Name -eq 'git_status' })[0]

        $symbol = if ($branchSection) {
            Get-StarshipSectionValue -SectionText $branchSection.Text -Key 'symbol'
        } else {
            # Starship's own default git_branch symbol, space included.
            "$([char]0xE0A0) "
        }
        # Used VERBATIM, never trimmed or padded. The gap before the branch lives in
        # whichever half the preset owns: presets that write their own format put it
        # there and leave the symbol bare (gruvbox-rainbow: "$symbol $branch" + ""),
        # while presets that inherit the default format carry it on the symbol
        # (nerd-font-symbols: " "). Normalising either one doubles the space.

        $background = ''
        foreach ($candidate in @($branchSection, $statusSection)) {
            if ($candidate -and -not $background) {
                $background = Get-StarshipStyleBackground -SectionText $candidate.Text
            }
        }

        $branchFormat = if ($branchSection) {
            Get-StarshipSectionValue -SectionText $branchSection.Text -Key 'format'
        } else { '' }
        $statusFormat = if ($statusSection) {
            Get-StarshipSectionValue -SectionText $statusSection.Text -Key 'format'
        } else { '' }
        $statusStyle = if ($statusSection) {
            Get-StarshipSectionValue -SectionText $statusSection.Text -Key 'style'
        } else { '' }

        $archiveParts = @()
        foreach ($candidate in @($branchSection, $statusSection)) {
            if ($candidate) { $archiveParts += $candidate.Text.Trim("`n") }
        }

        $kept = @($parsed.Sections | Where-Object {
            $_.Name -ne 'git_branch' -and $_.Name -ne 'git_status' -and $_.Name -notlike 'env_var.DEVKIT_GIT_*'
        })

        $preamble = Update-StarshipFormatForPanel -Preamble $parsed.Preamble
        if ($null -eq $preamble) { return $false }

        $rebuilt = @($preamble.Trim("`n")) + @($kept | ForEach-Object { $_.Text.Trim("`n") })
        $panel = New-DevkitStarshipPanelBlock -Symbol $symbol -Background $background `
            -BranchFormat $branchFormat -StatusFormat $statusFormat -StatusStyle $statusStyle `
            -Archive ($archiveParts -join "`n")
        $final = ((@($rebuilt | Where-Object { $_.Trim() }) -join "`n`n").TrimEnd() + "`n`n" + $panel + "`n")

        # No BOM: Starship's TOML parser reads the byte order mark as part of the first key.
        [System.IO.File]::WriteAllText($Path, $final, (New-Object System.Text.UTF8Encoding($false)))
        return $true
    } catch {
        Write-Warning "Failed to apply the Starship git panel: $_"
        return $false
    }
}

function Remove-DevkitStarshipGitPanel {
    <#
    .SYNOPSIS
        Removes the devkit git panel from a starship.toml, restoring the preset sections
    .OUTPUTS
        Boolean - True when the file no longer carries a panel
    #>
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        if (-not (Test-Path $Path)) {
            Write-Warning "Starship config not found: $Path"
            return $false
        }
        if (-not (Test-DevkitStarshipGitPanel -Path $Path)) { return $true }

        $restored = Remove-DevkitStarshipPanelText -Text (Get-Content -LiteralPath $Path -Raw)
        [System.IO.File]::WriteAllText($Path, $restored, (New-Object System.Text.UTF8Encoding($false)))
        return $true
    } catch {
        Write-Warning "Failed to remove the Starship git panel: $_"
        return $false
    }
}

#endregion

function Install-DevkitStarshipConfig {
    <#
    .SYNOPSIS
        Resolves the Starship config for the chosen mode
    .DESCRIPTION
        Fresh  - exports $Preset into ~/.devkit/themes/starship.toml
        Keep   - uses whatever Starship already finds itself; returns "" on purpose
        Custom - copies $CustomPath into ~/.devkit/themes/starship.toml

        MUST NEVER THROW. Invoke-Installation only aborts the run on a thrown exception,
        so returning "" is what degrades a starship-less box to a warning. With no config
        written it deliberately returns "" rather than a path to a file that is not there -
        Save-VariablesPs1 then omits DEVKIT_STARSHIP_CONFIG and Starship falls back to its
        own default, which is a working prompt rather than a broken one.
    .PARAMETER Mode
        Fresh | Keep | Custom
    .PARAMETER Preset
        Preset name for Fresh mode
    .PARAMETER CustomPath
        Source .toml for Custom mode
    .PARAMETER GitPanel
        Apply the devkit git panel to the resolved config. Keep mode cannot honour this -
        the config is wherever Starship finds it and the devkit does not own that file.
    .OUTPUTS
        String - path to the devkit-managed config, or "" when none should be recorded
    #>
    param(
        [ValidateSet('Fresh', 'Keep', 'Custom')]
        [string]$Mode = 'Fresh',

        [string]$Preset = '',

        [string]$CustomPath = '',

        [bool]$GitPanel = $true
    )

    try {
        if ($Mode -eq 'Keep') {
            return ""
        }

        $destPath = Get-DevkitStarshipConfigPath
        $themesDir = Split-Path $destPath -Parent
        if (-not (Test-Path $themesDir)) {
            New-Item -Path $themesDir -ItemType Directory -Force | Out-Null
        }

        # A config we are about to replace is worth keeping - it may be hand-edited.
        if (Test-Path $destPath) {
            Backup-ConfigFile -Path $destPath -Description "starship-config" | Out-Null
        }

        if ($Mode -eq 'Custom') {
            if (-not $CustomPath -or -not (Test-Path $CustomPath)) {
                Write-Warning "Starship config not found: $CustomPath"
                return ""
            }
            Copy-Item -Path $CustomPath -Destination $destPath -Force
            if ($GitPanel) { Add-DevkitStarshipGitPanel -Path $destPath | Out-Null }
            return $destPath
        }

        $presetName = if ($Preset) { $Preset } else { $script:DevkitDefaultStarshipPreset }
        $export = Invoke-StarshipPresetExport -PresetName $presetName -DestinationPath $destPath

        # Detection decides success, not the exit code - same rule as Install-Prerequisites.
        if (Test-Path $destPath) {
            # Never fatal: a config without the panel is still a working prompt, so the
            # warning Add-DevkitStarshipGitPanel emits is the whole failure handling.
            if ($GitPanel) { Add-DevkitStarshipGitPanel -Path $destPath | Out-Null }
            return $destPath
        }

        Write-Warning "Could not export the '$presetName' Starship preset: $($export.Output)"
        return ""
    } catch {
        Write-Warning "Failed to resolve Starship configuration: $_"
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
        Path to the copied Oh-My-Posh theme file in user space. Written whenever it is
        known, even for Starship users, so `devkit prompt use oh-my-posh` needs no re-run.
    .PARAMETER Engine
        Prompt engine the profile should initialise: oh-my-posh (default) or starship
    .PARAMETER StarshipConfigPath
        Path to the devkit-managed starship.toml. Empty means "let Starship find its own",
        and the DEVKIT_STARSHIP_CONFIG line is omitted entirely.
    .PARAMETER GitPanel
        True when the Starship config carries the devkit git panel. This is what gates
        Invoke-Starship-PreCommand in the profile: the classifier costs a `git status`
        per prompt and buys nothing when no env_var module is there to read it.
    .PARAMETER SourceRoot
        Optional path to the source devkit repo (recorded as DEVKIT_REPO_ROOT)
    .OUTPUTS
        String - Generated variables.ps1 content
    #>
    param(
        [string]$ThemePath = "",

        [ValidateSet('oh-my-posh', 'starship')]
        [string]$Engine = 'oh-my-posh',

        [string]$StarshipConfigPath = "",

        [bool]$GitPanel = $false,

        [string]$SourceRoot = ""
    )

    # Normalize paths to forward slashes
    $themeLine = ""
    if ($ThemePath) {
        $normalizedTheme = $ThemePath -replace '\\', '/'
        $themeLine = "`$env:DEVKIT_OMP_THEME = `"$normalizedTheme`"`n"
    }

    # Only written when there IS a config. Pointing STARSHIP_CONFIG at a file that was
    # never created is worse than leaving Starship on its own default.
    $starshipLine = ""
    if ($StarshipConfigPath) {
        $normalizedStarship = $StarshipConfigPath -replace '\\', '/'
        $starshipLine = "`$env:DEVKIT_STARSHIP_CONFIG = `"$normalizedStarship`"`n"
    }

    # Absent, not "0", when off - the profile's guard is a truthiness test and an empty
    # env var and a missing one behave the same there.
    $panelLine = ""
    if ($GitPanel) {
        $panelLine = "`$env:DEVKIT_GIT_PANEL = `"1`"`n"
    }

    $repoLine = ""
    if ($SourceRoot) {
        $repoPath = $SourceRoot -replace '\\', '/'
        $repoLine = "`$env:DEVKIT_REPO_ROOT = `"$repoPath`"`n"
    }

    return @"
# Devkit Environment Variables
# Generated by Devkit Installation Wizard

`$env:DEVKIT_ROOT = "`$HOME/.devkit"
`$env:DEVKIT_PROMPT_ENGINE = "$Engine"
$themeLine$starshipLine$panelLine$repoLine
"@
}

function Save-VariablesPs1 {
    <#
    .SYNOPSIS
        Saves the variables.ps1 file to user space
    .PARAMETER ThemePath
        Path to the copied Oh-My-Posh theme file in user space
    .PARAMETER Engine
        Prompt engine the profile should initialise: oh-my-posh (default) or starship
    .PARAMETER StarshipConfigPath
        Path to the devkit-managed starship.toml, or "" for Starship's own default
    .PARAMETER GitPanel
        True when the Starship config carries the devkit git panel
    .PARAMETER SourceRoot
        Optional path to the source devkit repo (recorded as DEVKIT_REPO_ROOT)
    .OUTPUTS
        Boolean - True if successful
    #>
    param(
        [string]$ThemePath = "",

        [ValidateSet('oh-my-posh', 'starship')]
        [string]$Engine = 'oh-my-posh',

        [string]$StarshipConfigPath = "",

        [bool]$GitPanel = $false,

        [string]$SourceRoot = ""
    )

    $userRoot = Get-DevkitUserRoot
    $variablesPath = Join-Path $userRoot "variables.ps1"

    try {
        $content = New-VariablesPs1 -ThemePath $ThemePath -Engine $Engine `
            -StarshipConfigPath $StarshipConfigPath -GitPanel $GitPanel -SourceRoot $SourceRoot

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

#region Prerequisite Installation

# Native-command guard, shared by every seam below.
#
# install.ps1 sets $ErrorActionPreference = "Stop" at script scope and dot-sourced
# functions inherit it. On PowerShell 7.4+ $PSNativeCommandUseErrorActionPreference
# defaults to $true, so ANY non-zero exit from winget/oh-my-posh would become a
# TERMINATING error - which Invoke-Installation's catch turns into Success = $false,
# silently converting "warn and continue" into "abort the whole install". Redirecting
# 2>&1 on a native command also produces ErrorRecords that terminate under Stop.
#
# Do not remove this. A tidy-up that drops it reintroduces hard failures on the
# perfectly ordinary "package already installed" exit codes.
function Invoke-NativeCapture {
    <#
    .SYNOPSIS
        Runs a native command with output captured and native errors made non-terminating
    .PARAMETER Executable
        Full path or command name to run
    .PARAMETER Arguments
        Argument array
    .OUTPUTS
        Hashtable with Success, ExitCode, Output, Command. Never throws.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Executable,

        [string[]]$Arguments = @()
    )

    $result = @{
        Success = $false
        ExitCode = -1
        Output = ''
        Command = "$Executable $($Arguments -join ' ')"
    }

    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'

    $hasNativePref = $null -ne (Get-Variable -Name PSNativeCommandUseErrorActionPreference -Scope Global -ErrorAction SilentlyContinue)
    $prevNativePref = $null
    if ($hasNativePref) {
        $prevNativePref = $PSNativeCommandUseErrorActionPreference
        $global:PSNativeCommandUseErrorActionPreference = $false
    }

    try {
        # Capturing into a variable redirects the child's stdout handle, which makes
        # winget drop its animated progress bar and emit plain text - so no cursor
        # escapes reach the console and the Spectre UI is never corrupted.
        $output = & $Executable @Arguments 2>&1 | Out-String
        $result.ExitCode = $LASTEXITCODE
        $result.Output = $output
        $result.Success = ($LASTEXITCODE -eq 0)
    } catch {
        $result.Output = "$_"
        $result.Success = $false
    } finally {
        $ErrorActionPreference = $prevEap
        if ($hasNativePref) { $global:PSNativeCommandUseErrorActionPreference = $prevNativePref }
    }

    if ($env:DEVKIT_PREREQ_TRACE) {
        Write-Host "[prereq-trace] $($result.Command) -> exit $($result.ExitCode)" -ForegroundColor DarkGray
    }

    return $result
}

function Invoke-WingetInstall {
    <#
    .SYNOPSIS
        THE winget seam - the only place `winget install` is invoked
    .DESCRIPTION
        Install-Prerequisites calls this BY NAME so test-prereqs.ps1 can shadow it and
        the suite never installs anything. Do not inline `& winget` into the caller.

        --source winget pins the source so a corporate msstore mirror cannot hijack the
        id; --disable-interactivity stops winget prompting inside the wizard.
    .PARAMETER PackageId
        Exact winget package id
    .PARAMETER ExtraArgs
        Additional winget arguments
    .OUTPUTS
        Hashtable with Success, ExitCode, Output, Command. Never throws.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$PackageId,

        [string[]]$ExtraArgs = @()
    )

    $winget = Test-WingetAvailable
    if (-not $winget.Found) {
        return @{ Success = $false; ExitCode = -1; Output = 'winget is not available'; Command = "winget install --id $PackageId" }
    }

    $arguments = @(
        'install', '--id', $PackageId, '-e',
        '--source', 'winget',
        '--accept-package-agreements',
        '--accept-source-agreements',
        '--disable-interactivity',
        '--silent'
    ) + $ExtraArgs

    return Invoke-NativeCapture -Executable $winget.Path -Arguments $arguments
}

function Invoke-RemoteScriptInstall {
    <#
    .SYNOPSIS
        THE remote-script seam - runs a vendor installer downloaded over HTTPS
    .DESCRIPTION
        Deliberately runs in a CHILD pwsh rather than the wizard's own runspace: the
        downloaded script is free to call exit, which would otherwise kill the wizard
        mid-run. Shadowed by test-prereqs.ps1, so it is called by name.

        The URL is printed by the caller before this runs, so it is always visible what
        remote code is about to execute.
    .PARAMETER Url
        HTTPS URL of the installer script
    .PARAMETER Name
        Friendly name, used only in messages
    .OUTPUTS
        Hashtable with Success, ExitCode, Output, Command. Never throws.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Url,

        [string]$Name = ''
    )

    if ($Url -notmatch '^https://') {
        return @{ Success = $false; ExitCode = -1; Output = "Refusing to run a non-HTTPS installer URL: $Url"; Command = $Url }
    }

    $pwsh = Test-PwshAvailable
    if (-not $pwsh.Found) {
        return @{ Success = $false; ExitCode = -1; Output = 'pwsh not found; cannot run the installer in a child process'; Command = $Url }
    }

    return Invoke-NativeCapture -Executable $pwsh.Path -Arguments @(
        '-NoProfile', '-NonInteractive', '-Command', "irm '$Url' | iex"
    )
}

function Invoke-OhMyPoshFontInstall {
    <#
    .SYNOPSIS
        THE font seam - installs one Nerd Font via oh-my-posh
    .DESCRIPTION
        ALWAYS passes both a font name and --headless. The bare `oh-my-posh font install`
        form opens an interactive TUI picker, which inside the wizard would hang it.

        oh-my-posh is resolved through Test-CommandAvailable (not just Get-Command) so a
        copy installed moments ago at its well-known path is used even when PATH is stale.
    .PARAMETER FontName
        Font to install (e.g. "meslo")
    .OUTPUTS
        Hashtable with Success, ExitCode, Output, Command. Never throws.
    #>
    param(
        [string]$FontName = 'meslo'
    )

    $omp = Test-CommandAvailable -Name 'oh-my-posh' `
        -VersionArgs @() `
        -FallbackPaths @('%LOCALAPPDATA%\Programs\oh-my-posh\bin\oh-my-posh.exe')

    if (-not $omp.Found) {
        return @{ Success = $false; ExitCode = -1; Output = 'oh-my-posh not found'; Command = "oh-my-posh font install $FontName --headless" }
    }

    return Invoke-NativeCapture -Executable $omp.Path -Arguments @('font', 'install', $FontName, '--headless')
}

function Get-StarshipPath {
    <#
    .SYNOPSIS
        Resolves the starship binary, PATH first then the winget install locations
    .OUTPUTS
        Hashtable from Test-CommandAvailable (Found, Version, Path, Source)
    #>
    return Test-CommandAvailable -Name 'starship' `
        -VersionArgs @('--version') -VersionPattern '([\d\.]+)' `
        -FallbackPaths @('%LOCALAPPDATA%\Microsoft\WinGet\Links\starship.exe', '%ProgramFiles%\starship\bin\starship.exe')
}

function Get-StarshipPresetList {
    <#
    .SYNOPSIS
        THE starship preset-listing seam - the names embedded in the installed binary
    .DESCRIPTION
        Presets ship inside the binary, so this needs no network - but it does need
        starship on disk. Returns an empty array on any failure (binary missing, unexpected
        output) so callers can fall back to a static list instead of erroring.

        Called by name so test-prompt-engine.ps1 can shadow it.
    .OUTPUTS
        String[] - preset names, or @() when they cannot be determined
    #>
    $starship = Get-StarshipPath
    if (-not $starship.Found) { return @() }

    $result = Invoke-NativeCapture -Executable $starship.Path -Arguments @('preset', '--list')
    if (-not $result.Success -or -not $result.Output) { return @() }

    return @(
        $result.Output -split "`r?`n" |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -match '^[a-z0-9][a-z0-9-]*$' }
    )
}

function Invoke-StarshipPresetExport {
    <#
    .SYNOPSIS
        THE starship preset-export seam - writes one preset to a .toml file
    .DESCRIPTION
        `starship preset <name> -o <path>` renders a preset embedded in the binary. No
        network, but starship must be on disk. Resolved through Test-CommandAvailable so a
        copy installed moments ago at its well-known path is used even when PATH is stale.

        --force is not optional. Without it starship REFUSES to overwrite an existing file
        and exits 1, and because detection decides success here the caller then finds the
        old config still on disk and reports the export as having worked - so every
        `devkit prompt preset <name>` after the first silently keeps the previous preset.
        The destination is backed up by Install-DevkitStarshipConfig before this runs.

        Called by name so test-prompt-engine.ps1 can shadow it.
    .PARAMETER PresetName
        Preset to export (e.g. "gruvbox-rainbow")
    .PARAMETER DestinationPath
        Full path of the .toml file to write
    .OUTPUTS
        Hashtable with Success, ExitCode, Output, Command. Never throws.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$PresetName,

        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    $starship = Get-StarshipPath

    if (-not $starship.Found) {
        return @{ Success = $false; ExitCode = -1; Output = 'starship not found'; Command = "starship preset $PresetName -o $DestinationPath --force" }
    }

    return Invoke-NativeCapture -Executable $starship.Path -Arguments @('preset', $PresetName, '-o', $DestinationPath, '--force')
}

function Update-SessionPath {
    <#
    .SYNOPSIS
        Refreshes $env:PATH in THIS process from the Machine and User registry values
    .DESCRIPTION
        winget does not refresh the calling process's PATH, so a tool installed seconds
        ago is invisible to Get-Command until a new shell. This closes that gap for the
        wizard's later steps (the Git-editor list and the Oh-My-Posh theme scan).

        Registry entries come first, then any process-only entries a caller added by hand
        this session, so nothing already in the session is lost. PATH only - deliberately
        not a general environment refresh.

        Limits worth knowing: this does nothing for FONTS (not a PATH concern at all), and
        App Execution Alias shims under WindowsApps may still need a new shell. PowerShell
        also caches some application lookups, so Get-Command right after a refresh can
        still miss - which is why every detector also checks FallbackPaths directly.
    .OUTPUTS
        Hashtable with Added, Count, Before, After. Never throws.
    #>

    $result = @{ Added = @(); Count = 0; Before = $env:PATH; After = $env:PATH }

    try {
        $machine = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        $user = [Environment]::GetEnvironmentVariable('Path', 'User')
        $current = @($env:PATH -split ';')

        $merged = @($machine -split ';') + @($user -split ';') + $current

        $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $ordered = [System.Collections.Generic.List[string]]::new()
        foreach ($entry in $merged) {
            if (-not $entry) { continue }
            $trimmed = "$entry".Trim()
            if (-not $trimmed) { continue }
            if ($seen.Add($trimmed.TrimEnd('\'))) { $ordered.Add($trimmed) | Out-Null }
        }

        $before = [System.Collections.Generic.HashSet[string]]::new([string[]]$current, [StringComparer]::OrdinalIgnoreCase)
        $result.Added = @($ordered | Where-Object { -not $before.Contains($_) })
        $result.Count = $result.Added.Count

        $env:PATH = ($ordered -join ';')
        $result.After = $env:PATH
    } catch {
        Write-Warning "Failed to refresh PATH from the registry: $_"
    }

    return $result
}

function Install-Prerequisites {
    <#
    .SYNOPSIS
        Installs the selected prerequisite tools
    .DESCRIPTION
        Mirrors Install-RequiredModules: checks what is already present and skips it,
        wraps every item so one failure cannot stop the rest, NEVER THROWS, and emits no
        output of its own - the caller prints.

        Success is decided by RE-DETECTION, not by exit codes. winget has a family of
        non-zero-but-fine codes (already installed, no applicable upgrade), and the
        reverse also happens (exit 0, but the binary only lands on PATH in a new shell).
        Re-detecting after the seam returns handles both without hardcoding constants.
    .PARAMETER Keys
        Catalogue Keys to install
    .PARAMETER Catalog
        Catalogue rows (defaults to Get-DevkitPrerequisites)
    .PARAMETER Fonts
        Nerd Font names for the nerd-font row (defaults to that row's Fonts)
    .PARAMETER DryRun
        Resolve and report the exact commands without running anything
    .PARAMETER NoPathRefresh
        Skip the in-process PATH refresh after each install
    .OUTPUTS
        Hashtable with Installed, AlreadyInstalled, Failed, Skipped, NeedsNewShell,
        PathRefreshed. Never throws.
    #>
    param(
        [string[]]$Keys = @(),
        [array]$Catalog = @(),
        [string[]]$Fonts = @(),
        [switch]$DryRun,
        [switch]$NoPathRefresh
    )

    $results = @{
        Installed = @()
        AlreadyInstalled = @()
        Failed = @()
        Skipped = @()
        NeedsNewShell = @()
        PathRefreshed = $false
    }

    if (-not $Catalog -or $Catalog.Count -eq 0) { $Catalog = Get-DevkitPrerequisites }
    if ($Keys.Count -eq 0) { return $results }

    $wingetAvailable = (Test-WingetAvailable).Found

    # Local helper: is this row satisfied right now?
    $isPresent = {
        param($Row)
        $state = Get-PrerequisiteState -Catalog @($Row) -Keys @($Row.Key) -Fast
        $entry = $state[$Row.Key]
        if (-not $entry) { return $false }
        # A registry-only font hit is deliberately NOT treated as satisfied: a false
        # positive costs the user their glyphs, a false negative costs a redundant
        # download.
        if ($Row.Mechanism -eq 'omp-font') {
            return ($entry.Found -and $entry.Confidence -eq 'strong')
        }
        return [bool]$entry.Found
    }

    foreach ($row in $Catalog) {
        if ($Keys -notcontains $row.Key) { continue }

        # 1. Dry run: report the command, touch nothing.
        if ($DryRun) {
            $results.Skipped += @{ Name = $row.Name; Reason = 'dry-run'; Command = $row.InstallHint }
            continue
        }

        # 2. Already satisfied.
        if (& $isPresent $row) {
            $results.AlreadyInstalled += $row.Name
            continue
        }

        # 3. Dependency guard - this is what stops the font install when oh-my-posh failed.
        $unmet = @()
        foreach ($dep in @($row.DependsOn)) {
            $depRow = $Catalog | Where-Object { $_.Key -eq $dep } | Select-Object -First 1
            if ($depRow -and -not (& $isPresent $depRow)) { $unmet += $dep }
        }
        if ($unmet.Count -gt 0) {
            $results.Skipped += @{ Name = $row.Name; Reason = "requires $($unmet -join ', ')" }
            continue
        }

        # 4. Mechanism gates.
        if ($row.Mechanism -eq 'winget' -and -not $wingetAvailable) {
            $results.Skipped += @{ Name = $row.Name; Reason = 'winget (App Installer) not available'; Command = $row.InstallHint }
            continue
        }
        if ($row.HandledBy -eq 'installer-bootstrap') {
            $results.Skipped += @{ Name = $row.Name; Reason = 'handled by the installer bootstrap'; Command = $row.InstallHint }
            continue
        }

        # 5. Install via the matching seam.
        #
        # NOTE: `continue` inside a PowerShell switch continues the SWITCH, not this
        # foreach. Branches that fully handle a row therefore set $handled and the
        # post-switch verification is guarded on it - otherwise a handled row falls
        # through and gets a second, bogus "exit unknown" failure appended.
        $outcome = $null
        $handled = $false
        try {
            switch ($row.Mechanism) {
                'winget' {
                    $outcome = Invoke-WingetInstall -PackageId $row.WingetId
                }
                'remote-script' {
                    $outcome = Invoke-RemoteScriptInstall -Url $row.ScriptUrl -Name $row.Name
                }
                'omp-font' {
                    # Each font gets its own call, so one bad name cannot lose the others.
                    $fontList = if ($Fonts.Count -gt 0) { $Fonts } else { @($row.Fonts) }
                    $fontFailures = @()
                    $fontInstalled = @()
                    foreach ($font in $fontList) {
                        $fontResult = Invoke-OhMyPoshFontInstall -FontName $font
                        if ($fontResult.Success) { $fontInstalled += $font }
                        else { $fontFailures += "$font (exit $($fontResult.ExitCode))" }
                    }
                    foreach ($font in $fontInstalled) { $results.Installed += "$($row.Name): $font" }
                    if ($fontFailures.Count -gt 0) {
                        $results.Failed += @{ Name = $row.Name; Error = "font install failed: $($fontFailures -join ', ')" }
                    }
                    if (-not $NoPathRefresh) { Update-SessionPath | Out-Null; $results.PathRefreshed = $true }
                    $handled = $true
                }
                default {
                    $results.Skipped += @{ Name = $row.Name; Reason = "unsupported mechanism '$($row.Mechanism)'" }
                    $handled = $true
                }
            }
        } catch {
            # Belt and braces - the seams already never throw.
            $results.Failed += @{ Name = $row.Name; Error = "$_" }
            continue
        }

        if ($handled) { continue }

        # 6. Refresh PATH before re-detecting, so a just-installed tool can resolve.
        if (-not $NoPathRefresh) {
            Update-SessionPath | Out-Null
            $results.PathRefreshed = $true
        }

        # 7. Detection decides, not the exit code.
        if (& $isPresent $row) {
            $results.Installed += $row.Name
        } elseif ($outcome -and $outcome.ExitCode -eq 0) {
            $results.Installed += $row.Name
            $results.NeedsNewShell += $row.Name
        } else {
            $exitCode = if ($outcome) { $outcome.ExitCode } else { 'unknown' }
            $output = if ($outcome) { "$($outcome.Output)".Trim() } else { '' }
            if ($output.Length -gt 400) { $output = $output.Substring(0, 400) + '...' }
            $results.Failed += @{ Name = $row.Name; Error = "exit $exitCode`n$output" }
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
        StarshipConfig = ""
        StarshipGitPanel = $false
        GitConfig = $false
        ProfileConfigs = @()
        Variables = $false
        Profile = $false
        Errors = @()
    }

    # Pre-PromptEngine configs have no engine key; Oh My Posh stays the default.
    $engine = $Config.PowerShell.PromptEngine
    if (-not $engine) { $engine = 'oh-my-posh' }

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

    # Step 3: Copy the Oh-My-Posh theme to user space.
    # Runs whatever the engine, so switching back to Oh My Posh later needs no re-run.
    # Only fatal when Oh My Posh is the engine actually rendering the prompt.
    try {
        if ($Config.PowerShell.OhMyPoshTheme) {
            $results.ThemeCopied = Copy-DevkitTheme -SourceThemePath $Config.PowerShell.OhMyPoshTheme
        }
        if (-not $results.ThemeCopied -and $engine -eq 'oh-my-posh') {
            $results.Errors += "Failed to copy theme"
            $results.Success = $false
        }
    } catch {
        $results.Errors += "ThemeCopy: $_"
        $results.Success = $false
    }

    # Step 3b: Resolve the Starship config when that is the selected engine
    try {
        if ($engine -eq 'starship') {
            $results.StarshipConfig = Install-DevkitStarshipConfig `
                -Mode $(if ($Config.PowerShell.StarshipMode) { $Config.PowerShell.StarshipMode } else { 'Fresh' }) `
                -Preset $Config.PowerShell.StarshipPreset `
                -CustomPath $Config.PowerShell.StarshipConfig `
                -GitPanel ([bool]$Config.PowerShell.StarshipGitPanel)

            # Recorded from the file, not from the request: Add-DevkitStarshipGitPanel
            # warns and returns false on a format it cannot place the branch into, and
            # the profile must not then pay for a classifier nothing reads.
            $results.StarshipGitPanel = Test-DevkitStarshipGitPanel -Path $results.StarshipConfig
        }
    } catch {
        $results.Errors += "StarshipConfig: $_"
        $results.Success = $false
    }

    # Step 4: Generate variables.ps1 in user space
    # Not gated on the theme copy: a Starship user with no .omp.json still needs the file.
    try {
        $results.Variables = Save-VariablesPs1 `
            -ThemePath $results.ThemeCopied `
            -Engine $engine `
            -StarshipConfigPath $results.StarshipConfig `
            -GitPanel $results.StarshipGitPanel `
            -SourceRoot $SourceRoot
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
# Prompt engines:
# - Get-StarshipPath, Get-StarshipPresetList, Invoke-StarshipPresetExport
# - Get-DevkitStarshipConfigPath, Install-DevkitStarshipConfig
# Starship git panel:
# - Split-StarshipToml, Get-StarshipStyleBackground, Get-StarshipSectionValue
# - New-DevkitStarshipPanelBlock, Convert-StarshipBranchFormat
# - Update-StarshipFormatForPanel, Remove-DevkitStarshipPanelText
# - Add-DevkitStarshipGitPanel, Remove-DevkitStarshipGitPanel, Test-DevkitStarshipGitPanel
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
# Prerequisites:
# - Invoke-NativeCapture, Invoke-WingetInstall, Invoke-RemoteScriptInstall
# - Invoke-OhMyPoshFontInstall, Update-SessionPath, Install-Prerequisites
# Full Installation:
# - Invoke-ConfigGeneration
