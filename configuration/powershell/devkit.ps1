#Requires -Version 7.0
<#
.SYNOPSIS
    Devkit in-shell CLI: inventory, health checks, and management commands.

.DESCRIPTION
    Provides the `devkit` command. Run `devkit help` for the full listing of
    modules, aliases, keybindings, functions, git aliases, and nvim keymaps
    bundled with the devkit. Auto-loaded from ~/.devkit/devkit.ps1 by the
    PowerShell profile.

    Output uses plain Write-Host (no PwshSpectreConsole dependency) to keep
    shell-start cost negligible.
#>

$script:DevkitCliVersion = '1.0.0'

#region Registry — descriptions for things the devkit owns
# When the profile template or nvim config gains a new alias / keybinding /
# function, add a row here so `devkit help` and `devkit find` stay accurate.

$script:DevkitRegistry = @{
    Modules = @(
        @{ Name = 'z';              Description = 'Directory jumper - cd to frequently visited dirs' }
        @{ Name = 'posh-git';       Description = 'Git status + tab completion in the prompt' }
        @{ Name = 'Terminal-Icons'; Description = 'Nerd-Font icons in Get-ChildItem listings' }
        @{ Name = 'PSReadLine';     Description = 'Enhanced command-line editing, history, predictions' }
        @{ Name = 'PSFzf';          Description = '(optional) Fuzzy finder integration' }
        @{ Name = 'CompletionPredictor'; Description = '(optional) AI command-completion predictions' }
    )

    Aliases = @(
        @{ Name = 'grep';   Maps = 'findstr';     Description = 'Windows grep substitute' }
        @{ Name = 'add';    Maps = 'git add';     Description = 'shortcut for git add' }
        @{ Name = 'status'; Maps = 'git status';  Description = 'shortcut for git status' }
        @{ Name = 'commit'; Maps = 'git commit';  Description = 'shortcut for git commit' }
        @{ Name = 'gut';    Maps = 'git';         Description = 'typo-tolerant git' }
        @{ Name = '~';      Maps = 'cuserprofile';Description = 'cd to $HOME' }
    )

    PSReadLineKeymaps = @(
        @{ Key = 'F2';             Description = 'Toggle prediction view (inline vs list)' }
        @{ Key = 'UpArrow';        Description = 'History search backward' }
        @{ Key = 'DownArrow';      Description = 'History search forward' }
        @{ Key = 'Ctrl+UpArrow';   Description = 'Previous suggestion' }
        @{ Key = 'Ctrl+DownArrow'; Description = 'Next suggestion' }
        @{ Key = 'Ctrl+f';         Description = 'Accept next suggestion word' }
        @{ Key = 'Ctrl+Shift+b';   Description = 'Insert "dotnet build" + run' }
        @{ Key = 'Ctrl+Shift+r';   Description = 'Insert "cls" + run' }
    )

    Functions = @(
        @{ Name = 'cws';                          Description = 'cd to $env:DEVKIT_REPOS_PATH (default ~/repos)' }
        @{ Name = 'cuserprofile';                 Description = 'cd to $HOME (also bound to alias "~")' }
        @{ Name = 'U <code>';                     Description = 'Unicode codepoint -> character' }
        @{ Name = 'Get-My-Public-Ip';             Description = 'Print your current public IP via ipify.org' }
        @{ Name = 'Get-MailDomainInfo <domain>';  Description = 'Inspect a domain''s MX/SPF/DKIM/DMARC/autodiscover records' }
        @{ Name = 'Move-PhotosToMonthlyFolders';  Description = 'Sort photos into YYYY-MM/ folders' }
        @{ Name = 'Move-PhotosToYearFolders';     Description = 'Sort photos into YYYY/ folders' }
    )

    NvimKeymaps = @(
        @{ Key = '<leader>e';  Description = 'Toggle neo-tree file explorer' }
        @{ Key = '<leader>db'; Description = 'easy-dotnet: build' }
        @{ Key = '<leader>dr'; Description = 'easy-dotnet: run' }
        @{ Key = '<leader>dt'; Description = 'easy-dotnet: test runner' }
        @{ Key = '<leader>dw'; Description = 'easy-dotnet: watch' }
        @{ Key = '<leader>dn'; Description = 'easy-dotnet: new from template' }
        @{ Key = '<leader>ds'; Description = 'easy-dotnet: user secrets' }
        @{ Key = '<leader>do'; Description = 'easy-dotnet: outdated packages' }
    )

    # Claude Code + Herdr assets bundled by the installer (a051f98). Installed to
    # ~/.claude/ (agents|commands|skills|CLAUDE.md|hooks + a settings.json hook)
    # and %APPDATA%\herdr\config.toml. These are hand-maintained; keep in sync
    # with configuration/claude/* and configuration/herdr/config.toml.
    ClaudeHerdr = @(
        @{ Name = 'CLAUDE.md';                 Kind = 'claude';      Description = 'Global Claude Code instructions -> ~/.claude/CLAUDE.md' }
        @{ Name = 'architect';                 Kind = 'agent';       Description = 'Subagent: plan/design software projects' }
        @{ Name = 'code-reviewer';             Kind = 'agent';       Description = 'Subagent: quality/security/maintainability review' }
        @{ Name = 'context-fetcher';           Kind = 'agent';       Description = 'Subagent: extract relevant info from docs' }
        @{ Name = 'context-manager';           Kind = 'agent';       Description = 'Subagent: coordinate multi-agent context' }
        @{ Name = 'debugger';                  Kind = 'agent';       Description = 'Subagent: root-cause errors and test failures' }
        @{ Name = 'sdk-research-specialist';   Kind = 'agent';       Description = 'Subagent: deep SDK/library documentation research' }
        @{ Name = 'terraform-specialist';      Kind = 'agent';       Description = 'Subagent: Terraform modules and IaC' }
        @{ Name = 'test-automator';            Kind = 'agent';       Description = 'Subagent: build unit/integration/e2e test suites' }
        @{ Name = 'test-runner';               Kind = 'agent';       Description = 'Subagent: run tests and analyze failures' }
        @{ Name = 'analyze-product';           Kind = 'command';     Description = 'Slash command: analyze the current product' }
        @{ Name = 'create-spec';               Kind = 'command';     Description = 'Slash command: spec creation workflow' }
        @{ Name = 'execute-tasks';             Kind = 'command';     Description = 'Slash command: execute planned tasks' }
        @{ Name = 'plan-product';              Kind = 'command';     Description = 'Slash command: product planning workflow' }
        @{ Name = 'herdr';                     Kind = 'skill';       Description = 'Skill: herdr CLI reference (tmux for AI agents)' }
        @{ Name = 'spin-up-herd';              Kind = 'skill';       Description = 'Skill: fan a herd of Claude agents into a tab' }
        @{ Name = 'herdr SessionStart hook';   Kind = 'integration'; Description = 'Reports Claude sessions to Herdr panes (settings.json)' }
        @{ Name = 'Herdr config.toml';         Kind = 'integration'; Description = 'Herdr app config -> %APPDATA%\herdr\config.toml' }
    )

    Commands = @(
        @{ Name = 'devkit help [topic]';            Description = 'This help, or one section (modules|aliases|keymaps|functions|git|nvim|claude|herdr|env|commands)' }
        @{ Name = 'devkit version';                 Description = 'Devkit version + install paths' }
        @{ Name = 'devkit doctor';                  Description = 'Run health checks' }
        @{ Name = 'devkit find <keyword>';          Description = 'Search inventory for matching rows' }
        @{ Name = 'devkit update';                  Description = 'Re-run install.ps1 (re-launches the wizard)' }
        @{ Name = 'devkit nvim refresh';            Description = 'Re-copy the bundled Neovim config' }
        @{ Name = 'devkit claude refresh [--force]'; Description = 'Re-copy bundled Claude Code assets into ~/.claude (--force replaces a drifted CLAUDE.md)' }
        @{ Name = 'devkit herdr refresh';           Description = 'Re-write %APPDATA%\herdr\config.toml' }
        @{ Name = 'devkit backups list';            Description = 'List ~/.devkit/backups/' }
        @{ Name = 'devkit backups restore <name>';  Description = 'Restore a backup file or directory' }
        @{ Name = 'devkit fix terminal-icons';      Description = 'Purge corrupt Terminal-Icons CLIXML cache' }
    )
}

