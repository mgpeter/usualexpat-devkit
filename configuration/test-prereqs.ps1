#Requires -Version 7.0
<#
.SYNOPSIS
    Sandboxed test for the prerequisite detection and installation area.

.DESCRIPTION
    Redirects USERPROFILE / APPDATA / LOCALAPPDATA to a scratch sandbox, then exercises
    the catalogue, the detection helpers and Install-Prerequisites.

    NOTHING IS EVER REALLY INSTALLED. Every external-installer seam is shadowed right
    after the libs are dot-sourced, with call-recording arrays so the tests can assert
    that a seam was or was not reached. That shadowing is the whole reason
    Install-Prerequisites calls Invoke-WingetInstall / Invoke-RemoteScriptInstall /
    Invoke-OhMyPoshFontInstall BY NAME instead of inlining them - if this file ever
    starts needing the network or a package manager, that seam has regressed.

.NOTES
    Run: pwsh -File test-prereqs.ps1
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

$sandbox = Join-Path ([System.IO.Path]::GetTempPath()) ("devkit-prereqs-test-" + [guid]::NewGuid().ToString('N').Substring(0,8))
$env:USERPROFILE = Join-Path $sandbox "home"
$env:APPDATA = Join-Path $sandbox "appdata"
$env:LOCALAPPDATA = Join-Path $sandbox "localappdata"
New-Item -Path $env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA -ItemType Directory -Force | Out-Null

Write-Host "Sandbox: $sandbox" -ForegroundColor Cyan
Write-Host "Source:  $SourceRoot" -ForegroundColor Cyan
Write-Host ""

. "$SourceRoot\configuration\lib\validators.ps1"
. "$SourceRoot\configuration\lib\backup.ps1"
. "$SourceRoot\configuration\lib\config-generator.ps1"

