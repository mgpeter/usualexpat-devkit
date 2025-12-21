# AzDevOpsPipelineAutomation.psm1

# Import required modules
using module Az
using module Az.Accounts
using module Az.Resources
using module Az.Websites
using module Az.Functions

# Module-level variables
$script:AzDevOpsConfig = @{
    Organization = $null
    Project = $null
    PatToken = $null
    BaseUrl = $null
    Headers = $null
}

# Initialize Azure DevOps pipeline automation
function Initialize-AzDevOpsPipeline {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$Organization,

        [Parameter(Mandatory = $true)]
        [string]$Project,

        [Parameter(Mandatory = $true)]
        [string]$PatToken
    )

    try {
        $script:AzDevOpsConfig.Organization = $Organization
        $script:AzDevOpsConfig.Project = $Project
        $script:AzDevOpsConfig.PatToken = $PatToken
        $script:AzDevOpsConfig.BaseUrl = "https://dev.azure.com/$Organization/$Project"
        
        # Set up headers for Azure DevOps API
        $auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$PatToken"))
        $script:AzDevOpsConfig.Headers = @{
            'Authorization' = "Basic $auth"
            'Content-Type' = 'application/json'
        }

        Write-Host "Successfully initialized Azure DevOps pipeline automation for $Organization/$Project" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to initialize Azure DevOps pipeline automation: $_"
        throw
    }
}

# Analyze solution structure
function Get-SolutionAnalysis {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$SolutionPath
    )

    try {
        $solutionInfo = @{
            SolutionPath = $SolutionPath
            Projects = @()
            TestProjects = @()
            FrameworkVersions = @()
            AzureDependencies = @()
        }

        # Parse solution file
        $solutionContent = Get-Content $SolutionPath -Raw
        $projectMatches = [regex]::Matches($solutionContent, 'Project\("{[^}]+}"\)\s*=\s*"[^"]+",\s*"([^"]+)",\s*"([^"]+)"')

        foreach ($match in $projectMatches) {
            $projectPath = $match.Groups[1].Value
            $projectGuid = $match.Groups[2].Value
            
            # Get project type and framework version
            $projectType = Get-ProjectType -ProjectPath $projectPath
            $frameworkVersion = Get-FrameworkVersion -ProjectPath $projectPath
            
            $projectInfo = @{
                Path = $projectPath
                Type = $projectType
                FrameworkVersion = $frameworkVersion
                Guid = $projectGuid
            }

            # Check if it's a test project
            if (Is-TestProject -ProjectPath $projectPath) {
                $solutionInfo.TestProjects += $projectInfo
            }
            else {
                $solutionInfo.Projects += $projectInfo
            }

            # Get Azure dependencies
            $azureDeps = Get-AzureDependencies -ProjectPath $projectPath
            if ($azureDeps) {
                $solutionInfo.AzureDependencies += $azureDeps
            }
        }

        return $solutionInfo
    }
    catch {
        Write-Error "Failed to analyze solution: $_"
        throw
    }
}

# Determine project type
function Get-ProjectType {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProjectPath
    )

    try {
        $projectContent = Get-Content $ProjectPath -Raw
        
        # Check for Web App
        if ($projectContent -match '<UseWebJobs>true</UseWebJobs>') {
            return 'WebApp'
        }
        
        # Check for Function App
        if ($projectContent -match '<AzureFunctionsVersion>') {
            return 'FunctionApp'
        }
        
        # Check for Blazor
        if ($projectContent -match '<BlazorWebAssemblyEnableLinking>') {
            return 'Blazor'
        }
        
        # Default to Class Library
        return 'ClassLibrary'
    }
    catch {
        Write-Error "Failed to determine project type: $_"
        throw
    }
}

# Get framework version
function Get-FrameworkVersion {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProjectPath
    )

    try {
        $projectContent = Get-Content $ProjectPath -Raw
        $frameworkMatch = [regex]::Match($projectContent, '<TargetFramework>([^<]+)</TargetFramework>')
        
        if ($frameworkMatch.Success) {
            return $frameworkMatch.Groups[1].Value
        }
        
        return $null
    }
    catch {
        Write-Error "Failed to get framework version: $_"
        throw
    }
}

# Check if project is a test project
function Is-TestProject {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProjectPath
    )

    try {
        $projectContent = Get-Content $ProjectPath -Raw
        
        # Check for test project references
        $testFrameworks = @(
            'xunit',
            'nunit',
            'mstest',
            'Microsoft.NET.Test.Sdk'
        )
        
        foreach ($framework in $testFrameworks) {
            if ($projectContent -match $framework) {
                return $true
            }
        }
        
        return $false
    }
    catch {
        Write-Error "Failed to check if project is a test project: $_"
        throw
    }
}