#endregion

#region Output helpers (plain Write-Host)

function _Devkit-WriteSection {
    param([Parameter(Mandatory)][string]$Title)
    Write-Host ""
    Write-Host $Title -ForegroundColor Cyan
}

function _Devkit-WriteRow {
    param(
        [Parameter(Mandatory)][string]$Left,
        [string]$Right = '',
        [ConsoleColor]$LeftColor = 'White',
        [int]$Pad = 22
    )
    $padded = $Left.PadRight($Pad)
    Write-Host "  $padded" -ForegroundColor $LeftColor -NoNewline
    if ($Right) {
        Write-Host " $Right" -ForegroundColor DarkGray
    } else {
        Write-Host ""
    }
}

function _Devkit-WriteDim {
    param([string]$Text)
    Write-Host $Text -ForegroundColor DarkGray
}

#endregion

#region Section printers

function _Devkit-PrintBanner {
    $root = if ($env:DEVKIT_ROOT) { $env:DEVKIT_ROOT } else { '(not installed)' }
    Write-Host ""
    Write-Host "DEVKIT v$script:DevkitCliVersion " -ForegroundColor Magenta -NoNewline
    Write-Host "(installed at $root)" -ForegroundColor DarkGray
}

function _Devkit-PrintModules {
    _Devkit-WriteSection "POWERSHELL MODULES"
    foreach ($mod in $script:DevkitRegistry.Modules) {
        $installed = $null -ne (Get-Module -ListAvailable -Name $mod.Name -ErrorAction SilentlyContinue)
        $marker = if ($installed) { '✓' } else { '✗' }
        $color = if ($installed) { 'Green' } else { 'DarkGray' }
        Write-Host "  $marker " -ForegroundColor $color -NoNewline
        _Devkit-WriteRow -Left $mod.Name -Right $mod.Description -Pad 20
    }
    _Devkit-WriteDim "  (✓ installed / ✗ not found)"
}

function _Devkit-PrintAliases {
    _Devkit-WriteSection "POWERSHELL ALIASES"
    foreach ($a in $script:DevkitRegistry.Aliases) {
        $rhs = "-> $($a.Maps)    $($a.Description)"
        _Devkit-WriteRow -Left $a.Name -Right $rhs -Pad 10
    }
}

function _Devkit-PrintPSReadLineKeymaps {
    _Devkit-WriteSection "PSREADLINE KEYBINDINGS"
    foreach ($k in $script:DevkitRegistry.PSReadLineKeymaps) {
        _Devkit-WriteRow -Left $k.Key -Right $k.Description -Pad 18
    }
}

function _Devkit-PrintFunctions {
    _Devkit-WriteSection "CUSTOM FUNCTIONS"
    foreach ($f in $script:DevkitRegistry.Functions) {
        _Devkit-WriteRow -Left $f.Name -Right $f.Description -Pad 32
    }
}

function _Devkit-PrintGitAliases {
    _Devkit-WriteSection "GIT ALIASES"
    try {
        $raw = git config --global --get-regexp '^alias\.' 2>$null
        if (-not $raw) {
            _Devkit-WriteDim "  (none configured in --global)"
            return
        }
        foreach ($line in $raw) {
            if ($line -match '^alias\.(\S+)\s+(.*)$') {
                $name = $Matches[1]
                $value = $Matches[2]
                # Truncate noisy long aliases for readability
                if ($value.Length -gt 80) { $value = $value.Substring(0, 77) + '...' }
                _Devkit-WriteRow -Left $name -Right $value -Pad 12
            }
        }
    } catch {
        _Devkit-WriteDim "  (git not on PATH)"
    }
}

