#Requires -Version 7.0
<#
.SYNOPSIS
    Sandboxed end-to-end test for the Claude Code + herdr install area.

.DESCRIPTION
    Redirects USERPROFILE / APPDATA / LOCALAPPDATA to a scratch sandbox so the
    real ~/.claude and %APPDATA%\herdr are never touched, then exercises the new
    installer functions: asset copies, the settings.json hook merge (fresh,
    idempotent, and merge-preserving), herdr config.toml pwsh discovery, and the
    pwsh-absent fallback.

.NOTES
    Run: pwsh -File test-claude-herdr.ps1
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
$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("devkit-claude-test-" + [guid]::NewGuid().ToString('N').Substring(0,8))
$env:USERPROFILE = Join-Path $sandbox "home"
$env:APPDATA = Join-Path $sandbox "appdata"
$env:LOCALAPPDATA = Join-Path $sandbox "localappdata"
New-Item -Path $env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA -ItemType Directory -Force | Out-Null

# $PROFILE is an automatic variable resolved at PowerShell startup from the Documents
# folder (often OneDrive-redirected). It is NOT derived from $env:USERPROFILE, so the
# redirect above does not contain code that reads or writes it. Override it explicitly.
$global:PROFILE = Join-Path $env:USERPROFILE "Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
New-Item -Path (Split-Path $global:PROFILE -Parent) -ItemType Directory -Force | Out-Null

Write-Host "Sandbox: $sandbox" -ForegroundColor Cyan
Write-Host "Source:  $SourceRoot" -ForegroundColor Cyan
Write-Host ""

. "$SourceRoot\configuration\lib\validators.ps1"
. "$SourceRoot\configuration\lib\backup.ps1"
. "$SourceRoot\configuration\lib\config-generator.ps1"
. "$SourceRoot\configuration\lib\config-loader.ps1"

$claudeRoot = Get-ClaudeUserRoot
$settingsPath = Join-Path $claudeRoot "settings.json"
$herdrConfig = Join-Path (Get-HerdrConfigRoot) "config.toml"

