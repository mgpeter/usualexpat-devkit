#Requires -Version 7.0
#Requires -Modules PwshSpectreConsole
<#
.SYNOPSIS
    Devkit Installation Wizard UI Components

.DESCRIPTION
    Contains all wizard UI functions using PwshSpectreConsole for the
    interactive installation experience.
#>

# Wizard state
$script:WizardState = @{
    Mode = $null  # "Fresh" or "Update"
    CurrentStep = 0
    TotalSteps = 7
    Config = @{
        RepoLocations = @()
        Git = @{
            DefaultProfile = @{ Name = ""; Email = "" }
            AdditionalProfiles = @()
        }
        PowerShell = @{
            Modules = @()
            OhMyPoshTheme = ""
        }
    }
}

#region Welcome Screen

function Show-WelcomeScreen {
    <#
    .SYNOPSIS
        Displays the branded welcome screen
    #>
    param(
        [string]$Version = "1.0.0"
    )

    Clear-Host

    $welcomeText = @"
Welcome to the Devkit Installation Wizard!

This wizard will help you configure:
  - Git profiles (name, email, directory mappings)
  - Repository locations
  - PowerShell modules
  - Oh-My-Posh theme

Let's get your development environment set up!
"@

    $welcomeText | Format-SpectrePanel -Title "[blue]Devkit by Usual Expat v$Version[/]" -Border Rounded -Color Blue

    Write-Host ""
}

#endregion

#region Mode Selection

function Get-InstallationMode {
    <#
    .SYNOPSIS
        Prompts user to select Fresh Install or Update mode
    .OUTPUTS
        String: "Fresh" or "Update"
    #>
    param(
        [bool]$ExistingConfigDetected = $false
    )

    $title = "Select installation mode:"

    if ($ExistingConfigDetected) {
        Write-SpectreHost "[yellow]Existing configuration detected![/]"
        Write-Host ""
    }

    $choices = @(
        "Fresh Install - Start with a clean configuration"
        "Update Existing - Modify your current configuration"
    )

    $selection = Read-SpectreSelection -Title $title -Choices $choices -Color Blue

    if ($selection -match "Fresh") {
        return "Fresh"
    } else {
        return "Update"
    }
}

#endregion

#region Navigation

function Show-StepHeader {
    <#
    .SYNOPSIS
        Shows the current step header with progress
    #>
    param(
        [Parameter(Mandatory)]
        [int]$StepNumber,

        [Parameter(Mandatory)]
        [string]$StepTitle,

        [int]$TotalSteps = 7
    )

    # Use escaped brackets for Spectre markup - [[ and ]] render as literal [ and ]
    $header = "[blue][[$StepNumber/$TotalSteps]][/] [bold]$StepTitle[/]"

    Write-Host ""
    Write-SpectreHost $header
    Write-SpectreHost "[dim]$("-" * 50)[/]"
    Write-Host ""
}

function Get-Confirmation {
    <#
    .SYNOPSIS
        Asks for yes/no confirmation
    .OUTPUTS
        Boolean
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Question,

        [bool]$DefaultYes = $true
    )

    return Read-SpectreConfirm -Prompt $Question -DefaultAnswer ($DefaultYes ? "y" : "n")
}

#endregion

#region Repository Locations Step

