#Requires -Version 7.0
#Requires -Modules PwshSpectreConsole
<#
.SYNOPSIS
    Devkit Installation Wizard UI Components

.DESCRIPTION
    Contains all wizard UI functions using PwshSpectreConsole for the
    interactive installation experience.
#>

# The single place the wizard's step count lives. Show-StepHeader defaults to it and
# every call site passes it, so inserting a step is a one-line change here.
$script:WizardTotalSteps = 12

# Wizard state
$script:WizardState = @{
    Mode = $null  # "Fresh" or "Update"
    CurrentStep = 0
    TotalSteps = $script:WizardTotalSteps
    Config = @{
        RepoLocations = @()
        Git = @{
            DefaultProfile = @{ Name = ""; Email = "" }
            AdditionalProfiles = @()
            Editor = ""
        }
        PowerShell = @{
            Modules = @()
            PromptEngine = "oh-my-posh"
            OhMyPoshTheme = ""
            StarshipConfig = ""
            StarshipPreset = ""
            StarshipMode = "Fresh"
        }
    }
}

# Fallback preset names for when starship is not on disk yet and `starship preset --list`
# cannot be asked. Same role as $script:AvailableNerdFonts below.
$script:AvailableStarshipPresets = @(
    'gruvbox-rainbow', 'tokyo-night', 'pastel-powerline', 'catppuccin-powerline',
    'jetpack', 'nerd-font-symbols', 'bracketed-segments', 'plain-text-symbols', 'no-nerd-font'
)

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
  - Prompt engine (Oh My Posh or Starship) and its theme

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

        [int]$TotalSteps = $script:WizardTotalSteps
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

#region Prompt Engine Step

