# New-Pipeline.ps1
# This script provides an interactive way to create Azure DevOps pipelines

# Import the module
Import-Module AzDevOpsPipelineAutomation

# Function to get secure input
function Get-SecureInput {
    param (
        [string]$Prompt
    )
    $secureString = Read-Host -AsSecureString $Prompt
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureString)
    return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
}

# Function to validate Azure DevOps organization
function Test-AzDevOpsOrganization {
    param (
        [string]$Organization,
        [string]$PatToken
    )
    try {
        $headers = @{
            'Authorization' = "Basic $([Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$PatToken")))"
            'Content-Type' = 'application/json'
        }
        $url = "https://dev.azure.com/$Organization/_apis/projects?api-version=6.0"
        $response = Invoke-RestMethod -Uri $url -Headers $headers
        return $true
    }
    catch {
        return $false
    }
}

# Function to validate Azure subscription
function Test-AzSubscription {
    try {
        $context = Get-AzContext
        return $true
    }
    catch {
        return $false
    }
}

# Main script
Write-Host "`n🚀 Azure DevOps Pipeline Automation" -ForegroundColor Cyan
Write-Host "================================`n" -ForegroundColor Cyan

# Step 1: Azure DevOps Authentication
Write-Host "Step 1: Azure DevOps Authentication" -ForegroundColor Yellow
Write-Host "--------------------------------" -ForegroundColor Yellow

$organization = Read-Host "Enter your Azure DevOps organization name"
$project = Read-Host "Enter your Azure DevOps project name"
$patToken = Get-SecureInput "Enter your Azure DevOps Personal Access Token (PAT)"

# Validate Azure DevOps connection
Write-Host "`nValidating Azure DevOps connection..." -ForegroundColor Yellow
if (-not (Test-AzDevOpsOrganization -Organization $organization -PatToken $patToken)) {
    Write-Host "❌ Failed to connect to Azure DevOps. Please check your organization name and PAT token." -ForegroundColor Red
    exit
}
Write-Host "✅ Successfully connected to Azure DevOps" -ForegroundColor Green

# Step 2: Azure Authentication
Write-Host "`nStep 2: Azure Authentication" -ForegroundColor Yellow
Write-Host "------------------------" -ForegroundColor Yellow

if (-not (Test-AzSubscription)) {
    Write-Host "Please sign in to Azure..." -ForegroundColor Yellow
    Connect-AzAccount
}

# Get Azure subscription
$subscriptions = Get-AzSubscription
if ($subscriptions.Count -gt 1) {
    Write-Host "`nAvailable subscriptions:" -ForegroundColor Yellow
    for ($i = 0; $i -lt $subscriptions.Count; $i++) {
        Write-Host "$($i + 1). $($subscriptions[$i].Name)"
    }
    $subscriptionIndex = Read-Host "Select subscription number" -ErrorAction SilentlyContinue
    if ($subscriptionIndex -match '^\d+$' -and [int]$subscriptionIndex -le $subscriptions.Count) {
        Set-AzContext -SubscriptionId $subscriptions[$subscriptionIndex - 1].Id
    }
}

# Step 3: Solution Analysis
Write-Host "`nStep 3: Solution Analysis" -ForegroundColor Yellow
Write-Host "----------------------" -ForegroundColor Yellow

$solutionPath = Read-Host "Enter the path to your solution file (.sln)"
if (-not (Test-Path $solutionPath)) {
    Write-Host "❌ Solution file not found. Please check the path." -ForegroundColor Red
    exit
}

Write-Host "`nAnalyzing solution..." -ForegroundColor Yellow
$solutionInfo = Get-SolutionAnalysis -SolutionPath $solutionPath

# Display solution analysis results
Write-Host "`nSolution Analysis Results:" -ForegroundColor Green
Write-Host "Projects found: $($solutionInfo.Projects.Count)" -ForegroundColor White
Write-Host "Test projects found: $($solutionInfo.TestProjects.Count)" -ForegroundColor White
Write-Host "Framework versions: $($solutionInfo.Projects.FrameworkVersion -join ', ')" -ForegroundColor White
Write-Host "Azure dependencies: $($solutionInfo.AzureDependencies -join ', ')" -ForegroundColor White