# Get Azure dependencies with more detailed information
function Get-AzureDependencies {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$ProjectPath
    )

    try {
        $projectContent = Get-Content $ProjectPath -Raw
        $dependencies = @()

        # Check for Azure Web App dependencies
        if ($projectContent -match 'Microsoft\.Azure\.WebJobs' -or 
            $projectContent -match 'Microsoft\.AspNetCore\.App') {
            $dependencies += @{
                Type = 'WebApp'
                Runtime = if ($projectContent -match 'net6\.0') { 'dotnet:6.0' }
                         elseif ($projectContent -match 'net7\.0') { 'dotnet:7.0' }
                         else { 'dotnet:6.0' }
                OS = if ($projectContent -match 'RuntimeIdentifier.*win') { 'Windows' }
                     else { 'Linux' }
            }
        }

        # Check for Azure Functions dependencies
        if ($projectContent -match 'Microsoft\.Azure\.Functions\.Worker' -or
            $projectContent -match 'Azure\.Functions\.Worker') {
            $dependencies += @{
                Type = 'FunctionApp'
                Runtime = if ($projectContent -match 'net6\.0') { 'dotnet:6.0' }
                         elseif ($projectContent -match 'net7\.0') { 'dotnet:7.0' }
                         else { 'dotnet:6.0' }
                OS = if ($projectContent -match 'RuntimeIdentifier.*win') { 'Windows' }
                     else { 'Linux' }
            }
        }

        # Check for Azure Key Vault
        if ($projectContent -match 'Azure\.Security\.KeyVault') {
            $dependencies += @{
                Type = 'KeyVault'
                SKU = 'standard'
            }
        }

        # Check for Azure SQL
        if ($projectContent -match 'Microsoft\.Azure\.SqlDatabase' -or
            $projectContent -match 'Microsoft\.Data\.SqlClient') {
            $dependencies += @{
                Type = 'SqlDatabase'
                Edition = 'Standard'
                ServiceObjective = 'S0'
            }
        }

        # Check for Azure Storage
        if ($projectContent -match 'Azure\.Storage\.Blobs' -or
            $projectContent -match 'Azure\.Storage\.Queues') {
            $dependencies += @{
                Type = 'StorageAccount'
                SKU = 'Standard_LRS'
            }
        }

        # Check for Azure Service Bus
        if ($projectContent -match 'Azure\.Messaging\.ServiceBus') {
            $dependencies += @{
                Type = 'ServiceBus'
                SKU = 'Standard'
            }
        }

        return $dependencies
    }
    catch {
        Write-Error "Failed to get Azure dependencies: $_"
        throw
    }
}

# Generate pipeline definition
function New-PipelineDefinition {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [object]$SolutionInfo,

        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    try {
        $pipelineYaml = @"
trigger:
  branches:
    include:
      - main
      - develop
  paths:
    include:
      - '**/*.cs'
      - '**/*.csproj'
      - '**/*.sln'
      - '**/azure-pipelines.yml'

variables:
  solution: '**/*.sln'
  buildPlatform: 'Any CPU'
  buildConfiguration: '$(Config.BuildConfiguration)'
  testCoverageThreshold: $(Config.TestCoverageThreshold)

stages:
  - stage: Build
    displayName: 'Build and Test'
    jobs:
      - job: Build
        displayName: 'Build and Test'
        pool:
          vmImage: 'windows-latest'
        steps:
          - task: UseDotNet@2
            inputs:
              version: '$(Get-LatestFrameworkVersion -SolutionInfo $SolutionInfo)'
              includePreviewVersions: false

          - task: NuGetToolInstaller@1

          - task: NuGetCommand@2
            inputs:
              restoreSolution: '$(solution)'

          - task: VSBuild@1
            inputs:
              solution: '$(solution)'
              platform: '$(buildPlatform)'
              configuration: '$(buildConfiguration)'

          - task: VSTest@2
            inputs:
              platform: '$(buildPlatform)'
              configuration: '$(buildConfiguration)'
              codeCoverageTool: 'Cobertura'
              testRunTitle: '$(Agent.OS)'

          - task: PublishCodeCoverageResults@1
            inputs:
              codeCoverageTool: 'Cobertura'
              summaryFileLocation: '$(Agent.TempDirectory)/**/coverage.cobertura.xml'
"@

        # Add deployment stages based on solution info
        foreach ($project in $SolutionInfo.Projects) {
            if ($project.Type -eq 'WebApp') {
                $pipelineYaml += @"

  - stage: DeployWebApp
    displayName: 'Deploy Web App'
    dependsOn: Build
    condition: succeeded()
    jobs:
      - deployment: Deploy
        displayName: 'Deploy to Azure Web App'
        environment: '$(Config.DeploymentEnvironments[0])'
        pool:
          vmImage: 'windows-latest'
        strategy:
          runOnce:
            deploy:
              steps:
                - task: AzureWebApp@1
                  inputs:
                    azureSubscription: '$(Config.AzureServiceConnection)'
                    appName: '$(Config.WebAppName)'
                    package: '$(System.DefaultWorkingDirectory)/**/*.zip'
"@
            }
            elseif ($project.Type -eq 'FunctionApp') {
                $pipelineYaml += @"

  - stage: DeployFunction
    displayName: 'Deploy Function App'
    dependsOn: Build
    condition: succeeded()
    jobs:
      - deployment: Deploy
        displayName: 'Deploy to Azure Function'
        environment: '$(Config.DeploymentEnvironments[0])'
        pool:
          vmImage: 'windows-latest'
        strategy:
          runOnce:
            deploy:
              steps:
                - task: AzureFunctionApp@1
                  inputs:
                    azureSubscription: '$(Config.AzureServiceConnection)'
                    appName: '$(Config.FunctionAppName)'
                    package: '$(System.DefaultWorkingDirectory)/**/*.zip'
"@
            }
        }

        return $pipelineYaml
    }
    catch {
        Write-Error "Failed to generate pipeline definition: $_"
        throw
    }
}