function _Devkit-PrintNvimKeymaps {
    _Devkit-WriteSection "NVIM KEYMAPS  (leader = space)"
    foreach ($k in $script:DevkitRegistry.NvimKeymaps) {
        _Devkit-WriteRow -Left $k.Key -Right $k.Description -Pad 14
    }
}

function _Devkit-PrintEnv {
    _Devkit-WriteSection "ENV VARS"
    $vars = Get-ChildItem env: | Where-Object { $_.Name -like 'DEVKIT_*' } | Sort-Object Name
    if (-not $vars) {
        _Devkit-WriteDim "  (no DEVKIT_* env vars in this session)"
        return
    }
    foreach ($v in $vars) {
        _Devkit-WriteRow -Left $v.Name -Right $v.Value -Pad 22
    }
}

function _Devkit-PrintCommands {
    _Devkit-WriteSection "COMMANDS"
    foreach ($c in $script:DevkitRegistry.Commands) {
        _Devkit-WriteRow -Left $c.Name -Right $c.Description -Pad 30
    }
}

function _Devkit-ClaudeHerdrPresence {
    # Live ✓/✗ for each registry row's Kind (installed by a051f98's installer).
    param([Parameter(Mandatory)]$Row)
    $claudeRoot = Join-Path $env:USERPROFILE '.claude'
    switch ($Row.Kind) {
        'claude'      { return (Test-Path (Join-Path $claudeRoot 'CLAUDE.md')) }
        'agent'       { return (Test-Path (Join-Path $claudeRoot "agents\$($Row.Name).md")) }
        'command'     { return (Test-Path (Join-Path $claudeRoot "commands\$($Row.Name).md")) }
        'skill'       { return (Test-Path (Join-Path $claudeRoot "skills\$($Row.Name)")) }
        'integration' {
            if ($Row.Name -match 'config\.toml') {
                return (Test-Path (Join-Path $env:APPDATA 'herdr\config.toml'))
            }
            return (Test-Path (Join-Path $claudeRoot 'hooks\herdr-agent-state.ps1'))
        }
        default { return $false }
    }
}

function _Devkit-PrintClaudeHerdr {
    _Devkit-WriteSection "CLAUDE / HERDR"
    foreach ($r in $script:DevkitRegistry.ClaudeHerdr) {
        $present = _Devkit-ClaudeHerdrPresence $r
        $marker = if ($present) { '✓' } else { '✗' }
        $color = if ($present) { 'Green' } else { 'DarkGray' }
        Write-Host "  $marker " -ForegroundColor $color -NoNewline
        _Devkit-WriteRow -Left $r.Name -Right $r.Description -Pad 24
    }
    _Devkit-WriteDim "  (✓ installed / ✗ not found)  refresh with: devkit claude refresh | devkit herdr refresh"
}

#endregion

#region Subcommand: help

function Show-DevkitHelp {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Topic
    )

    if (-not $Topic) {
        _Devkit-PrintBanner
        _Devkit-PrintModules
        _Devkit-PrintAliases
        _Devkit-PrintPSReadLineKeymaps
        _Devkit-PrintFunctions
        _Devkit-PrintGitAliases
        _Devkit-PrintNvimKeymaps
        _Devkit-PrintClaudeHerdr
        _Devkit-PrintEnv
        _Devkit-PrintCommands
        Write-Host ""
        return
    }

    switch ($Topic.ToLower()) {
        'modules'   { _Devkit-PrintModules }
        'aliases'   { _Devkit-PrintAliases }
        'keymaps'   { _Devkit-PrintPSReadLineKeymaps }
        'functions' { _Devkit-PrintFunctions }
        'git'       { _Devkit-PrintGitAliases }
        'nvim'      { _Devkit-PrintNvimKeymaps }
        'claude'    { _Devkit-PrintClaudeHerdr }
        'herdr'     { _Devkit-PrintClaudeHerdr }
        'env'       { _Devkit-PrintEnv }
        'commands'  { _Devkit-PrintCommands }
        default {
            Write-Warning "Unknown topic: $Topic"
            Write-Host "  Topics: modules, aliases, keymaps, functions, git, nvim, claude, herdr, env, commands" -ForegroundColor DarkGray
        }
    }
    Write-Host ""
}

#endregion

#region Subcommand: version

function Show-DevkitVersion {
    _Devkit-PrintBanner
    Write-Host ""

    $items = [ordered]@{
        'CLI version'      = $script:DevkitCliVersion
        'DEVKIT_ROOT'      = $env:DEVKIT_ROOT
        'DEVKIT_REPO_ROOT' = $env:DEVKIT_REPO_ROOT
        'DEVKIT_OMP_THEME' = $env:DEVKIT_OMP_THEME
    }

    $profilePath = Join-Path $env:USERPROFILE '.devkit\profile.ps1'
    if (Test-Path $profilePath) {
        $items['Profile installed'] = (Get-Item $profilePath).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
    }

    foreach ($k in $items.Keys) {
        $v = if ($items[$k]) { $items[$k] } else { '(not set)' }
        _Devkit-WriteRow -Left $k -Right $v -Pad 20
    }
    Write-Host ""
}

#endregion

#region Subcommand: doctor

