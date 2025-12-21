# Spec Requirements Document

> Spec: Interactive CLI Installation Wizard
> Created: 2025-12-20
> Status: Planning

## Overview

Create a rich, interactive console-based installation wizard using PwshSpectreConsole that guides users through configuring their development environment. The wizard replaces hardcoded template files with dynamically generated configurations for Git and PowerShell based on user input.

## User Stories

### First-Time Setup

As a developer setting up a new machine, I want an interactive wizard that guides me through configuration choices, so that I can quickly set up my dev environment without manually editing config files.

When I run the installer:
1. I see a welcome screen with devkit branding
2. I'm asked whether I want fresh install or update mode
3. I configure my repo locations (where I store code)
4. I set up Git profiles (name, email, directory mappings)
5. I select which PowerShell modules to install
6. I choose or preview Oh-My-Posh themes
7. The wizard generates all config files and installs modules
8. I see a summary of what was configured

### Updating Existing Configuration

As a returning user, I want to re-run the wizard to update my configuration, so that I can add new Git profiles or change settings without starting from scratch.

When I run in update mode:
1. The wizard detects my existing configuration
2. Current values are shown as defaults
3. I can modify specific sections without re-entering everything
4. Only changed files are updated
5. Previous config is backed up before changes

### Multi-Profile Git User

As a developer working with multiple clients, I want to configure directory-based Git profiles, so that commits in different repo directories use the correct email identity.

The wizard should:
1. Let me add multiple Git profiles
2. Ask for directory path, name, and email for each
3. Preview the generated `.gitconfig` with `includeIf` directives
4. Validate that directories exist or offer to create them

## Spec Scope

1. **PwshSpectreConsole Integration** - Install and use PwshSpectreConsole module for rich console UI with prompts, selections, and progress indicators
2. **Git Profile Configuration** - Collect name, email, and directory paths for multi-profile Git setup with `includeIf` support
3. **Repository Location Setup** - Configure where user stores repos (support multiple locations like C:/repos, D:/repos)
4. **PowerShell Module Selection** - Interactive selection of which modules to install (z, posh-git, Terminal-Icons, PSReadLine)
5. **Oh-My-Posh Theme Selection** - Browse and preview available themes, select preferred theme
6. **Config File Generation** - Generate `.gitconfig`, PowerShell profile, and variables.ps1 based on user input
7. **Install/Update Mode Detection** - Detect existing configuration and offer update mode with current values as defaults

## Out of Scope

- GUI/Windows Forms interface (console only)
- Azure DevOps module configuration (separate installer)
- Cross-platform support (Windows only for now)
- Theme customization editor (just selection)
- Automatic updates/self-updating installer

## Expected Deliverable

1. Running `./install.ps1` launches an interactive wizard with Spectre.Console UI elements (prompts, selections, progress bars)
2. User can configure Git profiles, repo locations, PowerShell modules, and Oh-My-Posh theme through guided prompts
3. Configuration files are generated dynamically based on user input (no hardcoded paths or values)
4. Existing users can re-run wizard to update configuration with current values shown as defaults