# Get latest framework version from solution
function Get-LatestFrameworkVersion {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [object]$SolutionInfo
    )

    try {
        $versions = $SolutionInfo.Projects | ForEach-Object { $_.FrameworkVersion } | Where-Object { $_ -ne $null }
        if ($versions) {
            return ($versions | Sort-Object -Descending)[0]
        }
        return '6.0.x'
    }
    catch {
        Write-Error "Failed to get latest framework version: $_"
        throw
    }
}

# Set up Azure DevOps pipeline
function Set-AzDevOpsPipeline {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [string]$PipelineYaml,

        [Parameter(Mandatory = $true)]
        [string]$PipelineName
    )

    try {
        $pipelineUrl = "$($script:AzDevOpsConfig.BaseUrl)/_apis/pipelines?api-version=6.0-preview.1"
        
        $pipelineBody = @{
            name = $PipelineName
            configuration = @{
                type = 'yaml'
                path = '/azure-pipelines.yml'
                content = $PipelineYaml
            }
            folder = '/'
        } | ConvertTo-Json -Depth 10

        $response = Invoke-RestMethod -Uri $pipelineUrl -Method Post -Headers $script:AzDevOpsConfig.Headers -Body $pipelineBody
        
        Write-Host "Successfully created pipeline: $PipelineName" -ForegroundColor Green
        return $response
    }
    catch {
        Write-Error "Failed to create pipeline: $_"
        throw
    }
}

# Configure Azure resources with intelligent deployment
function Set-AzureResources {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory = $true)]
        [object]$SolutionInfo,

        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    try {
        # Create resource group if it doesn't exist
        $resourceGroup = Get-AzResourceGroup -Name $Config.ResourceGroup -ErrorAction SilentlyContinue
        if (-not $resourceGroup) {
            Write-Host "Creating resource group: $($Config.ResourceGroup)" -ForegroundColor Yellow
            New-AzResourceGroup -Name $Config.ResourceGroup -Location $Config.Location
        }

        # Process each project's Azure dependencies
        foreach ($project in $SolutionInfo.Projects) {
            $projectDeps = Get-AzureDependencies -ProjectPath $project.Path
            
            foreach ($dep in $projectDeps) {
                $resourceName = Get-ResourceName -ProjectName $project.Name -Dependency $dep -Config $Config
                
                switch ($dep.Type) {
                    'WebApp' {
                        Create-WebApp -Name $resourceName -ResourceGroup $Config.ResourceGroup -Location $Config.Location -Runtime $dep.Runtime -OS $dep.OS
                    }
                    'FunctionApp' {
                        Create-FunctionApp -Name $resourceName -ResourceGroup $Config.ResourceGroup -Location $Config.Location -Runtime $dep.Runtime -OS $dep.OS
                    }
                    'KeyVault' {
                        Create-KeyVault -Name $resourceName -ResourceGroup $Config.ResourceGroup -Location $Config.Location -SKU $dep.SKU
                    }
                    'SqlDatabase' {
                        Create-SqlDatabase -Name $resourceName -ResourceGroup $Config.ResourceGroup -Location $Config.Location -Edition $dep.Edition -ServiceObjective $dep.ServiceObjective
                    }
                    'StorageAccount' {
                        Create-StorageAccount -Name $resourceName -ResourceGroup $Config.ResourceGroup -Location $Config.Location -SKU $dep.SKU
                    }
                    'ServiceBus' {
                        Create-ServiceBus -Name $resourceName -ResourceGroup $Config.ResourceGroup -Location $Config.Location -SKU $dep.SKU
                    }
                }
            }
        }

        Write-Host "Successfully configured Azure resources" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to configure Azure resources: $_"
        throw
    }
}

