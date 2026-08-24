#Requires -Version 7.0
<#
.SYNOPSIS
    Sandboxed test for the prompt-engine area (Oh My Posh vs Starship).

.DESCRIPTION
    Redirects USERPROFILE / APPDATA / LOCALAPPDATA to a scratch sandbox so the real
    ~/.devkit is never touched, then exercises the engine switch end to end:
    variables.ps1 generation per engine, Install-DevkitStarshipConfig in Fresh / Keep /
    Custom modes, degradation when starship is not installed, engine-aware validation,
    and the profile template's own branch.

    The starship binary is never invoked: Invoke-StarshipPresetExport and
    Get-StarshipPresetList are shadowed right after the libs are dot-sourced. Those
    seams are the reason the callers invoke them by name rather than inlining
    `& starship` - if this file ever needs a real starship.exe, a seam has regressed.

.NOTES
    Run: pwsh -File test-prompt-engine.ps1
    Exits non-zero if any assertion fails.
#>

$OutputEncoding = [console]::OutputEncoding = [System.Text.UTF8Encoding]::new()

$script:Failures = 0
function Assert($Condition, $Message) {
    if ($Condition) {
        Write-Host "  [PASS] $Message" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $Message" -ForegroundColor Red
        $script:Failures++
    }
}

# Source repo root (parent of this script's configuration/ dir)
$SourceRoot = Split-Path $PSScriptRoot -Parent

# --- Sandbox setup: redirect user dirs BEFORE dot-sourcing libs ---
$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("devkit-prompt-test-" + [guid]::NewGuid().ToString('N').Substring(0,8))
$env:USERPROFILE = Join-Path $sandbox "home"
$env:APPDATA = Join-Path $sandbox "appdata"
$env:LOCALAPPDATA = Join-Path $sandbox "localappdata"
New-Item -Path $env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA -ItemType Directory -Force | Out-Null

# $PROFILE is an automatic variable resolved at PowerShell startup from the Documents
# folder (often OneDrive-redirected). It is NOT derived from $env:USERPROFILE, so the
# redirect above does not contain code that reads or writes it. Override it explicitly.
$global:PROFILE = Join-Path $env:USERPROFILE "Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
New-Item -Path (Split-Path $global:PROFILE -Parent) -ItemType Directory -Force | Out-Null

# A stale engine from the caller's shell would leak into the assertions below.
$env:DEVKIT_PROMPT_ENGINE = $null
$env:DEVKIT_STARSHIP_CONFIG = $null
$env:DEVKIT_OMP_THEME = $null

Write-Host "Sandbox: $sandbox" -ForegroundColor Cyan
Write-Host "Source:  $SourceRoot" -ForegroundColor Cyan
Write-Host ""

. "$SourceRoot\configuration\lib\validators.ps1"
. "$SourceRoot\configuration\lib\backup.ps1"
. "$SourceRoot\configuration\lib\config-generator.ps1"
. "$SourceRoot\configuration\lib\config-loader.ps1"

# --- Test 0: the real export seam asks starship to overwrite ----------------
# Run BEFORE the stub below replaces Invoke-StarshipPresetExport, in a nested scope so
# these shadows do not leak into the rest of the file. `starship preset -o` REFUSES to
# overwrite an existing file and exits 1; since detection decides success here, the
# caller would then find the old config still on disk and report a successful export -
# so every `devkit prompt preset <name>` after the first silently kept the old preset.
Write-Host "Test 0: the preset export seam passes --force" -ForegroundColor Yellow
& {
    function Get-StarshipPath { return @{ Found = $true; Path = 'C:\fake\starship.exe' } }
    function Invoke-NativeCapture {
        param($Executable, $Arguments)
        $script:CapturedExportArgs = $Arguments
        return @{ Success = $true; ExitCode = 0; Output = ''; Command = 'captured' }
    }
    Invoke-StarshipPresetExport -PresetName 'tokyo-night' -DestinationPath 'C:\x\starship.toml' | Out-Null
}
Assert ($script:CapturedExportArgs -contains '--force') "starship preset is invoked with --force so it can replace an existing config"
Assert ($script:CapturedExportArgs -contains 'tokyo-night') "the preset name is passed through"
Write-Host ""

