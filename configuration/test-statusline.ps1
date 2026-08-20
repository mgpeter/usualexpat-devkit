#Requires -Version 7.0
<#
.SYNOPSIS
    Sandboxed test for the Claude Code statusline install area.

.DESCRIPTION
    Redirects USERPROFILE / APPDATA / LOCALAPPDATA to a scratch sandbox so the real
    ~/.claude is never touched, then exercises Install-ClaudeStatusLine and friends:
    fresh install (including the UTF-8 BOM), idempotency, sibling preservation in
    settings.json, both settings writers commuting, size changes, Keep mode, offline
    degradation, detection, and removal.

    The network is never touched: Get-AwesomeStatusLineSource is shadowed right after
    the libs are dot-sourced. That seam is the reason Install-ClaudeStatusLine calls
    the fetch by name rather than inlining Invoke-WebRequest - if this file ever needs
    real network access, the seam has regressed.

.NOTES
    Run: pwsh -File test-statusline.ps1
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
$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("devkit-statusline-test-" + [guid]::NewGuid().ToString('N').Substring(0,8))
$env:USERPROFILE = Join-Path $sandbox "home"
$env:APPDATA = Join-Path $sandbox "appdata"
$env:LOCALAPPDATA = Join-Path $sandbox "localappdata"
New-Item -Path $env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA -ItemType Directory -Force | Out-Null

# A stale override from the caller's shell would defeat the stub below.
$env:DEVKIT_STATUSLINE_SOURCE = $null

Write-Host "Sandbox: $sandbox" -ForegroundColor Cyan
Write-Host "Source:  $SourceRoot" -ForegroundColor Cyan
Write-Host ""

. "$SourceRoot\configuration\lib\validators.ps1"
. "$SourceRoot\configuration\lib\backup.ps1"
. "$SourceRoot\configuration\lib\config-generator.ps1"
. "$SourceRoot\configuration\lib\config-loader.ps1"

# --- Network stub -----------------------------------------------------------
# Padded past the >1000-character sanity gate in the real implementation.
$script:FakeRenderer = @'
param([string]$Size = 'large')
$in = [Console]::In.ReadToEnd()
Write-Host "fake statusline $Size"
'@ + ("`n# filler line to clear the length sanity gate" * 40)

$script:FetchSucceeds = $true
function Get-AwesomeStatusLineSource {
    param([string]$RawBaseUrl = '', [string]$Ref = 'main')
    if (-not $script:FetchSucceeds) {
        return @{ Success = $false; Content = ''; Source = ''; Error = 'simulated offline' }
    }
    # Upstream ships the renderer with a BOM and Invoke-WebRequest hands it back as a
    # literal U+FEFF character, so the stub reproduces that. Get-AwesomeStatusLineSource
    # is responsible for stripping it; the real implementation is shadowed here, so the
    # double-BOM assertion below tests the WRITER against a realistically-shaped input.
    return @{ Success = $true; Content = ([char]0xFEFF + $script:FakeRenderer); Source = 'stub'; Error = '' }
}

$claudeRoot = Get-ClaudeUserRoot
$settingsPath = Join-Path $claudeRoot "settings.json"
$rendererPath = Get-ClaudeStatusLinePath
$backupRoot = Join-Path $env:USERPROFILE ".devkit\backups"

function Get-Settings { Get-Content $settingsPath -Raw | ConvertFrom-Json -AsHashtable -Depth 20 }