try {
    #region Test 1: Catalogue integrity
    Write-Host "=== Test 1: Catalogue integrity ===" -ForegroundColor Yellow
    $catalog = Get-DevkitPrerequisites
    Assert ($catalog.Count -ge 9) "catalogue has rows ($($catalog.Count))"

    $keys = @($catalog | ForEach-Object { $_.Key })
    Assert (($keys | Sort-Object -Unique).Count -eq $keys.Count) "keys are unique"
    Assert (@($keys | Where-Object { $_ -cne $_.ToLower() }).Count -eq 0) "keys are lowercase"

    $validMechanisms = @('winget', 'remote-script', 'omp-font', 'psgallery')
    Assert (@($catalog | Where-Object { $validMechanisms -notcontains $_.Mechanism }).Count -eq 0) "every Mechanism is valid"
    Assert (@($catalog | Where-Object { $_.Tier -notin @('Required','Optional') }).Count -eq 0) "every Tier is valid"
    Assert (@($catalog | Where-Object { -not $_.Name -or -not $_.InstallHint }).Count -eq 0) "every row has Name and InstallHint"
    Assert (@($catalog | Where-Object { $_.Mechanism -eq 'winget' -and -not $_.WingetId }).Count -eq 0) "every winget row has a WingetId"

    # Elevation drives the "this will raise a UAC prompt" notice in the wizard step and
    # in `devkit prereqs install`. A row with no classification would be silently
    # reported as user-scope, which is the wrong way round to be wrong.
    Assert (@($catalog | Where-Object { $_.Elevation -notin @('machine','user') }).Count -eq 0) "every row has a valid Elevation"
    Assert ((@($catalog | Where-Object { $_.Elevation -eq 'machine' }).Count) -gt 0) "at least one row installs machine-wide"
    Assert ((@($catalog | Where-Object { $_.Elevation -eq 'user' }).Count) -gt 0) "at least one row installs per-user"

    # Encodes the security decision: a row that downloads and runs a remote script must
    # never be emphasised for default selection.
    $remote = @($catalog | Where-Object { $_.Mechanism -eq 'remote-script' })
    Assert (@($remote | Where-Object { -not $_.ScriptUrl }).Count -eq 0) "every remote-script row has a ScriptUrl"
    Assert (@($remote | Where-Object { $_.PreSelect }).Count -eq 0) "no remote-script row is pre-selected"
    Assert (@($remote | Where-Object { $_.ScriptUrl -notmatch '^https://' }).Count -eq 0) "remote-script URLs are HTTPS"

    foreach ($row in $catalog) {
        foreach ($dep in @($row.DependsOn)) {
            Assert ($keys -contains $dep) "DependsOn '$dep' on $($row.Key) names a real key"
        }
    }
    Write-Host ""
    #endregion

    #region Test 1b: Elevation classification
    Write-Host "=== Test 1b: Elevation classification ===" -ForegroundColor Yellow

    # Test-DevkitElevated answers about the current process, so the value depends on how
    # the suite was launched. What must hold either way is that it answers at all.
    $elevated = Test-DevkitElevated
    Assert ($elevated -is [bool]) "Test-DevkitElevated returns a boolean (got: $elevated)"

    # Anchored on where these packages actually land: Git and Neovim go to Program Files,
    # glow and oh-my-posh to %LOCALAPPDATA%. Getting this backwards would tell an
    # unelevated user their Git install needs no UAC prompt.
    $split = Get-ElevationSplit -Keys @('git', 'neovim', 'glow', 'oh-my-posh') -Catalog $catalog
    Assert ($split.Machine -contains 'Git') "git is classified machine-wide"
    Assert ($split.Machine -contains 'Neovim') "neovim is classified machine-wide"
    Assert ($split.User -contains 'glow') "glow is classified per-user"
    Assert ($split.User -contains 'Oh My Posh') "oh-my-posh is classified per-user"
    Assert ($split.Machine.Count -eq 2 -and $split.User.Count -eq 2) "every selected key lands on exactly one side"

    $empty = Get-ElevationSplit -Keys @() -Catalog $catalog
    Assert ($empty.Machine.Count -eq 0 -and $empty.User.Count -eq 0) "an empty selection splits into nothing"

    # An unknown key is dropped rather than guessed at - guessing 'user' would suppress
    # a warning the user needed.
    $unknown = Get-ElevationSplit -Keys @('not-a-real-tool') -Catalog $catalog
    Assert ($unknown.Machine.Count -eq 0 -and $unknown.User.Count -eq 0) "an unknown key is ignored, not guessed"
    Write-Host ""
    #endregion

    #region Test 2: Test-CommandAvailable (before it is shadowed)
    Write-Host "=== Test 2: Test-CommandAvailable ===" -ForegroundColor Yellow
    $real = Test-CommandAvailable -Name 'pwsh' -VersionArgs @('--version') -VersionPattern 'PowerShell ([\d\.]+)'
    Assert $real.Found "finds a real command (pwsh)"
    Assert ($real.Source -eq 'PATH') "reports Source = PATH"
    Assert ($real.Version -match '^\d') "parses a version"

    $missing = Test-CommandAvailable -Name ("nope-" + [guid]::NewGuid().ToString('N'))
    Assert (-not $missing.Found) "misses a nonexistent command"
    Assert ($null -eq $missing.Source) "Source is null when not found"

    # The fallback path is what makes a just-installed tool resolve before PATH updates.
    $fake = Join-Path $sandbox 'fake-tool.exe'
    Set-Content -Path $fake -Value 'x' -Encoding UTF8
    $viaFallback = Test-CommandAvailable -Name ("nope-" + [guid]::NewGuid().ToString('N')) -VersionArgs @() -FallbackPaths @($fake)
    Assert $viaFallback.Found "finds a command via FallbackPaths"
    Assert ($viaFallback.Source -eq 'fallback-path') "reports Source = fallback-path"

    # Env vars in fallback paths must expand at call time so the sandbox is honoured.
    $expandable = Test-CommandAvailable -Name ("nope-" + [guid]::NewGuid().ToString('N')) -VersionArgs @() -FallbackPaths @('%USERPROFILE%\..\fake-tool.exe')
    Assert ($expandable -is [hashtable]) "expandable fallback path does not throw"

    # Presence-only probes must NOT run the binary: glow/nvim/oh-my-posh open an
    # interactive UI with no arguments and would hang forever.
    $noProbe = Test-CommandAvailable -Name 'pwsh' -VersionArgs @()
    Assert ($noProbe.Found -and $null -eq $noProbe.Version) "empty VersionArgs skips the version probe entirely"
    Write-Host ""
    #endregion

    #region Test 3: Existing detector wrappers still honour their contract
    Write-Host "=== Test 3: Wrapper regression guard ===" -ForegroundColor Yellow
    foreach ($fn in @('Test-NeovimAvailable', 'Test-PwshAvailable', 'Test-ClaudeCodeAvailable')) {
        $cmd = Get-Command $fn -ErrorAction SilentlyContinue
        Assert ($null -ne $cmd) "$fn still exists"
    }
    $pwshState = Test-PwshAvailable
    Assert ($pwshState.ContainsKey('Found') -and $pwshState.ContainsKey('Version') -and $pwshState.ContainsKey('Path') -and $pwshState.ContainsKey('Source')) "Test-PwshAvailable keeps Found/Version/Path/Source"
    $nvimState = Test-NeovimAvailable
    Assert ($nvimState.ContainsKey('Found') -and $nvimState.ContainsKey('Version') -and $nvimState.ContainsKey('Path')) "Test-NeovimAvailable keeps Found/Version/Path"
    Write-Host ""
    #endregion

    #region Seam shadowing - nothing below this point installs anything
    $script:WingetCalls = @()
    $script:RemoteCalls = @()
    $script:FontCalls = @()
    $script:WingetPresent = $true
    $script:FakeInstalled = @{}          # command name -> $true once "installed"
    $script:FakeFontStrong = $false
    $script:SeamResult = @{}             # package id -> result override

    function Test-WingetAvailable {
        return @{ Found = $script:WingetPresent; Version = '1.9.0'; Path = 'stub-winget' }
    }
    function Test-CommandAvailable {
        param([string]$Name, [string[]]$VersionArgs = @(), [string]$VersionPattern = '', [string[]]$FallbackPaths = @())
        $found = [bool]$script:FakeInstalled[$Name]
        return @{ Found = $found; Version = $(if ($found) { '1.0' } else { $null }); Path = $(if ($found) { "stub-$Name" } else { $null }); Source = $(if ($found) { 'PATH' } else { $null }) }
    }
    function Test-NerdFontInstalled {
        param([string]$Family = '')
        if ($script:FakeFontStrong) { return @{ Found = $true; Confidence = 'strong'; Families = @('MesloLGS NF'); Source = 'stub'; Paths = @() } }
        return @{ Found = $false; Confidence = 'none'; Families = @(); Source = $null; Paths = @() }
    }
    function Invoke-WingetInstall {
        param([string]$PackageId, [string[]]$ExtraArgs = @())
        $script:WingetCalls += $PackageId
        if ($script:SeamResult.ContainsKey($PackageId)) { return $script:SeamResult[$PackageId] }
        $script:FakeInstalled[$script:PackageToCommand[$PackageId]] = $true
        return @{ Success = $true; ExitCode = 0; Output = ''; Command = "stub winget install $PackageId" }
    }
    function Invoke-RemoteScriptInstall {
        param([string]$Url, [string]$Name = '')
        $script:RemoteCalls += $Url
        return @{ Success = $false; ExitCode = 1; Output = 'this must not run in tests'; Command = "stub $Url" }
    }
    function Invoke-OhMyPoshFontInstall {
        param([string]$FontName = 'meslo')
        $script:FontCalls += $FontName
        if ($script:SeamResult.ContainsKey("font:$FontName")) { return $script:SeamResult["font:$FontName"] }
        return @{ Success = $true; ExitCode = 0; Output = ''; Command = "stub oh-my-posh font install $FontName" }
    }

    $script:PackageToCommand = @{}
    foreach ($row in $catalog) {
        if ($row.WingetId) { $script:PackageToCommand[$row.WingetId] = $row.Command }
    }

    function Reset-Stubs {
        $script:WingetCalls = @(); $script:RemoteCalls = @(); $script:FontCalls = @()
        $script:WingetPresent = $true; $script:FakeInstalled = @{}
        $script:FakeFontStrong = $false; $script:SeamResult = @{}
    }
    #endregion

    #region Test 4: Idempotent skip
    Write-Host "=== Test 4: Idempotent skip ===" -ForegroundColor Yellow
    Reset-Stubs
    $script:FakeInstalled['git'] = $true
    $r = Install-Prerequisites -Keys @('git') -Catalog $catalog
    Assert ($r.AlreadyInstalled -contains 'Git') "an already-present tool lands in AlreadyInstalled"
    Assert ($script:WingetCalls.Count -eq 0) "no seam call for an already-present tool"
    Assert ($r.Installed.Count -eq 0 -and $r.Failed.Count -eq 0) "nothing installed or failed"
    Write-Host ""
    #endregion

    #region Test 5: Failure lands in Failed and does not stop the rest
    Write-Host "=== Test 5: Failure handling ===" -ForegroundColor Yellow
    Reset-Stubs
    $script:SeamResult['Git.Git'] = @{ Success = $false; ExitCode = 1; Output = 'boom'; Command = 'stub' }
    $r = Install-Prerequisites -Keys @('git', 'neovim') -Catalog $catalog
    Assert (@($r.Failed | Where-Object { $_.Name -eq 'Git' }).Count -eq 1) "the failing row lands in Failed"
    Assert ($r.Failed[0].Error -match 'exit 1') "the failure records the exit code"
    Assert ($r.Installed -contains 'Neovim') "a later row still processes after a failure"
    Write-Host ""
    #endregion

    #region Test 6: Missing winget skips rather than fails
    Write-Host "=== Test 6: Missing winget ===" -ForegroundColor Yellow
    Reset-Stubs
    $script:WingetPresent = $false
    $r = Install-Prerequisites -Keys @('git', 'neovim', 'glow') -Catalog $catalog
    Assert ($r.Skipped.Count -eq 3) "every winget row is skipped"
    Assert ($r.Failed.Count -eq 0) "nothing is reported as failed"
    Assert ($script:WingetCalls.Count -eq 0) "no seam calls were made"
    Assert (@($r.Skipped | Where-Object { $_.Reason -match 'winget' }).Count -eq 3) "the reason names winget"
    Assert ($r.Skipped[0].Command) "the skip carries the manual command"
    foreach ($key in @('Installed','AlreadyInstalled','Failed','Skipped','NeedsNewShell','PathRefreshed')) {
        Assert ($r.ContainsKey($key)) "result has key $key"
    }
    Write-Host ""
    #endregion

    #region Test 7: Detection decides, not the exit code
    Write-Host "=== Test 7: Exit-code tolerance ===" -ForegroundColor Yellow
    Reset-Stubs
    # winget's "already installed" family returns non-zero but the tool IS present.
    $script:SeamResult['Neovim.Neovim'] = @{ Success = $false; ExitCode = -1978335189; Output = 'No applicable upgrade'; Command = 'stub' }
    $script:FakeInstalled['nvim'] = $false
    $r = Install-Prerequisites -Keys @('neovim') -Catalog $catalog -NoPathRefresh
    Assert ($r.Failed.Count -eq 1) "non-zero exit with the tool still absent is a failure"

    Reset-Stubs
    $script:SeamResult['Neovim.Neovim'] = @{ Success = $false; ExitCode = -1978335189; Output = 'Already installed'; Command = 'stub' }
    # Simulate detection succeeding after the seam ran
    function Invoke-WingetInstall {
        param([string]$PackageId, [string[]]$ExtraArgs = @())
        $script:WingetCalls += $PackageId
        $script:FakeInstalled['nvim'] = $true
        return @{ Success = $false; ExitCode = -1978335189; Output = 'Already installed'; Command = 'stub' }
    }
    $r = Install-Prerequisites -Keys @('neovim') -Catalog $catalog -NoPathRefresh
    Assert ($r.Installed -contains 'Neovim') "non-zero exit but now-present counts as Installed"
    Assert ($r.Failed.Count -eq 0) "and is not reported as a failure"
    Write-Host ""
    #endregion

    #region Test 8: Exit 0 but still missing -> NeedsNewShell
    Write-Host "=== Test 8: NeedsNewShell ===" -ForegroundColor Yellow
    Reset-Stubs
    function Invoke-WingetInstall {
        param([string]$PackageId, [string[]]$ExtraArgs = @())
        $script:WingetCalls += $PackageId
        return @{ Success = $true; ExitCode = 0; Output = ''; Command = 'stub' }   # never becomes detectable
    }
    $r = Install-Prerequisites -Keys @('glow') -Catalog $catalog -NoPathRefresh
    Assert ($r.Installed -contains 'glow') "exit 0 counts as installed"
    Assert ($r.NeedsNewShell -contains 'glow') "and is flagged as needing a new shell"
    Write-Host ""
    #endregion

    #region Test 9: Dependency guard
    Write-Host "=== Test 9: Dependency guard ===" -ForegroundColor Yellow
    Reset-Stubs
    function Invoke-WingetInstall {
        param([string]$PackageId, [string[]]$ExtraArgs = @())
        $script:WingetCalls += $PackageId
        return @{ Success = $false; ExitCode = 1; Output = 'failed'; Command = 'stub' }
    }
    $r = Install-Prerequisites -Keys @('oh-my-posh', 'nerd-font') -Catalog $catalog -NoPathRefresh
    Assert (@($r.Failed | Where-Object { $_.Name -eq 'Oh My Posh' }).Count -eq 1) "oh-my-posh failed"
    Assert (@($r.Skipped | Where-Object { $_.Reason -match 'requires oh-my-posh' }).Count -eq 1) "nerd-font skipped with a dependency reason"
    Assert ($script:FontCalls.Count -eq 0) "the font seam was never called"
    Write-Host ""
    #endregion

    #region Test 10: Multiple fonts in one go
    Write-Host "=== Test 10: Multi-font install ===" -ForegroundColor Yellow
    Reset-Stubs
    $script:FakeInstalled['oh-my-posh'] = $true
    $script:SeamResult['font:FiraCode'] = @{ Success = $false; ExitCode = 1; Output = 'no such font'; Command = 'stub' }
    $r = Install-Prerequisites -Keys @('nerd-font') -Catalog $catalog -Fonts @('meslo','CascadiaCode','FiraCode') -NoPathRefresh
    Assert ($script:FontCalls.Count -eq 3) "each font gets its own seam call"
    Assert (@($r.Installed | Where-Object { $_ -match 'meslo' }).Count -eq 1) "meslo installed"
    Assert (@($r.Installed | Where-Object { $_ -match 'CascadiaCode' }).Count -eq 1) "CascadiaCode installed"
    Assert ($r.Failed.Count -eq 1 -and $r.Failed[0].Error -match 'FiraCode') "one bad font fails alone without losing the others"
    Write-Host ""
    #endregion

    #region Test 11: remote-script rows never run unless named
    Write-Host "=== Test 11: remote-script is opt-in ===" -ForegroundColor Yellow
    Reset-Stubs
    $defaultKeys = @($catalog | Where-Object {
        $_.HandledBy -ne 'installer-bootstrap' -and $_.Mechanism -in @('winget','omp-font') -and $_.PreSelect
    } | ForEach-Object { $_.Key })
    Assert ($defaultKeys -notcontains 'claude-code') "claude-code is not in the default key set"
    $r = Install-Prerequisites -Keys $defaultKeys -Catalog $catalog -NoPathRefresh
    Assert ($script:RemoteCalls.Count -eq 0) "the remote-script seam was never reached"
    Write-Host ""
    #endregion

    #region Test 12: DryRun touches nothing
    Write-Host "=== Test 12: DryRun ===" -ForegroundColor Yellow
    Reset-Stubs
    $allKeys = @($catalog | ForEach-Object { $_.Key })
    $r = Install-Prerequisites -Keys $allKeys -Catalog $catalog -DryRun
    Assert ($script:WingetCalls.Count -eq 0 -and $script:RemoteCalls.Count -eq 0 -and $script:FontCalls.Count -eq 0) "no seam was called"
    Assert ($r.Skipped.Count -eq $allKeys.Count) "every key is reported as skipped"
    Assert (@($r.Skipped | Where-Object { $_.Reason -ne 'dry-run' }).Count -eq 0) "every skip reason is dry-run"
    Assert (@($r.Skipped | Where-Object { -not $_.Command }).Count -eq 0) "every skip carries the command it would run"
    Assert ($r.Installed.Count -eq 0) "nothing reported as installed"
    Write-Host ""
    #endregion

    #region Test 13: Update-SessionPath
    Write-Host "=== Test 13: Update-SessionPath ===" -ForegroundColor Yellow
    $sentinel = Join-Path $sandbox 'sentinel-bin'
    $env:PATH = "$sentinel;$env:PATH"
    $before = $env:PATH
    $result = Update-SessionPath
    Assert ($result -is [hashtable]) "returns a hashtable"
    foreach ($key in @('Added','Count','Before','After')) { Assert ($result.ContainsKey($key)) "result has key $key" }
    Assert ($env:PATH -split ';' -contains $sentinel) "a process-only PATH entry survives the refresh"

    $entries = @($env:PATH -split ';' | Where-Object { $_ } | ForEach-Object { $_.TrimEnd('\').ToLower() })
    Assert (($entries | Sort-Object -Unique).Count -eq $entries.Count) "no case-insensitive duplicates"
    $env:PATH = $before
    Write-Host ""
    #endregion

    #region Test 14: Config schema
    Write-Host "=== Test 14: Config schema ===" -ForegroundColor Yellow
    $cfg = New-DevkitConfig
    Assert ($cfg.ContainsKey('Prerequisites')) "New-DevkitConfig has a Prerequisites block"
    foreach ($key in @('Install','Selected','Fonts','Installed','AlreadyInstalled','Failed','Skipped','NeedsNewShell','WingetAvailable')) {
        Assert ($cfg.Prerequisites.ContainsKey($key)) "Prerequisites has key $key"
    }
    Assert ($cfg.Prerequisites.Install -eq $false) "prerequisites are opt-in by default"

    # Prerequisites must never be required for a valid config - a user who skips them
    # still has to be able to finish the wizard. Fill in the fields Test-DevkitConfig
    # genuinely requires so this asserts Prerequisites specifically, nothing else.
    $cfg.Git.DefaultProfile.Name = "Test User"
    $cfg.Git.DefaultProfile.Email = "test@example.com"
    $cfg.RepoLocations = @("C:
epos")
    $cfg.PowerShell.Modules = @("z")
    $cfg.PowerShell.OhMyPoshTheme = "theme.omp.json"
    $validation = Test-DevkitConfig -Config $cfg
    Assert ($validation.IsValid) "a config with Prerequisites.Install = false still validates"
    Write-Host ""
    #endregion

} finally {
    Remove-Item -Path $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
if ($script:Failures -eq 0) {
    Write-Host "ALL PREREQUISITE TESTS PASSED" -ForegroundColor Green
    exit 0
} else {
    Write-Host "$($script:Failures) ASSERTION(S) FAILED" -ForegroundColor Red
    exit 1
}
