# Spec Tasks

## Tasks

- [x] 1. Set up project structure and PwshSpectreConsole dependency
  - [x] 1.1 Create `configuration/lib/` directory structure
  - [x] 1.2 Create `configuration/templates/` directory
  - [x] 1.3 Add PwshSpectreConsole installation to prerequisites in install.ps1
  - [x] 1.4 Create basic install.ps1 entry point that checks for/installs PwshSpectreConsole
  - [x] 1.5 Verify PwshSpectreConsole loads and displays a test panel

- [x] 2. Build core wizard UI framework
  - [x] 2.1 Create `lib/wizard.ps1` with welcome screen function using Format-SpectrePanel
  - [x] 2.2 Add mode selection function (Fresh Install / Update) using Read-SpectreSelection
  - [x] 2.3 Create wizard navigation flow controller
  - [x] 2.4 Add confirmation and summary display functions using Format-SpectreTable
  - [x] 2.5 Test wizard flow with placeholder steps

- [x] 3. Implement configuration data model and validators
  - [x] 3.1 Create `lib/validators.ps1` with email validation function
  - [x] 3.2 Add directory path validation (exists or offer to create)
  - [x] 3.3 Add non-empty string validation for names
  - [x] 3.4 Create `$DevkitConfig` hashtable structure
  - [x] 3.5 Test validators with valid and invalid inputs

- [x] 4. Implement existing config detection and loading
  - [x] 4.1 Create `lib/config-loader.ps1`
  - [x] 4.2 Add function to parse existing ~/.gitconfig for user.name/email
  - [x] 4.3 Add function to detect devkit markers in PowerShell profile
  - [x] 4.4 Add function to load existing variables.ps1 values
  - [x] 4.5 Test config loader with existing and missing configs

- [x] 5. Build repository locations wizard step
  - [x] 5.1 Add repo locations prompt using Read-SpectreText
  - [x] 5.2 Support multiple locations (add/remove loop)
  - [x] 5.3 Validate paths and offer to create missing directories
  - [x] 5.4 Show current locations in update mode
  - [x] 5.5 Test with various path inputs

- [x] 6. Build Git profile configuration wizard step
  - [x] 6.1 Add default profile prompts (name, email)
  - [x] 6.2 Add "Add another profile?" loop using Read-SpectreConfirm
  - [x] 6.3 Collect directory, name, email for each additional profile
  - [x] 6.4 Preview generated .gitconfig content
  - [x] 6.5 Test with single and multiple profiles

- [x] 7. Build PowerShell modules selection wizard step
  - [x] 7.1 Define available modules with descriptions
  - [x] 7.2 Add multi-select using Read-SpectreMultiSelection
  - [x] 7.3 Show pre-selected defaults in update mode
  - [x] 7.4 Test module selection flow

- [x] 8. Build Oh-My-Posh theme selection wizard step
  - [x] 8.1 Scan for available .omp.json themes in devkit
  - [x] 8.2 Add theme selection using Read-SpectreSelection
  - [x] 8.3 Show current theme as default in update mode
  - [x] 8.4 Test theme selection

- [x] 9. Implement backup system
  - [x] 9.1 Create `lib/backup.ps1`
  - [x] 9.2 Add function to backup file with timestamp suffix
  - [x] 9.3 Create ~/.devkit-backups/ directory management
  - [x] 9.4 Add cleanup function to keep only last 5 backups
  - [x] 9.5 Test backup and restore functionality

- [x] 10. Implement config file generation
  - [x] 10.1 Create `lib/config-generator.ps1`
  - [x] 10.2 Create `templates/gitconfig.template` with placeholders
  - [x] 10.3 Add function to generate .gitconfig from config model
  - [x] 10.4 Add function to generate individual profile .gitconfig files
  - [x] 10.5 Add function to generate variables.ps1
  - [x] 10.6 Add function to update PowerShell profile
  - [x] 10.7 Test generated configs are valid

- [x] 11. Implement installation execution with progress
  - [x] 11.1 Add progress display using Invoke-SpectreCommandWithProgress
  - [x] 11.2 Integrate backup step before modifications
  - [x] 11.3 Integrate config file generation
  - [x] 11.4 Integrate PowerShell module installation
  - [x] 11.5 Add final summary with next steps
  - [x] 11.6 End-to-end test of complete wizard flow

- [x] 12. Final integration and cleanup
  - [x] 12.1 Remove old hardcoded install scripts or mark as deprecated
  - [x] 12.2 Update README with new installation instructions
  - [x] 12.3 Test fresh install on clean environment
  - [x] 12.4 Test update mode on existing installation
  - [x] 12.5 Verify all generated configs work correctly
