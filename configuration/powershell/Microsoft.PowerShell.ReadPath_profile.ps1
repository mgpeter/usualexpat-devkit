# Path to your separate script file
$scriptPath = "D:\repos\usualexpat-devkit\configuration\Microsoft.PowerShell_profile.ps1"

# Check if the script file exists
if (Test-Path $scriptPath) {
    $env:ohMyPoshConfig = "D:\repos\usualexpat-devkit\configuration\.mytheme-new.omp.json"
    # Execute the script file
} else {
    $scriptPath = "C:\repos\usualexpat-devkit\configuration\Microsoft.PowerShell_profile.ps1"
    $env:ohMyPoshConfig = "C:\repos\usualexpat-devkit\configuration\.mytheme-new.omp.json"
}

. $scriptPath