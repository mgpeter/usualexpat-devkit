@{
    # Script module or binary module file associated with this manifest.
    RootModule = 'AzDevOpsPipelineAutomation.psm1'

    # Version number of this module.
    ModuleVersion = '0.1.0'

    # ID used to uniquely identify this module
    GUID = '12345678-1234-1234-1234-123456789012'

    # Author of this module
    Author = 'Usual Expat'

    # Company or vendor of this module
    CompanyName = 'Usual Expat'

    # Copyright statement for this module
    Copyright = '(c) 2024 Usual Expat. All rights reserved.'

    # Description of the functionality provided by this module
    Description = 'Azure DevOps Pipeline Automation - Automatically generate and configure pipelines based on repository structure'

    # Minimum version of the PowerShell engine required by this module
    PowerShellVersion = '7.0'

    # Functions to export from this module
    FunctionsToExport = @(
        'Initialize-AzDevOpsPipeline',
        'New-AzDevOpsPipeline',
        'Set-AzDevOpsDeploymentConfig',
        'Invoke-AzDevOpsPipelineGeneration',
        'Get-SolutionAnalysis',
        'New-PipelineDefinition',
        'Set-AzDevOpsPipeline',
        'Set-AzureResources',
        'Get-ProjectType',
        'Get-FrameworkVersion',
        'Get-TestProjects',
        'Get-AzureDependencies'
    )

    # Cmdlets to export from this module
    CmdletsToExport = @()

    # Variables to export from this module
    VariablesToExport = '*'

    # Aliases to export from this module
    AliasesToExport = @()

    # Dependencies to import
    RequiredModules = @(
        @{ ModuleName='Az'; ModuleVersion='10.0.0' }
        @{ ModuleName='Az.Accounts'; ModuleVersion='2.12.0' }
        @{ ModuleName='Az.Resources'; ModuleVersion='6.5.0' }
        @{ ModuleName='Az.Websites'; ModuleVersion='2.12.0' }
        @{ ModuleName='Az.Functions'; ModuleVersion='4.0.0' }
    )

    # Private data to pass to the module specified in RootModule/ModuleToProcess
    PrivateData = @{
        PSData = @{
            # Tags applied to this module
            Tags = @('Azure', 'DevOps', 'Pipeline', 'Automation', 'CI/CD')

            # License URI for this module
            LicenseUri = 'https://github.com/mgpeter/usualexpat-devkit/blob/main/LICENSE'

            # Project URI for this module
            ProjectUri = 'https://github.com/mgpeter/usualexpat-devkit'

            # ReleaseNotes of this module
            ReleaseNotes = 'Initial release of Azure DevOps Pipeline Automation module'
        }
    }
} 