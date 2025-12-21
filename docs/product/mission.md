# Product Mission

## Pitch

Devkit by Usual Expat is a Windows developer toolkit that helps developers, DevOps engineers, and power users set up a polished, efficient development environment in minutes by providing automated configuration for PowerShell, Git, and Azure DevOps pipelines.

## Users

### Primary Customers

- **Windows Developers**: Software engineers working on Windows who want a beautiful, productive terminal experience without hours of manual configuration
- **DevOps Engineers**: Engineers who need to quickly generate Azure DevOps pipelines for .NET projects and provision Azure resources
- **Power Users**: Tech-savvy professionals who frequently set up new development machines and want consistency across environments

### User Personas

**Alex the Senior Developer** (30-45 years old)
- **Role:** Senior Software Engineer / Tech Lead
- **Context:** Works on multiple .NET projects across different clients, frequently switches between repositories with different Git email requirements
- **Pain Points:** Spending hours configuring each new dev machine, inconsistent terminal experience across projects, manual pipeline YAML creation
- **Goals:** One-command dev environment setup, beautiful terminal with useful information at a glance, automated CI/CD pipeline generation

**Jordan the DevOps Engineer** (25-40 years old)
- **Role:** DevOps Engineer / Platform Engineer
- **Context:** Responsible for setting up CI/CD pipelines for multiple teams, manages Azure resources across environments
- **Pain Points:** Repetitive pipeline configuration, manually detecting project dependencies, inconsistent build configurations across projects
- **Goals:** Auto-detect project types and generate appropriate pipelines, provision Azure resources based on project needs, standardize deployment patterns

**Sam the Contractor** (28-45 years old)
- **Role:** Freelance Developer / Consultant
- **Context:** Works with multiple clients, each with their own Git identity requirements, frequently onboards to new codebases
- **Pain Points:** Managing multiple Git identities, setting up environment from scratch for each client, inconsistent tooling
- **Goals:** Directory-based Git profile switching, quick environment setup, portable configuration that works across client machines

## The Problem

### Manual Dev Environment Setup is Tedious

Setting up a new Windows development machine requires installing multiple PowerShell modules, configuring themes, setting up Git with proper aliases and identity management, and customizing terminal behavior. This process takes hours and results in inconsistent configurations across machines.

**Our Solution:** Automated installation scripts that install required modules, configure profiles, and set up themes in minutes with a single command.

### Azure DevOps Pipeline Configuration is Repetitive

Every .NET project requires manually creating YAML pipeline definitions, detecting project types, identifying test projects, and configuring deployment stages. This repetitive work is error-prone and time-consuming.

**Our Solution:** Intelligent solution analysis that auto-detects project types, test frameworks, and Azure dependencies, then generates comprehensive pipeline YAML with build, test, and deployment stages.

### Git Identity Management is Cumbersome

Developers working across multiple organizations need different Git email addresses for different repositories. Managing this manually leads to commits with wrong identities and violated compliance requirements.

**Our Solution:** Directory-based Git profile switching using `includeIf` patterns, automatically applying the correct identity based on repository location.

## Differentiators

### Unified Automation-First Approach

Unlike scattered scripts and manual configurations, Devkit provides a cohesive, well-documented toolkit where each component is designed to work together. The installation process is automated and repeatable, making it easy to achieve consistent environments across machines.

### Beautiful Terminal Experience Out of the Box

Unlike default PowerShell configurations, Devkit includes a carefully crafted Oh-My-Posh theme, Terminal Icons, and PSReadLine configuration that provides a modern, informative terminal experience without requiring users to understand the intricacies of prompt customization.

### Intelligent Azure DevOps Integration

Unlike generic pipeline templates, Devkit analyzes your .NET solution structure, detects project types (Web Apps, Functions, Libraries), identifies test frameworks, and recognizes Azure dependencies to generate tailored pipeline configurations that match your actual project needs.

## Key Features

### Core Features

- **Automated Module Installation:** One-command setup of essential PowerShell modules (z, posh-git, Terminal-Icons, PSReadLine) with proper configuration
- **Custom Oh-My-Posh Theme:** Pre-configured theme with Git status, execution time, and environment information
- **Git Multi-Profile Support:** Directory-based email switching for seamless identity management across different organizations
- **Comprehensive Git Aliases:** Productivity aliases like `yesterday`, `standup`, `recently` for quick commit history views

### Azure DevOps Features

- **Solution Analysis:** Auto-detect .NET solution structure, project types, and framework versions
- **Dependency Detection:** Identify Azure service dependencies (Web Apps, Functions, Key Vault, SQL, Storage, Service Bus)
- **Pipeline Generation:** Generate multi-stage YAML pipelines with build, test, and deployment stages
- **Resource Provisioning:** Automatically create Azure resources based on detected project dependencies

### Developer Experience Features

- **Timed Initialization:** `Execute-Step` wrapper shows module load times for performance visibility
- **Quick Navigation:** `z` directory jumper for fast navigation to frequently used directories
- **Command Suggestions:** PSReadLine history-based suggestions with intuitive keybindings
- **Productivity Keybindings:** `Ctrl+Shift+b` for quick dotnet build, customizable shortcuts