function Get-RepoLocations {
    <#
    .SYNOPSIS
        Collects repository locations from the user using multi-select
    .PARAMETER ExistingLocations
        Array of existing locations to show as defaults
    .OUTPUTS
        Array of directory paths
    #>
    param(
        [string[]]$ExistingLocations = @()
    )

    $locations = [System.Collections.ArrayList]@()
    $addNewOption = "(+) Add new location..."

    # Build choices list - detected locations + add new option
    $choices = [System.Collections.ArrayList]@()
    foreach ($loc in $ExistingLocations) {
        $choices.Add($loc) | Out-Null
    }
    $choices.Add($addNewOption) | Out-Null

    # Multi-select with detected locations pre-selected
    if ($ExistingLocations.Count -gt 0) {
        Write-SpectreHost "[cyan]Select which repository locations to keep:[/]"
        Write-SpectreHost "[dim]Use Space to toggle, Enter to confirm[/]"
        Write-Host ""

        $selected = Read-SpectreMultiSelection `
            -Title "Repository Locations" `
            -Choices $choices `
            -AllowEmpty

        # Process selections
        foreach ($item in $selected) {
            if ($item -eq $addNewOption) {
                # User wants to add new location(s)
                $locations = Add-NewRepoLocations -ExistingLocations $locations
            } else {
                # Normalize path (remove trailing backslash for consistency)
                $normalizedPath = $item.TrimEnd('\')
                $locations.Add($normalizedPath) | Out-Null
            }
        }
    } else {
        # No existing locations - go straight to adding
        Write-SpectreHost "[cyan]No repository locations detected. Let's add some.[/]"
        $locations = Add-NewRepoLocations -ExistingLocations $locations
    }

    # If no locations selected, require at least one
    while ($locations.Count -eq 0) {
        Write-Host ""
        Write-SpectreHost "[red]At least one repository location is required.[/]"
        $locations = Add-NewRepoLocations -ExistingLocations $locations
    }

    # Show final list
    Write-Host ""
    Write-SpectreHost "[green]Repository locations configured:[/]"
    foreach ($loc in $locations) {
        Write-Host "  - $loc"
    }

    return $locations.ToArray()
}

function Add-NewRepoLocations {
    <#
    .SYNOPSIS
        Prompts user to add new repository locations
    .PARAMETER ExistingLocations
        ArrayList of already selected locations
    .OUTPUTS
        Updated ArrayList with new locations
    #>
    param(
        [System.Collections.ArrayList]$ExistingLocations = $null
    )

    # Ensure we have an ArrayList
    if ($null -eq $ExistingLocations) {
        $locations = [System.Collections.ArrayList]::new()
    } else {
        $locations = [System.Collections.ArrayList]::new($ExistingLocations)
    }
    $addMore = $true

    while ($addMore) {
        Write-Host ""
        $path = Read-SpectreText -Prompt "Enter repository path (e.g., C:\repos)" -AllowEmpty

        if ([string]::IsNullOrWhiteSpace($path)) {
            break
        }

        # Validate path format
        $validation = Test-DirectoryPath -Path $path
        if (-not $validation.IsValid) {
            Write-SpectreHost "[red]Invalid path format. Use Windows path format (e.g., C:\repos)[/]"
            continue
        }

        # Check if path exists
        if (-not $validation.Exists) {
            $create = Read-SpectreConfirm -Prompt "Directory doesn't exist. Create it?" -DefaultAnswer "y"
            if ($create) {
                try {
                    New-Item -Path $validation.NormalizedPath -ItemType Directory -Force | Out-Null
                    Write-SpectreHost "[green]Created: $($validation.NormalizedPath)[/]"
                } catch {
                    Write-SpectreHost "[red]Failed to create directory: $_[/]"
                    continue
                }
            } else {
                continue
            }
        }

        # Add to list (avoid duplicates)
        $normalizedPath = $validation.NormalizedPath.TrimEnd('\')
        if ($locations -notcontains $normalizedPath) {
            $locations.Add($normalizedPath) | Out-Null
            Write-SpectreHost "[green]Added: $normalizedPath[/]"
        } else {
            Write-SpectreHost "[yellow]Location already in list.[/]"
        }

        Write-Host ""
        $addMore = Read-SpectreConfirm -Prompt "Add another location?" -DefaultAnswer "n"
    }

    # Return as ArrayList to preserve type
    return ,$locations
}

function Show-RepoLocationsStep {
    <#
    .SYNOPSIS
        Displays the repository locations wizard step
    .PARAMETER Config
        Current configuration with existing locations
    .OUTPUTS
        Updated configuration
    #>
    param(
        [hashtable]$Config
    )

    Show-StepHeader -StepNumber 2 -StepTitle "Repository Locations" -TotalSteps 7

    Write-SpectreHost "Where do you store your code repositories?"
    Write-SpectreHost "[dim]These paths will be used for Git profile directory matching.[/]"
    Write-Host ""

    $existingLocations = @()
    if ($Config.RepoLocations -and $Config.RepoLocations.Count -gt 0) {
        $existingLocations = $Config.RepoLocations
    }

    $locations = Get-RepoLocations -ExistingLocations $existingLocations
    $Config.RepoLocations = $locations

    return $Config
}

#endregion

#region Git Profile Configuration Step

function Get-GitDefaultProfile {
    <#
    .SYNOPSIS
        Prompts for default Git profile (name and email)
    .PARAMETER ExistingProfile
        Existing profile to show as defaults
    .OUTPUTS
        Hashtable with Name and Email
    #>
    param(
        [hashtable]$ExistingProfile = @{ Name = ""; Email = "" }
    )

    $profile = @{
        Name = ""
        Email = ""
    }

    # Show existing values if present
    if ($ExistingProfile.Name -or $ExistingProfile.Email) {
        Write-SpectreHost "[yellow]Detected existing Git configuration:[/]"
        if ($ExistingProfile.Name) { Write-Host "  Name: $($ExistingProfile.Name)" }
        if ($ExistingProfile.Email) { Write-Host "  Email: $($ExistingProfile.Email)" }
        Write-Host ""
    }

    # Prompt for name
    $defaultName = $ExistingProfile.Name
    if ($defaultName) {
        $profile.Name = Read-SpectreText -Prompt "Git user name" -DefaultAnswer $defaultName
    } else {
        do {
            $profile.Name = Read-SpectreText -Prompt "Git user name"
            if ([string]::IsNullOrWhiteSpace($profile.Name)) {
                Write-SpectreHost "[red]Name is required.[/]"
            }
        } while ([string]::IsNullOrWhiteSpace($profile.Name))
    }

    # Prompt for email
    $defaultEmail = $ExistingProfile.Email
    if ($defaultEmail) {
        do {
            $profile.Email = Read-SpectreText -Prompt "Git email" -DefaultAnswer $defaultEmail
            if (-not (Test-EmailAddress -Email $profile.Email)) {
                Write-SpectreHost "[red]Please enter a valid email address.[/]"
            }
        } while (-not (Test-EmailAddress -Email $profile.Email))
    } else {
        do {
            $profile.Email = Read-SpectreText -Prompt "Git email"
            if (-not (Test-EmailAddress -Email $profile.Email)) {
                Write-SpectreHost "[red]Please enter a valid email address.[/]"
            }
        } while (-not (Test-EmailAddress -Email $profile.Email))
    }

    return $profile
}

function Get-GitAdditionalProfiles {
    <#
    .SYNOPSIS
        Prompts for additional Git profiles tied to directories
    .PARAMETER RepoLocations
        Array of repository locations for directory suggestions
    .PARAMETER ExistingProfiles
        Existing additional profiles to show
    .PARAMETER DefaultName
        Default name to suggest for new profiles
    .OUTPUTS
        Array of profile hashtables with Directory, Name, Email
    #>
    param(
        [string[]]$RepoLocations = @(),
        [array]$ExistingProfiles = @(),
        [string]$DefaultName = ""
    )

    $profiles = [System.Collections.ArrayList]::new()

    # Show existing additional profiles if any
    if ($ExistingProfiles.Count -gt 0) {
        Write-Host ""
        Write-SpectreHost "[yellow]Existing directory-specific profiles:[/]"
        foreach ($p in $ExistingProfiles) {
            Write-Host "  - $($p.Directory) -> $($p.Email)"
        }
        Write-Host ""

        $keepExisting = Read-SpectreConfirm -Prompt "Keep these profiles?" -DefaultAnswer "y"
        if ($keepExisting) {
            foreach ($p in $ExistingProfiles) {
                $profiles.Add($p) | Out-Null
            }
        }
    }

    # Ask if user wants to add directory-specific profiles
    Write-Host ""
    Write-SpectreHost "[cyan]Directory-specific profiles let you use different email/name for certain repos.[/]"
    Write-SpectreHost "[dim]Example: Use work email for repos in C:\repos\work\[/]"
    Write-Host ""

    $addMore = Read-SpectreConfirm -Prompt "Add a directory-specific profile?" -DefaultAnswer "n"

    while ($addMore) {
        Write-Host ""
        $newProfile = @{
            Directory = ""
            Name = ""
            Email = ""
        }

        # Build directory choices from repo locations
        $dirChoices = [System.Collections.ArrayList]::new()
        foreach ($loc in $RepoLocations) {
            $dirChoices.Add($loc) | Out-Null
            # Also add common subdirectories
            if (Test-Path $loc) {
                $subDirs = Get-ChildItem -Path $loc -Directory -ErrorAction SilentlyContinue | Select-Object -First 5
                foreach ($sub in $subDirs) {
                    $dirChoices.Add($sub.FullName) | Out-Null
                }
            }
        }
        $dirChoices.Add("(Enter custom path...)") | Out-Null

        # Select or enter directory
        if ($dirChoices.Count -gt 1) {
            $selectedDir = Read-SpectreSelection `
                -Title "Select directory for this profile" `
                -Choices $dirChoices `
                -Color Blue

            if ($selectedDir -eq "(Enter custom path...)") {
                $newProfile.Directory = Read-SpectreText -Prompt "Enter directory path"
            } else {
                $newProfile.Directory = $selectedDir
            }
        } else {
            $newProfile.Directory = Read-SpectreText -Prompt "Enter directory path for this profile"
        }

        # Ensure trailing slash for gitdir matching
        if (-not $newProfile.Directory.EndsWith('\') -and -not $newProfile.Directory.EndsWith('/')) {
            $newProfile.Directory += '/'
        }
        # Normalize to forward slashes for .gitconfig
        $newProfile.Directory = $newProfile.Directory -replace '\\', '/'

        # Name (default to same as default profile)
        $newProfile.Name = Read-SpectreText -Prompt "Name for this profile" -DefaultAnswer $DefaultName

        # Email
        do {
            $newProfile.Email = Read-SpectreText -Prompt "Email for this profile"
            if (-not (Test-EmailAddress -Email $newProfile.Email)) {
                Write-SpectreHost "[red]Please enter a valid email address.[/]"
            }
        } while (-not (Test-EmailAddress -Email $newProfile.Email))

        $profiles.Add($newProfile) | Out-Null
        Write-SpectreHost "[green]Added profile: $($newProfile.Directory) -> $($newProfile.Email)[/]"

        Write-Host ""
        $addMore = Read-SpectreConfirm -Prompt "Add another directory-specific profile?" -DefaultAnswer "n"
    }

    return ,$profiles
}