# Helper function to generate resource names
function Get-ResourceName {
    param (
        [string]$ProjectName,
        [object]$Dependency,
        [hashtable]$Config
    )

    # Clean project name for resource naming
    $cleanProjectName = $ProjectName -replace '[^a-zA-Z0-9]', ''
    
    # Generate environment-specific name
    $env = $Config.DeploymentEnvironments[0] # Use first environment for resource creation
    return "$cleanProjectName-$($Dependency.Type.ToLower())-$env"
}

# Helper functions for creating specific resources
function Create-WebApp {
    param (
        [string]$Name,
        [string]$ResourceGroup,
        [string]$Location,
        [string]$Runtime,
        [string]$OS
    )
    
    $appServicePlanName = "$Name-plan"
    $appServicePlan = New-AzAppServicePlan -Name $appServicePlanName -ResourceGroupName $ResourceGroup -Location $Location -Tier "Basic" -WorkerSize "Small" -OperatingSystem $OS
    
    New-AzWebApp -Name $Name -ResourceGroupName $ResourceGroup -Location $Location -AppServicePlan $appServicePlanName -RuntimeStack $Runtime
}

function Create-FunctionApp {
    param (
        [string]$Name,
        [string]$ResourceGroup,
        [string]$Location,
        [string]$Runtime,
        [string]$OS
    )
    
    $storageAccountName = "$Name`storage".ToLower()
    $storageAccount = New-AzStorageAccount -Name $storageAccountName -ResourceGroupName $ResourceGroup -Location $Location -SkuName "Standard_LRS"
    
    $appServicePlanName = "$Name-plan"
    $appServicePlan = New-AzAppServicePlan -Name $appServicePlanName -ResourceGroupName $ResourceGroup -Location $Location -Tier "Dynamic" -WorkerSize "Small" -OperatingSystem $OS
    
    New-AzFunctionApp -Name $Name -ResourceGroupName $ResourceGroup -Location $Location -StorageAccountName $storageAccountName -AppServicePlanName $appServicePlanName -Runtime $Runtime
}

function Create-KeyVault {
    param (
        [string]$Name,
        [string]$ResourceGroup,
        [string]$Location,
        [string]$SKU
    )
    
    New-AzKeyVault -Name $Name -ResourceGroupName $ResourceGroup -Location $Location -Sku $SKU
}

function Create-SqlDatabase {
    param (
        [string]$Name,
        [string]$ResourceGroup,
        [string]$Location,
        [string]$Edition,
        [string]$ServiceObjective
    )
    
    $serverName = "$Name-server"
    $server = New-AzSqlServer -Name $serverName -ResourceGroupName $ResourceGroup -Location $Location -SqlAdministratorLogin "admin" -SqlAdministratorLoginPassword (New-Guid).ToString()
    
    New-AzSqlDatabase -Name $Name -ResourceGroupName $ResourceGroup -ServerName $serverName -Edition $Edition -RequestedBackupStorageRedundancy "Geo"
}

function Create-StorageAccount {
    param (
        [string]$Name,
        [string]$ResourceGroup,
        [string]$Location,
        [string]$SKU
    )
    
    New-AzStorageAccount -Name $Name -ResourceGroupName $ResourceGroup -Location $Location -SkuName $SKU
}

function Create-ServiceBus {
    param (
        [string]$Name,
        [string]$ResourceGroup,
        [string]$Location,
        [string]$SKU
    )
    
    New-AzServiceBusNamespace -Name $Name -ResourceGroupName $ResourceGroup -Location $Location -SkuName $SKU
}

# Export module members
Export-ModuleMember -Function @(
    'Initialize-AzDevOpsPipeline',
    'Get-SolutionAnalysis',
    'New-PipelineDefinition',
    'Set-AzDevOpsPipeline',
    'Set-AzureResources',
    'Get-ProjectType',
    'Get-FrameworkVersion',
    'Is-TestProject',
    'Get-AzureDependencies'
) 