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
│   ├── config-generator.ps1 # Git, PowerShell, Neovim, Claude and statusline config generation
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
# Run the installation wizard (requires PowerShell 7+; Admin is NOT required)
. "./configuration/install.ps1"
```

The wizard needs no elevation. Admin is only ever relevant inside the prerequisites
step, for the tools that install machine-wide, and that step asks before doing so.

The wizard will:
1. Install PwshSpectreConsole for rich UI
2. Detect existing configurations
3. Choose the prompt engine (Oh My Posh or Starship) - step 2, before prerequisites
4. Optionally install missing prerequisite tools and Nerd Fonts
5. Prompt for Git identity and directory-based profiles
6. Select PowerShell modules to install
7. Choose the prompt theme: an Oh-My-Posh theme, or a Starship preset (plus the Starship git panel)
8. Offer to install the bundled Neovim configuration
9. Install everything to user space (`~/.devkit/`) — except Neovim, which goes to `$env:LOCALAPPDATA\nvim\`
10. Create backups of existing configs (including a recursive snapshot of any prior nvim/ directory)

### User Space Installation

The installer copies files to `~/.devkit/` making the installation independent of the source repository:

```
~/.devkit/
├── profile.ps1      # PowerShell profile
├── devkit.ps1       # `devkit` CLI (auto-loaded by profile.ps1)
├── variables.ps1    # Env vars (DEVKIT_ROOT, DEVKIT_PROMPT_ENGINE, DEVKIT_OMP_THEME, DEVKIT_STARSHIP_CONFIG, DEVKIT_GIT_PANEL, DEVKIT_REPO_ROOT)
├── themes/          # Oh-My-Posh themes + the devkit-managed starship.toml
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
- Top-level subcommands: `help [topic]`, `version`, `doctor`, `find <keyword>`, `update`, `nvim refresh`, `claude refresh [--force]`, `herdr refresh`, `statusline status|install|refresh|size <mode>|remove`, `prompt status|use <engine>|preset <name>|list|gitpanel <status|on|off>`, `prereqs check|install`, `backups list|restore`, `fix terminal-icons`.
- Uses plain `Write-Host -ForegroundColor` instead of PwshSpectreConsole at runtime so it has zero shell-start cost beyond the dot-source itself.
- Holds a hand-maintained registry (`$script:DevkitRegistry`) describing modules / aliases / PSReadLine keybindings / custom functions / nvim keymaps / **Claude+Herdr assets** / commands. **When you add a new alias, keybinding, custom function, nvim keymap, or Claude/Herdr/statusline asset (agent, command, skill, statusline row) to the profile template, `configuration/nvim/*`, or `configuration/claude/*`, also add a row to the registry** — `devkit help` and `devkit find` are the discovery surface for the user and silently get stale otherwise. Live state (installed modules, env vars, git aliases, backups) is queried at runtime and never duplicated in the registry.
- `devkit doctor` also verifies the Claude/Herdr install landed: `~/.claude/CLAUDE.md`, the Herdr SessionStart hook wired into `~/.claude/settings.json`, `~/.claude/hooks/herdr-agent-state.ps1`, and `%APPDATA%\herdr\config.toml`. Check 6 is engine-aware: for Starship it verifies the binary and that `DEVKIT_STARSHIP_CONFIG` resolves when set, and check 7 skips the engine the user did not pick so it does not nag about a missing `starship`. Check 6b covers the Starship git panel: the config and the profile hook are two halves of one feature and a config with the panel but no hook renders **no branch at all**, so that combination is a FAIL and the reverse is a WARN. Checks 13-14 cover the statusline: the renderer is present **and still carries its UTF-8 BOM**, and `statusLine` is wired with a `-File` path that actually resolves (a stale path copied from another machine is the failure this catches). Check 7 is driven by the prerequisite catalogue when `DEVKIT_REPO_ROOT` resolves (falling back to an inline list otherwise) and now also reports winget availability and whether any Nerd Font is installed. `claude`/`herdr` on PATH are optional (WARN-only) — the devkit configures Herdr but does not install it.
- `devkit update`, `devkit nvim refresh`, `devkit claude refresh`, `devkit herdr refresh`, `devkit prompt gitpanel on|off`, and `devkit statusline *` dot-source from `$env:DEVKIT_REPO_ROOT` (written into `~/.devkit/variables.ps1` by `Save-VariablesPs1`). If the repo moves, those commands print a clear error; everything else still works. `claude refresh` re-runs the installer's `Copy-DevkitClaude*` + `Install-HerdrHookAndSettings` helpers (and skips a drifted `CLAUDE.md` unless `--force`); `herdr refresh` re-runs `Save-HerdrConfig`.
- `devkit backups restore` infers the destination from the backup name. Besides `nvim_/gitconfig_/powershell-profile_`, it handles the Claude/Herdr backups the installer creates: `claude-md_*` → `~/.claude/CLAUDE.md`, `claude-settings_*` → `~/.claude/settings.json`, `herdr-config_*` → `%APPDATA%\herdr\config.toml`, `starship-config_*` → `~/.devkit/themes/starship.toml`, `claude-statusline_*` → `~/.claude/awesome-statusline.ps1`, and the `claude_<timestamp>/` snapshot. The snapshot is **merge-restored** into `~/.claude` (its contents copied in, existing sessions/projects/history left intact) — never delete-and-replaced, because the snapshot is only a subset of `~/.claude`.
- `devkit fix terminal-icons` inlines the cache-purge logic rather than dot-sourcing `backup.ps1`, so day-to-day commands have zero cross-file dependencies.