# --- Starship seam stubs ----------------------------------------------------
# Defined AFTER the dot-source so these definitions win in this scope.
$script:StarshipInstalled = $true
$script:ExportCalls = @()
$script:ExportSucceeds = $true

function Get-StarshipPresetList {
    if (-not $script:StarshipInstalled) { return @() }
    return @('gruvbox-rainbow', 'tokyo-night', 'pastel-powerline')
}

function Invoke-StarshipPresetExport {
    param(
        [Parameter(Mandatory)][string]$PresetName,
        [Parameter(Mandatory)][string]$DestinationPath
    )
    $script:ExportCalls += $PresetName

    if (-not $script:StarshipInstalled) {
        return @{ Success = $false; ExitCode = -1; Output = 'starship not found'; Command = "stub preset $PresetName" }
    }
    if (-not $script:ExportSucceeds) {
        return @{ Success = $false; ExitCode = 1; Output = 'simulated export failure'; Command = "stub preset $PresetName" }
    }

    Set-Content -Path $DestinationPath -Value "# stub preset: $PresetName" -Encoding UTF8 -Force
    return @{ Success = $true; ExitCode = 0; Output = ''; Command = "stub preset $PresetName" }
}

function Reset-Stubs {
    $script:StarshipInstalled = $true
    $script:ExportCalls = @()
    $script:ExportSucceeds = $true
}

$variablesPath = Join-Path $env:USERPROFILE '.devkit\variables.ps1'
$starshipPath = Join-Path $env:USERPROFILE '.devkit\themes\starship.toml'

# --- Test 1: variables.ps1 for Oh My Posh -----------------------------------
Write-Host "Test 1: variables.ps1 defaults to oh-my-posh" -ForegroundColor Yellow
Reset-Stubs
Initialize-DevkitUserSpace | Out-Null

$ok = Save-VariablesPs1 -ThemePath 'C:\themes\mine.omp.json' -SourceRoot $SourceRoot
$content = Get-Content $variablesPath -Raw
Assert $ok "Save-VariablesPs1 returned true"
Assert ($content -match 'DEVKIT_PROMPT_ENGINE = "oh-my-posh"') "engine defaults to oh-my-posh when -Engine is omitted"
Assert ($content -match 'DEVKIT_OMP_THEME = "C:/themes/mine.omp.json"') "theme path is written with forward slashes"
Assert ($content -notmatch 'DEVKIT_STARSHIP_CONFIG') "no starship config line for an oh-my-posh install"
Write-Host ""