function _Devkit-CheckResult {
    param(
        [Parameter(Mandatory)][string]$Status,  # OK | WARN | FAIL
        [Parameter(Mandatory)][string]$Name,
        [string]$Detail = '',
        [string]$Hint = ''
    )

    $color = switch ($Status) {
        'OK'   { 'Green' }
        'WARN' { 'Yellow' }
        'FAIL' { 'Red' }
        default { 'White' }
    }
    $tag = "[$Status]".PadRight(7)
    Write-Host "  $tag" -ForegroundColor $color -NoNewline
    Write-Host " $Name" -NoNewline
    if ($Detail) {
        Write-Host " - $Detail" -ForegroundColor DarkGray
    } else {
        Write-Host ""
    }
    if ($Hint -and $Status -ne 'OK') {
        Write-Host "         hint: $Hint" -ForegroundColor DarkGray
    }
}

function Invoke-DevkitDoctor {
    _Devkit-PrintBanner
    _Devkit-WriteSection "HEALTH CHECKS"

    # 1. $PROFILE sources ~/.devkit/profile.ps1
    if (Test-Path $PROFILE) {
        $profileContent = Get-Content $PROFILE -Raw -ErrorAction SilentlyContinue
        if ($profileContent -match 'DevKit Profile Configuration|\.devkit[\\/]profile\.ps1') {
            _Devkit-CheckResult OK '$PROFILE sources devkit'
        } else {
            _Devkit-CheckResult FAIL '$PROFILE does not source devkit' -Hint 'Run: devkit update'
        }
    } else {
        _Devkit-CheckResult FAIL '$PROFILE does not exist' -Hint 'Run: devkit update'
    }

    # 2. ~/.devkit/variables.ps1 exists
    $varsPath = Join-Path $env:USERPROFILE '.devkit\variables.ps1'
    if (Test-Path $varsPath) {
        _Devkit-CheckResult OK '~/.devkit/variables.ps1 present'
    } else {
        _Devkit-CheckResult FAIL '~/.devkit/variables.ps1 missing' -Hint 'Run: devkit update'
    }

    # 3. $env:DEVKIT_REPO_ROOT resolves
    if ($env:DEVKIT_REPO_ROOT -and (Test-Path $env:DEVKIT_REPO_ROOT)) {
        _Devkit-CheckResult OK '$env:DEVKIT_REPO_ROOT resolves' -Detail $env:DEVKIT_REPO_ROOT
    } elseif ($env:DEVKIT_REPO_ROOT) {
        _Devkit-CheckResult FAIL '$env:DEVKIT_REPO_ROOT does not exist' -Detail $env:DEVKIT_REPO_ROOT -Hint 'Re-clone the devkit repo and re-run install.ps1'
    } else {
        _Devkit-CheckResult WARN '$env:DEVKIT_REPO_ROOT not set' -Hint 'Re-run install.ps1 to populate variables.ps1'
    }

    # 4. Terminal-Icons CLIXML cache readable
    $cacheDir = Join-Path $env:APPDATA 'powershell\Community\Terminal-Icons'
    if (Test-Path $cacheDir) {
        $broken = @()
        foreach ($f in (Get-ChildItem $cacheDir -Filter 'devblackops_*.xml' -ErrorAction SilentlyContinue)) {
            try {
                Import-Clixml -Path $f.FullName -ErrorAction Stop | Out-Null
            } catch {
                $broken += $f.Name
            }
        }
        if ($broken.Count -eq 0) {
            _Devkit-CheckResult OK 'Terminal-Icons cache readable'
        } else {
            _Devkit-CheckResult FAIL ("Terminal-Icons cache corrupt ({0} file(s))" -f $broken.Count) -Detail ($broken -join ', ') -Hint 'Run: devkit fix terminal-icons'
        }
    } else {
        _Devkit-CheckResult OK 'Terminal-Icons cache absent (will regenerate)'
    }

    # 5. Nvim init.lua has devkit-managed marker
    $nvimInit = Join-Path $env:LOCALAPPDATA 'nvim\init.lua'
    if (Test-Path $nvimInit) {
        $firstLine = Get-Content $nvimInit -TotalCount 1
        if ($firstLine -match '^\s*--\s*devkit-managed') {
            _Devkit-CheckResult OK 'Nvim config is devkit-managed'
        } else {
            _Devkit-CheckResult WARN 'Nvim config exists but is not devkit-managed' -Hint 'Run: devkit nvim refresh'
        }
    } else {
        _Devkit-CheckResult WARN 'No Nvim config at $env:LOCALAPPDATA\nvim\init.lua' -Hint 'Run: devkit nvim refresh (or re-run install.ps1)'
    }

    # 6. Oh-My-Posh theme path resolves
    if ($env:DEVKIT_OMP_THEME) {
        if (Test-Path $env:DEVKIT_OMP_THEME) {
            _Devkit-CheckResult OK 'Oh-My-Posh theme resolves' -Detail (Split-Path $env:DEVKIT_OMP_THEME -Leaf)
        } else {
            _Devkit-CheckResult FAIL 'Oh-My-Posh theme path broken' -Detail $env:DEVKIT_OMP_THEME -Hint 'Run: devkit update'
        }
    } else {
        _Devkit-CheckResult WARN 'Oh-My-Posh theme not set' -Hint 'Run: devkit update'
    }

    # 7. Required tools on PATH (claude/herdr/glow are optional external apps the
    # devkit only configures or leverages - nothing here is installed by the devkit)
    foreach ($tool in @('git', 'nvim', 'oh-my-posh', 'claude', 'herdr', 'glow')) {
        $cmd = Get-Command $tool -ErrorAction SilentlyContinue
        if ($cmd) {
            _Devkit-CheckResult OK "$tool on PATH" -Detail $cmd.Source
        } else {
            $hint = switch ($tool) {
                'nvim'       { 'winget install Neovim.Neovim' }
                'oh-my-posh' { 'winget install JanDeDobbeleer.OhMyPosh' }
                'git'        { 'winget install Git.Git' }
                'claude'     { 'Optional: install Claude Code to use the bundled agents/commands' }
                'herdr'      { 'Optional: external multiplexer; the devkit only writes its config' }
                'glow'       { 'Optional: winget install charmbracelet.glow (terminal markdown renderer)' }
            }
            _Devkit-CheckResult WARN "$tool not on PATH" -Hint $hint
        }
    }

    # 8. Registered modules importable
    foreach ($mod in $script:DevkitRegistry.Modules) {
        $available = $null -ne (Get-Module -ListAvailable -Name $mod.Name -ErrorAction SilentlyContinue)
        if ($available) {
            _Devkit-CheckResult OK "Module $($mod.Name) available"
        } else {
            # PSFzf / CompletionPredictor are optional; downgrade to WARN
            $optional = $mod.Description -match '^\(optional\)'
            if ($optional) {
                _Devkit-CheckResult WARN "Module $($mod.Name) not installed (optional)"
            } else {
                _Devkit-CheckResult FAIL "Module $($mod.Name) missing" -Hint "Install-Module $($mod.Name) -Scope CurrentUser"
            }
        }
    }

    # 9. Claude Code assets present (installed by the wizard into ~/.claude)
    $claudeRoot = Join-Path $env:USERPROFILE '.claude'
    $claudeMd = Join-Path $claudeRoot 'CLAUDE.md'
    if (Test-Path $claudeMd) {
        _Devkit-CheckResult OK '~/.claude/CLAUDE.md present'
    } else {
        _Devkit-CheckResult WARN '~/.claude/CLAUDE.md missing' -Hint 'Run: devkit claude refresh'
    }

    # 10. Herdr SessionStart hook wired into settings.json
    $claudeSettings = Join-Path $claudeRoot 'settings.json'
    if (Test-Path $claudeSettings) {
        $settingsRaw = Get-Content $claudeSettings -Raw -ErrorAction SilentlyContinue
        if ($settingsRaw -match 'herdr-agent-state\.ps1') {
            _Devkit-CheckResult OK 'Herdr SessionStart hook wired in settings.json'
        } else {
            _Devkit-CheckResult WARN 'settings.json present but Herdr hook not wired' -Hint 'Run: devkit claude refresh'
        }
    } else {
        _Devkit-CheckResult WARN '~/.claude/settings.json missing' -Hint 'Run: devkit claude refresh'
    }

    # 11. Herdr hook script installed
    $herdrHook = Join-Path $claudeRoot 'hooks\herdr-agent-state.ps1'
    if (Test-Path $herdrHook) {
        _Devkit-CheckResult OK 'Herdr hook script present' -Detail 'hooks\herdr-agent-state.ps1'
    } else {
        _Devkit-CheckResult WARN 'Herdr hook script missing' -Hint 'Run: devkit claude refresh'
    }

    # 12. Herdr config.toml present
    $herdrConfig = Join-Path $env:APPDATA 'herdr\config.toml'
    if (Test-Path $herdrConfig) {
        _Devkit-CheckResult OK 'Herdr config.toml present' -Detail $herdrConfig
    } else {
        _Devkit-CheckResult WARN 'Herdr config.toml missing' -Hint 'Run: devkit herdr refresh'
    }

    Write-Host ""
}

