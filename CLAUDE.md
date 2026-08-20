# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a developer toolkit (devkit) providing configuration setups for PowerShell, Git, and Azure DevOps pipeline automation on Windows. The project consists of an interactive installation wizard and configuration files that enhance the development environment.

## Repository Structure

```
configuration/
├── install.ps1              # Main installation wizard (unified installer)
├── lib/                     # Wizard library modules
│   ├── wizard.ps1           # UI components and flow controller
│   ├── config-generator.ps1 # Git, PowerShell, and Neovim config generation
│   ├── config-loader.ps1    # Existing config detection
│   ├── backup.ps1           # Backup management + Terminal-Icons cache reset
│   └── validators.ps1       # Input validation + tool detection
├── powershell/
│   ├── Microsoft.PowerShell_profile.ps1  # Profile template
│   ├── devkit.ps1                        # In-shell `devkit` CLI (help/doctor/find/update/etc.)
│   └── .mytheme-new.omp.json             # Oh-My-Posh theme
└── nvim/                    # Neovim config template (init.lua + lua/plugins/)
    ├── init.lua
    └── lua/plugins/
        ├── neo-tree.lua
        └── easy-dotnet.lua
```

## Installation

The devkit uses a single unified installer with an interactive wizard UI:

```powershell
# Run the installation wizard (requires PowerShell 7+ and Admin privileges)
. "./configuration/install.ps1"
```