# --- Test 2: variables.ps1 for Starship -------------------------------------
Write-Host "Test 2: variables.ps1 for starship keeps the OMP theme warm" -ForegroundColor Yellow
Save-VariablesPs1 -ThemePath 'C:\themes\mine.omp.json' -Engine 'starship' `
    -StarshipConfigPath 'C:\home\.devkit\themes\starship.toml' -SourceRoot $SourceRoot | Out-Null
$content = Get-Content $variablesPath -Raw
Assert ($content -match 'DEVKIT_PROMPT_ENGINE = "starship"') "engine recorded as starship"
Assert ($content -match 'DEVKIT_STARSHIP_CONFIG = "C:/home/.devkit/themes/starship.toml"') "starship config line written"
Assert ($content -match 'DEVKIT_OMP_THEME') "OMP theme still recorded, so switching back needs no re-run"
Write-Host ""

# --- Test 3: no starship config path means no env var -----------------------
Write-Host "Test 3: an empty starship config path omits the line entirely" -ForegroundColor Yellow
Save-VariablesPs1 -ThemePath 'C:\themes\mine.omp.json' -Engine 'starship' -SourceRoot $SourceRoot | Out-Null
$content = Get-Content $variablesPath -Raw
Assert ($content -notmatch 'DEVKIT_STARSHIP_CONFIG') "STARSHIP_CONFIG is never pointed at a file that was not written"
Assert ($content -match 'DEVKIT_PROMPT_ENGINE = "starship"') "engine is still starship"
Write-Host ""

# --- Test 4: Fresh mode exports a preset ------------------------------------
Write-Host "Test 4: Install-DevkitStarshipConfig Fresh mode" -ForegroundColor Yellow
Reset-Stubs
$dest = Install-DevkitStarshipConfig -Mode Fresh -Preset 'tokyo-night'
Assert ($dest -eq $starshipPath) "returns the user-space starship.toml path"
Assert (Test-Path $starshipPath) "starship.toml was written"
Assert ($script:ExportCalls -contains 'tokyo-night') "the requested preset was exported"
Write-Host ""

# --- Test 5: Fresh with no preset falls back to the devkit default ----------
Write-Host "Test 5: Fresh mode with no preset uses the devkit default" -ForegroundColor Yellow
Reset-Stubs
Install-DevkitStarshipConfig -Mode Fresh | Out-Null
Assert ($script:ExportCalls -contains 'gruvbox-rainbow') "falls back to gruvbox-rainbow"
Write-Host ""

# --- Test 6: Fresh over an existing config backs it up ----------------------
Write-Host "Test 6: replacing a config backs the old one up" -ForegroundColor Yellow
Reset-Stubs
Set-Content -Path $starshipPath -Value "# hand-edited by the user" -Encoding UTF8 -Force
Install-DevkitStarshipConfig -Mode Fresh -Preset 'gruvbox-rainbow' | Out-Null
$backups = @(Get-ChildItem (Join-Path $env:USERPROFILE '.devkit\backups') -Filter 'starship-config_*' -ErrorAction SilentlyContinue)
Assert ($backups.Count -ge 1) "a starship-config backup was created"
Assert ((Get-Content $starshipPath -Raw) -match 'stub preset') "the new preset replaced the old file"
Write-Host ""

# --- Test 7: Keep mode returns empty ----------------------------------------
Write-Host "Test 7: Keep mode records nothing" -ForegroundColor Yellow
Reset-Stubs
$kept = Install-DevkitStarshipConfig -Mode Keep
Assert ($kept -eq "") "Keep returns empty so DEVKIT_STARSHIP_CONFIG stays unwritten"
Assert ($script:ExportCalls.Count -eq 0) "Keep never invokes the export seam"
Write-Host ""

# --- Test 8: Custom mode copies the file ------------------------------------
Write-Host "Test 8: Custom mode copies the supplied .toml" -ForegroundColor Yellow
Reset-Stubs
$customSource = Join-Path $sandbox 'my-starship.toml'
Set-Content -Path $customSource -Value "# my own config" -Encoding UTF8 -Force
$dest = Install-DevkitStarshipConfig -Mode Custom -CustomPath $customSource
Assert ($dest -eq $starshipPath) "Custom returns the user-space path"
Assert ((Get-Content $starshipPath -Raw) -match 'my own config') "the custom file's contents were copied"
Assert ($script:ExportCalls.Count -eq 0) "Custom never invokes the export seam"
Write-Host ""

# --- Test 9: Custom with a missing file degrades, does not throw ------------
Write-Host "Test 9: Custom mode with a missing file degrades" -ForegroundColor Yellow
Reset-Stubs
$threw = $false
$dest = "sentinel"
try {
    $dest = Install-DevkitStarshipConfig -Mode Custom -CustomPath (Join-Path $sandbox 'nope.toml') -WarningAction SilentlyContinue
} catch { $threw = $true }
Assert (-not $threw) "does not throw - Invoke-Installation only aborts on a thrown exception"
Assert ($dest -eq "") "returns empty rather than a path that does not resolve"
Write-Host ""

# --- Test 10: no starship binary degrades to a warning ----------------------
Write-Host "Test 10: a missing starship binary degrades to a warning" -ForegroundColor Yellow
Reset-Stubs
$script:StarshipInstalled = $false
Remove-Item $starshipPath -Force -ErrorAction SilentlyContinue
$threw = $false
$dest = "sentinel"
try {
    $dest = Install-DevkitStarshipConfig -Mode Fresh -Preset 'tokyo-night' -WarningAction SilentlyContinue
} catch { $threw = $true }
Assert (-not $threw) "does not throw when starship is absent"
Assert ($dest -eq "") "returns empty so the profile falls back to Starship's own default"
Assert (-not (Test-Path $starshipPath)) "no half-written config left behind"
Write-Host ""

# --- Test 11: a failed export leaves nothing recorded -----------------------
Write-Host "Test 11: a failed export records nothing" -ForegroundColor Yellow
Reset-Stubs
$script:ExportSucceeds = $false
$dest = Install-DevkitStarshipConfig -Mode Fresh -Preset 'tokyo-night' -WarningAction SilentlyContinue
Assert ($dest -eq "") "a non-zero export with no file on disk is a failure"
Write-Host ""

# --- Test 12: engine-aware validation ---------------------------------------
Write-Host "Test 12: Test-DevkitConfig is engine-aware" -ForegroundColor Yellow
$cfg = New-DevkitConfig
$cfg.RepoLocations = @("C:\repos")
$cfg.Git.DefaultProfile.Name = "Test User"
$cfg.Git.DefaultProfile.Email = "test@example.com"
$cfg.PowerShell.Modules = @("z")

Assert ($cfg.PowerShell.PromptEngine -eq 'oh-my-posh') "New-DevkitConfig defaults the engine to oh-my-posh"

$cfg.PowerShell.OhMyPoshTheme = ""
$result = Test-DevkitConfig -Config $cfg
Assert (-not $result.IsValid) "an oh-my-posh config with no theme is invalid"

$cfg.PowerShell.PromptEngine = 'starship'
$result = Test-DevkitConfig -Config $cfg
Assert $result.IsValid "a starship config with no OMP theme is valid"

$cfg.PowerShell.PromptEngine = 'fish-shell-prompt'
$result = Test-DevkitConfig -Config $cfg
Assert (-not $result.IsValid) "an unknown engine is rejected"

# A config written before PromptEngine existed must still validate as oh-my-posh.
$legacy = New-DevkitConfig
$legacy.RepoLocations = @("C:\repos")
$legacy.Git.DefaultProfile.Name = "Test User"
$legacy.Git.DefaultProfile.Email = "test@example.com"
$legacy.PowerShell.Modules = @("z")
$legacy.PowerShell.Remove('PromptEngine')
$legacy.PowerShell.OhMyPoshTheme = "C:\themes\mine.omp.json"
$result = Test-DevkitConfig -Config $legacy
Assert $result.IsValid "a pre-PromptEngine config still validates"
Write-Host ""

# --- Test 13: config-loader round-trips the engine --------------------------
Write-Host "Test 13: Get-ExistingDevkitVariables reads back what was written" -ForegroundColor Yellow
Save-VariablesPs1 -ThemePath 'C:\themes\mine.omp.json' -Engine 'starship' `
    -StarshipConfigPath $starshipPath -SourceRoot $SourceRoot | Out-Null