#endregion

#region Subcommand: find

function Find-DevkitEntry {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Keyword
    )

    if ([string]::IsNullOrWhiteSpace($Keyword)) {
        Write-Warning "Usage: devkit find <keyword>"
        return
    }

    $kw = $Keyword.ToLower()
    $anyHits = $false

    function _matchRow {
        param($Row, $Fields)
        foreach ($f in $Fields) {
            if ($Row.$f -and $Row.$f.ToString().ToLower().Contains($kw)) { return $true }
        }
        return $false
    }

    # Modules
    $hits = @($script:DevkitRegistry.Modules | Where-Object { _matchRow $_ @('Name', 'Description') })
    if ($hits.Count) {
        $anyHits = $true
        _Devkit-WriteSection "POWERSHELL MODULES"
        foreach ($r in $hits) { _Devkit-WriteRow -Left $r.Name -Right $r.Description -Pad 20 }
    }

    # Aliases
    $hits = @($script:DevkitRegistry.Aliases | Where-Object { _matchRow $_ @('Name', 'Maps', 'Description') })
    if ($hits.Count) {
        $anyHits = $true
        _Devkit-WriteSection "POWERSHELL ALIASES"
        foreach ($r in $hits) {
            _Devkit-WriteRow -Left $r.Name -Right "-> $($r.Maps)    $($r.Description)" -Pad 10
        }
    }

    # PSReadLine keymaps
    $hits = @($script:DevkitRegistry.PSReadLineKeymaps | Where-Object { _matchRow $_ @('Key', 'Description') })
    if ($hits.Count) {
        $anyHits = $true
        _Devkit-WriteSection "PSREADLINE KEYBINDINGS"
        foreach ($r in $hits) { _Devkit-WriteRow -Left $r.Key -Right $r.Description -Pad 18 }
    }

    # Functions
    $hits = @($script:DevkitRegistry.Functions | Where-Object { _matchRow $_ @('Name', 'Description') })
    if ($hits.Count) {
        $anyHits = $true
        _Devkit-WriteSection "CUSTOM FUNCTIONS"
        foreach ($r in $hits) { _Devkit-WriteRow -Left $r.Name -Right $r.Description -Pad 32 }
    }

    # Nvim keymaps
    $hits = @($script:DevkitRegistry.NvimKeymaps | Where-Object { _matchRow $_ @('Key', 'Description') })
    if ($hits.Count) {
        $anyHits = $true
        _Devkit-WriteSection "NVIM KEYMAPS"
        foreach ($r in $hits) { _Devkit-WriteRow -Left $r.Key -Right $r.Description -Pad 14 }
    }

    # Claude / Herdr assets
    $hits = @($script:DevkitRegistry.ClaudeHerdr | Where-Object { _matchRow $_ @('Name', 'Kind', 'Description') })
    if ($hits.Count) {
        $anyHits = $true
        _Devkit-WriteSection "CLAUDE / HERDR"
        foreach ($r in $hits) { _Devkit-WriteRow -Left $r.Name -Right $r.Description -Pad 24 }
    }

    # Git aliases (live)
    try {
        $raw = git config --global --get-regexp '^alias\.' 2>$null
        if ($raw) {
            $gitHits = @()
            foreach ($line in $raw) {
                if ($line -match '^alias\.(\S+)\s+(.*)$') {
                    $name = $Matches[1]; $value = $Matches[2]
                    if ("$name $value".ToLower().Contains($kw)) {
                        $gitHits += @{ Name = $name; Value = $value }
                    }
                }
            }
            if ($gitHits.Count) {
                $anyHits = $true
                _Devkit-WriteSection "GIT ALIASES"
                foreach ($r in $gitHits) {
                    $v = $r.Value
                    if ($v.Length -gt 80) { $v = $v.Substring(0, 77) + '...' }
                    _Devkit-WriteRow -Left $r.Name -Right $v -Pad 12
                }
            }
        }
    } catch { }

    # Env vars
    $envHits = @(Get-ChildItem env: | Where-Object {
            $_.Name -like 'DEVKIT_*' -and
            ("$($_.Name) $($_.Value)".ToLower().Contains($kw))
        })
    if ($envHits.Count) {
        $anyHits = $true
        _Devkit-WriteSection "ENV VARS"
        foreach ($v in $envHits) { _Devkit-WriteRow -Left $v.Name -Right $v.Value -Pad 22 }
    }

    # Commands
    $hits = @($script:DevkitRegistry.Commands | Where-Object { _matchRow $_ @('Name', 'Description') })
    if ($hits.Count) {
        $anyHits = $true
        _Devkit-WriteSection "COMMANDS"
        foreach ($r in $hits) { _Devkit-WriteRow -Left $r.Name -Right $r.Description -Pad 30 }
    }

    if (-not $anyHits) {
        Write-Host ""
        Write-Host "  No matches for '$Keyword'." -ForegroundColor DarkGray
    }
    Write-Host ""
}