The wizard will:
1. Install PwshSpectreConsole for rich UI
2. Detect existing configurations
3. Prompt for Git identity and directory-based profiles
4. Select PowerShell modules to install
5. Choose Oh-My-Posh theme
6. Offer to install the bundled Neovim configuration
7. Install everything to user space (`~/.devkit/`) — except Neovim, which goes to `$env:LOCALAPPDATA\nvim\`
8. Create backups of existing configs (including a recursive snapshot of any prior nvim/ directory)

### User Space Installation

The installer copies files to `~/.devkit/` making the installation independent of the source repository:

```
~/.devkit/
├── profile.ps1      # PowerShell profile
├── devkit.ps1       # `devkit` CLI (auto-loaded by profile.ps1)
├── variables.ps1    # Environment variables (DEVKIT_ROOT, DEVKIT_OMP_THEME, DEVKIT_REPO_ROOT)
├── themes/          # Oh-My-Posh themes
└── backups/         # Config backups
```

## Key Components

### PowerShell Profile (`Microsoft.PowerShell_profile.ps1`)

- Uses `Execute-Step` wrapper for timed initialization of modules
- Imports: `z`, `posh-git`, `Terminal-Icons`, `PSReadLine`, Chocolatey profile
- PSReadLine keybindings: `Ctrl+Shift+b` (dotnet build), `Ctrl+Shift+r` (clear console)
- Utility functions: `Move-PhotosToMonthlyFolders`, `Move-PhotosToYearFolders`, `Get-MailDomainInfo`

### Git Configuration

- Multi-profile support via `includeIf` for directory-based email switching
- Pre-configured aliases: `yesterday`, `recently`, `standup`, `lg`, `ls`, `la`, `ll`, `amend`
- Auto-setup for push and rebase behaviors

### Devkit CLI (`configuration/powershell/devkit.ps1`)

- Auto-loaded by `Microsoft.PowerShell_profile.ps1` from `~/.devkit/devkit.ps1`. Exposes the `devkit` function plus a `Register-ArgumentCompleter` for tab completion.
- Top-level subcommands: `help [topic]`, `version`, `doctor`, `find <keyword>`, `update`, `nvim refresh`, `claude refresh [--force]`, `herdr refresh`, `backups list|restore`, `fix terminal-icons`.
- Uses plain `Write-Host -ForegroundColor` instead of PwshSpectreConsole at runtime so it has zero shell-start cost beyond the dot-source itself.
- Holds a hand-maintained registry (`$script:DevkitRegistry`) describing modules / aliases / PSReadLine keybindings / custom functions / nvim keymaps / **Claude+Herdr assets** / commands. **When you add a new alias, keybinding, custom function, nvim keymap, or Claude/Herdr asset (agent, command, skill) to the profile template, `configuration/nvim/*`, or `configuration/claude/*`, also add a row to the registry** — `devkit help` and `devkit find` are the discovery surface for the user and silently get stale otherwise. Live state (installed modules, env vars, git aliases, backups) is queried at runtime and never duplicated in the registry.
- `devkit doctor` also verifies the Claude/Herdr install landed: `~/.claude/CLAUDE.md`, the Herdr SessionStart hook wired into `~/.claude/settings.json`, `~/.claude/hooks/herdr-agent-state.ps1`, and `%APPDATA%\herdr\config.toml`. `claude`/`herdr` on PATH are optional (WARN-only) — the devkit configures Herdr but does not install it.
- `devkit update`, `devkit nvim refresh`, `devkit claude refresh`, and `devkit herdr refresh` dot-source from `$env:DEVKIT_REPO_ROOT` (written into `~/.devkit/variables.ps1` by `Save-VariablesPs1`). If the repo moves, those commands print a clear error; everything else still works. `claude refresh` re-runs the installer's `Copy-DevkitClaude*` + `Install-HerdrHookAndSettings` helpers (and skips a drifted `CLAUDE.md` unless `--force`); `herdr refresh` re-runs `Save-HerdrConfig`.
- `devkit backups restore` infers the destination from the backup name. Besides `nvim_/gitconfig_/powershell-profile_`, it handles the Claude/Herdr backups the installer creates: `claude-md_*` → `~/.claude/CLAUDE.md`, `claude-settings_*` → `~/.claude/settings.json`, `herdr-config_*` → `%APPDATA%\herdr\config.toml`, and the `claude_<timestamp>/` snapshot. The snapshot is **merge-restored** into `~/.claude` (its contents copied in, existing sessions/projects/history left intact) — never delete-and-replaced, because the snapshot is only a subset of `~/.claude`.
- `devkit fix terminal-icons` inlines the cache-purge logic rather than dot-sourcing `backup.ps1`, so day-to-day commands have zero cross-file dependencies.

### Neovim Configuration (`configuration/nvim/`)

- Source-of-truth template for the user's Neovim setup: `init.lua` + `lua/plugins/` (neo-tree, easy-dotnet)
- Installed to `$env:LOCALAPPDATA\nvim\` (Neovim's standard Windows config path) — **not** under `~/.devkit/`. Symlinks on Windows need Admin/Developer-Mode and `$env:XDG_CONFIG_HOME` is too broad; a direct copy is the least surprising option.
- The first line of `init.lua` carries a `-- devkit-managed` marker. `Get-ExistingNvimConfig` in `config-loader.ps1` uses it to tell the difference between a devkit install and a user-authored config (which gets backed up before being replaced).
- `lazy-lock.json` is intentionally **not** bundled — `lazy.nvim` regenerates it on first launch. Bundling it would create drift every time `:Lazy sync` runs.
- `Copy-DevkitNvimConfig` in `config-generator.ps1` is idempotent: re-running `install.ps1` refreshes the three source files; user-installed plugins under `nvim-data/` are never touched.

## Development Notes

- The wizard installs to user space (`~/.devkit/`) for repo-independent operation
- Existing configs are backed up to `~/.devkit/backups/` with timestamps (nvim trees are backed up as `nvim_<timestamp>/` subdirectories)
- Oh-My-Posh theme is configured via `$env:DEVKIT_OMP_THEME` environment variable
- The `cws` function uses `$env:DEVKIT_REPOS_PATH` (defaults to `~/repos` if not set)
- Fresh vs Update mode is auto-detected based on existing configuration
- **Terminal-Icons cache self-heal**: the profile template wraps `Import-Module -Name Terminal-Icons` in a try/catch that purges `$env:APPDATA\powershell\Community\Terminal-Icons\devblackops_*.xml` and retries on failure. Do not simplify this back to a bare `Import-Module` — PowerShell upgrades periodically break the cached CLIXML format (symptom: `'Text' is an invalid XmlNodeType`), and the catch block is what stops the error from resurfacing.
- `Clear-TerminalIconsCache` (in `backup.ps1`) runs early in `Invoke-Installation` so the broken cache is cleared on the very first install too, not only via the runtime self-heal.
- **`Save-GitConfig` is merge-preserving, not an overwrite.** It calls `Get-UnmanagedGitConfigSections` first and re-appends every section the devkit does not author under a single `# --- preserved ...` marker. Ownership is keyed on the *full* header, so `[gpg]` is regenerated but `[gpg "ssh"]` is preserved; the owned set is `$script:DevkitGitSections` plus any `[includeIf ...]`. Do not regress this to a plain `Set-Content` of `New-GitConfig` output - it silently destroys git-lfs filters, credential helpers, url rewrites and `safe.directory` entries the user never asked the devkit to manage.
- **`includeIf` is written as `gitdir/i:` and parsed as `gitdir(?:/i)?:`.** `New-GitConfig` emits the case-insensitive form; `Get-ExistingGitConfig` must keep accepting both, or a devkit-written `.gitconfig` re-reads as having zero additional profiles and every re-run drops the `includeIf` blocks while orphaning the `.gitconfig-*` files.
- **`Copy-DevkitClaudeMd` refuses to overwrite a drifted `~/.claude/CLAUDE.md`** unless `-Force` is passed (`Test-DevkitClaudeMdDrift` does the comparison). That file is where personal global instructions accumulate between installs, so the wizard asks and `devkit claude refresh` skips it with a hint. Keep the repo copy in sync when instructions are added on a machine.