$vars = Get-ExistingDevkitVariables
Assert $vars.Found "variables.ps1 was found at ~/.devkit/variables.ps1"
Assert ($vars.PromptEngine -eq 'starship') "the engine round-trips"
Assert ($vars.StarshipConfig -match 'starship\.toml') "the starship config path round-trips"
Assert ($vars.OhMyPoshTheme -match 'mine\.omp\.json') "the OMP theme round-trips"
Write-Host ""

# --- Test 14: the profile template branches on the engine -------------------
Write-Host "Test 14: the profile template initialises the selected engine" -ForegroundColor Yellow
$profileText = Get-Content "$SourceRoot\configuration\powershell\Microsoft.PowerShell_profile.ps1" -Raw
Assert ($profileText -match 'switch \(\$env:DEVKIT_PROMPT_ENGINE\)') "the profile switches on DEVKIT_PROMPT_ENGINE"
Assert ($profileText -match 'starship init powershell') "the starship arm initialises starship"
Assert ($profileText -match 'oh-my-posh init pwsh') "the oh-my-posh arm is still there"
# The 'default' arm - not an explicit 'oh-my-posh' case - is what keeps a variables.ps1
# written before DEVKIT_PROMPT_ENGINE existed rendering the same prompt as before.
Assert ($profileText -match '(?m)^\s+default \{') "the oh-my-posh arm is the switch default, so legacy installs keep working"
Assert ($profileText -notmatch "'oh-my-posh' \{") "oh-my-posh is NOT an explicit case (that would break legacy installs)"
Write-Host ""