function Show-GitConfigPreview {
    <#
    .SYNOPSIS
        Shows a preview of the generated .gitconfig content
    #>
    param(
        [hashtable]$DefaultProfile,
        [array]$AdditionalProfiles = @()
    )

    Write-Host ""
    Write-SpectreHost "[blue]Generated .gitconfig preview:[/]"
    Write-Host ""

    $preview = @"
[[user]]
    name = $($DefaultProfile.Name)
    email = $($DefaultProfile.Email)
"@

    foreach ($profile in $AdditionalProfiles) {
        $configFileName = ".gitconfig-" + ($profile.Directory -replace '[:/\\]', '-').Trim('-')
        $preview += @"

[[includeIf "gitdir:$($profile.Directory)"]]
    path = ~/$configFileName
"@
    }

    # Display in a panel - use Out-Host to render without returning to pipeline
    $preview | Format-SpectrePanel -Title "~/.gitconfig" -Border Rounded -Color Blue | Out-Host
}

function Show-GitConfigStep {
    <#
    .SYNOPSIS
        Displays the Git configuration wizard step
    .PARAMETER Config
        Current configuration
    .OUTPUTS
        Updated configuration
    #>
    param(
        [hashtable]$Config
    )

    Show-StepHeader -StepNumber 3 -StepTitle "Git Configuration" -TotalSteps 7

    Write-SpectreHost "Configure your Git identity for commits."
    Write-SpectreHost "[dim]This sets your default name and email for all repositories.[/]"
    Write-Host ""

    # Get default profile
    $existingDefault = @{ Name = ""; Email = "" }
    if ($Config.Git.DefaultProfile) {
        $existingDefault = $Config.Git.DefaultProfile
    }

    $defaultProfile = Get-GitDefaultProfile -ExistingProfile $existingDefault
    $Config.Git.DefaultProfile = $defaultProfile

    # Get additional profiles
    $existingAdditional = @()
    if ($Config.Git.AdditionalProfiles) {
        $existingAdditional = $Config.Git.AdditionalProfiles
    }

    $additionalProfiles = Get-GitAdditionalProfiles `
        -RepoLocations $Config.RepoLocations `
        -ExistingProfiles $existingAdditional `
        -DefaultName $defaultProfile.Name

    $Config.Git.AdditionalProfiles = $additionalProfiles

    # Show preview
    Show-GitConfigPreview -DefaultProfile $defaultProfile -AdditionalProfiles $additionalProfiles

    return $Config
}

#endregion

#region PowerShell Modules Selection Step

# Available modules with descriptions
$script:AvailableModules = @(
    @{
        Name = "z"
        Description = "Directory jumper - quickly navigate to frequent directories"
        Recommended = $true
    }
    @{
        Name = "posh-git"
        Description = "Git status and tab completion for PowerShell"
        Recommended = $true
    }
    @{
        Name = "Terminal-Icons"
        Description = "File and folder icons in terminal listings"
        Recommended = $true
    }
    @{
        Name = "PSReadLine"
        Description = "Enhanced command line editing and history"
        Recommended = $true
    }
    @{
        Name = "PSFzf"
        Description = "Fuzzy finder integration for PowerShell"
        Recommended = $false
    }
    @{
        Name = "CompletionPredictor"
        Description = "AI-powered command completion predictions"
        Recommended = $false
    }
)

function Get-ModuleSelections {
    <#
    .SYNOPSIS
        Prompts user to select PowerShell modules to install
    .PARAMETER InstalledModules
        Array of already installed module names
    .OUTPUTS
        Array of selected module names
    #>
    param(
        [string[]]$InstalledModules = @()
    )

    # Build choices with descriptions
    $choices = [System.Collections.ArrayList]::new()
    foreach ($module in $script:AvailableModules) {
        $label = $module.Name
        if ($module.Recommended) {
            $label += " (Recommended)"
        }
        $choices.Add(@{
            Name = $label
            Description = $module.Description
            ModuleName = $module.Name
        }) | Out-Null
    }

    # Show installed status
    if ($InstalledModules.Count -gt 0) {
        Write-SpectreHost "[yellow]Already installed modules:[/]"
        foreach ($mod in $InstalledModules) {
            Write-Host "  - $mod"
        }
        Write-Host ""
    }

    Write-SpectreHost "[cyan]Select modules to install/keep:[/]"
    Write-SpectreHost "[dim]Use Space to toggle, Enter to confirm[/]"
    Write-Host ""

    # Use simple string choices for Read-SpectreMultiSelection
    $choiceLabels = $choices | ForEach-Object { "$($_.Name) - $($_.Description)" }

    $selected = Read-SpectreMultiSelection `
        -Title "PowerShell Modules" `
        -Choices $choiceLabels `
        -AllowEmpty

    # Extract module names from selections
    $selectedModules = [System.Collections.ArrayList]::new()
    foreach ($selection in $selected) {
        # Extract module name (first word before space or parenthesis)
        $moduleName = ($selection -split ' ')[0]
        $selectedModules.Add($moduleName) | Out-Null
    }

    return ,$selectedModules
}