#endregion

#region Subcommand: update

function Invoke-DevkitUpdate {
    if (-not $env:DEVKIT_REPO_ROOT) {
        Write-Host "ERROR: " -ForegroundColor Red -NoNewline
        Write-Host '$env:DEVKIT_REPO_ROOT is not set. Re-clone the devkit and run install.ps1 directly.'
        return
    }
    if (-not (Test-Path $env:DEVKIT_REPO_ROOT)) {
        Write-Host "ERROR: " -ForegroundColor Red -NoNewline
        Write-Host "Repo root not found at: $env:DEVKIT_REPO_ROOT"
        return
    }

    $installer = Join-Path $env:DEVKIT_REPO_ROOT 'configuration\install.ps1'
    if (-not (Test-Path $installer)) {
        Write-Host "ERROR: " -ForegroundColor Red -NoNewline
        Write-Host "install.ps1 not found at: $installer"
        return
    }

    $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')
    if (-not $isAdmin) {
        Write-Host "WARN: " -ForegroundColor Yellow -NoNewline
        Write-Host "Not running as Admin. The installer needs Admin to install PowerShell modules."
        Write-Host "      Re-run from an Admin PowerShell, or proceed at your own risk." -ForegroundColor DarkGray
    }

    Write-Host "Launching devkit installer..." -ForegroundColor Cyan
    & $installer
}

#endregion

#region Subcommand: nvim

function Invoke-DevkitNvim {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Action
    )

    switch ($Action) {
        'refresh' {
            if (-not $env:DEVKIT_REPO_ROOT -or -not (Test-Path $env:DEVKIT_REPO_ROOT)) {
                Write-Host "ERROR: " -ForegroundColor Red -NoNewline
                Write-Host '$env:DEVKIT_REPO_ROOT is not set or does not exist.'
                return
            }

            $libPath = Join-Path $env:DEVKIT_REPO_ROOT 'configuration\lib\config-generator.ps1'
            if (-not (Test-Path $libPath)) {
                Write-Host "ERROR: " -ForegroundColor Red -NoNewline
                Write-Host "config-generator.ps1 not found at: $libPath"
                return
            }

            . $libPath
            $dest = Copy-DevkitNvimConfig -SourceRoot $env:DEVKIT_REPO_ROOT
            if ($dest) {
                Write-Host "Refreshed nvim config at " -NoNewline
                Write-Host $dest -ForegroundColor Green
            } else {
                Write-Host "Failed to refresh nvim config." -ForegroundColor Red
            }
        }
        default {
            Write-Warning "Usage: devkit nvim refresh"
        }
    }
}

#endregion

#region Subcommand: claude / herdr

function _Devkit-ResolveGenerator {
    # Shared guard + dot-source for the refresh commands that reuse the
    # installer's copy helpers. Returns the config-generator.ps1 path, or $null.
    if (-not $env:DEVKIT_REPO_ROOT -or -not (Test-Path $env:DEVKIT_REPO_ROOT)) {
        Write-Host "ERROR: " -ForegroundColor Red -NoNewline
        Write-Host '$env:DEVKIT_REPO_ROOT is not set or does not exist.'
        return $null
    }
    $libPath = Join-Path $env:DEVKIT_REPO_ROOT 'configuration\lib\config-generator.ps1'
    if (-not (Test-Path $libPath)) {
        Write-Host "ERROR: " -ForegroundColor Red -NoNewline
        Write-Host "config-generator.ps1 not found at: $libPath"
        return $null
    }
    return $libPath
}