# --- Test 15: the catalogue carries a starship row --------------------------
Write-Host "Test 15: the prerequisite catalogue lists starship" -ForegroundColor Yellow
$catalog = Get-DevkitPrerequisites
$row = $catalog | Where-Object { $_.Key -eq 'starship' }
Assert ($null -ne $row) "a starship row exists"
Assert ($row.WingetId -eq 'Starship.Starship') "the winget id is Starship.Starship"
Assert ($row.Command -eq 'starship') "detection probes the starship binary"
Assert ($row.VersionArgs.Count -gt 0) "a version probe is defined (starship --version does not hang)"
Write-Host ""

# --- Test 16: the CLI knows how to restore a starship-config backup ---------
Write-Host "Test 16: devkit backups restore infers the starship destination" -ForegroundColor Yellow
$cliText = Get-Content "$SourceRoot\configuration\powershell\devkit.ps1" -Raw
Assert ($cliText -match "\^starship-config_") "devkit.ps1 maps starship-config_* back to its original location"
Assert ($cliText -match "'prompt'\s+\{\s+Invoke-DevkitPrompt") "devkit dispatches the prompt subcommand"
Write-Host ""

# --- Test 17: the CLI resolves configs from disk, not only from the env -----
# `devkit prompt use` rewrites the WHOLE of variables.ps1, so if it read only
# $env:DEVKIT_OMP_THEME it would silently drop the theme line in any shell that has
# not sourced variables.ps1 yet - which is the shell you are in right after installing.
Write-Host "Test 17: the CLI falls back to disk when the env vars are cold" -ForegroundColor Yellow
. "$SourceRoot\configuration\powershell\devkit.ps1"

$env:DEVKIT_OMP_THEME = $null
$env:DEVKIT_STARSHIP_CONFIG = $null
$themesDir = Join-Path $env:USERPROFILE '.devkit\themes'
if (-not (Test-Path $themesDir)) { New-Item -Path $themesDir -ItemType Directory -Force | Out-Null }
Set-Content -Path (Join-Path $themesDir 'ondisk.omp.json') -Value "{}" -Encoding UTF8 -Force
Set-Content -Path $starshipPath -Value "# on disk" -Encoding UTF8 -Force

Assert ((_Devkit-GetOmpThemePath) -match 'ondisk\.omp\.json') "the OMP theme is found on disk with no env var set"
Assert ((_Devkit-GetStarshipConfigPath) -match 'starship\.toml') "the starship config is found on disk with no env var set"

Remove-Item $starshipPath -Force -ErrorAction SilentlyContinue
Assert ((_Devkit-GetStarshipConfigPath) -eq "") "no config on disk resolves to empty, meaning Starship's own default"

$env:DEVKIT_OMP_THEME = 'C:\explicit\wins.omp.json'
Assert ((_Devkit-GetOmpThemePath) -eq 'C:\explicit\wins.omp.json') "an explicit env var wins over the disk scan"

$env:DEVKIT_PROMPT_ENGINE = $null
Assert ((_Devkit-GetPromptEngine) -eq 'oh-my-posh') "an unset engine reads as oh-my-posh, matching the profile's switch default"
$env:DEVKIT_PROMPT_ENGINE = 'nonsense'
Assert ((_Devkit-GetPromptEngine) -eq 'oh-my-posh') "an unrecognised engine also falls back to oh-my-posh"
Write-Host ""

# --- Cleanup ----------------------------------------------------------------
Remove-Item -Path $sandbox -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
if ($script:Failures -eq 0) {
    Write-Host "All prompt-engine tests passed." -ForegroundColor Green
    exit 0
} else {
    Write-Host "$script:Failures assertion(s) failed." -ForegroundColor Red
    exit 1
}
