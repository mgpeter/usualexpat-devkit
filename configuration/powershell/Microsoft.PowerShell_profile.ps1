function Execute-Step {
    param (
        [string]$stepName,
        [scriptblock]$action
    )

    $currentTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
    Write-Host "$currentTime - $stepName" -NoNewline

    try {
        $startTime = Get-Date
        & $action
        $endTime = Get-Date
        $timeTaken = ($endTime - $startTime).TotalMilliseconds
        Write-Host " DONE" -ForegroundColor Green -NoNewline
        Write-Host " ($([math]::Round($timeTaken)) ms)" -ForegroundColor Cyan
    } catch {
        Write-Host " ERROR: $_" -ForegroundColor Red
    }
}

# Aliases and Helper Functions

Set-Alias grep findstr -Option AllScope
Set-Alias add "git add" -Option AllScope
Set-Alias status "git status" -Option AllScope
Set-Alias commit "git commit" -Option AllScope
Set-Alias gut git -Option AllScope

function cws {
    # Use DEVKIT_REPOS_PATH env var, or default to ~/repos
    $reposPath = $env:DEVKIT_REPOS_PATH
    if (-not $reposPath) {
        $reposPath = Join-Path $env:USERPROFILE "repos"
    }

    if (Test-Path $reposPath) {
        Set-Location $reposPath
    } else {
        Write-Warning "Repos path not found: $reposPath. Set `$env:DEVKIT_REPOS_PATH to configure."
    }
}

function cuserprofile { Set-Location ~ }
Set-Alias ~ cuserprofile -Option AllScope

function check-excluded-ports {
    netsh int ipv4 show excludedportrange protocol=tcp
}

function U {
    param
    (
        [int] $Code
    )
 
    if ((0 -le $Code) -and ($Code -le 0xFFFF)) {
        return [char] $Code
    }
 
    if ((0x10000 -le $Code) -and ($Code -le 0x10FFFF)) {
        return [char]::ConvertFromUtf32($Code)
    }
 
    throw "Invalid character code $Code"
}

# Helper functions

function Get-My-Public-Ip {
    $myIP = (Invoke-WebRequest -uri "https://api.ipify.org/"). Content
    Write-Output $myIP
}

# Steps for Initializations and Setups

Execute-Step -stepName "Importing z..." -action {
    Import-Module z
}


Execute-Step -stepName "Importing posh-git..." -action {
    Import-Module -Name posh-git
}

Execute-Step -stepName "Importing Terminal-Icons..." -action {
    try {
        Import-Module -Name Terminal-Icons -ErrorAction Stop
    } catch {
        # Terminal-Icons caches theme data as CLIXML; an Import-Clixml format
        # change between PowerShell versions can render the cache unreadable.
        # Purge the cache and retry once before propagating the failure.
        $cache = Join-Path $env:APPDATA 'powershell\Community\Terminal-Icons'
        if (Test-Path $cache) {
            Remove-Item (Join-Path $cache 'devblackops_*.xml') -Force -ErrorAction SilentlyContinue
        }
        Import-Module -Name Terminal-Icons -ErrorAction Stop
    }
}