function Show-PowerShellModulesStep {
    <#
    .SYNOPSIS
        Displays the PowerShell modules selection wizard step
    .PARAMETER Config
        Current configuration
    .OUTPUTS
        Updated configuration
    #>
    param(
        [hashtable]$Config
    )

    Show-StepHeader -StepNumber 4 -StepTitle "PowerShell Modules" -TotalSteps 7

    Write-SpectreHost "Select PowerShell modules to enhance your terminal experience."
    Write-SpectreHost "[dim]These modules add features like Git status, directory jumping, and icons.[/]"
    Write-Host ""

    # Get currently installed modules
    $installedModules = @()
    if ($Config.PowerShell.Modules) {
        $installedModules = $Config.PowerShell.Modules
    }

    $selectedModules = Get-ModuleSelections -InstalledModules $installedModules
    $Config.PowerShell.Modules = $selectedModules

    # Show summary
    Write-Host ""
    Write-SpectreHost "[green]Selected modules:[/]"
    foreach ($mod in $selectedModules) {
        Write-Host "  - $mod"
    }

    return $Config
}

#endregion

#region Oh-My-Posh Theme Selection Step

function Get-AvailableThemes {
    <#
    .SYNOPSIS
        Scans for available Oh-My-Posh themes in the devkit
    .PARAMETER DevkitRoot
        Root path of the devkit installation
    .OUTPUTS
        Array of theme file paths
    #>
    param(
        [string]$DevkitRoot = ""
    )

    $themes = [System.Collections.ArrayList]::new()

    # Scan devkit for .omp.json files
    if ($DevkitRoot -and (Test-Path $DevkitRoot)) {
        $devkitThemes = Get-ChildItem -Path $DevkitRoot -Filter "*.omp.json" -Recurse -ErrorAction SilentlyContinue
        foreach ($theme in $devkitThemes) {
            $themeName = $theme.BaseName -replace '\.omp', ''
            $themes.Add(@{
                Name = $themeName
                Path = $theme.FullName
                Source = "Devkit"
            }) | Out-Null
        }
    }

    # Also check Oh-My-Posh built-in themes location
    $ompThemesPath = Join-Path $env:LOCALAPPDATA "Programs\oh-my-posh\themes"
    if (Test-Path $ompThemesPath) {
        $builtinThemes = Get-ChildItem -Path $ompThemesPath -Filter "*.omp.json" -ErrorAction SilentlyContinue | Select-Object -First 10
        foreach ($theme in $builtinThemes) {
            $themeName = $theme.BaseName -replace '\.omp', ''
            $themes.Add(@{
                Name = $themeName
                Path = $theme.FullName
                Source = "Built-in"
            }) | Out-Null
        }
    }

    # Add option for custom path
    $themes.Add(@{
        Name = "(Enter custom theme path...)"
        Path = ""
        Source = "Custom"
    }) | Out-Null

    return ,$themes
}

