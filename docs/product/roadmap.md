# Product Roadmap

## Phase 0: Already Completed

The following features have been implemented:

- [x] PowerShell profile with Execute-Step wrapper for timed initialization
- [x] Automated module installation (z, posh-git, Terminal-Icons, PSReadLine)
- [x] Custom Oh-My-Posh theme (.mytheme-new.omp.json)
- [x] PSReadLine configuration with history-based suggestions
- [x] Productivity keybindings (Ctrl+Shift+b for dotnet build)
- [x] Git configuration with multi-profile support via includeIf
- [x] Interactive Git configuration installer
- [x] Comprehensive Git aliases (yesterday, standup, recently, lg, etc.)
- [x] Azure DevOps Pipeline Automation module (v0.1.0)
- [x] Solution analysis with project type detection
- [x] Azure dependency detection (WebApp, Functions, KeyVault, SQL, Storage, ServiceBus)
- [x] YAML pipeline generation with build, test, and deployment stages
- [x] Azure resource provisioning functions
- [x] Utility functions (Move-PhotosToMonthlyFolders, Get-MailDomainInfo)
- [x] Removed deprecated multi-tenant Azure CLI functions from PowerShell profile (DEC-004)
- [x] Interactive CLI Installation Wizard (PwshSpectreConsole) - see spec `2025-12-20-interactive-cli-wizard`
  - Fresh install / Update mode detection
  - Repository locations multi-select with path validation
  - Default Git profile + directory-specific `includeIf` profiles (case-insensitive)
  - Git commit message editor selection (VS Code, Neovim, Vim, Notepad++, Nano, custom)
  - PowerShell module multi-select (z, posh-git, Terminal-Icons, PSReadLine, PSFzf, CompletionPredictor)
  - Oh-My-Posh theme selection (devkit + built-in themes) with quoted path handling
  - Review step with summary tables and confirmation
- [x] User-space installation architecture (`~/.devkit/`) decoupled from source repo
- [x] Automatic timestamped backup system with 5-backup retention
- [x] Input validators (email, directory paths, non-empty names)
- [x] README cleanup - reduced emoji use, accurate Azure DevOps module docs (spec `2025-12-20-readme-cleanup`)

## Phase 1: Rollback and Restore

**Goal:** Give users a safety net when an install or update misbehaves
**Success Criteria:** A single command restores the most recent backup of Git and PowerShell config files

### Features

- [ ] `Restore-DevkitBackup` command - Revert `.gitconfig`, profile, and `variables.ps1` from `~/.devkit/backups/` `S`
- [ ] Wizard entry point for restore - List available backups, select one, apply `S`

### Dependencies

- None

## Phase 2: Project Templates

**Goal:** Provide .NET project templates optimized for Azure DevOps and Terraform
**Success Criteria:** Users can scaffold new projects with pre-configured CI/CD

### Features

- [ ] .NET Web API template with Azure DevOps pipeline `L`
- [ ] .NET Function App template with deployment configuration `L`
- [ ] Terraform module templates for common Azure resources `L`
- [ ] Shared Terraform code library `M`
- [ ] Template installation and management commands `M`

### Dependencies

- None

## Phase 3: Community & Polish

**Goal:** Prepare for open source community adoption
**Success Criteria:** Clear documentation, contribution guidelines, and consistent quality

### Features

- [ ] Contribution guidelines (CONTRIBUTING.md) `S`
- [ ] Issue and PR templates `XS`
- [ ] Comprehensive usage documentation `M`
- [ ] Video tutorials or GIFs demonstrating features `L`
- [ ] Automated testing for installation scripts `L`

### Dependencies

- Phase 2 completion

## Phase 4: Advanced Features

**Goal:** Enterprise-ready features and advanced automation
**Success Criteria:** Support for complex multi-repo and multi-environment scenarios

### Features

- [ ] Multi-repo workspace management `L`
- [ ] Environment-specific configuration profiles `M`
- [ ] Pipeline template library with customization `L`
- [ ] Integration with Azure Key Vault for secrets `M`
- [ ] Automated dependency updates `M`

### Dependencies

- Phase 3 completion

## Effort Scale

- XS: 1 day
- S: 2-3 days
- M: 1 week
- L: 2 weeks
- XL: 3+ weeks
