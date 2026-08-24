#Requires -Version 7.0
<#
.SYNOPSIS
    Sandboxed test for the Starship git panel (branch coloured by repo state + counts).

.DESCRIPTION
    Covers the two halves of the feature and, more importantly, the contract between
    them: the panel in starship.toml disables git_branch and renders the branch from
    four env_var modules, and only Invoke-Starship-PreCommand in the profile template
    ever sets those. If the two sets of names drift apart the prompt silently loses its
    branch, so this file asserts they match.

    Starship is never invoked - Add-DevkitStarshipGitPanel is text manipulation and the
    preset fixtures below are inlined. `git` IS invoked, against a throwaway repo in the
    sandbox, because the classifier's whole job is reading real repository state.

.NOTES
    Run: pwsh -File test-starship-gitpanel.ps1
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

$SourceRoot = Split-Path $PSScriptRoot -Parent

# --- Sandbox setup: redirect user dirs BEFORE dot-sourcing libs ---
$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("devkit-gitpanel-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
$env:USERPROFILE = Join-Path $sandbox "home"
$env:APPDATA = Join-Path $sandbox "appdata"
$env:LOCALAPPDATA = Join-Path $sandbox "localappdata"
New-Item -Path $env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA -ItemType Directory -Force | Out-Null

# $PROFILE is resolved at startup from the Documents folder and is NOT derived from
# $env:USERPROFILE, so the redirect above does not contain it. Override it explicitly.
$global:PROFILE = Join-Path $env:USERPROFILE "Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
New-Item -Path (Split-Path $global:PROFILE -Parent) -ItemType Directory -Force | Out-Null

$env:DEVKIT_PROMPT_ENGINE = $null
$env:DEVKIT_STARSHIP_CONFIG = $null
$env:DEVKIT_GIT_PANEL = $null

Write-Host "Sandbox: $sandbox" -ForegroundColor Cyan
Write-Host ""

. "$SourceRoot\configuration\lib\validators.ps1"
. "$SourceRoot\configuration\lib\backup.ps1"
. "$SourceRoot\configuration\lib\config-generator.ps1"

# The export seam is stubbed for the same reason test-prompt-engine.ps1 stubs it: if
# this file ever needs a real starship.exe, a seam has regressed.
$script:StubPresetBody = ''
function Invoke-StarshipPresetExport {
    param(
        [Parameter(Mandatory)][string]$PresetName,
        [Parameter(Mandatory)][string]$DestinationPath
    )
    Set-Content -Path $DestinationPath -Value $script:StubPresetBody -Encoding UTF8 -Force
    return @{ Success = $true; ExitCode = 0; Output = ''; Command = "stub preset $PresetName" }
}

$fixtures = Join-Path $sandbox 'fixtures'
New-Item -Path $fixtures -ItemType Directory -Force | Out-Null

function New-Fixture($Name, $Body) {
    $path = Join-Path $fixtures "$Name.toml"
    [System.IO.File]::WriteAllText($path, $Body, (New-Object System.Text.UTF8Encoding($false)))
    return $path
}

# A powerline preset: multi-line format whose lines start with [ ... ], plus the
# [git_branch] / [git_status] pair that carries the segment background.
$powerline = @'
"$schema" = 'https://starship.rs/config-schema.json'

format = """
[](color_orange)\
$directory\
[](bg:color_yellow fg:color_orange)\
$git_branch\
$git_state\
$git_status\
[](fg:color_aqua)\
$line_break$character"""

palette = 'gruvbox_dark'

[palettes.gruvbox_dark]
color_aqua = '#689d6a'
color_fg0 = '#fbf1c7'

[directory]
style = "fg:color_fg0 bg:color_yellow"

[git_branch]
symbol = "BR"
style = "bg:color_aqua"
format = '[[ $symbol $branch ](fg:color_fg0 bg:color_aqua)]($style)'

[git_status]
style = "bg:color_aqua"
format = '[[($all_status$ahead_behind )](fg:color_fg0 bg:color_aqua)]($style)'

[time]
disabled = false
'@

# A symbols-only preset: no top-level format at all, so Starship is on "$all".
$symbolsOnly = @'
[aws]
symbol = "AWS "

[git_branch]
symbol = "git "
'@

# A format that mentions the git segment but not the branch.
$statusOnly = @'
format = "$directory$git_status$character"

[git_status]
style = "cyan"
'@

# A format with no git segment at all: nowhere to put the branch.
$noGit = @'
format = "$directory$character"
'@

# --- Test 1: powerline preset ------------------------------------------------
Write-Host "Test 1: a powerline preset keeps its glyph and its background" -ForegroundColor Yellow
$path = New-Fixture 'powerline' $powerline
Assert (Add-DevkitStarshipGitPanel -Path $path) "Add-DevkitStarshipGitPanel returned true"
$text = Get-Content -LiteralPath $path -Raw

Assert (Test-DevkitStarshipGitPanel -Path $path) "the panel marker is detectable afterwards"
Assert ($text -match '(?m)^\[git_branch\]\s*\r?\ndisabled = true') "git_branch is disabled"
foreach ($state in @('CONFLICT', 'DIRTY', 'DIVERGED', 'CLEAN')) {
    Assert ($text -match "\[env_var\.DEVKIT_GIT_$state\]") "env_var.DEVKIT_GIT_$state is defined"
    Assert ($text -match "\$\{env_var\.DEVKIT_GIT_$state\}") "the format references DEVKIT_GIT_$state"
}
Assert ($text -notmatch '\$git_branch') "no bare `$git_branch` is left in the format"
Assert ($text -match 'symbol = "BR "') "the preset's branch glyph carries over, with one trailing space"
Assert (([regex]::Matches($text, 'bold fg:green bg:color_aqua')).Count -ge 1) "the segment background is reused"
Assert ($text -match '\$\{count\}') "git_status counts are numbered"
Assert ($text -match 'modified\s*=\s*"\[~\$\{count\}\]') "modified renders as ~N"
Assert ($text -match '\[time\]') "unrelated sections survive"
Assert ($text -match 'palettes\.gruvbox_dark') "the palette survives"
Write-Host ""

# --- Test 2: no duplicate tables --------------------------------------------
Write-Host "Test 2: git_branch / git_status are replaced, never duplicated" -ForegroundColor Yellow
# TOML rejects a duplicate table outright and Starship then falls back to its DEFAULT
# config - the prompt silently loses the whole preset. Appending instead of replacing
# is the easy mistake here, so this is the guard.
Assert (([regex]::Matches($text, '(?m)^\[git_branch\]')).Count -eq 1) "exactly one [git_branch] table"
Assert (([regex]::Matches($text, '(?m)^\[git_status\]')).Count -eq 1) "exactly one [git_status] table"
$dupes = ([regex]::Matches($text, '(?m)^\[([A-Za-z0-9_\.]+)\]') | ForEach-Object { $_.Groups[1].Value } |
    Group-Object | Where-Object { $_.Count -gt 1 })
Assert ($dupes.Count -eq 0) "no table name appears twice anywhere in the file"
Write-Host ""

# --- Test 3: idempotence and round trip -------------------------------------
Write-Host "Test 3: re-applying is a no-op, removing restores the preset" -ForegroundColor Yellow
Add-DevkitStarshipGitPanel -Path $path | Out-Null
Assert ((Get-Content -LiteralPath $path -Raw) -eq $text) "applying the panel twice produces identical text"

Assert (Remove-DevkitStarshipGitPanel -Path $path) "Remove-DevkitStarshipGitPanel returned true"
Assert (-not (Test-DevkitStarshipGitPanel -Path $path)) "the marker is gone"
$restored = Get-Content -LiteralPath $path -Raw
$normalise = { param($t) (($t -replace "`r`n", "`n") -split "`n" | Where-Object { $_.Trim() }) -join "`n" }
# Section ORDER changes on restore - the archived pair is re-appended at the end - but
# TOML does not care about order, so compare as a set of non-blank lines.
$diff = Compare-Object (& $normalise $powerline).Split("`n") (& $normalise $restored).Split("`n")
Assert ($null -eq $diff) "the restored config matches the original line for line"
Assert ($restored -match '\$git_branch') "`$git_branch is back in the format"
Write-Host ""

# --- Test 4: a config with no top-level format ------------------------------
Write-Host "Test 4: a config on Starship's `$all gets a format synthesised" -ForegroundColor Yellow
$path2 = New-Fixture 'symbols' $symbolsOnly
Assert (Add-DevkitStarshipGitPanel -Path $path2) "the panel applies with no format to edit"
$text2 = Get-Content -LiteralPath $path2 -Raw
# Naming only the modules needed to position the branch, rather than expanding $all,
# keeps the config from freezing Starship's module list at install time.
Assert ($text2 -match '(?m)^format = "\$username\$hostname\$directory\$\{env_var\.DEVKIT_GIT_CONFLICT\}') "a format is written that places the branch after the directory"
Assert ($text2 -match '\$all"') "everything else is left to `$all"
Assert ($text2 -match 'symbol = "git "') "the preset's own branch symbol is still used"
Assert ($text2 -match '\[aws\]') "unrelated sections survive"
Remove-DevkitStarshipGitPanel -Path $path2 | Out-Null
Assert ((Get-Content -LiteralPath $path2 -Raw) -notmatch '(?m)^format =') "removing the panel takes the synthesised format with it"
Write-Host ""

# --- Test 5: format with git_status but no git_branch ------------------------
Write-Host "Test 5: the branch lands before the git status when git_branch is absent" -ForegroundColor Yellow
$path3 = New-Fixture 'statusonly' $statusOnly
Assert (Add-DevkitStarshipGitPanel -Path $path3) "the panel applies"
$text3 = Get-Content -LiteralPath $path3 -Raw
Assert ($text3 -match '\$\{env_var\.DEVKIT_GIT_CLEAN\}\$git_status') "the refs are inserted immediately before `$git_status"
Write-Host ""

# --- Test 6: a format with nowhere to put the branch -------------------------
Write-Host "Test 6: a format with no git segment is declined, not mangled" -ForegroundColor Yellow
$path4 = New-Fixture 'nogit' $noGit
$before4 = Get-Content -LiteralPath $path4 -Raw
$result4 = Add-DevkitStarshipGitPanel -Path $path4 -WarningAction SilentlyContinue
Assert (-not $result4) "Add-DevkitStarshipGitPanel returns false"
Assert ((Get-Content -LiteralPath $path4 -Raw) -eq $before4) "the file is left exactly as it was"
Write-Host ""

# --- Test 7: Install-DevkitStarshipConfig honours -GitPanel ------------------
Write-Host "Test 7: the installer applies the panel only when asked" -ForegroundColor Yellow
Initialize-DevkitUserSpace | Out-Null
$script:StubPresetBody = $powerline

$dest = Install-DevkitStarshipConfig -Mode Fresh -Preset 'stub' -GitPanel $false
Assert ($dest -and (Test-Path $dest)) "the config is written with -GitPanel `$false"
Assert (-not (Test-DevkitStarshipGitPanel -Path $dest)) "no panel when -GitPanel is false"

$dest = Install-DevkitStarshipConfig -Mode Fresh -Preset 'stub' -GitPanel $true
Assert (Test-DevkitStarshipGitPanel -Path $dest) "the panel is applied when -GitPanel is true"

# Keep mode owns no file, so there is nothing to panel and nothing to record.
Assert ((Install-DevkitStarshipConfig -Mode Keep -GitPanel $true) -eq "") "Keep mode still returns empty with -GitPanel"
Write-Host ""

# --- Test 8: variables.ps1 gating -------------------------------------------
Write-Host "Test 8: DEVKIT_GIT_PANEL is written only when the panel exists" -ForegroundColor Yellow
$variablesPath = Join-Path $env:USERPROFILE '.devkit\variables.ps1'
Save-VariablesPs1 -Engine 'starship' -StarshipConfigPath $dest -GitPanel $true -SourceRoot $SourceRoot | Out-Null
Assert ((Get-Content $variablesPath -Raw) -match 'DEVKIT_GIT_PANEL = "1"') "the gate is written when the panel is on"

Save-VariablesPs1 -Engine 'starship' -StarshipConfigPath $dest -GitPanel $false -SourceRoot $SourceRoot | Out-Null
# Absent rather than "0": the profile's guard is a truthiness test, and paying for a
# git status per prompt that no module reads is the failure this prevents.
Assert ((Get-Content $variablesPath -Raw) -notmatch 'DEVKIT_GIT_PANEL') "the line is omitted entirely when the panel is off"
Write-Host ""

# --- Test 9: the profile template's half of the contract --------------------
Write-Host "Test 9: the profile hook matches the module names the panel writes" -ForegroundColor Yellow
$profileTemplate = Get-Content "$SourceRoot\configuration\powershell\Microsoft.PowerShell_profile.ps1" -Raw
$panelBlock = New-DevkitStarshipPanelBlock -Symbol 'x ' -Background ''

Assert ($profileTemplate -match 'function global:Invoke-Starship-PreCommand') "the hook is defined globally, so Starship's dynamic module can find it"
Assert ($profileTemplate -match 'if \(\$env:DEVKIT_GIT_PANEL\) \{ Enable-DevkitStarshipGitPanel \}') "the hook is installed only when the gate is set"
foreach ($state in @('CONFLICT', 'DIRTY', 'DIVERGED', 'CLEAN')) {
    # Both halves have to name the same variable. If they drift, the panel renders no
    # branch at all - worse than either half being missing.
    Assert ($panelBlock -match "\[env_var\.DEVKIT_GIT_$state\]") "the panel defines a module for DEVKIT_GIT_$state"
    Assert ($profileTemplate -match "env:DEVKIT_GIT_$state\s*=") "the profile classifier sets DEVKIT_GIT_$state"
}
Write-Host ""

# --- Test 10: the classifier against a real repository ----------------------
Write-Host "Test 10: the classifier reads real repository state" -ForegroundColor Yellow
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    "$SourceRoot\configuration\powershell\Microsoft.PowerShell_profile.ps1", [ref]$null, [ref]$errors)
$fn = $ast.FindAll({ param($n)
    $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $n.Name -eq 'Enable-DevkitStarshipGitPanel' }, $true) | Select-Object -First 1