try {
    #region Test 1: Fresh install
    Write-Host "=== Test 1: Fresh install ===" -ForegroundColor Yellow
    $agents = Copy-DevkitClaudeAgents -SourceRoot $SourceRoot
    $skills = Copy-DevkitClaudeSkills -SourceRoot $SourceRoot
    $commands = Copy-DevkitClaudeCommands -SourceRoot $SourceRoot
    # -Force: this test asserts a deterministic install, and without it a CLAUDE.md
    # that has drifted from the bundled copy is deliberately left alone.
    $mdOk = Copy-DevkitClaudeMd -SourceRoot $SourceRoot -Force
    $hookOk = Install-HerdrHookAndSettings -SourceRoot $SourceRoot
    $herdrOk = Save-HerdrConfig -SourceRoot $SourceRoot

    Assert ($agents -and (Test-Path (Join-Path $claudeRoot "agents\architect.md"))) "agents installed"
    Assert ($skills -and (Test-Path (Join-Path $claudeRoot "skills\herdr\scripts\herd.sh"))) "skills installed (herd.sh present)"
    Assert ($commands -and (Test-Path (Join-Path $claudeRoot "commands\create-spec.md"))) "commands installed"
    Assert ($mdOk -and (Test-Path (Join-Path $claudeRoot "CLAUDE.md"))) "CLAUDE.md installed"
    Assert $hookOk "Install-HerdrHookAndSettings returned true"
    Assert (Test-Path (Join-Path $claudeRoot "hooks\herdr-agent-state.ps1")) "herdr hook file installed"
    Assert $herdrOk "Save-HerdrConfig returned true"

    # herd.sh must remain LF
    $herdRaw = Get-Content -Raw (Join-Path $claudeRoot "skills\herdr\scripts\herd.sh")
    Assert ($herdRaw -notmatch "`r") "herd.sh has no CR bytes (LF preserved)"

    # CLAUDE.md must not carry the dropped policy
    $mdRaw = Get-Content -Raw (Join-Path $claudeRoot "CLAUDE.md")
    Assert ($mdRaw -notmatch "Build and Test Policy") "CLAUDE.md has no 'Build and Test Policy'"

    # settings.json valid + single herdr hook pointing at the sandbox
    Assert (Test-Path $settingsPath) "settings.json created"
    $settings = Get-Content -Raw $settingsPath | ConvertFrom-Json -AsHashtable -Depth 20
    $herdrHooks = @($settings.hooks.SessionStart | Where-Object {
        @($_.hooks).command -match 'herdr-agent-state\.ps1'
    })
    Assert ($herdrHooks.Count -eq 1) "exactly one herdr SessionStart entry"
    $cmd = @($herdrHooks[0].hooks)[0].command
    Assert ($cmd -match [regex]::Escape($claudeRoot)) "hook -File path points into sandbox ~/.claude"
    # The backup's hardcoded absolute hook path (distinct from the sandbox one).
    $staleHook = 'C:\Users\mgpet\.claude\hooks\herdr-agent-state.ps1'
    Assert ($cmd -notmatch [regex]::Escape($staleHook)) "hook path is not the hardcoded backup path"

    # herdr config.toml default_shell = discovered pwsh path
    $pwsh = Test-PwshAvailable
    $tomlRaw = Get-Content -Raw $herdrConfig
    if ($pwsh.Found) {
        Assert ($tomlRaw -match "default_shell = '" + [regex]::Escape($pwsh.Path) + "'") "config.toml default_shell = discovered pwsh ($($pwsh.Source))"
    } else {
        Assert ($tomlRaw -notmatch '__PWSH_PATH__') "config.toml token replaced even without pwsh"
    }
    Assert ($tomlRaw -notmatch '__PWSH_PATH__') "config.toml has no leftover token"
    Write-Host ""
    #endregion

    #region Test 2: Idempotency
    Write-Host "=== Test 2: Idempotency (re-run) ===" -ForegroundColor Yellow
    Install-HerdrHookAndSettings -SourceRoot $SourceRoot | Out-Null
    Save-HerdrConfig -SourceRoot $SourceRoot | Out-Null
    $settings2 = Get-Content -Raw $settingsPath | ConvertFrom-Json -AsHashtable -Depth 20
    $herdrHooks2 = @($settings2.hooks.SessionStart | Where-Object {
        @($_.hooks).command -match 'herdr-agent-state\.ps1'
    })
    Assert ($herdrHooks2.Count -eq 1) "still exactly one herdr SessionStart entry after re-run"
    Write-Host ""
    #endregion

    #region Test 3: Merge preservation + self-heal of stale path
    Write-Host "=== Test 3: Merge preservation ===" -ForegroundColor Yellow
    $preSeed = @'
{
  "env": { "DISABLE_AUTOUPDATER": "1" },
  "model": "opus[1m]",
  "hooks": {
    "SessionStart": [
      { "matcher": "*", "hooks": [ { "type": "command", "command": "powershell -File \"C:\\Users\\mgpet\\.claude\\hooks\\herdr-agent-state.ps1\" session", "timeout": 10 } ] }
    ]
  },
  "enabledPlugins": { "context7@claude-plugins-official": true },
  "alwaysThinkingEnabled": true
}
'@
    Set-Content -Path $settingsPath -Value $preSeed -Encoding UTF8 -Force
    Install-HerdrHookAndSettings -SourceRoot $SourceRoot | Out-Null
    $settings3 = Get-Content -Raw $settingsPath | ConvertFrom-Json -AsHashtable -Depth 20

    Assert ($settings3.model -eq 'opus[1m]') "model preserved"
    Assert ($settings3.env.DISABLE_AUTOUPDATER -eq '1') "env preserved"
    Assert ($settings3.enabledPlugins['context7@claude-plugins-official'] -eq $true) "enabledPlugins preserved"
    Assert ($settings3.alwaysThinkingEnabled -eq $true) "alwaysThinkingEnabled preserved"
    $herdrHooks3 = @($settings3.hooks.SessionStart | Where-Object {
        @($_.hooks).command -match 'herdr-agent-state\.ps1'
    })
    Assert ($herdrHooks3.Count -eq 1) "stale herdr entry replaced (not duplicated)"
    $cmd3 = @($herdrHooks3[0].hooks)[0].command
    $staleHook3 = 'C:\Users\mgpet\.claude\hooks\herdr-agent-state.ps1'
    Assert ($cmd3 -notmatch [regex]::Escape($staleHook3)) "stale backup hook path healed to current user"
    Assert ($cmd3 -match [regex]::Escape($claudeRoot)) "healed hook path points into sandbox ~/.claude"
    Write-Host ""
    #endregion

    #region Test 4: pwsh-absent fallback
    Write-Host "=== Test 4: pwsh-absent fallback ===" -ForegroundColor Yellow
    # Shadow the detector so it reports not-found for this sub-test only.
    function Test-PwshAvailable { @{ Found = $false; Version = $null; Path = $null; Source = $null } }
    Remove-Item $herdrConfig -Force -ErrorAction SilentlyContinue
    $r = Save-HerdrConfig -SourceRoot $SourceRoot 3>$null
    Assert $r "Save-HerdrConfig still succeeds without pwsh"
    $tomlNoPwsh = Get-Content -Raw $herdrConfig
    Assert ($tomlNoPwsh -notmatch "(?m)^\s*default_shell\s*=\s*'") "default_shell omitted when pwsh not found"
    Assert ($tomlNoPwsh -match 'pwsh not detected') "explanatory comment left in place of default_shell"
    Write-Host ""
    #endregion

    #region Test 5: config-loader detection
    Write-Host "=== Test 5: config-loader detection ===" -ForegroundColor Yellow
    $det = Get-ExistingClaudeConfig
    Assert $det.Found "detector: ~/.claude found"
    Assert $det.ClaudeMdFound "detector: CLAUDE.md found"
    Assert $det.SettingsFound "detector: settings.json found"
    Assert $det.HerdrHookPresent "detector: herdr hook present in settings"
    Assert $det.HerdrConfigFound "detector: herdr config.toml found"
    Write-Host ""
    #endregion

} finally {
    # Clean up the sandbox
    Remove-Item -Path $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
if ($script:Failures -eq 0) {
    Write-Host "ALL CLAUDE/HERDR TESTS PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "$($script:Failures) ASSERTION(S) FAILED" -ForegroundColor Red
    exit 1
}
