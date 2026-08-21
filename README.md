# Devkit by Usual Expat

## What

This repository provides a **pragmatic, versatile, and visually appealing** configuration setup for developers. It includes:  

- **Git** – Streamlined config with useful aliases and signing setup  
- **PowerShell** – Custom profiles, productivity scripts, and automation  
- **Windows Terminal** – Beautiful themes, shortcuts, and profiles  
- **Claude Code & Herdr** – Optionally install Claude agents, skills, commands, and global `CLAUDE.md`, plus the herdr terminal-multiplexer configuration

Everything is designed to be **easy to set up, powerful, and visually refined**.

![assets/windows-terminal-screenshot.png](assets/windows-terminal-screenshot.png)

**Note**: this is very much work in progress, and the configuration provided is rather custom to my needs, so might need some edits to make sure it suits your needs. Sharing early as the terminal configuration was requested by a friend. The plan is to make the installation and management of configs easy and user friendly, making sure that setting up a new box for development is automated and personalised to the user.

---

## How

### Prerequisites

**The wizard can install most of these for you.** Step 2 detects what is missing and offers to install it with [winget](https://learn.microsoft.com/windows/package-manager/winget/) (or the tool's own installer); each tool is individually selectable and nothing is installed without an explicit tick. Install them yourself first if you prefer, or if `winget` is unavailable.

The **Auto** column shows what the wizard can install: `yes` for winget and font rows, `opt-in` for Claude Code (which runs a script downloaded from the internet, so it is never pre-selected), and `n/a` for anything that is not a package.

**Required**

| Tool | Why | Install | Auto |
| --- | --- | --- | --- |
| PowerShell 7+ | The wizard and generated profile require it (`#Requires -Version 7.0`) | `winget install --id Microsoft.PowerShell -e` | yes |
| Git | Git config generation + aliases | `winget install --id Git.Git -e` | yes |
| Oh My Posh | The profile calls `oh-my-posh` by name to render the prompt | `winget install --id JanDeDobbeleer.OhMyPosh -e` | yes |
| A Nerd Font | Glyphs/icons in the prompt, Terminal-Icons, and the Claude statusline bars | `oh-my-posh font install meslo --headless` (after installing Oh My Posh), then set it as your terminal font | yes |

> `PwshSpectreConsole` (the wizard UI) is installed from the PowerShell Gallery, but the installer **asks first**. It cannot use its own UI to ask, so this is a plain y/N prompt before the wizard starts; declining exits cleanly with the manual command. If PSGallery is not already trusted the prompt says so, because continuing marks it Trusted, a machine-wide setting that is not reverted afterwards. The selected PowerShell modules (`z`, `posh-git`, `Terminal-Icons`, `PSReadLine`) install automatically with no `PATH` change.

> **Any Nerd Font satisfies the requirement.** The prompt, Terminal-Icons and the statusline need the glyph ranges, not one specific family. If you already run CaskaydiaCove NF, FiraCode NF or similar, the wizard detects it and does not offer to install another. When none is found you can select several fonts to install in one go.

**Optional (only if you enable the matching feature)**

| Tool | Needed for | Install | Auto |
| --- | --- | --- | --- |
| Neovim | The bundled Neovim config, or Neovim as the Git editor | `winget install --id Neovim.Neovim -e` | yes |
| Node.js | General dev workflows (and npm-based Claude Code install) | `winget install --id OpenJS.NodeJS.LTS -e` | yes |
| Claude Code CLI | Using the Claude agents/skills/commands the wizard installs into `~/.claude` | Native (recommended): `irm https://claude.ai/install.ps1 \| iex` (installs to `%USERPROFILE%\.local\bin`) &nbsp;·&nbsp; or npm: `npm install -g @anthropic-ai/claude-code` | opt-in |
| Herdr | Using the herdr terminal-multiplexer configuration/skill | Windows: `winget install --id Herdr.Herdr.Preview -e` (installs to `%LOCALAPPDATA%\Programs\Herdr\bin`) &nbsp;·&nbsp; macOS/Linux: `brew install herdr` or `curl -fsSL https://herdr.dev/install.sh \| sh` | yes |
| glow | Rendering markdown in the terminal (READMEs, `CLAUDE.md`, notes) | `winget install --id charmbracelet.glow -e` | yes |
| Internet access at install time | Fetching the Awesome Statusline renderer from GitHub (the statusline area only) | Nothing to install; if offline, the step is skipped with a warning | n/a |

> Herdr publishes a preview channel only (`Herdr.Herdr.Preview`); there is no stable winget id. That matches the devkit's own `config.toml`, which pins `channel = "preview"`.

> The wizard installs the Claude assets to `~/.claude` and writes the herdr config to `%APPDATA%\herdr` **regardless** of whether the Claude Code / Herdr binaries are present — but you need the respective CLI installed to actually use them.

### Installation & Setup

1. **Clone this repo**

   ```powershell
   git clone https://github.com/mgpeter/usualexpat-devkit.git
   cd usualexpat-devkit
   ```

2. **Run the Interactive Installation Wizard**

   Run as admin in PowerShell 7+:

   ```powershell
   . "./configuration/install.ps1"
   ```

   The wizard will guide you through:
   - **Prerequisite Tools** - Optionally install anything missing (Git, Oh My Posh, Neovim, Node.js, glow, PowerShell 7, Herdr) with winget, plus one or more Nerd Fonts. Each tool is individually selectable, nothing installs without an explicit tick, and this step runs first so the later steps can see the new tools
   - **Repository Locations** - Select where you store your code
   - **Git Configuration** - Set up your name, email, and directory-specific profiles
   - **Git Editor** - Pick your commit message editor (VS Code, Neovim, Vim, Notepad++, Nano, or custom)
   - **PowerShell Modules** - Choose which modules to install (z, posh-git, Terminal-Icons, etc.)
   - **Oh-My-Posh Theme** - Select your terminal theme
   - **Neovim Configuration** - Optionally install the bundled Neovim config
   - **Claude Code & Herdr** - Optionally install Claude agents, skills, commands, and `CLAUDE.md` into `~/.claude`, plus the herdr configuration (each area is individually toggleable)

   The wizard automatically:
   - Backs up your existing configuration files
   - Refreshes `$env:PATH` in-process after installing a prerequisite, so the Git-editor list and theme scan see it without a restart
   - Generates `.gitconfig` with your settings, carrying over any section the devkit does not author (git-lfs filters, credential helpers, `[gpg "ssh"]`, url rewrites, `safe.directory`) and listing what it kept
   - Creates `~/.gitignore_global` if it is missing, so `core.excludesfile` points at a real file
   - Creates directory-specific Git profiles (e.g., different email for work repos)
   - Leaves an edited `~/.claude/CLAUDE.md` alone unless you confirm the replacement
   - Updates your PowerShell profile
   - Installs selected modules
   - Installs the selected Claude Code assets and merges the herdr `SessionStart` hook into `~/.claude/settings.json` without touching your other settings
   - Discovers the installed PowerShell 7 (`pwsh`) path and writes it into `%APPDATA%\herdr\config.toml`

3. **Restart your terminal and enjoy!**

### A note on PATH

**The devkit installer does not modify your `PATH`.** It writes configuration to `~/.devkit`, `~/.claude`, and `%APPDATA%\herdr` — all of which are loaded by your PowerShell profile (`$PROFILE`) or read directly by the tools, so none of them require `PATH` entries. PowerShell modules install into the module path, not `PATH`.

What *does* need to be on `PATH` is the [prerequisite tools](#prerequisites) — and each tool's own installer adds itself:

| Tool | Location its installer adds to `PATH` |
| --- | --- |
| `pwsh` | `%LOCALAPPDATA%\Microsoft\WindowsApps` (Store/winget alias) |
| `oh-my-posh` | `%LOCALAPPDATA%\Programs\oh-my-posh\bin` |
| `git` | `C:\Program Files\Git\cmd` |
| `nvim` | `C:\Program Files\Neovim\bin` |
| `claude` | `%USERPROFILE%\.local\bin` (native install) |
| `herdr` | `%LOCALAPPDATA%\Programs\Herdr\bin` |
| `node` / `npm` | `C:\Program Files\nodejs` |
| `glow` | `%LOCALAPPDATA%\Microsoft\WinGet\Links` (winget shim) |

Because the generated PowerShell profile calls `oh-my-posh` (and, if you set it as the Git editor, `nvim`) **by name**, those need to be on `PATH` before your first new session.

When the wizard installs a prerequisite itself it refreshes `$env:PATH` from the registry in-process, so the later steps (the Git-editor list, the Oh My Posh theme scan) see the new tool immediately. You do not need to restart the wizard. Two things that refresh cannot fix, and which the step warns about:

- **A newly installed font** is not a `PATH` matter at all. Restart the terminal *and* select the font in your terminal profile.
- **App Execution Alias shims** under `%LOCALAPPDATA%\Microsoft\WindowsApps` may still need a new shell.

If you install the prerequisites by hand instead, open a fresh terminal before running the wizard.

> Herdr, by design, pins its shell to the **App Execution Alias** `pwsh` shim (`%LOCALAPPDATA%\Microsoft\WindowsApps\pwsh.exe`) rather than a version-stamped path, so it survives PowerShell updates. The wizard detects this automatically.

### The `devkit` CLI

After installation, an in-shell `devkit` command is auto-loaded by your PowerShell profile (from `~/.devkit/devkit.ps1`). It's the discovery and management surface for everything the devkit installs — inventory, health checks, and refresh/restore helpers — and it uses plain `Write-Host` (no heavy modules) so it adds no shell-start cost. Tab completion is wired for every subcommand.

| Command | What it does |
| --- | --- |
| `devkit help [topic]` | Full inventory, or one section: `modules`, `aliases`, `keymaps`, `functions`, `git`, `nvim`, `claude`, `herdr`, `statusline`, `env`, `commands` |
| `devkit version` | Devkit version + install paths |
| `devkit doctor` | Health checks: profile wiring, modules, tools on `PATH`, nvim/OMP config, **the Claude/Herdr install** (`~/.claude/CLAUDE.md`, the herdr `SessionStart` hook, the hook script, and `%APPDATA%\herdr\config.toml`), **and the statusline** (renderer present with its UTF-8 BOM, `statusLine` wired and its script path resolving) |
| `devkit find <keyword>` | Search the whole inventory — modules, aliases, keybindings, functions, git aliases, nvim keymaps, bundled Claude agents/commands/skills, and the statusline |
| `devkit update` | Re-run the installation wizard |
| `devkit nvim refresh` | Re-copy the bundled Neovim config |
| `devkit claude refresh [--force]` | Re-copy the bundled Claude assets into `~/.claude` (agents, commands, skills, `CLAUDE.md`, herdr hook). A `CLAUDE.md` that differs from the bundled copy is left alone; `--force` replaces it (after a backup) |
| `devkit herdr refresh` | Re-write `%APPDATA%\herdr\config.toml` |
| `devkit statusline status` | Show the statusline state: renderer path, whether it is on disk, wired, its size, and whether the wired path resolves |
| `devkit statusline install` / `refresh` | Download the Awesome Statusline renderer from upstream and wire it into `settings.json`. Add `--size <mode>`; without it, a refresh keeps the size you already run |
| `devkit statusline size <mode>` | Change the size (`xsmall`, `small`, `medium`, `large`, `xlarge`) without downloading anything |
| `devkit statusline remove` | Unwire the statusline and delete the renderer (both backed up first). `--keep-script` leaves the renderer on disk |
| `devkit prereqs check` | Report which prerequisite tools, Nerd Font and winget are present, with the install command for anything missing |
| `devkit prereqs install [name...]` | Install missing prerequisites. `--all` widens the default set, `--yes` skips the confirmation, `--dry-run` prints the commands without running them, `--font <name>` (repeatable) picks the Nerd Fonts |
| `devkit backups list` | List timestamped backups in `~/.devkit/backups/` |
| `devkit backups restore <name>` | Restore a backup; the destination is inferred from the name (nvim, gitconfig, PowerShell profile, `CLAUDE.md`, `settings.json`, the statusline renderer, herdr `config.toml`, or a `~/.claude` snapshot merged in non-destructively) |
| `devkit fix terminal-icons` | Purge a corrupt Terminal-Icons icon cache |

> `devkit help` shows a live ✓/✗ next to each Claude/Herdr asset so you can see at a glance what is installed. The `refresh` commands and `backups restore` read the repo path from `$env:DEVKIT_REPO_ROOT` (recorded at install time); if the repo has moved, they print a clear error and everything else keeps working.

#### Claude Code Statusline

The wizard can install [Awesome Statusline](https://github.com/AwesomeJun/CC-statusline) (`AwesomeJun/CC-statusline`, MIT) — a status line for Claude Code showing the model, git state, cwd, cost, and gradient bars for context use and the 5-hour / 7-day rate limits.

It is **third-party code that is not bundled in this repo**. The wizard downloads a fresh copy from upstream at install time and writes it to `~/.claude/awesome-statusline.ps1`, then wires `statusLine` into `~/.claude/settings.json` — every other setting in that file (model, env, plugins, your existing hooks) is preserved. If a renderer is already present, the wizard offers to keep it instead of overwriting; either way the current file is backed up to `~/.devkit/backups/` first.

Five sizes are available — `xsmall` and `small` render two lines, `medium` four, `large` and `xlarge` five (the larger modes add cost, duration, and the rate-limit bars). The wizard defaults to whichever size you already run, or `small` on a fresh machine.

```powershell
devkit statusline status          # what is installed and wired
devkit statusline refresh         # re-download upstream, keep the current size
devkit statusline size large      # resize, no download
devkit statusline remove          # unwire and delete (--keep-script keeps the file)
```

The renderer needs no Node, bun, or jq — it is native PowerShell reading Claude Code's JSON from stdin. Installing offline is not fatal: the step is skipped with a warning, and `$env:DEVKIT_STATUSLINE_SOURCE` can point at a local copy if GitHub is unreachable.

### PowerShell Features

The DevKit includes a powerful set of PowerShell features to enhance your development workflow:

#### Visual Enhancements

- **Oh My Posh** integration with a modern, informative prompt
- **Terminal Icons** for better file type visualization
- **Syntax highlighting** for better code readability
- **Auto-suggestions** for command completion

#### Productivity Tools

- **Directory Navigation**
  - `z` command for quick directory jumping
  - Enhanced `cd` with directory history
  - Directory stack management

- **Git Integration**
  - `posh-git` for enhanced git status and branch information
  - Git aliases for common operations
  - Branch management shortcuts

- **Command History**
  - Enhanced history search with `Ctrl+R`
  - History-based suggestions
  - Better history navigation

#### Custom Aliases

- `yesterday` - Show commits from yesterday
- `recently` - Show commits from the last 3 days
- `standup` - Show commits since last standup
- `lg` - Enhanced git log with graph view
- `ls` - Pretty git log with decorations
- `la` - All branches git log
- `ll` - Detailed git log with changes
- `amend` - Quick amend last commit

#### Configuration Management

- **Profile System**
  - Modular profile structure
  - Easy customization
  - Automatic module loading

- **Environment Variables**
  - Centralized variable management
  - Profile-specific settings
  - Easy path management

#### Search & Navigation

- **Fuzzy Search**
  - Quick file finding
  - Directory navigation
  - Command history search

- **Directory Bookmarks**
  - Save frequently used directories
  - Quick navigation
  - Persistent bookmarks

#### Security Features

- **Execution Policy Management**
- **Secure Credential Storage**
- **Profile Integrity Checks**

#### Module Management

- **Automatic Module Installation**
- **Version Management**
- **Dependency Resolution**

### PowerShell Modules

The DevKit uses several powerful PowerShell modules to enhance your development experience. Here's a detailed overview of each module and how to use them:

#### z - Directory Jumper

- **Source**: [GitHub - rupa/z](https://github.com/rupa/z)
- **Purpose**: Quick directory navigation using frequency and recency
- **Usage**:

  ```powershell
  z <directory>     # Jump to directory
  z -l             # List all directories
  z -t             # List directories by frequency
  z -x             # Remove directory from database
  ```

#### Terminal Icons - File Type Icons

- **Source**: [PowerShell Gallery - Terminal Icons](https://www.powershellgallery.com/packages/Terminal-Icons)
- **Purpose**: Adds file and folder icons to your terminal
- **Usage**:

  ```powershell
  Get-ChildItem    # Icons will be displayed automatically
  Set-TerminalIconsTheme -Theme <theme-name>  # Change icon theme
  ```

#### posh-git - Git Integration

- **Source**: [GitHub - dahlbyk/posh-git](https://github.com/dahlbyk/posh-git)
- **Purpose**: Enhanced Git status and branch information
- **Features**:
  - Branch status indicators
  - File status indicators
  - Git command auto-completion
- **Usage**:

  ```powershell
  git status      # Shows enhanced status with indicators
  git checkout    # Shows branch suggestions
  ```

#### PSReadLine - Command Line Editor

- **Source**: [GitHub - PowerShell/PSReadLine](https://github.com/PowerShell/PSReadLine)
- **Purpose**: Enhanced command-line editing experience
- **Features**:
  - Syntax highlighting
  - Better history search
  - Improved tab completion
- **Usage**:

  ```powershell
  Ctrl+R          # Search command history
  Ctrl+Space      # Show completion menu
  Ctrl+Shift+Space # Show completion menu with descriptions
  ```

#### Oh My Posh - Prompt Customization

- **Source**: [GitHub - JanDeDobbeleer/oh-my-posh](https://github.com/JanDeDobbeleer/oh-my-posh)
- **Purpose**: Beautiful and informative terminal prompts
- **Features**:
  - Git status integration
  - Environment information
  - Custom themes
- **Usage**:

  ```powershell
  oh-my-posh init pwsh --config <theme-path> | Invoke-Expression
  ```

#### PSFzf - Fuzzy Finder

- **Source**: [GitHub - kelleyma49/PSFzf](https://github.com/kelleyma49/PSFzf)
- **Purpose**: Fuzzy file and command finding
- **Usage**:

  ```powershell
  Ctrl+T           # Fuzzy file finder
  Ctrl+R           # Fuzzy command history
  Alt+C            # Fuzzy directory navigation
  ```

#### PSFzf - Directory Navigation

- **Source**: [PowerShell Gallery - PSFzf](https://www.powershellgallery.com/packages/PSFzf)
- **Purpose**: Enhanced directory navigation with fuzzy finding
- **Usage**:

  ```powershell
  Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
  ```

#### PSFzf - Git Status

- **Source**: [PowerShell Gallery - PSFzf](https://www.powershellgallery.com/packages/PSFzf)
- **Purpose**: Enhanced git status with fuzzy finding
- **Usage**:

  ```powershell
  git status | Fzf | Out-String | Invoke-Expression
  ```

#### CredentialManager - Credential Management

- **Source**: [PowerShell Gallery - CredentialManager](https://www.powershellgallery.com/packages/CredentialManager)
- **Purpose**: Secure credential storage and retrieval
- **Usage**:

  ```powershell
  Add-Credential -Target "git:https://github.com" -UserName "username" -Password "password"
  Get-Credential -Target "git:https://github.com"
  ```

#### Module Management

All modules are automatically installed during the DevKit setup. To manually update modules:

```powershell
Update-Module -Name <module-name> -Force
```

To see all installed modules and their versions:

```powershell
Get-Module -ListAvailable | Where-Object { $_.Name -in @('z', 'Terminal-Icons', 'posh-git', 'PSReadLine', 'PSFzf', 'CredentialManager') }
```

#### Customization

Each module can be customized through its configuration file or environment variables. Check the respective module's documentation for detailed customization options.

---

## Who

This kit is for **developers, DevOps engineers, and power users** who want:

- A **polished** and **efficient** development environment
- Quick but **flexible** setup for Git, PowerShell, and Windows Terminal
- A **beautiful** CLI experience without hassle

Whether you're a **beginner looking for a strong starting point** or a **seasoned developer** looking to streamline your workflow, this kit will help you get up and running fast.

## Status

- ✔️ Initial git and powershell configs **[DONE]**

  - Powershell configuration including useful modules and **oh-my-posh**
  - Multi-account setup for git

- ✔️ Automated install scripts **[DONE]**

  - ✔️ automated installation of powershell modules
  - ✔️ automated installation of git configuration with interactive setup

- ✔️ Azure DevOps Pipeline Automation module **[DONE]**

  - ✔️ Solution analysis and project type detection
  - ✔️ Azure dependency detection
  - ✔️ YAML pipeline generation

- ✔️ Interactive CLI Installation Wizard **[DONE]**

  - ✔️ Rich console UI with PwshSpectreConsole
  - ✔️ Repository location configuration
  - ✔️ Git profile setup (default + directory-specific profiles)
  - ✔️ PowerShell module selection
  - ✔️ Oh-My-Posh theme selection
  - ✔️ Automatic backup of existing configs
  - ✔️ Update mode for existing installations

- ✔️ Claude Code & Herdr integration **[DONE]**

  - ✔️ Install Claude agents, skills, commands, and global `CLAUDE.md` into `~/.claude` (each area toggleable)
  - ✔️ Idempotent merge of the herdr `SessionStart` hook into `~/.claude/settings.json`
  - ✔️ Auto-discovery of the installed `pwsh` path for `%APPDATA%\herdr\config.toml`

- ✔️ In-shell `devkit` CLI **[DONE]**

  - ✔️ Inventory + search (`help`, `find`) over modules, aliases, keybindings, functions, nvim keymaps, and Claude/Herdr assets
  - ✔️ Health checks (`doctor`) covering the PowerShell, Neovim, and Claude/Herdr installs
  - ✔️ Refresh helpers (`nvim`/`claude`/`herdr refresh`) and name-inferred backup restore