### Prerequisite Installation

- The wizard's **step 3** can install the external tools the devkit depends on. Opt-in gated, individually selectable, and it installs **immediately inside the step** rather than in `Invoke-Installation`.
- `Get-DevkitPrerequisites` in `lib/validators.ps1` is the catalogue and the single source of truth for winget ids, detection commands, fallback paths and install hints. The wizard step, `Install-Prerequisites`, `devkit prereqs` and `devkit doctor` all read it, so **adding a tool is one row**.
- `devkit.ps1` reaches the catalogue through `_Devkit-TryGetPrereqCatalog`, which dot-sources `validators.ps1` on demand. **Never call it at file scope** - `devkit.ps1` is sourced on every shell start and must stay dependency-free.

### Neovim Configuration (`configuration/nvim/`)

- Source-of-truth template for the user's Neovim setup: `init.lua` + `lua/plugins/` (neo-tree, easy-dotnet)
- Installed to `$env:LOCALAPPDATA\nvim\` (Neovim's standard Windows config path) — **not** under `~/.devkit/`. Symlinks on Windows need Admin/Developer-Mode and `$env:XDG_CONFIG_HOME` is too broad; a direct copy is the least surprising option.
- The first line of `init.lua` carries a `-- devkit-managed` marker. `Get-ExistingNvimConfig` in `config-loader.ps1` uses it to tell the difference between a devkit install and a user-authored config (which gets backed up before being replaced).
- `lazy-lock.json` is intentionally **not** bundled — `lazy.nvim` regenerates it on first launch. Bundling it would create drift every time `:Lazy sync` runs.
- `Copy-DevkitNvimConfig` in `config-generator.ps1` is idempotent: re-running `install.ps1` refreshes the three source files; user-installed plugins under `nvim-data/` are never touched.

## Development Notes

- The wizard installs to user space (`~/.devkit/`) for repo-independent operation
- Existing configs are backed up to `~/.devkit/backups/` with timestamps (nvim trees are backed up as `nvim_<timestamp>/` subdirectories)
- The prompt engine is selected with `$env:DEVKIT_PROMPT_ENGINE`; its config is `$env:DEVKIT_OMP_THEME` or `$env:DEVKIT_STARSHIP_CONFIG`
- The `cws` function uses `$env:DEVKIT_REPOS_PATH` (defaults to `~/repos` if not set)
- Fresh vs Update mode is auto-detected based on existing configuration
- **Terminal-Icons cache self-heal**: the profile template wraps `Import-Module -Name Terminal-Icons` in a try/catch that purges `$env:APPDATA\powershell\Community\Terminal-Icons\devblackops_*.xml` and retries on failure. Do not simplify this back to a bare `Import-Module` — PowerShell upgrades periodically break the cached CLIXML format (symptom: `'Text' is an invalid XmlNodeType`), and the catch block is what stops the error from resurfacing.
- `Clear-TerminalIconsCache` (in `backup.ps1`) runs early in `Invoke-Installation` so the broken cache is cleared on the very first install too, not only via the runtime self-heal.
- **`Save-GitConfig` is merge-preserving, not an overwrite.** It calls `Get-UnmanagedGitConfigSections` first and re-appends every section the devkit does not author under a single `# --- preserved ...` marker. Ownership is keyed on the *full* header, so `[gpg]` is regenerated but `[gpg "ssh"]` is preserved; the owned set is `$script:DevkitGitSections` plus any `[includeIf ...]`. Do not regress this to a plain `Set-Content` of `New-GitConfig` output - it silently destroys git-lfs filters, credential helpers, url rewrites and `safe.directory` entries the user never asked the devkit to manage.
- **`includeIf` is written as `gitdir/i:` and parsed as `gitdir(?:/i)?:`.** `New-GitConfig` emits the case-insensitive form; `Get-ExistingGitConfig` must keep accepting both, or a devkit-written `.gitconfig` re-reads as having zero additional profiles and every re-run drops the `includeIf` blocks while orphaning the `.gitconfig-*` files.
- **The statusline renderer is fetched from upstream, never vendored.** `Install-ClaudeStatusLine` downloads `scripts/awesome-statusline-windows.ps1` from `AwesomeJun/CC-statusline` (MIT) at install time; there is deliberately no copy in this repo, which is also why it is the one installer here with no `-SourceRoot`. Specifics that a future refactor would otherwise break:
  - It is written **UTF-8 with a BOM on purpose**. Do not "simplify" `[System.IO.File]::WriteAllText(..., UTF8Encoding($true))` back to `Set-Content -Encoding UTF8` - Windows PowerShell mis-decodes the block glyphs without it and the bars render as mojibake.
  - `Set-ClaudeStatusLineSetting` reuses the `Install-HerdrHookAndSettings` merge pattern. `statusLine` is a single object, so plain assignment **is** the idempotent replacement (no de-dup loop, unlike `hooks.SessionStart`), and every sibling key survives.
  - **The devkit does not run upstream's `install.ps1`**, on purpose: it would open an interactive size menu inside the wizard (`[Environment]::UserInteractive` is true there), round-trip the whole `settings.json` through a third-party writer, and litter `~/.claude/settings.json.backup-*` outside `~/.devkit/backups/`.
  - `Install-ClaudeStatusLine` **must never throw**. `Invoke-Installation` only aborts the run on a thrown exception, so returning `$false` is what degrades an offline install to a warning. With no renderer on disk it deliberately leaves `statusLine` unwritten rather than pointing Claude Code at a missing file.
  - `Get-AwesomeStatusLineSource` is the **single network seam** and is called by name so `test-statusline.ps1` can shadow it. Do not inline `Invoke-WebRequest` into the caller, or the suite starts needing the network.
  - `Mode Keep` exists so a locally customized renderer is not clobbered; the wizard only offers it when a renderer is already present, and Fresh stays the highlighted default.
  - A full install now writes **two** `claude-settings` backups (herdr step + statusline step), so `-KeepCount 5` covers about 2.5 runs of settings history.