function Enable-DevkitStarshipGitPanel {
    <#
    .SYNOPSIS
        Installs the per-prompt git classifier the devkit Starship git panel reads
    .DESCRIPTION
        Starship gives each module one fixed style, so git_branch cannot change colour with
        what the repo is doing. The devkit panel in starship.toml disables git_branch and
        puts four env_var modules in its slot, one per state; this classifier sets exactly
        one of them per prompt, so exactly one branch segment renders.

        Invoke-Starship-PreCommand is Starship's own hook and the only safe seam here. It
        runs inside starship's prompt function AFTER that function has captured $? and
        $LASTEXITCODE and BEFORE it restores them, so calling git from it cannot corrupt
        the error indicator. Wrapping `prompt` by hand would.

        Both functions are global on purpose: Execute-Step invokes its -action in a child
        scope, and Starship's dynamic module resolves the hook through the global
        function: drive.
    #>
    function global:Get-DevkitGitDirForPrompt {
        # Walk up for .git rather than spawning `git rev-parse`, which costs about as much
        # as the `git status` below and would double the classifier's price per prompt.
        $loc = Get-Location
        if ($loc.Provider.Name -ne 'FileSystem') { return $null }
        $dir = $loc.ProviderPath
        while ($dir) {
            $candidate = Join-Path $dir '.git'
            if (Test-Path -LiteralPath $candidate -PathType Container) { return $candidate }
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                # Worktree or submodule: ".git" is a file pointing at the real git dir.
                $line = (Get-Content -LiteralPath $candidate -TotalCount 1).Trim()
                if ($line -match '^gitdir:\s*(.+)$') {
                    $target = $Matches[1]
                    if (-not [System.IO.Path]::IsPathRooted($target)) { $target = Join-Path $dir $target }
                    return [System.IO.Path]::GetFullPath($target)
                }
                return $null
            }
            $dir = Split-Path -Path $dir -Parent
        }
        return $null
    }

    function global:Invoke-Starship-PreCommand {
        $env:DEVKIT_GIT_CONFLICT = $null
        $env:DEVKIT_GIT_DIRTY    = $null
        $env:DEVKIT_GIT_DIVERGED = $null
        $env:DEVKIT_GIT_CLEAN    = $null

        $eap = $ErrorActionPreference
        $ErrorActionPreference = 'Ignore'
        try {
            $gitDir = Get-DevkitGitDirForPrompt
            if (-not $gitDir) { return }

            $lines = @(& git status --porcelain=v2 --branch 2>$null)
            if ($LASTEXITCODE -ne 0) { return }

            $branch = $null; $ahead = 0; $behind = 0
            $dirty = $false; $unmerged = $false

            foreach ($line in $lines) {
                if ($line.StartsWith('# branch.head ')) {
                    $branch = $line.Substring(14)
                } elseif ($line.StartsWith('# branch.ab ')) {
                    $ab = $line.Substring(12) -split ' '
                    $ahead  = [int]$ab[0]   # +N
                    $behind = [int]$ab[1]   # -N, already signed
                } elseif (-not $line.StartsWith('#')) {
                    $dirty = $true
                    if ($line.StartsWith('u ')) { $unmerged = $true }
                }
            }

            $inProgress = @('rebase-merge', 'rebase-apply', 'MERGE_HEAD', 'CHERRY_PICK_HEAD', 'REVERT_HEAD', 'BISECT_LOG') |
                Where-Object { Test-Path -LiteralPath (Join-Path $gitDir $_) }

            if ($branch -eq '(detached)') {
                # Mid-rebase HEAD is detached; git parks the original branch name here.
                # Without this the prompt shows a short SHA exactly when knowing the
                # branch matters most.
                $headName = @('rebase-merge\head-name', 'rebase-apply\head-name') |
                    ForEach-Object { Join-Path $gitDir $_ } |
                    Where-Object { Test-Path -LiteralPath $_ } |
                    Select-Object -First 1
                $branch = if ($headName) {
                    (Get-Content -LiteralPath $headName -TotalCount 1).Trim() -replace '^refs/heads/', ''
                } else {
                    & git rev-parse --short HEAD 2>$null
                }
            }
            if (-not $branch) { return }

            # Precedence: a repo mid-rebase is also dirty and also ahead, and the most
            # alarming state is the one worth showing.
            if ($unmerged -or $inProgress)      { $env:DEVKIT_GIT_CONFLICT = $branch; return }
            if ($dirty)                         { $env:DEVKIT_GIT_DIRTY    = $branch; return }
            if ($ahead -ne 0 -or $behind -ne 0) { $env:DEVKIT_GIT_DIVERGED = $branch; return }
            $env:DEVKIT_GIT_CLEAN = $branch
        } catch {
        } finally {
            $ErrorActionPreference = $eap
        }
    }
}

Execute-Step -stepName "Loading prompt engine..." -action {
    # The 'default' arm - not an explicit 'oh-my-posh' case - is what keeps a variables.ps1
    # written before DEVKIT_PROMPT_ENGINE existed rendering the same prompt as before.
    switch ($env:DEVKIT_PROMPT_ENGINE) {
        'starship' {
            if (-not (Get-Command starship -ErrorAction SilentlyContinue)) {
                Write-Host "starship not found on PATH. Run: devkit prereqs install" -ForegroundColor Yellow
                return
            }
            if ($env:DEVKIT_STARSHIP_CONFIG -and (Test-Path $env:DEVKIT_STARSHIP_CONFIG)) {
                $env:STARSHIP_CONFIG = $env:DEVKIT_STARSHIP_CONFIG
            }
            if ($env:DEVKIT_GIT_PANEL) { Enable-DevkitStarshipGitPanel }
            Invoke-Expression (&starship init powershell)
        }
        default {
            $ohMyPoshConfig = $env:DEVKIT_OMP_THEME
            if ($ohMyPoshConfig -and (Test-Path $ohMyPoshConfig)) {
                oh-my-posh init pwsh --config "$ohMyPoshConfig" | Invoke-Expression
            } else {
                Write-Host "Oh-My-Posh theme not found at: $ohMyPoshConfig" -ForegroundColor Yellow
            }
        }
    }
}

Execute-Step -stepName "Loading Chocolatey profile..." -action {
    $ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
    if (Test-Path($ChocolateyProfile)) {
        Import-Module "$ChocolateyProfile"
    }
}