function Get-ThemeSelection {
    <#
    .SYNOPSIS
        Prompts user to select an Oh-My-Posh theme
    .PARAMETER AvailableThemes
        Array of available theme objects
    .PARAMETER CurrentTheme
        Currently configured theme path
    .OUTPUTS
        Selected theme path
    #>
    param(
        [array]$AvailableThemes,
        [string]$CurrentTheme = ""
    )

    # Show current theme if set
    if ($CurrentTheme) {
        Write-SpectreHost "[yellow]Current theme: $CurrentTheme[/]"
        Write-Host ""
    }

    # Build choice labels
    $choices = [System.Collections.ArrayList]::new()
    foreach ($theme in $AvailableThemes) {
        if ($theme.Source -eq "Custom") {
            $choices.Add($theme.Name) | Out-Null
        } else {
            $label = "$($theme.Name) [dim]($($theme.Source))[/]"
            $choices.Add($theme.Name) | Out-Null
        }
    }

    Write-SpectreHost "[cyan]Select an Oh-My-Posh theme:[/]"
    Write-Host ""

    $selected = Read-SpectreSelection `
        -Title "Oh-My-Posh Theme" `
        -Choices $choices `
        -Color Blue

    # Find the selected theme
    $selectedTheme = $AvailableThemes | Where-Object { $_.Name -eq $selected } | Select-Object -First 1

    if ($selectedTheme.Source -eq "Custom") {
        # Prompt for custom path
        do {
            $customPath = Read-SpectreText -Prompt "Enter path to .omp.json theme file"
            if (-not (Test-Path $customPath)) {
                Write-SpectreHost "[red]File not found. Please enter a valid path.[/]"
            }
        } while (-not (Test-Path $customPath))
        return $customPath
    }

    return $selectedTheme.Path
}

function Show-OhMyPoshStep {
    <#
    .SYNOPSIS
        Displays the Oh-My-Posh theme selection wizard step
    .PARAMETER Config
        Current configuration
    .PARAMETER DevkitRoot
        Root path of the devkit installation
    .OUTPUTS
        Updated configuration
    #>
    param(
        [hashtable]$Config,
        [string]$DevkitRoot = ""
    )

    Show-StepHeader -StepNumber 5 -StepTitle "Oh-My-Posh Theme" -TotalSteps 7

    Write-SpectreHost "Select a theme for your terminal prompt."
    Write-SpectreHost "[dim]Oh-My-Posh provides beautiful, informative prompts with Git status and more.[/]"
    Write-Host ""

    # Get available themes
    $themes = Get-AvailableThemes -DevkitRoot $DevkitRoot

    if ($themes.Count -le 1) {
        Write-SpectreHost "[yellow]No themes found in devkit. You can specify a custom theme path.[/]"
    }

    # Get current theme
    $currentTheme = ""
    if ($Config.PowerShell.OhMyPoshTheme) {
        $currentTheme = $Config.PowerShell.OhMyPoshTheme
    }

    $selectedTheme = Get-ThemeSelection -AvailableThemes $themes -CurrentTheme $currentTheme
    $Config.PowerShell.OhMyPoshTheme = $selectedTheme

    Write-Host ""
    Write-SpectreHost "[green]Selected theme: $selectedTheme[/]"

    return $Config
}

#endregion

#region Installation Execution

function Invoke-Installation {
    <#
    .SYNOPSIS
        Executes the installation with progress display
    .PARAMETER Config
        DevkitConfig hashtable
    .PARAMETER DevkitRoot
        Root path of the devkit installation
    .OUTPUTS
        Hashtable with installation results
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,

        [Parameter(Mandatory)]
        [string]$DevkitRoot
    )

    $results = @{
        Success = $true
        BackupResults = $null
        ConfigResults = $null
        ModuleResults = $null
        Errors = @()
    }

    Write-Host ""

    # Define installation steps
    $steps = @(
        @{
            Name = "Backing up existing files"
            Action = {
                $backupResults = Backup-AllConfigFiles
                $results.BackupResults = $backupResults
                return $backupResults.Success
            }
        }
        @{
            Name = "Generating Git configuration"
            Action = {
                $gitResult = Save-GitConfig -Config $Config
                return $gitResult
            }
        }
        @{
            Name = "Creating profile-specific configs"
            Action = {
                $profileConfigs = Save-GitProfileConfigs -Config $Config
                return $true
            }
        }
        @{
            Name = "Generating variables.ps1"
            Action = {
                $varsResult = Save-VariablesPs1 -DevkitRoot $DevkitRoot -OhMyPoshTheme $Config.PowerShell.OhMyPoshTheme
                return $varsResult
            }
        }
        @{
            Name = "Updating PowerShell profile"
            Action = {
                $profileResult = Update-PowerShellProfile -DevkitRoot $DevkitRoot
                return $profileResult
            }
        }
        @{
            Name = "Installing PowerShell modules"
            Action = {
                $moduleResults = Install-RequiredModules -Modules $Config.PowerShell.Modules
                $results.ModuleResults = $moduleResults
                return ($moduleResults.Failed.Count -eq 0)
            }
        }
        @{
            Name = "Cleaning up old backups"
            Action = {
                Invoke-BackupCleanup -KeepCount 5 | Out-Null
                return $true
            }
        }
    )

    # Execute steps with progress
    $totalSteps = $steps.Count
    $currentStep = 0

    foreach ($step in $steps) {
        $currentStep++
        $percent = [math]::Round(($currentStep / $totalSteps) * 100)

        Write-SpectreHost "[blue][[$currentStep/$totalSteps]][/] $($step.Name)..."

        try {
            $stepResult = & $step.Action
            if ($stepResult) {
                Write-SpectreHost "  [green]Done[/]"
            } else {
                Write-SpectreHost "  [yellow]Warning[/]"
                $results.Errors += "$($step.Name) completed with warnings"
            }
        } catch {
            Write-SpectreHost "  [red]Failed: $_[/]"
            $results.Errors += "$($step.Name): $_"
            $results.Success = $false
        }
    }

    Write-Host ""

    # Show module installation summary
    if ($results.ModuleResults) {
        if ($results.ModuleResults.Installed.Count -gt 0) {
            Write-SpectreHost "[green]Installed modules:[/] $($results.ModuleResults.Installed -join ', ')"
        }
        if ($results.ModuleResults.AlreadyInstalled.Count -gt 0) {
            Write-SpectreHost "[dim]Already installed:[/] $($results.ModuleResults.AlreadyInstalled -join ', ')"
        }
        if ($results.ModuleResults.Failed.Count -gt 0) {
            Write-SpectreHost "[red]Failed to install:[/] $(($results.ModuleResults.Failed | ForEach-Object { $_.Name }) -join ', ')"
        }
    }

    # Show backup summary
    if ($results.BackupResults -and $results.BackupResults.Backups.Count -gt 0) {
        Write-Host ""
        Write-SpectreHost "[dim]Backups saved to: $(Get-BackupDirectory)[/]"
    }

    return $results
}

function Show-InstallationStep {
    <#
    .SYNOPSIS
        Displays the installation step with progress
    .PARAMETER Config
        DevkitConfig hashtable
    .PARAMETER DevkitRoot
        Root path of the devkit installation
    .OUTPUTS
        Installation results
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,

        [Parameter(Mandatory)]
        [string]$DevkitRoot
    )

    Show-StepHeader -StepNumber 7 -StepTitle "Installing" -TotalSteps 7

    Write-SpectreHost "Applying your configuration..."
    Write-Host ""

    $results = Invoke-Installation -Config $Config -DevkitRoot $DevkitRoot

    return $results
}

#endregion

#region Summary Display

function Show-ConfigurationSummary {
    <#
    .SYNOPSIS
        Displays a summary table of the configuration
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config
    )

    Write-Host ""
    Write-SpectreHost "[green]Configuration Summary[/]"
    Write-Host ""

    # Git Configuration
    $gitData = @(
        [PSCustomObject]@{ Setting = "Git Name"; Value = $Config.Git.DefaultProfile.Name }
        [PSCustomObject]@{ Setting = "Git Email"; Value = $Config.Git.DefaultProfile.Email }
    )

    # Add additional profiles
    $profileNum = 1
    foreach ($profile in $Config.Git.AdditionalProfiles) {
        $gitData += [PSCustomObject]@{ Setting = "Profile $profileNum Directory"; Value = $profile.Directory }
        $gitData += [PSCustomObject]@{ Setting = "Profile $profileNum Email"; Value = $profile.Email }
        $profileNum++
    }

    Write-SpectreHost "[blue]Git Configuration:[/]"
    $gitData | Format-SpectreTable -Border Rounded -Color Blue | Out-Host

    # Repo Locations
    if ($Config.RepoLocations -and $Config.RepoLocations.Count -gt 0) {
        Write-Host ""
        Write-SpectreHost "[blue]Repository Locations:[/]"
        $repoData = $Config.RepoLocations | ForEach-Object { [PSCustomObject]@{ Path = $_ } }
        $repoData | Format-SpectreTable -Border Rounded -Color Blue | Out-Host
    }

    # PowerShell Configuration
    Write-Host ""
    Write-SpectreHost "[blue]PowerShell Configuration:[/]"
    $modulesValue = if ($Config.PowerShell.Modules) { $Config.PowerShell.Modules -join ", " } else { "(none)" }
    $themeValue = if ($Config.PowerShell.OhMyPoshTheme) { $Config.PowerShell.OhMyPoshTheme } else { "(none)" }
    $psData = @(
        [PSCustomObject]@{ Setting = "Modules"; Value = $modulesValue }
        [PSCustomObject]@{ Setting = "Oh-My-Posh Theme"; Value = $themeValue }
    )
    $psData | Format-SpectreTable -Border Rounded -Color Blue | Out-Host
}

function Show-CompletionMessage {
    <#
    .SYNOPSIS
        Shows the final completion message with next steps
    #>
    param(
        [switch]$Success
    )

    Write-Host ""

    if ($Success) {
        $message = @"
Installation completed successfully!

Next steps:
  1. Restart your terminal to apply changes
  2. Run 'git config --list' to verify Git configuration
  3. Your PowerShell profile will load automatically

Enjoy your new development environment!
"@
        $message | Format-SpectrePanel -Title "[green]Success![/]" -Border Rounded -Color Green
    } else {
        $message = @"
Installation was cancelled or encountered an error.

Your previous configuration has been preserved.
Run the installer again if you'd like to try again.
"@
        $message | Format-SpectrePanel -Title "[yellow]Installation Cancelled[/]" -Border Rounded -Color Yellow
    }
}

#endregion

#region Wizard Flow Controller

function Start-Wizard {
    <#
    .SYNOPSIS
        Main wizard flow controller
    .DESCRIPTION
        Orchestrates the entire wizard experience from welcome to completion
    .PARAMETER Version
        Version string to display
    .PARAMETER ExistingConfig
        Existing configuration hashtable from config-loader
    .PARAMETER DevkitRoot
        Root path of the devkit installation for theme scanning
    #>
    param(
        [string]$Version = "1.0.0",
        [hashtable]$ExistingConfig = $null,
        [string]$DevkitRoot = ""
    )

    # Determine if we have existing config
    $existingConfigDetected = $false
    if ($ExistingConfig -and $ExistingConfig._Detection) {
        $existingConfigDetected = $ExistingConfig._Detection.DevkitInstalled -or
                                   $ExistingConfig._Detection.GitConfigFound
    }

    # Initialize config from existing or create new
    if ($ExistingConfig) {
        $script:WizardState.Config = $ExistingConfig
    }

    # Step 1: Welcome
    Show-WelcomeScreen -Version $Version

    # Step 2: Mode Selection
    $script:WizardState.Mode = Get-InstallationMode -ExistingConfigDetected $existingConfigDetected
    Write-SpectreHost "[green]Selected mode: $($script:WizardState.Mode)[/]"
    Write-Host ""

    # Step 2: Repository Locations
    $script:WizardState.Config = Show-RepoLocationsStep -Config $script:WizardState.Config

    # Step 3: Git Configuration
    $script:WizardState.Config = Show-GitConfigStep -Config $script:WizardState.Config

    # Step 4: PowerShell Modules
    $script:WizardState.Config = Show-PowerShellModulesStep -Config $script:WizardState.Config

    # Step 5: Oh-My-Posh Theme
    $script:WizardState.Config = Show-OhMyPoshStep -Config $script:WizardState.Config -DevkitRoot $DevkitRoot

    # Confirmation step
    Show-StepHeader -StepNumber 6 -StepTitle "Review Configuration" -TotalSteps 7

    # Use fully collected config
    $displayConfig = @{
        RepoLocations = $script:WizardState.Config.RepoLocations
        Git = $script:WizardState.Config.Git
        PowerShell = $script:WizardState.Config.PowerShell
    }

    Show-ConfigurationSummary -Config $displayConfig

    Write-Host ""
    $proceed = Get-Confirmation -Question "Proceed with installation?"

    if ($proceed) {
        $installResults = Show-InstallationStep -Config $script:WizardState.Config -DevkitRoot $DevkitRoot
        $script:WizardState.Installed = $true
        $script:WizardState.InstallSuccess = $installResults.Success

        if ($installResults.Success) {
            Show-CompletionMessage -Success
        } else {
            Write-Host ""
            Write-SpectreHost "[yellow]Installation completed with some issues:[/]"
            foreach ($err in $installResults.Errors) {
                Write-SpectreHost "  [red]- $err[/]"
            }
            Write-Host ""
            Show-CompletionMessage -Success
        }
    } else {
        $script:WizardState.Installed = $false
        $script:WizardState.InstallSuccess = $false
        Show-CompletionMessage
    }

    return $script:WizardState
}

#endregion

# Functions exported when dot-sourced:
# - Show-WelcomeScreen, Get-InstallationMode
# - Show-StepHeader, Get-Confirmation
# - Show-ConfigurationSummary, Show-CompletionMessage
# - Start-Wizard
# Variable: $WizardState