- **External binaries are invoked from exactly four seams.** `Invoke-WingetInstall`, `Invoke-RemoteScriptInstall`, `Invoke-OhMyPoshFontInstall` and `Invoke-StarshipPresetExport` in `config-generator.ps1` are the only places a package manager or vendor binary runs, and their callers reach them **by name** so `test-prereqs.ps1` and `test-prompt-engine.ps1` can shadow them. (`Invoke-StarshipPresetExport` generates config rather than installing anything, and `Get-StarshipPresetList` is its read-only twin, but both run `starship.exe` and follow the same rules.) Inline `& winget` into the caller and the test suite starts installing software. Specifics a future refactor would otherwise break:
  - Each seam goes through `Invoke-NativeCapture`, which locally sets `$ErrorActionPreference = 'Continue'` **and** `$PSNativeCommandUseErrorActionPreference = $false`. `install.ps1` sets `EAP = Stop` script-wide, and on PowerShell 7.4+ a non-zero native exit would otherwise throw, turning "warn and continue" into an aborted wizard. winget returns non-zero for perfectly ordinary cases such as "already installed".
  - **Detection decides success, not exit codes.** After a seam returns, the row is re-detected: present means installed whatever the code, exit 0 but still absent means installed plus `NeedsNewShell`, anything else is a failure.
  - `FallbackPaths` exist because winget does not refresh the calling process's `PATH`. Without them a just-installed tool looks missing and gets re-installed on the next run.
  - **`continue` inside a PowerShell `switch` continues the switch, not the enclosing loop.** The mechanism switch in `Install-Prerequisites` sets `$handled` and the post-switch verification is guarded on it; using `continue` there appends a bogus second "exit unknown" failure to every font install.
  - `Test-CommandAvailable` returns early when `-VersionArgs` is empty. Running the binary bare is not a safe fallback: `glow`, `nvim` and `oh-my-posh` all open an interactive UI with no arguments and hang the caller.
  - `Install-Prerequisites` **never throws** and emits no output of its own, exactly like `Install-RequiredModules`.
  - **Any** Nerd Font satisfies the font row. `Test-NerdFontInstalled` must match both the spelled-out `Nerd Font` form and the bare `NF`/`NFM`/`NFP` suffixes, or every CaskaydiaCove install is missed. A registry hit is only `strong` once the referenced file is confirmed on disk.
  - `Read-SpectreMultiSelection` cannot pre-tick choices, so already-installed tools are excluded from the selector and shown in a table above it. `PreSelect` controls ordering and emphasis, not a tick.
  - Because the step installs immediately, cancelling at Review keeps whatever was installed. The Review summary is phrased in the past tense and the cancel branch says so explicitly.