try {
    #region Test 1: Fresh install
    Write-Host "=== Test 1: Fresh install ===" -ForegroundColor Yellow
    $ok = Install-ClaudeStatusLine -Size small -Mode Fresh
    Assert $ok "Install-ClaudeStatusLine returned true"
    Assert (Test-Path $rendererPath) "renderer written to ~/.claude"

    $bytes = Get-Content -Path $rendererPath -AsByteStream -TotalCount 6
    Assert ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) "renderer carries a UTF-8 BOM"
    # Regression: upstream's body arrives WITH a literal U+FEFF, and the writer adds a
    # BOM of its own. Failing to strip one produces EF BB BF EF BB BF.
    Assert (-not ($bytes[3] -eq 0xEF -and $bytes[4] -eq 0xBB -and $bytes[5] -eq 0xBF)) "renderer has a single BOM, not a double BOM"

    # On-disk size must be exactly BOM + the body, with no stray leading character.
    $expectedBytes = 3 + [System.Text.Encoding]::UTF8.GetByteCount($script:FakeRenderer)
    Assert ((Get-Item $rendererPath).Length -eq $expectedBytes) "renderer byte length is BOM + body exactly"

    $s = Get-Settings
    Assert ($s.statusLine.type -eq 'command') "statusLine.type is command"
    Assert ($s.statusLine.command -match '-Size small') "command carries -Size small"
    Assert ($s.statusLine.command -match 'awesome-statusline\.ps1') "command points at the renderer"

    # The -File argument must use forward slashes (matches upstream, avoids JSON escapes)
    $fileArg = if ($s.statusLine.command -match '-File\s+"([^"]+)"') { $Matches[1] } else { '' }
    Assert ($fileArg -and $fileArg -notmatch '\\') "-File path uses forward slashes only"
    Write-Host ""
    #endregion

    #region Test 2: Idempotency
    Write-Host "=== Test 2: Idempotency ===" -ForegroundColor Yellow
    $firstCommand = (Get-Settings).statusLine.command
    $firstContent = Get-Content $rendererPath -Raw

    $ok2 = Install-ClaudeStatusLine -Size small -Mode Fresh
    Assert $ok2 "second install returned true"

    $s = Get-Settings
    Assert ($s.statusLine.command -ceq $firstCommand) "statusLine command unchanged on re-run"
    Assert ((Get-Content $rendererPath -Raw) -ceq $firstContent) "renderer content unchanged on re-run"
    Assert ($s.statusLine -isnot [array]) "statusLine is a single object, not duplicated"
    Assert ((Get-ChildItem $backupRoot -Filter 'claude-settings_*').Count -ge 1) "settings.json was backed up"
    Write-Host ""
    #endregion

    #region Test 3: Sibling preservation (headline regression test)
    Write-Host "=== Test 3: Sibling preservation ===" -ForegroundColor Yellow
    $seed = @{
        model = 'opus[1m]'
        env = @{ DISABLE_AUTOUPDATER = '1' }
        alwaysThinkingEnabled = $true
        enabledPlugins = @{ 'context7@claude-plugins-official' = $true }
        extraKnownMarketplaces = @{ gitkraken = @{ source = @{ source = 'directory'; path = 'C:\x' } } }
        hooks = @{
            PreToolUse = @(@{ matcher = '*'; hooks = @(@{ type = 'command'; command = 'orca-hook.cmd'; timeout = 10 }) })
        }
    }
    $seed | ConvertTo-Json -Depth 20 | Set-Content -Path $settingsPath -Encoding UTF8 -Force

    $hookOk = Install-HerdrHookAndSettings -SourceRoot $SourceRoot
    $slOk = Install-ClaudeStatusLine -Size medium -Mode Fresh
    Assert $hookOk "herdr hook install returned true"
    Assert $slOk "statusline install returned true"

    $s = Get-Settings
    Assert ($s.model -eq 'opus[1m]') "model preserved"
    Assert ($s.env.DISABLE_AUTOUPDATER -eq '1') "env preserved"
    Assert ($s.alwaysThinkingEnabled -eq $true) "alwaysThinkingEnabled preserved"
    Assert ($s.enabledPlugins.'context7@claude-plugins-official' -eq $true) "enabledPlugins preserved"
    Assert ($s.extraKnownMarketplaces.gitkraken.source.path -eq 'C:\x') "extraKnownMarketplaces preserved"
    Assert (@($s.hooks.PreToolUse).Count -eq 1) "unrelated Orca hook family preserved"
    $herdrGroups = @($s.hooks.SessionStart | Where-Object { @($_.hooks).command -match 'herdr-agent-state' })
    Assert ($herdrGroups.Count -eq 1) "herdr SessionStart hook present exactly once"
    Assert ($s.statusLine.command -match '-Size medium') "statusLine set alongside everything else"
    Write-Host ""
    #endregion

    #region Test 4: Reverse order - the two settings writers commute
    Write-Host "=== Test 4: Reverse write order ===" -ForegroundColor Yellow
    Remove-Item $settingsPath -Force -ErrorAction SilentlyContinue
    $slOk = Install-ClaudeStatusLine -Size large -Mode Fresh
    $hookOk = Install-HerdrHookAndSettings -SourceRoot $SourceRoot
    Assert ($slOk -and $hookOk) "both writers returned true"

    $s = Get-Settings
    Assert ($s.statusLine.command -match '-Size large') "statusLine survived the herdr writer's round-trip"
    Assert (@($s.hooks.SessionStart | Where-Object { @($_.hooks).command -match 'herdr-agent-state' }).Count -eq 1) "herdr hook still wired once"
    Write-Host ""
    #endregion

    #region Test 5: Size change without download
    Write-Host "=== Test 5: Size change ===" -ForegroundColor Yellow
    $before = Get-Content $rendererPath -Raw
    $ok = Set-ClaudeStatusLineSetting -RendererPath $rendererPath -Size xlarge
    Assert $ok "Set-ClaudeStatusLineSetting returned true"
    Assert ((Get-Settings).statusLine.command -match '-Size xlarge') "size rewired to xlarge"
    Assert ((Get-Content $rendererPath -Raw) -ceq $before) "renderer untouched by a size change"
    Write-Host ""
    #endregion

    #region Test 6: Keep mode leaves a customized renderer alone
    Write-Host "=== Test 6: Keep mode ===" -ForegroundColor Yellow
    $sentinel = "# LOCAL SENTINEL - must survive Keep mode`n" + $script:FakeRenderer
    [System.IO.File]::WriteAllText($rendererPath, $sentinel, (New-Object System.Text.UTF8Encoding($true)))

    $ok = Install-ClaudeStatusLine -Size small -Mode Keep
    Assert $ok "Keep mode returned true"
    Assert ((Get-Content $rendererPath -Raw) -match 'LOCAL SENTINEL') "Keep mode did not overwrite the renderer"
    Assert ((Get-Settings).statusLine.command -match '-Size small') "Keep mode still rewired the size"
    Write-Host ""
    #endregion

    #region Test 7: Offline degradation
    Write-Host "=== Test 7: Offline degradation ===" -ForegroundColor Yellow
    $script:FetchSucceeds = $false

    # (a) renderer already on disk: wire against it and succeed
    $ok = Install-ClaudeStatusLine -Size medium -Mode Fresh -WarningAction SilentlyContinue
    Assert $ok "offline with an existing renderer still returns true"
    Assert ((Get-Content $rendererPath -Raw) -match 'LOCAL SENTINEL') "offline fallback did not destroy the existing renderer"
    Assert ((Get-Settings).statusLine.command -match '-Size medium') "offline fallback rewired against the existing renderer"

    # (b) no renderer at all: refuse to wire a path that does not exist
    Remove-Item $rendererPath -Force
    Remove-Item $settingsPath -Force -ErrorAction SilentlyContinue
    $ok = Install-ClaudeStatusLine -Size small -Mode Fresh -WarningAction SilentlyContinue
    Assert (-not $ok) "offline with no renderer returns false"
    $wroteStatusLine = (Test-Path $settingsPath) -and ((Get-Settings).ContainsKey('statusLine'))
    Assert (-not $wroteStatusLine) "offline with no renderer leaves statusLine unwritten"

    $script:FetchSucceeds = $true
    Write-Host ""
    #endregion

    #region Test 8: config-loader detection
    Write-Host "=== Test 8: Detection ===" -ForegroundColor Yellow
    Install-ClaudeStatusLine -Size medium -Mode Fresh | Out-Null
    $det = Get-ExistingClaudeConfig
    Assert $det.StatusLineScriptFound "detector: renderer found"
    Assert $det.StatusLineWired "detector: statusLine wired"
    Assert ($det.StatusLineSize -eq 'medium') "detector: size reported as medium"

    $state = Test-ClaudeStatusLinePresent
    Assert $state.ScriptFound "Test-ClaudeStatusLinePresent: script found"
    Assert $state.SettingWired "Test-ClaudeStatusLinePresent: setting wired"
    Assert ($state.Size -eq 'medium') "Test-ClaudeStatusLinePresent: size medium"
    Assert $state.ScriptPathResolves "Test-ClaudeStatusLinePresent: wired path resolves"
    Write-Host ""
    #endregion

    #region Test 9: Removal
    Write-Host "=== Test 9: Removal ===" -ForegroundColor Yellow
    # Re-seed siblings so we can prove removal is surgical. Test 7b deleted
    # settings.json, so hooks has to be put back explicitly to be worth asserting on.
    Install-HerdrHookAndSettings -SourceRoot $SourceRoot | Out-Null
    $s = Get-Settings
    $s['model'] = 'opus[1m]'
    $s | ConvertTo-Json -Depth 20 | Set-Content -Path $settingsPath -Encoding UTF8 -Force
    Assert ($s.ContainsKey('hooks')) "precondition: hooks present before removal"

    $ok = Remove-ClaudeStatusLine
    Assert $ok "Remove-ClaudeStatusLine returned true"
    $s = Get-Settings
    Assert (-not $s.ContainsKey('statusLine')) "statusLine key removed"
    Assert ($s.model -eq 'opus[1m]') "unrelated keys preserved by removal"
    Assert ($s.ContainsKey('hooks')) "hooks preserved by removal"
    Assert (-not (Test-Path $rendererPath)) "renderer deleted"
    Assert ((Get-ChildItem $backupRoot -Filter 'claude-statusline_*').Count -ge 1) "renderer was backed up before deletion"

    # -KeepRenderer leaves the file in place
    Install-ClaudeStatusLine -Size small -Mode Fresh | Out-Null
    $ok = Remove-ClaudeStatusLine -KeepRenderer
    Assert ($ok -and (Test-Path $rendererPath)) "-KeepRenderer leaves the renderer on disk"
    Assert (-not (Get-Settings).ContainsKey('statusLine')) "-KeepRenderer still unwires settings.json"
    Write-Host ""
    #endregion

    #region Test 10a: BOM-character stripping
    Write-Host "=== Test 10a: BOM stripping ===" -ForegroundColor Yellow
    $withBom = [char]0xFEFF + 'abc'
    Assert ((Remove-Utf8BomChar $withBom) -ceq 'abc') "Remove-Utf8BomChar strips a leading U+FEFF"
    Assert ((Remove-Utf8BomChar 'abc') -ceq 'abc') "Remove-Utf8BomChar leaves clean text alone"
    Assert ((Remove-Utf8BomChar '') -ceq '') "Remove-Utf8BomChar tolerates empty input"
    Assert ((Remove-Utf8BomChar ('a' + [char]0xFEFF)) -ceq ('a' + [char]0xFEFF)) "Remove-Utf8BomChar only strips at position 0"
    Write-Host ""
    #endregion

    #region Test 10: Backup prefixes stay disjoint
    Write-Host "=== Test 10: Backup prefix disjointness ===" -ForegroundColor Yellow
    # Remove-OldBackups filters with -Filter "<type>_*", which honours only * and ?.
    # If that ever changed, a "claude" cleanup pass would start eating claude-statusline
    # backups, so pin the assumption here.
    $probe = Join-Path $sandbox 'filter-probe'
    New-Item -ItemType Directory -Force -Path $probe | Out-Null
    'claude_x', 'claude-md_x', 'claude-settings_x', 'claude-statusline_x' | ForEach-Object {
        New-Item -ItemType File -Path (Join-Path $probe $_) -Force | Out-Null
    }
    $claudeOnly = @(Get-ChildItem $probe -Filter 'claude_*')
    Assert ($claudeOnly.Count -eq 1 -and $claudeOnly[0].Name -eq 'claude_x') "'claude_*' does not match the hyphenated prefixes"
    Assert (@(Get-ChildItem $probe -Filter 'claude-statusline_*').Count -eq 1) "'claude-statusline_*' matches only its own backups"
    Write-Host ""
    #endregion

} finally {
    # Clean up the sandbox
    Remove-Item -Path $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
if ($script:Failures -eq 0) {
    Write-Host "ALL STATUSLINE TESTS PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "$($script:Failures) ASSERTION(S) FAILED" -ForegroundColor Red
    exit 1
}