function Invoke-DevkitClaude {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Action,

        [Parameter(ValueFromRemainingArguments)]
        [string[]]$Rest
    )

    switch ($Action) {
        'refresh' {
            $libPath = _Devkit-ResolveGenerator
            if (-not $libPath) { return }
            . $libPath

            $force = @($Rest) -contains '--force' -or @($Rest) -contains '-Force'
            $root = $env:DEVKIT_REPO_ROOT

            # CLAUDE.md is the one asset that accumulates edits outside the repo, so a
            # plain refresh leaves a drifted file alone and says so.
            if (-not (Copy-DevkitClaudeMd -SourceRoot $root -Force:$force)) {
                Write-Host "  CLAUDE.md skipped - re-run as " -NoNewline -ForegroundColor DarkGray
                Write-Host "devkit claude refresh --force" -NoNewline -ForegroundColor Yellow
                Write-Host " to overwrite it." -ForegroundColor DarkGray
            }

            Copy-DevkitClaudeAgents   -SourceRoot $root
            Copy-DevkitClaudeSkills   -SourceRoot $root
            Copy-DevkitClaudeCommands -SourceRoot $root
            Install-HerdrHookAndSettings -SourceRoot $root

            Write-Host "Refreshed Claude Code assets in " -NoNewline
            Write-Host (Join-Path $env:USERPROFILE '.claude') -ForegroundColor Green
        }
        default {
            Write-Warning "Usage: devkit claude refresh [--force]"
        }
    }
}

function Invoke-DevkitHerdr {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Action
    )

    switch ($Action) {
        'refresh' {
            $libPath = _Devkit-ResolveGenerator
            if (-not $libPath) { return }
            . $libPath

            Save-HerdrConfig -SourceRoot $env:DEVKIT_REPO_ROOT
            Write-Host "Refreshed Herdr config at " -NoNewline
            Write-Host (Join-Path $env:APPDATA 'herdr\config.toml') -ForegroundColor Green
        }
        default {
            Write-Warning "Usage: devkit herdr refresh"
        }
    }
}

#endregion

#region Subcommand: backups

function _Devkit-GetBackupRoot {
    return Join-Path $env:USERPROFILE '.devkit\backups'
}

function _Devkit-DirectorySize {
    param([string]$Path)
    try {
        $bytes = (Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Sum Length).Sum
        if ($null -eq $bytes) { return 0 } else { return $bytes }
    } catch {
        return 0
    }
}

function _Devkit-FormatSize {
    param([int64]$Bytes)
    if ($Bytes -lt 1024) { return "$Bytes B" }
    if ($Bytes -lt 1MB)  { return ("{0:N1} KB" -f ($Bytes / 1KB)) }
    if ($Bytes -lt 1GB)  { return ("{0:N1} MB" -f ($Bytes / 1MB)) }
    return ("{0:N1} GB" -f ($Bytes / 1GB))
}

function Invoke-DevkitBackups {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Action,

        [Parameter(Position = 1)]
        [string]$Name
    )

    $root = _Devkit-GetBackupRoot
    if (-not (Test-Path $root)) {
        Write-Host "No backups directory at $root" -ForegroundColor DarkGray
        return
    }

    switch ($Action) {
        'list' {
            $entries = Get-ChildItem $root -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
            if (-not $entries) {
                Write-Host "No backups in $root" -ForegroundColor DarkGray
                return
            }
            _Devkit-WriteSection "BACKUPS in $root"
            $rows = foreach ($e in $entries) {
                $size = if ($e.PSIsContainer) { _Devkit-DirectorySize $e.FullName } else { $e.Length }
                [pscustomobject]@{
                    Name          = $e.Name
                    Type          = if ($e.PSIsContainer) { 'Dir' } else { 'File' }
                    Size          = _Devkit-FormatSize $size
                    LastWriteTime = $e.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
                }
            }
            $rows | Format-Table -AutoSize | Out-Host
        }

        'restore' {
            if ([string]::IsNullOrWhiteSpace($Name)) {
                Write-Warning "Usage: devkit backups restore <name>"
                return
            }
            $exact = Join-Path $root $Name
            $match = $null
            if (Test-Path $exact) {
                $match = Get-Item $exact
            } else {
                $candidates = @(Get-ChildItem $root -ErrorAction SilentlyContinue | Where-Object { $_.Name -like "$Name*" })
                if ($candidates.Count -eq 1) {
                    $match = $candidates[0]
                } elseif ($candidates.Count -gt 1) {
                    Write-Warning "Ambiguous prefix '$Name'. Candidates:"
                    foreach ($c in $candidates) { Write-Host "  $($c.Name)" -ForegroundColor DarkGray }
                    return
                }
            }
            if (-not $match) {
                Write-Warning "No backup found matching '$Name'"
                return
            }

            # Infer destination. $mergeIntoClaude marks the claude_<timestamp>
            # snapshot, which is only a SUBSET of ~/.claude - it must be merged
            # in, never delete-and-replaced (that would wipe sessions/projects).
            $dest = $null
            $mergeIntoClaude = $false
            switch -Regex ($match.Name) {
                '^nvim_'                 { $dest = Join-Path $env:LOCALAPPDATA 'nvim'; break }
                '^gitconfig_'            { $dest = Join-Path $env:USERPROFILE '.gitconfig'; break }
                '^gitconfig-profile_.*_(\.gitconfig-.+)$' {
                    $dest = Join-Path $env:USERPROFILE $Matches[1]
                    break
                }
                '^powershell-profile_'   { $dest = $PROFILE; break }
                '^claude-md_'            { $dest = Join-Path $env:USERPROFILE '.claude\CLAUDE.md'; break }
                '^claude-settings_'      { $dest = Join-Path $env:USERPROFILE '.claude\settings.json'; break }
                '^herdr-config_'         { $dest = Join-Path $env:APPDATA 'herdr\config.toml'; break }
                '^claude_' {
                    $dest = Join-Path $env:USERPROFILE '.claude'
                    $mergeIntoClaude = $true
                    break
                }
            }

            if (-not $dest) {
                Write-Warning "Could not infer original location for '$($match.Name)'. Restore manually."
                return
            }

            Write-Host "Restore plan:" -ForegroundColor Cyan
            Write-Host "  Source: $($match.FullName)"
            if ($mergeIntoClaude) {
                Write-Host "  Target: $dest (merge - existing sessions/projects preserved)"
            } else {
                Write-Host "  Target: $dest"
            }
            $confirm = Read-Host "Proceed? (y/N)"
            if ($confirm -notmatch '^[yY]') {
                Write-Host "Cancelled." -ForegroundColor DarkGray
                return
            }

            try {
                if ($mergeIntoClaude) {
                    # Merge the snapshot's contents INTO ~/.claude, overwriting only
                    # the managed items it contains; never remove the target tree.
                    if (-not (Test-Path $dest)) {
                        New-Item -Path $dest -ItemType Directory -Force | Out-Null
                    }
                    foreach ($item in (Get-ChildItem -Path $match.FullName -Force)) {
                        Copy-Item -Path $item.FullName -Destination $dest -Recurse -Force
                    }
                } elseif ($match.PSIsContainer) {
                    if (Test-Path $dest) {
                        Remove-Item -Path $dest -Recurse -Force
                    }
                    Copy-Item -Path $match.FullName -Destination $dest -Recurse -Force
                } else {
                    $parent = Split-Path $dest -Parent
                    if ($parent -and -not (Test-Path $parent)) {
                        New-Item -Path $parent -ItemType Directory -Force | Out-Null
                    }
                    Copy-Item -Path $match.FullName -Destination $dest -Force
                }
                Write-Host "Restored." -ForegroundColor Green
            } catch {
                Write-Host "Restore failed: $_" -ForegroundColor Red
            }
        }

        default {
            Write-Warning "Usage: devkit backups list | restore <name>"
        }
    }
}