- **The prompt engine is one choice with two config artifacts.** `$env:DEVKIT_PROMPT_ENGINE` in `variables.ps1` decides which one `profile.ps1` initialises; `devkit prompt use <engine>` rewrites that file to switch. Specifics a future refactor would otherwise break:
  - **The `oh-my-posh` arm is the `switch` *default*, not an explicit `'oh-my-posh'` case.** A `variables.ps1` written before this option existed has no `DEVKIT_PROMPT_ENGINE` line, and the default arm is the only reason those installs keep rendering the prompt they had. `Test-DevkitConfig`, `Invoke-Installation` and `_Devkit-GetPromptEngine` all apply the same fallback, and they must stay in agreement.
  - **The Oh-My-Posh theme is copied even when Starship is the engine**, and `Show-PromptThemeStep` fills `OhMyPoshTheme` from the bundled theme without prompting. Copying a `.omp.json` is free, whereas a `starship.toml` can only be produced by the Starship binary — so `devkit prompt use oh-my-posh` is instant while `use starship` may have to export a preset first. The theme-copy step is therefore only a hard failure when Oh My Posh is the live engine.
  - **The engine step runs BEFORE the prerequisites step**, which is why the step count moved to 12. The prerequisites step is what installs `starship.exe` and then calls `Update-SessionPath`; the theme step asks the binary for `starship preset --list`. Move the engine question after prerequisites and the preset picker is empty exactly when it is needed.
  - `Install-DevkitStarshipConfig` **must never throw**, for the same reason as `Install-ClaudeStatusLine`: `Invoke-Installation` only aborts the run on a thrown exception, so returning `''` is what degrades a starship-less box to a warning. With no config written it deliberately leaves `DEVKIT_STARSHIP_CONFIG` unset rather than pointing `STARSHIP_CONFIG` at a file that is not there — Starship's own default is a working prompt, a bad path is not.
  - `Mode Keep` returns `''` **on purpose**. It means "let Starship find its own `~/.config/starship.toml`", not "failed".
  - `New-VariablesPs1` omits any line whose value is empty. Do not "simplify" it back to always emitting `DEVKIT_STARSHIP_CONFIG` — an empty value there is not the same as an absent line to the profile's `Test-Path` guard.
  - **Nerd Fonts are installed BY oh-my-posh** (`Mechanism = 'omp-font'`, `DependsOn = @('oh-my-posh')`). `Show-PrerequisitesStep` therefore pulls `oh-my-posh` into the install set when the user ticks `nerd-font` without it, and says so. Remove that and a Starship user's font tick is silently dropped by the dependency guard in `Install-Prerequisites`.
  - The step re-tiers the two engine rows around the choice (selected engine becomes `Required`/`PreSelect`, the other `Optional`). `Get-DevkitPrerequisites` returns fresh hashtables per call, so this is local to the step. The unselected engine is **not** hidden — Oh My Posh is still the font installer.
