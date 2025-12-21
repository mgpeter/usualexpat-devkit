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
│   ├── config-generator.ps1 # Git and PowerShell config generation
│   ├── config-loader.ps1    # Existing config detection
│   ├── backup.ps1           # Backup management
│   └── validators.ps1       # Input validation
├── powershell/
│   ├── Microsoft.PowerShell_profile.ps1  # Profile template
│   └── .mytheme-new.omp.json             # Oh-My-Posh theme
├── git/                     # (empty - configs generated dynamically)
azure-devops/
├── install.ps1              # Azure module installer
├── AzDevOpsPipelineAutomation/
│   ├── AzDevOpsPipelineAutomation.psm1   # Main PowerShell module
│   └── AzDevOpsPipelineAutomation.psd1   # Module manifest
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
6. Install everything to user space (`~/.devkit/`)
7. Create backups of existing configs

### User Space Installation

The installer copies files to `~/.devkit/` making the installation independent of the source repository:

```
~/.devkit/
├── profile.ps1      # PowerShell profile
├── variables.ps1    # Environment variables
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

### Azure DevOps Pipeline Automation Module

Key exported functions:
- `Initialize-AzDevOpsPipeline` - Configure org/project/PAT
- `Get-SolutionAnalysis` - Analyze .sln files for project types and Azure dependencies
- `New-PipelineDefinition` - Generate YAML pipeline definitions
- `Set-AzDevOpsPipeline` - Create pipelines via Azure DevOps REST API
- `Set-AzureResources` - Provision Azure resources based on detected dependencies

The module auto-detects: WebApps, FunctionApps, KeyVault, SqlDatabase, StorageAccount, ServiceBus from project references.

## Development Notes

- The wizard installs to user space (`~/.devkit/`) for repo-independent operation
- Existing configs are backed up to `~/.devkit/backups/` with timestamps
- Oh-My-Posh theme is configured via `$env:DEVKIT_OMP_THEME` environment variable
- The `cws` function uses `$env:DEVKIT_REPOS_PATH` (defaults to `~/repos` if not set)
- Fresh vs Update mode is auto-detected based on existing configuration
