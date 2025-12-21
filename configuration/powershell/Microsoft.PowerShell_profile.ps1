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

    if (Test-Path "c:\repos") {
        Set-Location c:\repos 
    } else {
        Set-Location d:\repos
    }
}

function cuserprofile { Set-Location ~ }
Set-Alias ~ cuserprofile -Option AllScope

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
    Import-Module -Name Terminal-Icons
}

Execute-Step -stepName "Loading Oh My Posh configuration and theme..." -action {
    $ohMyPoshConfig = $env:DEVKIT_OMP_THEME
    if ($ohMyPoshConfig -and (Test-Path $ohMyPoshConfig)) {
        oh-my-posh init pwsh --config $ohMyPoshConfig | Invoke-Expression
    } else {
        Write-Host "Oh-My-Posh theme not found at: $ohMyPoshConfig" -ForegroundColor Yellow
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

$stepName = "All done, enjoy!"
$currentTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss.fff"
Write-Host "$currentTime - " -NoNewline
Write-Host "$stepName" -ForegroundColor Magenta


# # $ohMyPoshConfig = "C:\Users\mgpet\AppData\Local\Programs\oh-my-posh\themes\microverse-power.omp.json"
# # $ohMyPoshConfig = "C:\Users\mgpet\AppData\Local\Programs\oh-my-posh\themes\quick-term.omp.json"
# # $ohMyPoshConfig = "C:\Users\mgpet\AppData\Local\Programs\oh-my-posh\themes\microverse-power.omp.json"
# # $ohMyPoshConfig = "C:\Users\mgpet\AppData\Local\Programs\oh-my-posh\themes\lambdageneration.omp.json"
# # $ohMyPoshConfig = "C:\Users\mgpet\AppData\Local\Programs\oh-my-posh\themes\cloud-native-azure.omp.json"
# # $ohMyPoshConfig = "C:\Users\mgpet\AppData\Local\Programs\oh-my-posh\themes\1_shell.omp.json"
# # $ohMyPoshConfig = "C:\Users\mgpet\AppData\Local\Programs\oh-my-posh\themes\sonicboom_dark.omp.json"
# $ohMyPoshConfig = "C:\repos\usualexpat-devkit\configuration\.mytheme.omp.json"
# oh-my-posh init pwsh --config $ohMyPoshConfig | Invoke-Expression




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