- **The Starship git panel is one feature in two files, and both halves are required.** `starship.toml` disables `git_branch` and renders the branch from four `env_var` modules (`DEVKIT_GIT_CONFLICT/DIRTY/DIVERGED/CLEAN`); `Invoke-Starship-PreCommand` in the profile template sets exactly one of them per prompt. A config with the panel and a shell without the hook shows **no branch at all**, which is why `$env:DEVKIT_GIT_PANEL` gates the hook, `Invoke-Installation` records it from `Test-DevkitStarshipGitPanel` rather than from what the wizard asked for, doctor check 6b fails on the mismatch, and `test-starship-gitpanel.ps1` asserts the two name sets against each other. Specifics a future refactor would otherwise break:
  - **`env_var` modules, not `custom` modules.** Starship's own docs reach for four `custom` modules with mutually exclusive `when` conditions; on Windows each `when` spawns its own shell, so that costs four pwsh launches per prompt against one `git status` here.
  - **`Add-DevkitStarshipGitPanel` REPLACES `[git_branch]` and `[git_status]`, never appends.** TOML rejects a duplicate table outright and Starship then silently falls back to its *default* config, losing the whole preset. The originals are archived inside the block behind `#!devkit-orig!` so `gitpanel off` restores the preset instead of a degraded copy. Restoring re-appends them at the end of the file, so section order changes and only content is comparable.
  - **`Split-StarshipToml` has to track triple-quoted strings.** Every powerline preset writes its top-level format as a `"""` block whose lines start with things like `[](fg:color_aqua)`. A line scan that treats those as section headers truncates the format and the panel edits the wrong text.
  - **`Get-StarshipSectionValue`'s backreference is ``, not ``.** Group 1 is the opening quote, group 2 the value; pointing the backreference at the value matches it against itself, always fails, and silently costs the panel its branch glyph. It looked like it worked.
  - The panel reuses the preset's `bg:` token and branch `symbol`, which is what keeps it from punching a transparent hole through the middle of a powerline prompt.
  - **The panel reuses the preset's `git_branch.format` and `git_status.format`; it must not write its own.** Those formats are where the `on ` before the branch and the `[ ]` around the status live, and `$all_status` is where the category order lives. Imposing replacements silently restyled a prompt the user chose - `nerd-font-symbols` lost both. `Convert-StarshipBranchFormat` makes the preset's branch format renderable by an `env_var` module with two substitutions and nothing else: `$branch` becomes `$env_value`, and an inline style group containing `fg:` becomes `($style)` so the per-state colour on the module can win. A preset that never overrode `git_status.format`/`style` gets **no** key written, so Starship's own default still applies.
  - **The branch `symbol` is copied verbatim - never trimmed, never padded.** The gap before the branch belongs to whichever half the preset owns: presets with their own format put it in the format and leave the symbol bare (`gruvbox-rainbow`: `"$symbol $branch"` with `symbol = ""`), presets inheriting the default format carry it on the symbol (`nerd-font-symbols`: `symbol = " "`). Normalising either one renders two spaces.
  - **A config with no top-level `format` gets one synthesised naming only `$username$hostname$directory<refs>$all`.** Starship's `$all` orders `env_var` nowhere near the git segment, and expanding `$all` in full would freeze the module list at install time. `$all` does not re-render a module the format already names - that is the property this relies on.
  - `Install-DevkitStarshipConfig -Mode Keep` never applies the panel. Keep means the user's own `~/.config/starship.toml`, which the devkit does not own and must not rewrite.
  - Written UTF-8 **without** a BOM: Starship's TOML parser reads the mark as part of the first key. This is the opposite of the statusline renderer's requirement, so do not unify them.