if ($host.Name -eq 'ConsoleHost') {
    Execute-Step -stepName "Configuring PSReadLine..." -action {
        Import-Module PSReadLine

        Set-PSReadLineOption -PredictionSource History
        #Set-PSReadLineOption -PredictionViewStyle ListView
        Set-PSReadLineOption -EditMode Windows

        Set-PSReadLineKeyHandler -Key F2 -Function SwitchPredictionView
        Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward
        Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
        Set-PSReadLineKeyHandler -Key Ctrl+UpArrow -Function PreviousSuggestion
        Set-PSReadLineKeyHandler -Key Ctrl+DownArrow -Function NextSuggestion
        Set-PSReadLineKeyHandler -Key Ctrl+f -Function AcceptNextSuggestionWord


        Set-PSReadLineKeyHandler -Key Ctrl+Shift+b `
            -BriefDescription BuildCurrentDirectory `
            -LongDescription "Build the current directory" `
            -ScriptBlock {
            [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert("dotnet build")
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
        }

        Set-PSReadLineKeyHandler -Key Ctrl+Shift+r `
            -BriefDescription ClearConsole `
            -LongDescription "Clear the console window" `
            -ScriptBlock {
            [Microsoft.PowerShell.PSConsoleReadLine]::RevertLine()
            [Microsoft.PowerShell.PSConsoleReadLine]::Insert("cls")
            [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
        }

    }
}

# Devkit CLI - exposes `devkit` / `devkit help` / `devkit doctor` etc.
$devkitCli = Join-Path $HOME ".devkit/devkit.ps1"
if (Test-Path $devkitCli) {
    . $devkitCli
}

$stepName = "All done, enjoy!"
$currentTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
Write-Host "$currentTime - " -NoNewline
Write-Host "$stepName" -ForegroundColor Magenta

# Custom tools
function Move-PhotosToMonthlyFolders {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [string]$InputDirectory,

        [Parameter(Mandatory=$true)]
        [string]$OutputDirectory
    )

    Begin {
        Write-Host "Starting to process files in $InputDirectory"
        if (-not (Test-Path -Path $OutputDirectory)) {
            Write-Host "Creating output directory: $OutputDirectory"
            New-Item -Path $OutputDirectory -ItemType Directory
        }
    }

    Process {
        $files = Get-ChildItem -Path $InputDirectory

        foreach ($file in $files) {
            if ($file.Name -match "(19|20\d{2})(\d{2})(\d{2})") {
                $year = $matches[1]
                $month = $matches[2]

                # Check if the year and month are valid
                if (!([DateTime]::TryParseExact("$year$month", 'yyyyMM', $null, [System.Globalization.DateTimeStyles]::None, [ref]$null))) {
                    Write-Host "Skipping $($file.Name) - Invalid date format in filename"
                    continue
                }
            } else {
                Write-Host "File $($file.Name) does not match pattern, using last write time"
                $year = $file.LastWriteTime.Year.ToString()
                $month = "{0:D2}" -f $file.LastWriteTime.Month
            }

            $newFolder = Join-Path -Path $OutputDirectory -ChildPath "$year-$month"

            if (-not (Test-Path -Path $newFolder)) {
                Write-Host "Creating folder: $newFolder"
                New-Item -Path $newFolder -ItemType Directory
            }

            $newFilePath = Join-Path -Path $newFolder -ChildPath $file.Name

            Write-Host "Moving $($file.Name) to $newFilePath"
            Move-Item -Path $file.FullName -Destination $newFilePath
        }
    }

    End {
        Write-Host "Processing complete."
    }
}


