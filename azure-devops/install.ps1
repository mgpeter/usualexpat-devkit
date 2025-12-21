# Azure DevOps Pipeline Automation Installation Script

# Ensure script is running as Administrator
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Please run this script as Administrator!" -ForegroundColor Red
    exit
}

# Get the root directory of the devkit
$devkitRoot = $PSScriptRoot | Split-Path | Split-Path
$modulePath = Join-Path $devkitRoot "azure-devops\AzDevOpsPipelineAutomation"

# Create module directory if it doesn't exist
if (-not (Test-Path $modulePath)) {
    New-Item -ItemType Directory -Path $modulePath | Out-Null
}

# Install required Azure PowerShell modules
$requiredModules = @(
    @{ Name = 'Az'; Version = '10.0.0' }
    @{ Name = 'Az.Accounts'; Version = '2.12.0' }
    @{ Name = 'Az.Resources'; Version = '6.5.0' }
    @{ Name = 'Az.Websites'; Version = '2.12.0' }
    @{ Name = 'Az.Functions'; Version = '4.0.0' }
)

foreach ($module in $requiredModules) {
    if (-not (Get-Module -ListAvailable -Name $module.Name)) {
        Write-Host "Installing module: $($module.Name)" -ForegroundColor Yellow
        Install-Module -Name $module.Name -RequiredVersion $module.Version -Force -AllowClobber
    }
    else {
        Write-Host "Module $($module.Name) is already installed." -ForegroundColor Green
    }
}

# Copy module files
$moduleFiles = @(
    'AzDevOpsPipelineAutomation.psd1',
    'AzDevOpsPipelineAutomation.psm1'
)

foreach ($file in $moduleFiles) {
    $sourcePath = Join-Path $PSScriptRoot "AzDevOpsPipelineAutomation\$file"
    $targetPath = Join-Path $modulePath $file
    
    if (Test-Path $sourcePath) {
        Copy-Item -Path $sourcePath -Destination $targetPath -Force
        Write-Host "Copied $file to module directory" -ForegroundColor Green
    }
    else {
        Write-Host "Warning: Source file $file not found" -ForegroundColor Yellow
    }
}

# Add module to PowerShell path
$userModulesPath = Join-Path $env:USERPROFILE "Documents\WindowsPowerShell\Modules"
if (-not (Test-Path $userModulesPath)) {
    New-Item -ItemType Directory -Path $userModulesPath | Out-Null
}

# Create symbolic link to module
$moduleLinkPath = Join-Path $userModulesPath "AzDevOpsPipelineAutomation"
if (Test-Path $moduleLinkPath) {
    Remove-Item -Path $moduleLinkPath -Force
}

New-Item -ItemType SymbolicLink -Path $moduleLinkPath -Target $modulePath | Out-Null

Write-Host "`nAzure DevOps Pipeline Automation module installed successfully!" -ForegroundColor Green
Write-Host "You can now use the module by importing it:" -ForegroundColor Yellow
Write-Host "```powershell" -ForegroundColor Cyan
Write-Host "Import-Module AzDevOpsPipelineAutomation" -ForegroundColor Cyan
Write-Host "```" -ForegroundColor Cyan
Write-Host "`nExample usage:" -ForegroundColor Yellow
Write-Host "```powershell" -ForegroundColor Cyan
Write-Host "# Initialize the module" -ForegroundColor Cyan
Write-Host "Initialize-AzDevOpsPipeline -Organization 'your-org' -Project 'your-project' -PatToken 'your-pat-token'" -ForegroundColor Cyan
Write-Host "`n# Analyze a solution" -ForegroundColor Cyan
Write-Host "$solutionInfo = Get-SolutionAnalysis -SolutionPath 'path/to/solution.sln'" -ForegroundColor Cyan
Write-Host "`n# Generate pipeline" -ForegroundColor Cyan
Write-Host "$pipelineYaml = New-PipelineDefinition -SolutionInfo $solutionInfo -Config @{ BuildConfiguration = 'Release' }" -ForegroundColor Cyan
Write-Host "```" -ForegroundColor Cyan 