- **`Invoke-StarshipPresetExport` must pass `--force`.** `starship preset -o` refuses to overwrite an existing file and exits 1. Because detection decides success in `Install-DevkitStarshipConfig`, the old config is still on disk afterwards and the export reports as having worked - so before this, every `devkit prompt preset <name>` after the first silently kept the previous preset. `test-prompt-engine.ps1` Test 0 is the guard, and it runs before the file's own stub replaces the seam.
- **`Invoke-Starship-PreCommand` is the only safe place to run code per prompt.** Starship's PowerShell init calls it inside its `prompt` function *after* capturing `$?` and `$LASTEXITCODE` and *before* restoring them, so calling `git` from it cannot corrupt the error indicator. Wrapping `prompt` by hand does: `$?` is read-only and there is no honest way to restore a False. Both the hook and its `Get-DevkitGitDirForPrompt` helper are declared `global:` because `Execute-Step` invokes its `-action` in a child scope and Starship's dynamic module resolves the hook through the global `function:` drive.
- **The classifier costs one `git status` per prompt (~80ms here) and nothing outside a repository (~6ms).** It walks up for `.git` in PowerShell rather than spawning `git rev-parse`, which would roughly double that. `behind` reflects only the last `git fetch` - Starship does not fetch and neither does this, so a branch behind origin renders green until something fetches.
- **The installer has no Admin gate, and must not regain one.** `install.ps1` used to hard-exit 1 for any non-elevated shell, which made `devkit update` unusable from an ordinary prompt: `Invoke-DevkitUpdate` calls the installer bare and never passed `-SkipAdminCheck`. The gate was also unanswerable where it stood - whether a run needs elevation depends on which prerequisites get ticked in **step 3**, and nothing before that step knows. Everything else the wizard writes is user-space (`~/.devkit`, `$PROFILE`, `~/.gitconfig`, `~/.claude`, `%LOCALAPPDATA%\nvim`), and `Install-RequiredModules` has always passed `-Scope CurrentUser`, so the old "needs Admin to install PowerShell modules" warning in `devkit update` was simply false. `-SkipAdminCheck` survives as a declared no-op so existing invocations do not start erroring. Specifics a future refactor would otherwise break:
  - **`Elevation` on each catalogue row is classification only.** It drives the warning and nothing else - no `--scope user`, no changed winget arguments - so a tool that installs today cannot start failing because of it. The value tracks where the package actually lands, which the row's own `FallbackPaths` already record: Program Files means `machine`, `%LOCALAPPDATA%` / `%USERPROFILE%` means `user`.
  - **The notice warns and proceeds; it does not refuse.** winget raises its own elevation prompt per package, so an unelevated machine-wide install still works, it just asks. Declining takes the existing "nothing selected" path rather than aborting the wizard.
  - `Test-DevkitElevated` and `Get-ElevationSplit` in `lib/validators.ps1` are the single implementation, shared by the wizard step and `devkit prereqs install`, so the two surfaces cannot drift. `Get-ElevationSplit` **drops an unknown key rather than defaulting it to `user`** - guessing would suppress exactly the warning the user needed.