function Get-MailDomainInfo {
    param(
        [parameter(Mandatory = $true)][string[]]$DomainName,
        [parameter(Mandatory = $false)][string]$DNSserver = '1.1.1.1'
    )
     
    $info = foreach ($domain in $DomainName) {
        
        # Check if domain name is valid, output warning it not and continue to the next domain (if any)
        try {
            Resolve-DnsName -Name $domain -Server $DNSserver -ErrorAction Stop | Out-Null
            #Retrieve all mail DNS records
            $autodiscoverA = (Resolve-DnsName -Name "autodiscover.$($domain)" -Type A -Server $DNSserver -ErrorAction SilentlyContinue).IPAddress
            $autodiscoverCNAME = (Resolve-DnsName -Name "autodiscover.$($domain)" -Type CNAME -Server $DNSserver -ErrorAction SilentlyContinue).NameHost
            $dkim1 = Resolve-DnsName -Name "selector1._domainkey.$($domain)" -Type CNAME -Server $DNSserver -ErrorAction SilentlyContinue
            $dkim2 = Resolve-DnsName -Name "selector2._domainkey.$($domain)" -Type CNAME -Server $DNSserver -ErrorAction SilentlyContinue
            $dmarc = (Resolve-DnsName -Name "_dmarc.$($domain)" -Type TXT -Server $DNSserver -ErrorAction SilentlyContinue | Where-Object Strings -Match 'DMARC').Strings
            $mx = (Resolve-DnsName -Name $domain -Type MX -Server $DNSserver -ErrorAction SilentlyContinue).NameExchange
            $spf = (Resolve-DnsName -Name $domain -Type TXT -Server $DNSserver -ErrorAction SilentlyContinue | Where-Object Strings -Match 'v=spf').Strings
            $includes = (Resolve-DnsName -Name $domain -Type TXT -Server $DNSserver -ErrorAction SilentlyContinue | Where-Object Strings -Match 'v=spf').Strings -split ' ' | Select-String 'Include:'
 
            # Set variables to Not enabled or found if they can't be retrieved
            $errorfinding = 'Not enabled'
           
 
            if ($null -eq $dkim1 -and $null -eq $dkim2) {
                $dkim = $errorfinding
            }
            else {
                $dkim = "$($dkim1.Name) , $($dkim2.Name)"
            }
 
            if ($null -eq $dmarc) {
                $dmarc = $errorfinding
            }
 
            if ($null -eq $mx) {
                $mx = $errorfinding
            }
 
            if ($null -eq $spf) {
                $spf = $errorfinding
            }
            if ($null -eq $autodiscoverCNAME) {
                $autodiscoverCNAME = $errorfinding
            }
            if (($autodiscoverA).count -gt 1 -or $null -ne $autodiscoverCNAME) {
                $autodiscoverA = $errorfinding
            }
            if ($null -eq $includes) {
                $includes = $errorfinding
            }
            else {
                $foundincludes = foreach ($include in $includes) {
                    if ((Resolve-DnsName -Server $DNSserver -Name $include.ToString().Split(':')[1] -Type txt -ErrorAction SilentlyContinue).Strings) {
                        [PSCustomObject]@{
                            SPFIncludes = "$($include.ToString().Split(':')[1]) : " + $(Resolve-DnsName -Server $DNSserver -Name $include.ToString().Split(':')[1] -Type txt).Strings
                        }
                    }
                    else {
                        [PSCustomObject]@{
                            SPFIncludes = $errorfinding
                        }
                    }
                }
            }
 
            [PSCustomObject]@{
                'Domain Name'             = $domain
                'Autodiscover IP-Address' = $autodiscoverA
                'Autodiscover CNAME '     = $autodiscoverCNAME
                'DKIM Record'             = $dkim
                'DMARC Record'            = "$($dmarc)"
                'MX Record(s)'            = $mx -join ', '
                'SPF Record'              = "$($spf)"
                'SPF Include values'      = "$($foundincludes.SPFIncludes)" -replace "all", "all`n`b"
            }
        }
        catch {
            Write-Warning ("{0} not found" -f $domain)
        }     
    }
    return $info 
}


function Move-PhotosToYearFolders {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true)]
        [string]$InputDirectory,

        [Parameter(Mandatory=$true)]
        [string]$OutputDirectory
    )

    Begin {
        Write-Host "Starting to process files in $InputDirectory"
        if (-not (Test-Path -Path $OutputDirectory)) {
            Write-Host "Creating output directory: $OutputDirectory"
            New-Item -Path $OutputDirectory -ItemType Directory
        }
    }

    Process {
        $files = Get-ChildItem -Path $InputDirectory

        foreach ($file in $files) {
            if ($file.Name -match "(19|20\d{2})(\d{2})(\d{2})") {
                $year = $matches[1]

                # Check if the extracted date is valid
                if (!([DateTime]::TryParseExact("$year$($matches[2])$($matches[3])", 'yyyyMMdd', $null, [System.Globalization.DateTimeStyles]::None, [ref]$null))) {
                    Write-Host "Skipping $($file.Name) - Invalid date format in filename"
                    continue
                }
            } else {
                Write-Host "File $($file.Name) does not match pattern, using last write time"
                $year = $file.LastWriteTime.Year.ToString()
            }

            $newFolder = Join-Path -Path $OutputDirectory -ChildPath "$year"

            if (-not (Test-Path -Path $newFolder)) {
                Write-Host "Creating folder: $newFolder"
                New-Item -Path $newFolder -ItemType Directory
            }

            $newFilePath = Join-Path -Path $newFolder -ChildPath $file.Name

            Write-Host "Moving $($file.Name) to $newFilePath"
            Move-Item -Path $file.FullName -Destination $newFilePath
        }
    }

    End {
        Write-Host "Processing complete."
    }
}