function Show-PromptEngineStep {
    <#
    .SYNOPSIS
        Wizard step for choosing which prompt engine renders the shell prompt
    .DESCRIPTION
        RUNS BEFORE THE PREREQUISITES STEP, and that ordering is the whole point: the
        prerequisites step is what installs starship.exe and then refreshes PATH in
        process. The later theme step calls `starship preset --list` to populate its
        picker, so asking after prerequisites would leave the picker empty exactly when
        it matters.

        Oh My Posh stays the default so re-running the installer on an existing box
        changes nothing unless the user actively picks Starship.
    .PARAMETER Config
        Current DevkitConfig hashtable
    .OUTPUTS
        Updated configuration hashtable
    #>
    param(
        [hashtable]$Config
    )

    Show-StepHeader -StepNumber 2 -StepTitle "Prompt Engine" -TotalSteps $script:WizardTotalSteps

    # An older config-loader shape has no engine keys; seed them before reading.
    if (-not $Config.PowerShell.ContainsKey('PromptEngine')) { $Config.PowerShell.PromptEngine = 'oh-my-posh' }
    if (-not $Config.PowerShell.ContainsKey('StarshipConfig')) { $Config.PowerShell.StarshipConfig = '' }
    if (-not $Config.PowerShell.ContainsKey('StarshipPreset')) { $Config.PowerShell.StarshipPreset = '' }
    if (-not $Config.PowerShell.ContainsKey('StarshipMode')) { $Config.PowerShell.StarshipMode = 'Fresh' }

    Write-SpectreHost "Choose what renders your PowerShell prompt."
    Write-SpectreHost "[dim]Both write their config to ~/.devkit/, so 'devkit prompt use <engine>' switches[/]"
    Write-SpectreHost "[dim]later without re-running this installer. Either way you want a Nerd Font.[/]"
    Write-Host ""

    $ompLabel = "Oh My Posh - the devkit default, bundled orange powerline theme"
    $starshipLabel = "Starship - fast Rust prompt, configured from a built-in preset"

    # Detected value wins, so re-running never silently changes a working setup.
    # Read-SpectreSelection highlights index 0, so the default is moved to the front.
    $current = $Config.PowerShell.PromptEngine
    if ($current -notin @('oh-my-posh', 'starship')) { $current = 'oh-my-posh' }

    if ($Config._Detection -and $Config._Detection.VariablesFound) {
        $currentName = if ($current -eq 'starship') { 'Starship' } else { 'Oh My Posh' }
        Write-SpectreHost "[yellow]Currently configured: $currentName[/]"
        Write-Host ""
    }

    $choices = if ($current -eq 'starship') { @($starshipLabel, $ompLabel) } else { @($ompLabel, $starshipLabel) }

    $selected = Read-SpectreSelection -Title "Prompt engine" -Choices $choices -Color Blue
    $Config.PowerShell.PromptEngine = if ($selected -eq $starshipLabel) { 'starship' } else { 'oh-my-posh' }

    Write-Host ""
    if ($Config.PowerShell.PromptEngine -eq 'starship') {
        Write-SpectreHost "[green]Selected: Starship[/]"
        $starship = Test-CommandAvailable -Name 'starship' -VersionArgs @('--version') -VersionPattern '([\d\.]+)' `
            -FallbackPaths @('%LOCALAPPDATA%\Microsoft\WinGet\Links\starship.exe', '%ProgramFiles%\starship\bin\starship.exe')
        if ($starship.Found) {
            $versionText = if ($starship.Version) { "v$($starship.Version)" } else { "(version unknown)" }
            Write-SpectreHost "[dim]Detected starship $versionText at $($starship.Path)[/]"
        } else {
            Write-SpectreHost "[yellow]starship is not installed yet - tick it in the next step.[/]"
        }
    } else {
        Write-SpectreHost "[green]Selected: Oh My Posh[/]"
    }

    return $Config
}

#endregion

#region Prerequisites Step

# Nerd Fonts offered when none is installed. Meslo is first because
# Read-SpectreSelection/MultiSelection highlight index 0 and README names it.
$script:AvailableNerdFonts = @('meslo', 'CascadiaCode', 'FiraCode', 'JetBrainsMono', 'Hack')

function Show-PrerequisitesStep {
    <#
    .SYNOPSIS
        Wizard step for installing missing prerequisite tools
    .DESCRIPTION
        UNLIKE EVERY OTHER STEP, this one performs its work immediately rather than
        recording config for Invoke-Installation to apply later. That is deliberate: the
        Git-editor step (Get-AvailableEditors) and the Oh-My-Posh theme scan both probe
        the filesystem at PROMPT time, so a tool installed at the end of the wizard would
        be invisible to them. Installing here, then refreshing PATH, makes the rest of
        the run see the truth.

        The consequence is that a user who cancels at the Review step keeps whatever was
        installed here. Show-ConfigurationSummary and the cancel branch both say so.

        Nothing is installed without an explicit opt-in plus an explicit tick.
    .PARAMETER Config
        Current DevkitConfig hashtable
    .OUTPUTS
        Updated configuration hashtable
    #>
    param(
        [hashtable]$Config
    )

    Show-StepHeader -StepNumber 3 -StepTitle "Prerequisite Tools" -TotalSteps $script:WizardTotalSteps

    Write-SpectreHost "The devkit configures these tools; it can also install the missing ones for you."
    Write-SpectreHost "[dim]Installs run now, not at the end, so later steps can see the new tools.[/]"
    Write-Host ""

    # Seed the block even if config-loader did not populate it
    if (-not $Config.ContainsKey('Prerequisites')) {
        $Config.Prerequisites = @{
            Install = $false; Selected = @(); Fonts = @()
            Installed = @(); AlreadyInstalled = @(); Failed = @(); Skipped = @()
            NeedsNewShell = @(); WingetAvailable = $false
        }
    }

    $catalog = Get-DevkitPrerequisites
    $state = Get-PrerequisiteState -Catalog $catalog

    # Re-tier the two prompt engines around the choice made in step 2. Get-DevkitPrerequisites
    # hands back fresh hashtables on every call, so this only affects the current step.
    # The unselected engine is left in the list rather than hidden: Oh My Posh is still the
    # Nerd Font installer, and a starship user may well want it for that.
    $promptEngine = $Config.PowerShell.PromptEngine
    if (-not $promptEngine) { $promptEngine = 'oh-my-posh' }
    foreach ($row in $catalog) {
        if ($row.Key -notin @('oh-my-posh', 'starship')) { continue }
        if ($row.Key -eq $promptEngine) {
            $row.Tier = 'Required'
            $row.PreSelect = $true
        } else {
            $row.Tier = 'Optional'
            $row.PreSelect = $false
        }
    }

    # --- Detection table -----------------------------------------------------
    $rows = foreach ($row in $catalog) {
        $entry = $state[$row.Key]
        $status = if ($entry.Found) {
            if ($row.Mechanism -eq 'omp-font' -and $entry.Confidence -ne 'strong') { "Possibly installed" } else { "Installed" }
        } else { "Missing" }
        $detail = if ($entry.Version) { $entry.Version } elseif ($entry.Path) { $entry.Path } else { $row.InstallHint }
        [PSCustomObject]@{ Tool = $row.Name; Tier = $row.Tier; Status = $status; Detail = $detail }
    }
    $rows | Format-SpectreTable -Border Rounded -Color Blue | Out-Host

    # --- winget availability -------------------------------------------------
    $winget = Test-WingetAvailable
    $Config.Prerequisites.WingetAvailable = $winget.Found
    if ($winget.Found) {
        Write-SpectreHost "[dim]winget $($winget.Version) at $($winget.Path)[/]"
    } else {
        Write-SpectreHost "[yellow]winget (App Installer) not found - most tools cannot be installed automatically.[/]"
        Write-SpectreHost "[dim]Install 'App Installer' from the Microsoft Store, or install the tools by hand.[/]"
    }
    Write-Host ""

    # Rows the wizard can act on: missing, and not owned by the installer bootstrap.
    # A weak font hit counts as missing so it gets re-offered (a false positive costs
    # the user their glyphs; a false negative costs a redundant download).
    $missing = @($catalog | Where-Object {
        $_.HandledBy -ne 'installer-bootstrap' -and (
            -not $state[$_.Key].Found -or
            ($_.Mechanism -eq 'omp-font' -and $state[$_.Key].Confidence -ne 'strong')
        )
    })

    if ($missing.Count -eq 0) {
        Write-SpectreHost "[green]All prerequisites are already installed.[/]"
        $Config.Prerequisites.Install = $false
        $Config.Prerequisites.AlreadyInstalled = @($catalog | Where-Object { $state[$_.Key].Found } | ForEach-Object { $_.Name })
        Write-Host ""
        return $Config
    }

    # --- Parent opt-in gate --------------------------------------------------
    $requiredMissing = @($missing | Where-Object { $_.Tier -eq 'Required' })
    $defaultAnswer = if ($requiredMissing.Count -gt 0) { "y" } else { "n" }

    Write-SpectreHost "[yellow]$($missing.Count) prerequisite(s) are missing.[/]"
    Write-SpectreHost "[dim]Each tool is installed with winget or its own installer. Nothing installs without an explicit tick on the next screen.[/]"
    Write-Host ""

    $Config.Prerequisites.Install = Read-SpectreConfirm -Prompt "Install missing prerequisites now?" -DefaultAnswer $defaultAnswer
    if (-not $Config.Prerequisites.Install) {
        Write-SpectreHost "[yellow]Skipping prerequisite installation.[/]"
        if ($requiredMissing.Count -gt 0) {
            Write-SpectreHost "[dim]Install these by hand before using the devkit:[/]"
            foreach ($row in $requiredMissing) {
                Write-SpectreHost "  [dim]$($row.InstallHint)[/]"
            }
        }
        Write-Host ""
        return $Config
    }

    # --- Selection -----------------------------------------------------------
    # Already-installed tools are excluded from this list entirely rather than shown
    # unticked: Read-SpectreMultiSelection cannot pre-select choices, so a mixed list
    # would force the user to re-tick things they already have. They are in the table
    # above instead. PreSelect therefore controls ordering and emphasis, not a tick.
    Write-Host ""
    Write-SpectreHost "[cyan]Select prerequisites to install:[/]"
    Write-SpectreHost "[dim]Use Space to toggle, Enter to confirm. Already-installed tools are listed above and not repeated here.[/]"
    Write-Host ""

    $ordered = @($missing | Sort-Object @{ Expression = { -not $_.PreSelect } }, @{ Expression = { $_.Tier -ne 'Required' } })
    $choices = [ordered]@{}
    foreach ($row in $ordered) {
        $label = "$($row.Name) - $($row.Description)"
        if ($row.Tier -eq 'Required') { $label += " (required)" }
        if ($row.Mechanism -eq 'remote-script') { $label += " (runs a script downloaded from $($row.ScriptUrl))" }
        $choices[$label] = $row.Key
    }

    $selected = Read-SpectreMultiSelection `
        -Title "Prerequisites" `
        -Choices ([string[]]$choices.Keys) `
        -AllowEmpty

    $keys = @()
    foreach ($label in $choices.Keys) {
        if ($selected -contains $label) { $keys += $choices[$label] }
    }

    # Nerd Fonts are installed BY oh-my-posh (Mechanism 'omp-font'), so a font tick with
    # no oh-my-posh on the box would be silently dropped by the dependency guard in
    # Install-Prerequisites. Pull it in rather than let the fonts quietly not happen.
    if ($keys -contains 'nerd-font' -and $keys -notcontains 'oh-my-posh' -and -not $state['oh-my-posh'].Found) {
        Write-Host ""
        Write-SpectreHost "[yellow]Adding Oh My Posh: it ships the Nerd Font installer, whichever prompt engine you use.[/]"
        $keys = @('oh-my-posh') + $keys
    }

    if ($keys.Count -eq 0) {
        Write-SpectreHost "[yellow]Nothing selected; skipping prerequisite installation.[/]"
        $Config.Prerequisites.Install = $false
        Write-Host ""
        return $Config
    }

    # --- Font sub-prompt (multi-select: several fonts in one go) -------------
    $fonts = @()
    if ($keys -contains 'nerd-font') {
        Write-Host ""
        Write-SpectreHost "[cyan]Nerd Fonts to install:[/]"
        Write-SpectreHost "[dim]Any Nerd Font provides the glyphs; pick as many as you want.[/]"
        $fonts = @(Read-SpectreMultiSelection `
            -Title "Nerd Fonts" `
            -Choices ([string[]]$script:AvailableNerdFonts) `
            -AllowEmpty)
        if ($fonts.Count -eq 0) {
            Write-SpectreHost "[dim]No fonts selected; skipping the font install.[/]"
            $keys = @($keys | Where-Object { $_ -ne 'nerd-font' })
        }
    }

    $Config.Prerequisites.Selected = $keys
    $Config.Prerequisites.Fonts = $fonts

    if ($keys.Count -eq 0) {
        $Config.Prerequisites.Install = $false
        Write-Host ""
        return $Config
    }

    # --- Install now ---------------------------------------------------------
    Write-Host ""
    Write-SpectreHost "[dim]Installer output is captured to keep this screen readable; each package can take a minute or two.[/]"
    Write-Host ""

    $merged = @{
        Installed = @(); AlreadyInstalled = @(); Failed = @(); Skipped = @(); NeedsNewShell = @()
    }

    # Per-key loop so progress can be printed. Install-Prerequisites deliberately emits
    # no output of its own (same contract as Install-RequiredModules), so the caller owns
    # the UI.
    $index = 0
    foreach ($key in $keys) {
        $index++
        $row = $catalog | Where-Object { $_.Key -eq $key } | Select-Object -First 1
        Write-SpectreHost "[blue][[$index/$($keys.Count)]][/] Installing $($row.Name)..."
        # Showing the real command is what stops a slow install looking like a hang.
        Write-SpectreHost "  [dim]$($row.InstallHint)[/]"

        $result = Install-Prerequisites -Keys @($key) -Catalog $catalog -Fonts $fonts

        foreach ($name in $result.Installed) {
            $merged.Installed += $name
            Write-SpectreHost "  [green]Installed[/]"
        }
        foreach ($name in $result.AlreadyInstalled) {
            $merged.AlreadyInstalled += $name
            Write-SpectreHost "  [dim]Already installed[/]"
        }
        foreach ($item in $result.Failed) {
            $merged.Failed += $item
            Write-SpectreHost "  [yellow]Failed: $($item.Error -replace '\r?\n', ' ')[/]"
        }
        foreach ($item in $result.Skipped) {
            $merged.Skipped += $item
            Write-SpectreHost "  [yellow]Skipped: $($item.Reason)[/]"
        }
        $merged.NeedsNewShell += $result.NeedsNewShell
    }

    $Config.Prerequisites.Installed = $merged.Installed
    $Config.Prerequisites.AlreadyInstalled = $merged.AlreadyInstalled
    $Config.Prerequisites.Failed = $merged.Failed
    $Config.Prerequisites.Skipped = $merged.Skipped
    $Config.Prerequisites.NeedsNewShell = $merged.NeedsNewShell

    # Refresh PATH and re-detect so the later steps see reality, not the pre-install state.
    Update-SessionPath | Out-Null
    if ($Config._Detection) {
        $Config._Detection.Prereqs = Get-PrerequisiteState -Catalog $catalog -Fast
    }

    # --- Closing summary and caveats ----------------------------------------
    Write-Host ""
    if ($merged.Installed.Count -gt 0) {
        Write-SpectreHost "[green]Installed: $($merged.Installed -join ', ')[/]"
    }
    if ($merged.Failed.Count -gt 0) {
        Write-SpectreHost "[yellow]$($merged.Failed.Count) prerequisite(s) failed; the wizard will continue.[/]"
    }
    if ($merged.NeedsNewShell.Count -gt 0) {
        Write-SpectreHost "[yellow]Open a new terminal to pick up: $($merged.NeedsNewShell -join ', ')[/]"
    }
    if ($fonts.Count -gt 0) {
        Write-SpectreHost "[yellow]Fonts are installed but this terminal will not use one until you restart it[/]"
        Write-SpectreHost "[yellow]and select the font in your terminal profile.[/]"
    }
    Write-Host ""

    return $Config
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

    Show-StepHeader -StepNumber 4 -StepTitle "Repository Locations" -TotalSteps $script:WizardTotalSteps

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
        # Mirror New-GitConfig exactly rather than re-deriving the name here.
        $configFileName = Get-ProfileConfigFileName -Directory $profile.Directory
        $configPath = (Join-Path $env:USERPROFILE $configFileName) -replace '\\', '/'
        $preview += @"

[[includeIf "gitdir/i:$($profile.Directory)"]]
    path = $configPath
"@
    }

    $preview += @"


# plus [[core]], aliases, [[push]], [[branch]], [[help]], [[color]], [[gpg]], [[init]]
# sections the devkit does not author are preserved from your current file
"@

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

    Show-StepHeader -StepNumber 5 -StepTitle "Git Configuration" -TotalSteps $script:WizardTotalSteps

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

#region Git Editor Selection Step

function Get-AvailableEditors {
    <#
    .SYNOPSIS
        Detects installed text editors that can be used for Git commit messages
    .OUTPUTS
        Array of hashtables with Name, Command, and Available properties
    #>

    $editors = [System.Collections.ArrayList]::new()

    # VS Code
    $vscodeAvailable = $null -ne (Get-Command code -ErrorAction SilentlyContinue)
    if ($vscodeAvailable) {
        $editors.Add(@{
            Name = "Visual Studio Code"
            Command = "code --wait"
            Available = $true
        }) | Out-Null
    }

    # Neovim
    $nvimAvailable = $null -ne (Get-Command nvim -ErrorAction SilentlyContinue)
    if ($nvimAvailable) {
        $editors.Add(@{
            Name = "Neovim"
            Command = "nvim"
            Available = $true
        }) | Out-Null
    }

    # Vim (standalone)
    $vimAvailable = $null -ne (Get-Command vim -ErrorAction SilentlyContinue)
    if ($vimAvailable) {
        $editors.Add(@{
            Name = "Vim"
            Command = "vim"
            Available = $true
        }) | Out-Null
    }

    # Vim (Git bundled)
    $gitVimPath = "$env:ProgramFiles\Git\usr\bin\vim.exe"
    if (Test-Path $gitVimPath) {
        # Only add if standalone vim wasn't found
        if (-not $vimAvailable) {
            $editors.Add(@{
                Name = "Vim (Git bundled)"
                Command = "'C:\\Program Files\\Git\\usr\\bin\\vim.exe'"
                Available = $true
            }) | Out-Null
        }
    }

    # Notepad++
    $notepadPlusPlusPath = "$env:ProgramFiles\Notepad++\notepad++.exe"
    $notepadPlusPlusPath86 = "${env:ProgramFiles(x86)}\Notepad++\notepad++.exe"
    if (Test-Path $notepadPlusPlusPath) {
        $editors.Add(@{
            Name = "Notepad++"
            Command = "'C:\\Program Files\\Notepad++\\notepad++.exe' -multiInst -notabbar -nosession -noPlugin"
            Available = $true
        }) | Out-Null
    } elseif (Test-Path $notepadPlusPlusPath86) {
        $editors.Add(@{
            Name = "Notepad++"
            Command = "'C:\\Program Files (x86)\\Notepad++\\notepad++.exe' -multiInst -notabbar -nosession -noPlugin"
            Available = $true
        }) | Out-Null
    }

    # Nano
    $nanoAvailable = $null -ne (Get-Command nano -ErrorAction SilentlyContinue)
    if ($nanoAvailable) {
        $editors.Add(@{
            Name = "Nano"
            Command = "nano"
            Available = $true
        }) | Out-Null
    }

    # Always add custom option
    $editors.Add(@{
        Name = "(Enter custom editor command...)"
        Command = ""
        Available = $true
    }) | Out-Null

    return ,$editors
}

function Get-EditorSelection {
    <#
    .SYNOPSIS
        Prompts user to select a Git commit message editor
    .PARAMETER AvailableEditors
        Array of available editor objects
    .PARAMETER CurrentEditor
        Currently configured editor command
    .OUTPUTS
        Selected editor command string
    #>
    param(
        [array]$AvailableEditors,
        [string]$CurrentEditor = ""
    )

    # Show current editor if set
    if ($CurrentEditor) {
        Write-SpectreHost "[yellow]Current editor: $CurrentEditor[/]"
        Write-Host ""
    }

    # Build choice labels
    $choices = [System.Collections.ArrayList]::new()
    foreach ($editor in $AvailableEditors) {
        $choices.Add($editor.Name) | Out-Null
    }

    Write-SpectreHost "[cyan]Select your preferred Git commit message editor:[/]"
    Write-Host ""

    $selected = Read-SpectreSelection `
        -Title "Git Editor" `
        -Choices $choices `
        -Color Blue

    # Find the selected editor
    $selectedEditor = $AvailableEditors | Where-Object { $_.Name -eq $selected } | Select-Object -First 1

    if ($selected -eq "(Enter custom editor command...)") {
        # Prompt for custom command
        Write-Host ""
        Write-SpectreHost "[dim]Enter the command Git should use to open your editor.[/]"
        Write-SpectreHost "[dim]Examples: 'notepad', 'code --wait', 'vim'[/]"
        Write-Host ""
        $customCommand = Read-SpectreText -Prompt "Editor command"
        return $customCommand
    }

    return $selectedEditor.Command
}

function Show-GitEditorStep {
    <#
    .SYNOPSIS
        Displays the Git editor selection wizard step
    .PARAMETER Config
        Current configuration
    .OUTPUTS
        Updated configuration
    #>
    param(
        [hashtable]$Config
    )

    Show-StepHeader -StepNumber 6 -StepTitle "Git Editor" -TotalSteps $script:WizardTotalSteps

    Write-SpectreHost "Select the editor Git will use for commit messages and interactive operations."
    Write-SpectreHost "[dim]This is used when you run 'git commit' without -m, or during rebases.[/]"
    Write-Host ""

    # Get available editors
    $editors = Get-AvailableEditors

    if ($editors.Count -le 1) {
        Write-SpectreHost "[yellow]No common editors detected. You can specify a custom editor command.[/]"
    }

    # Get current editor
    $currentEditor = ""
    if ($Config.Git.Editor) {
        $currentEditor = $Config.Git.Editor
    }

    $selectedEditor = Get-EditorSelection -AvailableEditors $editors -CurrentEditor $currentEditor
    $Config.Git.Editor = $selectedEditor

    Write-Host ""
    Write-SpectreHost "[green]Selected editor: $selectedEditor[/]"

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

    Show-StepHeader -StepNumber 7 -StepTitle "PowerShell Modules" -TotalSteps $script:WizardTotalSteps

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

#region Prompt Theme Selection Step

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

function Get-AvailableStarshipPresets {
    <#
    .SYNOPSIS
        Lists Starship presets, from the installed binary when possible
    .DESCRIPTION
        Presets are embedded in starship.exe, so `starship preset --list` needs no
        network. When the binary is missing (the user declined the prereq install) the
        static $script:AvailableStarshipPresets list keeps the step usable.
    .OUTPUTS
        String[] - preset names
    #>
    $presets = @()
    if (Get-Command Get-StarshipPresetList -ErrorAction SilentlyContinue) {
        $presets = @(Get-StarshipPresetList)
    }

    if ($presets.Count -eq 0) {
        return $script:AvailableStarshipPresets
    }

    # Put the devkit's preferred preset first - Read-SpectreSelection highlights index 0.
    $preferred = 'gruvbox-rainbow'
    if ($presets -contains $preferred) {
        return @($preferred) + ($presets | Where-Object { $_ -ne $preferred })
    }
    return $presets
}

function Get-StarshipSelection {
    <#
    .SYNOPSIS
        Prompts for a Starship preset, an existing config to keep, or a custom .toml
    .PARAMETER Config
        Current configuration (mutated with StarshipMode / StarshipPreset / StarshipConfig)
    .OUTPUTS
        Updated configuration
    #>
    param(
        [hashtable]$Config
    )

    $keepChoice = "(Keep the existing ~/.config/starship.toml)"
    $customChoice = "(Enter a custom .toml path...)"

    $presets = @(Get-AvailableStarshipPresets)
    $choices = [System.Collections.ArrayList]::new()
    foreach ($preset in $presets) { $choices.Add($preset) | Out-Null }

    # Only offered when there IS something to keep, exactly like the statusline step.
    if ($Config._Detection -and $Config._Detection.StarshipConfigFound) {
        Write-SpectreHost "[yellow]You already have $($Config._Detection.StarshipConfigPath).[/]"
        Write-SpectreHost "[dim]Keeping it leaves STARSHIP_CONFIG unset so Starship finds it on its own.[/]"
        Write-Host ""
        $choices.Add($keepChoice) | Out-Null
    }
    $choices.Add($customChoice) | Out-Null

    $selected = Read-SpectreSelection -Title "Starship configuration" -Choices $choices -Color Blue

    if ($selected -eq $keepChoice) {
        $Config.PowerShell.StarshipMode = 'Keep'
        $Config.PowerShell.StarshipPreset = ''
        $Config.PowerShell.StarshipConfig = ''
        Write-Host ""
        Write-SpectreHost "[green]Keeping your existing Starship configuration.[/]"
        return $Config
    }

    if ($selected -eq $customChoice) {
        do {
            $customPath = Read-SpectreText -Prompt "Enter path to a starship .toml file"
            if (-not (Test-Path $customPath)) {
                Write-SpectreHost "[red]File not found. Please enter a valid path.[/]"
            }
        } while (-not (Test-Path $customPath))

        $Config.PowerShell.StarshipMode = 'Custom'
        $Config.PowerShell.StarshipPreset = ''
        $Config.PowerShell.StarshipConfig = $customPath
        Write-Host ""
        Write-SpectreHost "[green]Using $customPath[/]"
        return $Config
    }

    $Config.PowerShell.StarshipMode = 'Fresh'
    $Config.PowerShell.StarshipPreset = $selected
    $Config.PowerShell.StarshipConfig = ''
    Write-Host ""
    Write-SpectreHost "[green]Selected preset: $selected[/]"
    return $Config
}

function Show-PromptThemeStep {
    <#
    .SYNOPSIS
        Displays the theme/preset step for whichever prompt engine was chosen in step 2
    .DESCRIPTION
        Whatever the engine, an Oh-My-Posh theme path is always recorded - the bundled
        one when the user is on Starship and never picked a theme. Copying a .omp.json
        costs nothing and keeps `devkit prompt use oh-my-posh` instant, whereas a
        starship.toml can only be produced by the Starship binary.
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

    $engine = $Config.PowerShell.PromptEngine
    if (-not $engine) { $engine = 'oh-my-posh' }

    $stepTitle = if ($engine -eq 'starship') { "Starship Configuration" } else { "Oh-My-Posh Theme" }
    Show-StepHeader -StepNumber 8 -StepTitle $stepTitle -TotalSteps $script:WizardTotalSteps

    # Get available themes - needed in both branches (see the .DESCRIPTION above).
    $themes = Get-AvailableThemes -DevkitRoot $DevkitRoot

    if ($engine -eq 'starship') {
        Write-SpectreHost "Choose the Starship preset for your prompt."
        Write-SpectreHost "[dim]Presets are built into starship itself - no download required.[/]"
        Write-Host ""

        $Config = Get-StarshipSelection -Config $Config

        # Record a theme anyway so switching back to Oh My Posh later needs no re-run.
        if (-not $Config.PowerShell.OhMyPoshTheme) {
            $bundled = $themes | Where-Object { $_.Source -eq 'Devkit' } | Select-Object -First 1
            if ($bundled) { $Config.PowerShell.OhMyPoshTheme = $bundled.Path }
        }

        return $Config
    }

    Write-SpectreHost "Select a theme for your terminal prompt."
    Write-SpectreHost "[dim]Oh-My-Posh provides beautiful, informative prompts with Git status and more.[/]"
    Write-Host ""

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

#region Neovim Configuration Step

function Show-NvimConfigStep {
    <#
    .SYNOPSIS
        Wizard step for installing the bundled Neovim configuration
    .PARAMETER Config
        Current DevkitConfig hashtable
    .OUTPUTS
        Updated configuration hashtable
    #>
    param(
        [hashtable]$Config
    )

    Show-StepHeader -StepNumber 9 -StepTitle "Neovim Configuration" -TotalSteps $script:WizardTotalSteps

    Write-SpectreHost "Install the bundled Neovim configuration (lazy.nvim + neo-tree + easy-dotnet)."
    Write-SpectreHost "[dim]Installs to `$env:LOCALAPPDATA\nvim\ - Neovim's standard Windows location.[/]"
    Write-Host ""

    $nvim = Test-NeovimAvailable
    if (-not $nvim.Found) {
        Write-SpectreHost "[yellow]Neovim is not on PATH.[/]"
        Write-SpectreHost "[dim]The config will still be installed; install Neovim with 'winget install Neovim.Neovim' to use it.[/]"
        Write-Host ""
    } else {
        $versionText = if ($nvim.Version) { "v$($nvim.Version)" } else { "(version unknown)" }
        Write-SpectreHost "[green]Detected Neovim $versionText at $($nvim.Path)[/]"
        Write-Host ""
    }

    $existingNvimFound = $false
    $existingDevkitManaged = $false
    if ($Config._Detection -and $Config._Detection.NvimConfigFound) {
        $existingNvimFound = $true
        if ($Config.Nvim) {
            $existingDevkitManaged = [bool]$Config.Nvim.ExistingIsDevkitManaged
        }
    }

    # Ensure the Nvim sub-hashtable exists even when config-loader didn't populate it
    if (-not $Config.ContainsKey('Nvim')) {
        $Config.Nvim = @{ Install = $false }
    }

    if ($existingNvimFound -and -not $existingDevkitManaged) {
        Write-SpectreHost "[yellow]Existing Neovim configuration detected at `$env:LOCALAPPDATA\nvim\.[/]"
        $pm = $Config.Nvim.ExistingPluginManager
        if ($pm) {
            Write-Host "  Plugin manager: $pm"
        }
        Write-SpectreHost "[dim]It will be backed up under ~/.devkit/backups/nvim_<timestamp>/ before being replaced.[/]"
        Write-Host ""

        $Config.Nvim.Install = Read-SpectreConfirm -Prompt "Back up and replace it with the devkit config?" -DefaultAnswer "y"
        if (-not $Config.Nvim.Install) {
            Write-SpectreHost "[yellow]Skipping Neovim configuration; existing config will be left in place.[/]"
            return $Config
        }
    } elseif ($existingNvimFound -and $existingDevkitManaged) {
        Write-SpectreHost "[cyan]Devkit-managed Neovim config already present. It will be refreshed from the template.[/]"
        Write-Host ""
        $Config.Nvim.Install = Read-SpectreConfirm -Prompt "Refresh the devkit Neovim configuration?" -DefaultAnswer "y"
    } else {
        $Config.Nvim.Install = Read-SpectreConfirm -Prompt "Install the devkit Neovim configuration?" -DefaultAnswer "y"
    }

    if ($Config.Nvim.Install) {
        Write-Host ""
        Write-SpectreHost "[green]Neovim configuration will be installed.[/]"
    }

    return $Config
}

#endregion

#region Claude Code & Herdr Configuration Step

function Show-ClaudeCodeStep {
    <#
    .SYNOPSIS
        Wizard step for installing Claude Code assets and herdr configuration
    .DESCRIPTION
        Offers a parent gate plus per-area sub-toggles for agents, skills,
        commands, CLAUDE.md, herdr configuration, and the statusline. Assets install
        into ~/.claude (and %APPDATA%\herdr for the herdr config) regardless of
        whether the Claude CLI is on PATH. The statusline area differs from the rest:
        its renderer is downloaded from upstream rather than bundled in this repo.
    .PARAMETER Config
        Current DevkitConfig hashtable
    .PARAMETER DevkitRoot
        Root path of the source devkit repo, used to compare the bundled CLAUDE.md
        against the one already installed
    .OUTPUTS
        Updated configuration hashtable
    #>
    param(
        [hashtable]$Config,

        [string]$DevkitRoot = ""
    )

    Show-StepHeader -StepNumber 10 -StepTitle "Claude Code, Statusline & Herdr" -TotalSteps $script:WizardTotalSteps

    Write-SpectreHost "Install Claude Code assets (agents, skills, commands, CLAUDE.md) into `$env:USERPROFILE\.claude"
    Write-SpectreHost "[dim]the herdr terminal-multiplexer configuration (settings.json hook + %APPDATA%\herdr\config.toml),[/]"
    Write-SpectreHost "[dim]and the Awesome Statusline renderer, downloaded fresh from upstream.[/]"
    Write-Host ""

    # Ensure the Claude sub-hashtable exists even if config-loader didn't populate it
    if (-not $Config.ContainsKey('Claude')) {
        $Config.Claude = @{
            Install = $false; InstallAgents = $false; InstallSkills = $false
            InstallCommands = $false; InstallClaudeMd = $false; InstallHerdr = $false
            ForceClaudeMd = $false
            InstallStatusLine = $false; StatusLineSize = 'small'; StatusLineMode = 'Fresh'
        }
    }

    # Seed the statusline keys individually too, so a Claude block built by an older
    # config-loader still gets them (same belt-and-braces as ForceClaudeMd).
    if (-not $Config.Claude.ContainsKey('InstallStatusLine')) { $Config.Claude.InstallStatusLine = $false }
    if (-not $Config.Claude.ContainsKey('StatusLineSize')) { $Config.Claude.StatusLineSize = 'small' }
    if (-not $Config.Claude.ContainsKey('StatusLineMode')) { $Config.Claude.StatusLineMode = 'Fresh' }

    # Detection display (informational)
    $claude = Test-ClaudeCodeAvailable
    if ($claude.Found) {
        $versionText = if ($claude.Version) { $claude.Version } else { "(version unknown)" }
        Write-SpectreHost "[green]Detected Claude Code $versionText at $($claude.Path)[/]"
    } else {
        Write-SpectreHost "[yellow]Claude Code CLI not on PATH.[/] [dim]Assets still install to ~/.claude.[/]"
    }

    $pwsh = Test-PwshAvailable
    if ($pwsh.Found) {
        Write-SpectreHost "[green]pwsh: $($pwsh.Path) [dim]($($pwsh.Source))[/][/]"
    } else {
        Write-SpectreHost "[yellow]pwsh not found - herdr default_shell will be left unset.[/]"
    }

    if ($Config._Detection -and $Config._Detection.ClaudeSettingsFound) {
        Write-SpectreHost "[dim]Existing ~/.claude/settings.json detected; the herdr hook is merged without touching your other settings.[/]"
    }

    if ($Config._Detection -and $Config._Detection.StatusLineFound) {
        $sizeText = if ($Config._Detection.StatusLineSize) { $Config._Detection.StatusLineSize } else { "unknown" }
        Write-SpectreHost "[dim]Existing statusline wired (size: $sizeText).[/]"
    } elseif ($Config._Detection -and $Config._Detection.StatusLineScriptFound) {
        Write-SpectreHost "[dim]An awesome-statusline.ps1 exists but is not wired into settings.json.[/]"
    }
    Write-Host ""

    # Parent gate
    $Config.Claude.Install = Read-SpectreConfirm -Prompt "Install Claude Code assets, statusline and herdr configuration?" -DefaultAnswer "y"
    if (-not $Config.Claude.Install) {
        $Config.Claude.InstallAgents = $false
        $Config.Claude.InstallSkills = $false
        $Config.Claude.InstallCommands = $false
        $Config.Claude.InstallClaudeMd = $false
        $Config.Claude.InstallHerdr = $false
        $Config.Claude.InstallStatusLine = $false
        Write-SpectreHost "[yellow]Skipping Claude Code, statusline & herdr configuration.[/]"
        return $Config
    }

    Write-Host ""
    Write-SpectreHost "[cyan]Select areas to install:[/]"
    Write-SpectreHost "[dim]Use Space to toggle, Enter to confirm.[/]"
    Write-Host ""

    # Map labels -> config keys
    $areas = [ordered]@{
        "Agents (subagents)"                 = "InstallAgents"
        "Skills (herdr, spin-up-herd)"       = "InstallSkills"
        "Commands (slash commands)"          = "InstallCommands"
        "CLAUDE.md (global instructions)"    = "InstallClaudeMd"
        "Herdr configuration (settings hook + config.toml)" = "InstallHerdr"
        "Statusline (Awesome Statusline, downloaded from upstream)" = "InstallStatusLine"
    }

    $selected = Read-SpectreMultiSelection `
        -Title "Claude Code, Statusline & Herdr" `
        -Choices ([string[]]$areas.Keys) `
        -AllowEmpty

    foreach ($label in $areas.Keys) {
        $Config.Claude[$areas[$label]] = ($selected -contains $label)
    }

    # ~/.claude/CLAUDE.md is where personal global instructions accumulate, so it often
    # runs ahead of the bundled copy. Ask rather than let the repo silently win.
    $Config.Claude.ForceClaudeMd = $false
    if ($Config.Claude.InstallClaudeMd -and $DevkitRoot -and
        (Test-DevkitClaudeMdDrift -SourceRoot $DevkitRoot)) {
        Write-Host ""
        Write-SpectreHost "[yellow]Your ~/.claude/CLAUDE.md differs from the bundled copy.[/]"
        Write-SpectreHost "[dim]Either way the current file is backed up to ~/.devkit/backups/.[/]"
        $Config.Claude.ForceClaudeMd = Read-SpectreConfirm -Prompt "Replace it with the devkit version?" -DefaultAnswer "n"
        if (-not $Config.Claude.ForceClaudeMd) {
            $Config.Claude.InstallClaudeMd = $false
            Write-SpectreHost "[dim]Keeping your CLAUDE.md as-is.[/]"
        }
    }

    # The statusline renderer is third-party MIT code (AwesomeJun/CC-statusline) that
    # runs on every prompt render, so say where it comes from before downloading it.
    $Config.Claude.StatusLineMode = 'Fresh'
    if ($Config.Claude.InstallStatusLine) {
        Write-Host ""
        Write-SpectreHost "[dim]Awesome Statusline (AwesomeJun/CC-statusline, MIT) is fetched from GitHub at install time.[/]"
        Write-SpectreHost "[dim]Needs internet access; if offline the step is skipped with a warning.[/]"

        if ($Config._Detection -and $Config._Detection.StatusLineScriptFound) {
            Write-SpectreHost "[yellow]You already have ~/.claude/awesome-statusline.ps1.[/]"
            Write-SpectreHost "[dim]A fresh install backs the current file up to ~/.devkit/backups/ first.[/]"
            $rendererChoice = Read-SpectreSelection `
                -Title "Awesome Statusline renderer" `
                -Color Blue `
                -Choices @(
                    "Install a fresh copy from upstream (recommended)",
                    "Keep the existing ~/.claude/awesome-statusline.ps1"
                )
            $Config.Claude.StatusLineMode = if ($rendererChoice -like 'Install a fresh*') { 'Fresh' } else { 'Keep' }
        }

        # Detected size wins, so re-running the wizard never silently resizes a
        # working statusline. Read-SpectreSelection highlights index 0.
        $defaultSize = if ($Config._Detection -and $Config._Detection.StatusLineSize) {
            $Config._Detection.StatusLineSize
        } else {
            'small'
        }
        $allSizes = @('xsmall', 'small', 'medium', 'large', 'xlarge')
        if ($allSizes -notcontains $defaultSize) { $defaultSize = 'small' }
        $sizeChoices = @($defaultSize) + ($allSizes | Where-Object { $_ -ne $defaultSize })
        $Config.Claude.StatusLineSize = Read-SpectreSelection `
            -Title "Statusline size" `
            -Color Blue `
            -Choices $sizeChoices
    }

    Write-Host ""
    $anySelected = $Config.Claude.InstallAgents -or $Config.Claude.InstallSkills -or
                   $Config.Claude.InstallCommands -or $Config.Claude.InstallClaudeMd -or
                   $Config.Claude.InstallHerdr -or $Config.Claude.InstallStatusLine
    if ($anySelected) {
        Write-SpectreHost "[green]Selected Claude Code / herdr areas will be installed.[/]"
    } else {
        Write-SpectreHost "[yellow]No Claude areas selected; nothing will be installed.[/]"
    }

    return $Config
}

#endregion

#region Installation Execution

function Invoke-Installation {
    <#
    .SYNOPSIS
        Executes the installation with progress display
    .DESCRIPTION
        Installs devkit to user space (~/.devkit/) with step-by-step progress
    .PARAMETER Config
        DevkitConfig hashtable
    .PARAMETER SourceRoot
        Root path of the source devkit repo (for copying templates)
    .OUTPUTS
        Hashtable with installation results
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Config,

        [Parameter(Mandatory)]
        [string]$SourceRoot
    )

    $results = @{
        Success = $true
        BackupResults = $null
        ConfigResults = $null
        ModuleResults = $null
        ThemePath = $null
        StarshipConfig = ""
        Errors = @()
    }

    # Pre-PromptEngine configs have no engine key; Oh My Posh stays the default.
    $promptEngine = $Config.PowerShell.PromptEngine
    if (-not $promptEngine) { $promptEngine = 'oh-my-posh' }

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
            Name = "Clearing Terminal-Icons CLIXML cache"
            Action = {
                Clear-TerminalIconsCache | Out-Null
                return $true
            }
        }
        @{
            Name = "Creating user space directory"
            Action = {
                return Initialize-DevkitUserSpace
            }
        }
        @{
            Name = "Copying profile template"
            Action = {
                $profilePath = Copy-DevkitProfile -SourceRoot $SourceRoot
                return ($null -ne $profilePath -and $profilePath -ne "")
            }
        }
        @{
            Name = "Copying devkit CLI"
            Action = {
                $cliPath = Copy-DevkitCli -SourceRoot $SourceRoot
                return ($null -ne $cliPath -and $cliPath -ne "")
            }
        }
        @{
            # Runs whatever the engine, so `devkit prompt use oh-my-posh` needs no re-run.
            # Only a hard failure when Oh My Posh is what actually renders the prompt.
            Name = "Copying Oh-My-Posh theme"
            Action = {
                if ($Config.PowerShell.OhMyPoshTheme) {
                    $results.ThemePath = Copy-DevkitTheme -SourceThemePath $Config.PowerShell.OhMyPoshTheme
                }
                $copied = ($null -ne $results.ThemePath -and $results.ThemePath -ne "")
                if (-not $copied -and $promptEngine -ne 'oh-my-posh') {
                    Write-SpectreHost "  [dim](no theme selected - Starship is the prompt engine)[/]"
                    return $true
                }
                return $copied
            }
        }
        @{
            Name = "Resolving Starship configuration"
            Action = {
                if ($promptEngine -ne 'starship') {
                    Write-SpectreHost "  [dim](skipped - not the selected prompt engine)[/]"
                    return $true
                }

                $mode = if ($Config.PowerShell.StarshipMode) { $Config.PowerShell.StarshipMode } else { 'Fresh' }
                $results.StarshipConfig = Install-DevkitStarshipConfig `
                    -Mode $mode `
                    -Preset $Config.PowerShell.StarshipPreset `
                    -CustomPath $Config.PowerShell.StarshipConfig

                if ($mode -eq 'Keep') {
                    Write-SpectreHost "  [dim](keeping your existing starship.toml)[/]"
                    return $true
                }

                # A warning, not a failure: with no config written the profile still
                # starts Starship, it just falls back to Starship's own default.
                if (-not $results.StarshipConfig) {
                    Write-SpectreHost "  [yellow]Could not write a Starship config; Starship will use its own default.[/]"
                    return $false
                }
                return $true
            }
        }
        @{
            Name = "Installing Neovim configuration"
            Action = {
                if (-not ($Config.Nvim -and $Config.Nvim.Install)) {
                    Write-SpectreHost "  [dim](skipped - not selected)[/]"
                    return $true
                }
                $nvimPath = Copy-DevkitNvimConfig -SourceRoot $SourceRoot
                return ($null -ne $nvimPath -and $nvimPath -ne "")
            }
        }
        @{
            # NOT gated on the theme copy: a Starship user with no .omp.json still needs
            # this file, and without it the profile sources nothing at all.
            Name = "Generating variables.ps1"
            Action = {
                $themeArg = if ($results.ThemePath) { $results.ThemePath } else { "" }
                return Save-VariablesPs1 `
                    -ThemePath $themeArg `
                    -Engine $promptEngine `
                    -StarshipConfigPath $results.StarshipConfig `
                    -SourceRoot $SourceRoot
            }
        }
        @{
            Name = "Generating Git configuration"
            Action = {
                # Read the user-owned sections first: Save-GitConfig carries them into
                # the new file, and naming them here means a stale [include] or an old
                # credential helper is visible instead of silently inherited.
                $gitConfigPath = Join-Path $env:USERPROFILE ".gitconfig"
                $preserved = @(Get-UnmanagedGitConfigSections -Path $gitConfigPath)

                $gitResult = Save-GitConfig -Config $Config
                New-GlobalGitIgnore | Out-Null

                if ($preserved.Count -gt 0) {
                    $names = ($preserved | ForEach-Object { "[[$($_.Header)]]" }) -join ", "
                    Write-SpectreHost "  [dim]kept your own sections: $names[/]"
                }

                return $gitResult
            }
        }
        @{
            Name = "Creating profile-specific Git configs"
            Action = {
                $profileConfigs = Save-GitProfileConfigs -Config $Config
                return $true
            }
        }
        @{
            Name = "Updating PowerShell profile"
            Action = {
                $profileResult = Update-PowerShellProfile
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
            Name = "Installing Claude agents"
            Action = {
                if (-not ($Config.Claude -and $Config.Claude.InstallAgents)) {
                    Write-SpectreHost "  [dim](skipped - not selected)[/]"
                    return $true
                }
                $p = Copy-DevkitClaudeAgents -SourceRoot $SourceRoot
                return ($null -ne $p -and $p -ne "")
            }
        }
        @{
            Name = "Installing Claude skills"
            Action = {
                if (-not ($Config.Claude -and $Config.Claude.InstallSkills)) {
                    Write-SpectreHost "  [dim](skipped - not selected)[/]"
                    return $true
                }
                $p = Copy-DevkitClaudeSkills -SourceRoot $SourceRoot
                return ($null -ne $p -and $p -ne "")
            }
        }
        @{
            Name = "Installing Claude commands"
            Action = {
                if (-not ($Config.Claude -and $Config.Claude.InstallCommands)) {
                    Write-SpectreHost "  [dim](skipped - not selected)[/]"
                    return $true
                }
                $p = Copy-DevkitClaudeCommands -SourceRoot $SourceRoot
                return ($null -ne $p -and $p -ne "")
            }
        }
        @{
            Name = "Installing CLAUDE.md"
            Action = {
                if (-not ($Config.Claude -and $Config.Claude.InstallClaudeMd)) {
                    Write-SpectreHost "  [dim](skipped - not selected)[/]"
                    return $true
                }
                return Copy-DevkitClaudeMd -SourceRoot $SourceRoot -Force:([bool]$Config.Claude.ForceClaudeMd)
            }
        }
        @{
            Name = "Configuring herdr (settings hook + config.toml)"
            Action = {
                if (-not ($Config.Claude -and $Config.Claude.InstallHerdr)) {
                    Write-SpectreHost "  [dim](skipped - not selected)[/]"
                    return $true
                }
                $ok1 = Install-HerdrHookAndSettings -SourceRoot $SourceRoot
                $ok2 = Save-HerdrConfig -SourceRoot $SourceRoot
                return ($ok1 -and $ok2)
            }
        }
        @{
            # Runs AFTER herdr: both write settings.json, so a fixed order means the
            # last writer sees complete state. It is also the only step that can block
            # on the network, so a slow fetch delays nothing else, and a failure leaves
            # every other install already committed. Still ahead of backup cleanup so
            # the backups it creates are pruned in the same run.
            Name = "Installing Claude statusline"
            Action = {
                if (-not ($Config.Claude -and $Config.Claude.InstallStatusLine)) {
                    Write-SpectreHost "  [dim](skipped - not selected)[/]"
                    return $true
                }
                return Install-ClaudeStatusLine `
                    -Size $Config.Claude.StatusLineSize `
                    -Mode $Config.Claude.StatusLineMode
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

    Show-StepHeader -StepNumber 12 -StepTitle "Installing" -TotalSteps $script:WizardTotalSteps

    Write-SpectreHost "Applying your configuration..."
    Write-Host ""

    $results = Invoke-Installation -Config $Config -SourceRoot $DevkitRoot

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
    $editorValue = if ($Config.Git.Editor) { $Config.Git.Editor } else { "(not set)" }
    $gitData = @(
        [PSCustomObject]@{ Setting = "Git Name"; Value = $Config.Git.DefaultProfile.Name }
        [PSCustomObject]@{ Setting = "Git Email"; Value = $Config.Git.DefaultProfile.Email }
        [PSCustomObject]@{ Setting = "Git Editor"; Value = $editorValue }
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

    $engine = $Config.PowerShell.PromptEngine
    if (-not $engine) { $engine = 'oh-my-posh' }
    $engineValue = if ($engine -eq 'starship') { "Starship" } else { "Oh My Posh" }

    $psData = @(
        [PSCustomObject]@{ Setting = "Modules"; Value = $modulesValue }
        [PSCustomObject]@{ Setting = "Prompt Engine"; Value = $engineValue }
    )

    if ($engine -eq 'starship') {
        $starshipValue = switch ($Config.PowerShell.StarshipMode) {
            'Keep'   { "Keep existing ~/.config/starship.toml" }
            'Custom' { "Custom: $($Config.PowerShell.StarshipConfig)" }
            default  { "Preset: $($Config.PowerShell.StarshipPreset)" }
        }
        $psData += [PSCustomObject]@{ Setting = "Starship Config"; Value = $starshipValue }
        $psData += [PSCustomObject]@{ Setting = "Oh-My-Posh Theme"; Value = "$themeValue (kept ready to switch back)" }
    } else {
        $psData += [PSCustomObject]@{ Setting = "Oh-My-Posh Theme"; Value = $themeValue }
    }
    $psData | Format-SpectreTable -Border Rounded -Color Blue | Out-Host

    # Neovim Configuration
    Write-Host ""
    Write-SpectreHost "[blue]Neovim Configuration:[/]"
    $nvimInstall = if ($Config.Nvim -and $Config.Nvim.Install) { "Yes (installs to `$env:LOCALAPPDATA\nvim\)" } else { "No (skipped)" }
    $nvimData = @(
        [PSCustomObject]@{ Setting = "Install devkit nvim config"; Value = $nvimInstall }
    )
    $nvimData | Format-SpectreTable -Border Rounded -Color Blue | Out-Host

    # Prerequisites - past tense: these were applied in step 2, before this screen.
    if ($Config.Prerequisites -and $Config.Prerequisites.Install) {
        $p = $Config.Prerequisites
        $none = "(none)"
        $prereqData = @(
            [PSCustomObject]@{ Setting = "Installed";       Value = $(if (@($p.Installed).Count) { @($p.Installed) -join ', ' } else { $none }) }
            [PSCustomObject]@{ Setting = "Already present"; Value = $(if (@($p.AlreadyInstalled).Count) { @($p.AlreadyInstalled) -join ', ' } else { $none }) }
            [PSCustomObject]@{ Setting = "Failed";          Value = $(if (@($p.Failed).Count) { (@($p.Failed) | ForEach-Object { $_.Name }) -join ', ' } else { $none }) }
            [PSCustomObject]@{ Setting = "Skipped";         Value = $(if (@($p.Skipped).Count) { (@($p.Skipped) | ForEach-Object { "$($_.Name) ($($_.Reason))" }) -join ', ' } else { $none }) }
        )
        Write-Host ""
        Write-SpectreHost "[blue]Prerequisites (installed earlier in this run):[/]"
        $prereqData | Format-SpectreTable -Border Rounded -Color Blue | Out-Host
        Write-SpectreHost "[dim]These were applied in step 2 and are not affected by the choice below.[/]"
    }

    # Claude Code, Statusline & Herdr
    Write-Host ""
    Write-SpectreHost "[blue]Claude Code, Statusline & Herdr:[/]"
    $yn = { param($b) if ($b) { "Yes" } else { "No (skipped)" } }
    $claude = $Config.Claude

    # The statusline row carries a source and a size, so $yn is not expressive enough.
    $statusLineValue = if ($claude -and $claude.InstallStatusLine) {
        $src = if ($claude.StatusLineMode -eq 'Keep') { "keep existing" } else { "fresh from upstream" }
        "Yes ($src, size $($claude.StatusLineSize))"
    } else {
        "No (skipped)"
    }
    $claudeData = @(
        [PSCustomObject]@{ Setting = "Agents";   Value = (& $yn ($claude -and $claude.InstallAgents)) }
        [PSCustomObject]@{ Setting = "Skills";    Value = (& $yn ($claude -and $claude.InstallSkills)) }
        [PSCustomObject]@{ Setting = "Commands";  Value = (& $yn ($claude -and $claude.InstallCommands)) }
        [PSCustomObject]@{ Setting = "CLAUDE.md"; Value = (& $yn ($claude -and $claude.InstallClaudeMd)) }
        [PSCustomObject]@{ Setting = "Herdr config"; Value = (& $yn ($claude -and $claude.InstallHerdr)) }
        [PSCustomObject]@{ Setting = "Statusline"; Value = $statusLineValue }
    )
    $claudeData | Format-SpectreTable -Border Rounded -Color Blue | Out-Host
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

    # Welcome + mode selection (no step header of their own)
    Show-WelcomeScreen -Version $Version

    $script:WizardState.Mode = Get-InstallationMode -ExistingConfigDetected $existingConfigDetected
    Write-SpectreHost "[green]Selected mode: $($script:WizardState.Mode)[/]"
    Write-Host ""

    # Step 2: Prompt engine. Must precede Prerequisites - that step is what installs
    # starship.exe, and the theme step below asks the binary for its preset list.
    $script:WizardState.Config = Show-PromptEngineStep -Config $script:WizardState.Config

    # Step 3: Prerequisites. Runs FIRST among the installing steps and installs
    # immediately, so the Git-editor and prompt-theme steps below can see new tools.
    $script:WizardState.Config = Show-PrerequisitesStep -Config $script:WizardState.Config

    # Step 4: Repository Locations
    $script:WizardState.Config = Show-RepoLocationsStep -Config $script:WizardState.Config

    # Step 5: Git Configuration
    $script:WizardState.Config = Show-GitConfigStep -Config $script:WizardState.Config

    # Step 6: Git Editor
    $script:WizardState.Config = Show-GitEditorStep -Config $script:WizardState.Config

    # Step 7: PowerShell Modules
    $script:WizardState.Config = Show-PowerShellModulesStep -Config $script:WizardState.Config

    # Step 8: Prompt theme (Oh-My-Posh theme or Starship preset)
    $script:WizardState.Config = Show-PromptThemeStep -Config $script:WizardState.Config -DevkitRoot $DevkitRoot

    # Step 9: Neovim Configuration
    $script:WizardState.Config = Show-NvimConfigStep -Config $script:WizardState.Config

    # Step 10: Claude Code, Statusline & Herdr
    $script:WizardState.Config = Show-ClaudeCodeStep -Config $script:WizardState.Config -DevkitRoot $DevkitRoot

    # Confirmation step
    Show-StepHeader -StepNumber 11 -StepTitle "Review Configuration" -TotalSteps $script:WizardTotalSteps

    # Use fully collected config
    # NOTE: this is a hand-copied projection, not the whole config. A new top-level
    # config block will NOT reach Show-ConfigurationSummary unless it is added here.
    $displayConfig = @{
        RepoLocations = $script:WizardState.Config.RepoLocations
        Git = $script:WizardState.Config.Git
        PowerShell = $script:WizardState.Config.PowerShell
        Nvim = $script:WizardState.Config.Nvim
        Claude = $script:WizardState.Config.Claude
        Prerequisites = $script:WizardState.Config.Prerequisites
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

        # Step 2 installs immediately, so cancelling here does not undo it. Say so
        # rather than letting "Installation was cancelled" imply nothing happened.
        $prereqs = $script:WizardState.Config.Prerequisites
        if ($prereqs -and @($prereqs.Installed).Count -gt 0) {
            Write-Host ""
            Write-SpectreHost "[yellow]Note: $(@($prereqs.Installed).Count) prerequisite(s) were installed earlier in this run and remain installed.[/]"
            Write-SpectreHost "[dim]Nothing else was changed. Open a new terminal to pick up PATH changes.[/]"
        }

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
