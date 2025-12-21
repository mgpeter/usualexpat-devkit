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

## Phase 1: Current Development

**Goal:** Clean up codebase and add Windows Terminal support
**Success Criteria:** Clean profile without deprecated features, Windows Terminal configuration included

### Features

- [ ] Remove deprecated multi-tenant Azure CLI functions - Approach doesn't work well in practice `S`
- [ ] Add Windows Terminal configuration - Theme and profile settings `M`
- [ ] Update README to reflect current feature set `XS`

### Dependencies

- None

## Phase 2: Interactive Experience

**Goal:** Improve installation experience with interactive prompts
**Success Criteria:** Users can configure their environment through guided prompts

### Features

- [ ] Interactive PowerShell installer - Guided module selection and configuration `M`
- [ ] Interactive Git configuration wizard - Step-by-step profile setup `M`
- [ ] Configuration validation - Verify successful installation `S`
- [ ] Rollback capability - Undo changes if installation fails `M`

### Dependencies

- Phase 1 completion

## Phase 3: Project Templates

**Goal:** Provide .NET project templates optimized for Azure DevOps and Terraform
**Success Criteria:** Users can scaffold new projects with pre-configured CI/CD

### Features

- [ ] .NET Web API template with Azure DevOps pipeline `L`
- [ ] .NET Function App template with deployment configuration `L`
- [ ] Terraform module templates for common Azure resources `L`
- [ ] Shared Terraform code library `M`
- [ ] Template installation and management commands `M`

### Dependencies

- Phase 1 completion

## Phase 4: Community & Polish

**Goal:** Prepare for open source community adoption
**Success Criteria:** Clear documentation, contribution guidelines, and consistent quality

### Features

- [ ] Contribution guidelines (CONTRIBUTING.md) `S`
- [ ] Issue and PR templates `XS`
- [ ] Comprehensive usage documentation `M`
- [ ] Video tutorials or GIFs demonstrating features `L`
- [ ] Automated testing for installation scripts `L`

### Dependencies

- Phase 2 and 3 completion

## Phase 5: Advanced Features

**Goal:** Enterprise-ready features and advanced automation
**Success Criteria:** Support for complex multi-repo and multi-environment scenarios

### Features

- [ ] Multi-repo workspace management `L`
- [ ] Environment-specific configuration profiles `M`
- [ ] Pipeline template library with customization `L`
- [ ] Integration with Azure Key Vault for secrets `M`
- [ ] Automated dependency updates `M`

### Dependencies

- Phase 4 completion

## Effort Scale

- XS: 1 day
- S: 2-3 days
- M: 1 week
- L: 2 weeks
- XL: 3+ weeks
