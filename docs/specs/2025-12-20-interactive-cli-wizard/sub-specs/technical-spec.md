# Technical Specification

This is the technical specification for the spec detailed in @docs/specs/2025-12-20-interactive-cli-wizard/spec.md

## Technical Requirements

### UI Components (PwshSpectreConsole)

- **Welcome Panel** - Branded header with devkit name and version using `Format-SpectrePanel`
- **Mode Selection** - Radio button choice between "Fresh Install" and "Update Existing" using `Read-SpectreSelection`
- **Text Prompts** - Input fields for name, email, paths using `Read-SpectreText` with validation
- **Multi-Select** - Checkbox list for PowerShell modules using `Read-SpectreMultiSelection`
- **Single Select** - Dropdown/list for theme selection using `Read-SpectreSelection`
- **Confirmation** - Yes/No prompts using `Read-SpectreConfirm`
- **Progress** - Installation progress using `Invoke-SpectreCommandWithProgress`
- **Summary Table** - Final configuration summary using `Format-SpectreTable`

### Configuration Data Model

```powershell
$DevkitConfig = @{
    Mode = "Fresh" | "Update"
    RepoLocations = @("C:/repos", "D:/repos")  # Array of paths
    Git = @{
        DefaultProfile = @{
            Name = "John Doe"
            Email = "john@example.com"
        }
        AdditionalProfiles = @(
            @{
                Name = "John Doe"
                Email = "john@work.com"
                Directory = "C:/repos/work/"
            }
        )
    }
    PowerShell = @{
        Modules = @("z", "posh-git", "Terminal-Icons", "PSReadLine")
        OhMyPoshTheme = ".mytheme-new.omp.json"
    }
}
```

### File Generation

- **Git Config** - Generate `~/.gitconfig` with `includeIf` directives for each profile
- **Profile Configs** - Generate individual `.gitconfig` files in profile directories
- **PowerShell Variables** - Generate `variables.ps1` with `$env:DEVKIT_*` variables
- **Profile Loader** - Update/create PowerShell profile to source devkit config

### Existing Config Detection

- Check for `~/.gitconfig` and parse existing user.name/user.email
- Check for `$PROFILE` and look for devkit markers
- Check for `variables.ps1` in devkit directory
- Present detected values as defaults in prompts

### Validation Rules

- **Email** - Must match email regex pattern
- **Directory Paths** - Must be valid Windows paths, offer to create if missing
- **Git Name** - Non-empty string
- **Repo Locations** - At least one location required

### Backup Strategy

- Before modifying any file, create `.backup-YYYYMMDD-HHMMSS` copy
- Store backups in `~/.devkit-backups/` directory
- Keep last 5 backups, auto-cleanup older ones

### Wizard Flow

```
1. Welcome Screen
   └── Display branded panel

2. Mode Selection
   ├── Fresh Install → Clear existing config
   └── Update Mode → Load existing values

3. Repository Locations
   ├── Show current locations (if update mode)
   ├── Add/remove locations
   └── Validate paths exist

4. Git Configuration
   ├── Default Profile (name, email)
   ├── Add Additional Profiles loop
   │   ├── Directory path
   │   ├── Name (default: same as default)
   │   └── Email
   └── Preview generated .gitconfig

5. PowerShell Modules
   ├── Multi-select from available modules
   └── Show descriptions for each

6. Oh-My-Posh Theme
   ├── List available themes
   ├── Preview option (optional)
   └── Select theme

7. Confirmation
   ├── Show summary table
   └── Confirm to proceed

8. Installation
   ├── Progress bar for each step
   ├── Backup existing files
   ├── Generate new configs
   ├── Install modules
   └── Apply theme

9. Summary
   ├── Show what was configured
   └── Next steps / restart terminal
```

## External Dependencies

- **PwshSpectreConsole** - PowerShell module wrapping Spectre.Console
  - Install: `Install-Module -Name PwshSpectreConsole -Scope CurrentUser`
  - Source: https://pwshspectreconsole.com/
  - **Justification:** Provides rich console UI components (prompts, selections, tables, progress bars) that are not available in native PowerShell. The module is actively maintained and well-documented.

## File Structure

```
configuration/
├── install.ps1              # Main installer entry point
├── lib/
│   ├── wizard.ps1           # Wizard UI logic
│   ├── config-loader.ps1    # Load/parse existing config
│   ├── config-generator.ps1 # Generate config files
│   ├── validators.ps1       # Input validation functions
│   └── backup.ps1           # Backup management
├── templates/
│   ├── gitconfig.template   # Git config template with placeholders
│   └── profile.template     # PowerShell profile template
└── powershell/
    └── (existing files)
```