Assert ($null -ne $fn) "Enable-DevkitStarshipGitPanel is present in the profile template"
Invoke-Expression $fn.Extent.Text
Enable-DevkitStarshipGitPanel

$repoDir = Join-Path $sandbox 'repo'
New-Item -Path $repoDir -ItemType Directory -Force | Out-Null
Push-Location $repoDir
try {
    $q = @('-c', 'user.email=t@t.t', '-c', 'user.name=t', '-c', 'commit.gpgsign=false')
    & git init -q -b main . 2>$null
    'one' | Out-File -Encoding ascii a.txt
    & git add a.txt 2>$null
    & git @q commit -qm init 2>$null

    Invoke-Starship-PreCommand
    Assert ($env:DEVKIT_GIT_CLEAN -eq 'main') "a clean repo with no upstream reads as CLEAN"

    'two' | Out-File -Encoding ascii a.txt
    Invoke-Starship-PreCommand
    Assert ($env:DEVKIT_GIT_DIRTY -eq 'main') "a modified working tree reads as DIRTY"
    Assert (-not $env:DEVKIT_GIT_CLEAN) "the other three variables are cleared each prompt"

    & git checkout -q -- . 2>$null
    $bare = Join-Path $sandbox 'origin.git'
    & git init -q --bare $bare 2>$null
    & git remote add origin $bare 2>$null
    & git push -q -u origin main 2>$null
    Invoke-Starship-PreCommand
    Assert ($env:DEVKIT_GIT_CLEAN -eq 'main') "clean and in step with upstream reads as CLEAN"

    'three' | Out-File -Encoding ascii b.txt
    & git add b.txt 2>$null
    & git @q commit -qm second 2>$null
    Invoke-Starship-PreCommand
    Assert ($env:DEVKIT_GIT_DIVERGED -eq 'main') "one commit ahead of upstream reads as DIVERGED"

    # A rebase conflict detaches HEAD, so this also covers the head-name lookup that
    # keeps the branch name in the prompt instead of a short SHA.
    & git checkout -q -b feature 2>$null
    'feature' | Out-File -Encoding ascii clash.txt
    & git add clash.txt 2>$null
    & git @q commit -qm feat 2>$null
    & git checkout -q main 2>$null
    'main' | Out-File -Encoding ascii clash.txt
    & git add clash.txt 2>$null
    & git @q commit -qm mainside 2>$null
    & git @q rebase feature 2>$null | Out-Null
    Invoke-Starship-PreCommand
    Assert ($env:DEVKIT_GIT_CONFLICT -eq 'main') "a rebase conflict reads as CONFLICT and keeps the branch name"
    & git rebase --abort 2>$null
} finally {
    Pop-Location
}

Set-Location $sandbox
Invoke-Starship-PreCommand
$anySet = @('CONFLICT', 'DIRTY', 'DIVERGED', 'CLEAN') |
    Where-Object { [Environment]::GetEnvironmentVariable("DEVKIT_GIT_$_") }
Assert ($anySet.Count -eq 0) "outside a repository nothing is set at all"
Write-Host ""

# --- Cleanup ----------------------------------------------------------------
Set-Location $PSScriptRoot
Remove-Item -Path $sandbox -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
if ($script:Failures -eq 0) {
    Write-Host "ALL STARSHIP GIT PANEL TESTS PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "$script:Failures assertion(s) failed." -ForegroundColor Red
    exit 1
}