# Step 4: Pipeline Configuration
Write-Host "`nStep 4: Pipeline Configuration" -ForegroundColor Yellow
Write-Host "---------------------------" -ForegroundColor Yellow

$config = @{
    BuildConfiguration = Read-Host "Enter build configuration (Debug/Release)" -DefaultValue "Release"
    TestCoverageThreshold = Read-Host "Enter minimum test coverage threshold (%)" -DefaultValue "80"
    DeploymentEnvironments = @()
    ResourceGroup = Read-Host "Enter Azure resource group name"
    Location = Read-Host "Enter Azure region (e.g., westeurope)" -DefaultValue "westeurope"
}

# Configure environments
Write-Host "`nConfigure deployment environments:" -ForegroundColor Yellow
$envCount = Read-Host "How many environments do you want to configure?" -DefaultValue "3"
for ($i = 0; $i -lt [int]$envCount; $i++) {
    $envName = Read-Host "Enter environment name (e.g., dev, staging, prod)" -DefaultValue @("dev", "staging", "prod")[$i]
    $config.DeploymentEnvironments += $envName
}

# Step 5: Generate and Apply Pipeline
Write-Host "`nStep 5: Generate and Apply Pipeline" -ForegroundColor Yellow
Write-Host "--------------------------------" -ForegroundColor Yellow

# Initialize Azure DevOps pipeline
Write-Host "`nInitializing Azure DevOps pipeline..." -ForegroundColor Yellow
Initialize-AzDevOpsPipeline -Organization $organization -Project $project -PatToken $patToken

# Generate pipeline definition
Write-Host "Generating pipeline definition..." -ForegroundColor Yellow
$pipelineYaml = New-PipelineDefinition -SolutionInfo $solutionInfo -Config $config

# Create pipeline
$pipelineName = Read-Host "Enter pipeline name" -DefaultValue "CI-CD-Pipeline"
Write-Host "Creating pipeline in Azure DevOps..." -ForegroundColor Yellow
$pipeline = Set-AzDevOpsPipeline -PipelineYaml $pipelineYaml -PipelineName $pipelineName

# Step 6: Configure Azure Resources
Write-Host "`nStep 6: Configure Azure Resources" -ForegroundColor Yellow
Write-Host "-----------------------------" -ForegroundColor Yellow

$createResources = Read-Host "Do you want to create Azure resources? (y/n)" -DefaultValue "y"
if ($createResources -eq 'y') {
    Write-Host "Creating Azure resources..." -ForegroundColor Yellow
    Set-AzureResources -SolutionInfo $solutionInfo -Config $config
}

# Final Summary
Write-Host "`n✨ Pipeline Creation Complete!" -ForegroundColor Green
Write-Host "===========================" -ForegroundColor Green
Write-Host "`nPipeline Details:" -ForegroundColor Yellow
Write-Host "- Name: $pipelineName" -ForegroundColor White
Write-Host "- Organization: $organization" -ForegroundColor White
Write-Host "- Project: $project" -ForegroundColor White
Write-Host "- Environments: $($config.DeploymentEnvironments -join ', ')" -ForegroundColor White
Write-Host "- Resource Group: $($config.ResourceGroup)" -ForegroundColor White
Write-Host "- Location: $($config.Location)" -ForegroundColor White

Write-Host "`nNext steps:" -ForegroundColor Yellow
Write-Host "1. Push your code to Azure DevOps" -ForegroundColor White
Write-Host "2. The pipeline will automatically trigger on changes to main and develop branches" -ForegroundColor White
Write-Host "3. Monitor pipeline runs in Azure DevOps portal" -ForegroundColor White
Write-Host "4. Configure environment-specific variables in Azure DevOps" -ForegroundColor White 