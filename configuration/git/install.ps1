# Git Configuration Installation Script
# This script will set up git configuration with profile support

# Ensure script is running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Please run this script as Administrator!" -ForegroundColor Red
    exit
}

# Get the root directory of the devkit
$devkitRoot = $PSScriptRoot | Split-Path | Split-Path
$gitConfigDir = Join-Path $devkitRoot "configuration\git"
$profilesDir = Join-Path $gitConfigDir "profiles"

# Create profiles directory if it doesn't exist
if (-not (Test-Path $profilesDir)) {
    New-Item -ItemType Directory -Path $profilesDir | Out-Null
}

# Function to get user input with validation
function Get-ValidatedInput {
    param (
        [string]$prompt,
        [string]$validationPattern,
        [string]$errorMessage
    )
    
    do {
        $input = Read-Host $prompt
        if ($input -match $validationPattern) {
            return $input
        }
        Write-Host $errorMessage -ForegroundColor Red
    } while ($true)
}

# Get user information
Write-Host "`nGit Configuration Setup" -ForegroundColor Cyan
Write-Host "=====================" -ForegroundColor Cyan

$userName = Get-ValidatedInput -prompt "Enter your full name" -validationPattern ".+" -errorMessage "Name cannot be empty"
$userEmail = Get-ValidatedInput -prompt "Enter your primary email" -validationPattern "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" -errorMessage "Please enter a valid email address"

# Create default profile
$defaultProfileContent = @"
[user]
    name = $userName
    email = $userEmail

[core]
    autocrlf = true
    editor = C:/Program\\ Files/Git/usr/bin/vim.exe
    excludesfile = $env:USERPROFILE\\Documents\\gitignore_global.txt
    longpaths = true

[alias]	
yesterday = !"git log --reverse --branches --since='yesterday' --author=$(git config --get user.email) --format=format:'%C(cyan bold ul) %ad %Creset %C(magenta)%h %C(blue bold) %s %Cgreen%d' --date=local"
recently = !"git log --reverse --branches --since='3 days ago' --author=$(git config --get user.email) --format=format:'%C(cyan bold ul) %ad %Creset %C(magenta)%h %C(blue bold) %s %Cgreen%d' --date=local"
standup = !"git log --reverse --branches --since='$(if [[ "Mon" == "$(date +%a)" ]]; then echo "last friday"; else echo "yesterday"; fi)' --author=$(git config --get user.email) --format=format:'%C(cyan bold ul) %ad %Creset %C(magenta)%h %C(blue bold) %s %Cgreen%d' --date=local"

[alias]	
lg1 = log --graph --abbrev-commit --decorate --date=relative --format=format:'%C(bold blue)%h%C(reset) - %C(bold green)(%ar)%C(reset) %C(white)%s%C(reset) %C(dim white)- %an%C(reset)%C(bold yellow)%d%C(reset)' --all
lg2 = log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) - %C(bold cyan)%aD%C(reset) %C(bold green)(%ar)%C(reset)%C(bold yellow)%d%C(reset)%n''          %C(white)%s%C(reset) %C(dim white)- %an%C(reset)' --all
lg = !"git lg1"
ls = log --pretty=format:'%C(green bold)%h%C(blue bold)  [%cn]  %C(red)%d  %C(cyan bold)%s' --decorate
la = log --pretty=format:'%C(green bold)%h%C(blue bold)  [%cn]  %C(red)%d  %C(cyan bold)%s' --decorate --all
ll = log --pretty=format:'%C(green bold)%h%C(blue bold)  [%cn]  %C(red)%d  %C(cyan bold)%s' --decorate --numstat

amend = commit -a --amend

[push]
    default = simple
    autoSetupRemote = true

[branch]
    autoSetupRebase = always

[help]
    autocorrect = 20

[color]
    ui = always
    branch = always
    diff = always
    interactive = always
    status = always
    grep = always
    pager = true
    decorate = always
    showbranch = always

[gpg]
    program = gpg

[commit]
    gpgSign = false

[tag]
    forceSignAnnotated = false
"@

$defaultProfilePath = Join-Path $profilesDir "default.gitconfig"
$defaultProfileContent | Out-File -FilePath $defaultProfilePath -Encoding UTF8

# Create main gitconfig that includes the default profile
$mainGitConfigContent = @"
[include]
    path = $defaultProfilePath
"@

$mainGitConfigPath = Join-Path $env:USERPROFILE ".gitconfig"
$mainGitConfigContent | Out-File -FilePath $mainGitConfigPath -Encoding UTF8

# Ask if user wants to create additional profiles
$createMoreProfiles = Read-Host "Would you like to create additional git profiles for different email addresses? (y/n)"
if ($createMoreProfiles -eq 'y') {
    do {
        $profileName = Read-Host "`nEnter profile name (e.g., work, personal)"
        $profileEmail = Get-ValidatedInput -prompt "Enter email for this profile" -validationPattern "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$" -errorMessage "Please enter a valid email address"
        $profilePath = Read-Host "Enter git directory path for this profile (e.g., C:/repos/work/)"

        $profileContent = @"
[user]
    name = $userName
    email = $profileEmail
"@

        $profileFilePath = Join-Path $profilesDir "$profileName.gitconfig"
        $profileContent | Out-File -FilePath $profileFilePath -Encoding UTF8

        # Add includeIf to main gitconfig
        $includeLine = "[includeIf `"gitdir:$profilePath`"]`n    path = $profileFilePath`n`n"
        Add-Content -Path $mainGitConfigPath -Value $includeLine

        $createAnother = Read-Host "Would you like to create another profile? (y/n)"
    } while ($createAnother -eq 'y')
}

Write-Host "`nGit configuration completed successfully!" -ForegroundColor Green
Write-Host "Your git configuration is now set up with the following:" -ForegroundColor Green
Write-Host "1. Default profile with your primary email" -ForegroundColor Yellow
Write-Host "2. Additional profiles as configured" -ForegroundColor Yellow
Write-Host "3. All necessary aliases and settings" -ForegroundColor Yellow
Write-Host "`nYou can verify your configuration by running: git config --list" -ForegroundColor Cyan 