#endregion

#region Subcommand: fix

function Invoke-DevkitFix {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Target
    )

    switch ($Target) {
        'terminal-icons' {
            # Inlined copy of Clear-TerminalIconsCache so the runtime CLI has no
            # cross-file dependencies for day-to-day commands.
            $cacheDir = Join-Path $env:APPDATA 'powershell\Community\Terminal-Icons'
            if (-not (Test-Path $cacheDir)) {
                Write-Host "No Terminal-Icons cache directory; nothing to do." -ForegroundColor DarkGray
                return
            }
            $files = Get-ChildItem -Path $cacheDir -Filter 'devblackops_*.xml' -ErrorAction SilentlyContinue
            $removed = 0
            foreach ($f in $files) {
                try {
                    Remove-Item -Path $f.FullName -Force
                    $removed++
                } catch {
                    Write-Warning "Could not remove $($f.Name): $_"
                }
            }
            Write-Host "Purged $removed Terminal-Icons cache file(s). Open a new PowerShell session to verify." -ForegroundColor Green
        }
        default {
            Write-Warning "Usage: devkit fix terminal-icons"
        }
    }
}

#endregion

#region Top-level dispatch

function devkit {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Command = 'help',

        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$Rest
    )

    switch ($Command.ToLower()) {
        'help'    { Show-DevkitHelp @Rest }
        '--help'  { Show-DevkitHelp @Rest }
        '-h'      { Show-DevkitHelp @Rest }
        'version' { Show-DevkitVersion }
        '--version' { Show-DevkitVersion }
        'doctor'  { Invoke-DevkitDoctor }
        'find'    { Find-DevkitEntry @Rest }
        'update'  { Invoke-DevkitUpdate }
        'nvim'    { Invoke-DevkitNvim @Rest }
        'claude'  { Invoke-DevkitClaude @Rest }
        'herdr'   { Invoke-DevkitHerdr @Rest }
        'backups' { Invoke-DevkitBackups @Rest }
        'fix'     { Invoke-DevkitFix @Rest }
        default {
            Write-Warning "Unknown command: $Command"
            Write-Host "  Run 'devkit help' for the list of commands." -ForegroundColor DarkGray
        }
    }
}

#endregion

#region Tab completion

Register-ArgumentCompleter -CommandName devkit -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)

    $elements = $commandAst.CommandElements
    $tokens = @($elements | ForEach-Object { $_.Value })
    # tokens[0] = 'devkit'; tokens[1] = top-level command; tokens[2+] = subcommand args

    $depth = $tokens.Count
    # If wordToComplete is empty, the user just pressed Tab after a space; we're
    # completing position $depth. If non-empty, we're completing position $depth-1.
    $position = if ([string]::IsNullOrEmpty($wordToComplete)) { $depth } else { $depth - 1 }

    $candidates = @()
    switch ($position) {
        1 {
            # Top-level commands
            $candidates = @('help', 'version', 'doctor', 'find', 'update', 'nvim', 'claude', 'herdr', 'backups', 'fix')
        }
        2 {
            switch ($tokens[1].ToLower()) {
                'help'    { $candidates = @('modules', 'aliases', 'keymaps', 'functions', 'git', 'nvim', 'claude', 'herdr', 'env', 'commands') }
                'nvim'    { $candidates = @('refresh') }
                'claude'  { $candidates = @('refresh', '--force') }
                'herdr'   { $candidates = @('refresh') }
                'backups' { $candidates = @('list', 'restore') }
                'fix'     { $candidates = @('terminal-icons') }
            }
        }
        3 {
            if ($tokens[1].ToLower() -eq 'backups' -and $tokens[2].ToLower() -eq 'restore') {
                $backupRoot = Join-Path $env:USERPROFILE '.devkit\backups'
                if (Test-Path $backupRoot) {
                    $candidates = @(Get-ChildItem $backupRoot -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name)
                }
            }
        }
    }

    $candidates | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}

#endregion