- **`Invoke-Installation` in `lib/wizard.ps1` is the installer. `Invoke-ConfigGeneration` in `lib/config-generator.ps1` is DEAD CODE that looks exactly like it.** Nothing calls `Invoke-ConfigGeneration` - it is referenced only by its own definition and the export comment - yet it carries a near-identical numbered task list, so a search for "where does the installer resolve the Starship config" lands on the wrong one. This already cost one real bug: the git-panel wiring was added to the dead copy, so a full install wrote the panel into `starship.toml` but omitted `DEVKIT_GIT_PANEL` from `variables.ps1`, and the prompt rendered **no branch at all** until `devkit prompt gitpanel off` + `on` repaired it. Before editing installer behaviour, confirm the call chain: `install.ps1` -> `Start-Wizard` -> `Show-InstallationStep` -> `Invoke-Installation`.
- **Anything the installer writes into `variables.ps1` must be threaded through BOTH of `Invoke-Installation`'s tasks.** Task 7 (`Resolving Starship configuration`) calls `Install-DevkitStarshipConfig` and task 9 (`Generating variables.ps1`) calls `Save-VariablesPs1`; they are separate scriptblocks sharing a `$results` hashtable, so a new switch has to be added in two places or the halves disagree silently. `-GitPanel` defaults to `$true` on the installer and `$false` on the variables writer, which is why forgetting it produced a config with the panel and a shell without the hook rather than an obvious error. `$results.StarshipGitPanel` is recorded from `Test-DevkitStarshipGitPanel` against the file on disk, never from what the wizard asked for. `test-starship-gitpanel.ps1` Test 9b walks the AST of `Invoke-Installation` and fails if either call site drops the parameter.
- **`$script:WizardTotalSteps` in `wizard.ps1` is the single place the step count lives.** `Show-StepHeader` defaults to it and every call site passes it, so changing the count is a one-line change. The per-step `-StepNumber` literals still have to be bumped by hand, as adding the prompt-engine step at position 2 required.
- **`$displayConfig` in `Start-Wizard` is a hand-copied projection**, not the whole config. A new top-level config block will not reach `Show-ConfigurationSummary` unless it is added there, and the omission fails silently.
- **`$PROFILE` is NOT sandboxable by redirecting `$env:USERPROFILE`.** It is an automatic variable PowerShell resolves at startup from the Documents folder, which on a machine with OneDrive Known Folder Move is `C:\Users\<u>\OneDrive\Documents\PowerShell\`. Redirecting `USERPROFILE`/`APPDATA`/`LOCALAPPDATA` - the pattern every sandboxed test uses - does not contain it, so `Backup-AllConfigFiles` and `Update-PowerShellProfile` write the developer's **real** profile and home directory while everything else in the test is safely in a temp dir. Any test that dot-sources `backup.ps1` or `config-generator.ps1` must also set `$global:PROFILE` into the sandbox. `test-backup.ps1` Test 6 is the regression guard: it hashes the real profile before the redirect and fails if the run touched it, or if the real `~/.devkit/backups` gained entries. This bit for real - `test-backup.ps1` used to snapshot the developer's entire `~/.claude` into their real `~/.devkit/backups` on every run.
- **`configuration/test-wizard.ps1` is an interactive harness, not an automated test.** It calls `Start-Wizard` and blocks on the first prompt. It appears to "pass" only when `PwshSpectreConsole` is absent, because `Import-Module` fails and the script falls through to exit 0. Do not count it as regression coverage.
- **`Copy-DevkitClaudeMd` refuses to overwrite a drifted `~/.claude/CLAUDE.md`** unless `-Force` is passed (`Test-DevkitClaudeMdDrift` does the comparison). That file is where personal global instructions accumulate between installs, so the wizard asks and `devkit claude refresh` skips it with a hint. Keep the repo copy in sync when instructions are added on a machine.
