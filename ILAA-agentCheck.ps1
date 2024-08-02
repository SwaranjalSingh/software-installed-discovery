# Define log folder path and create a new log file with timestamp
$logFolder = "Logs"
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$logFile = "$logFolder\Discovery-Logs-$timestamp.log"

# Function to log messages
function Write-Log {
    param (
        [string]$message,
        [string]$level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "$timestamp [$level] $message"
    Add-Content -Path $logFile -Value $logMessage
}

# Ensure the log folder exists
if (-not (Test-Path -Path $logFolder)) {
    New-Item -Path $logFolder -ItemType Directory -Force
    Write-Log "Log folder created at $logFolder."
}

Write-Log "Script started."

try {
    # Retrieve all Log Analytics workspaces in the subscription
    $workspaces = az monitor log-analytics workspace list | ConvertFrom-Json
    Write-Log "Retrieved Log Analytics workspaces."

    foreach ($workspace in $workspaces) {
        $rgName = $workspace.resourceGroup
        $wsName = $workspace.name
        $wsID = $workspace.customerId
        Write-Log "Processing Log Analytics Workspace: $wsName in Resource Group: $rgName"

        # Get the shared keys for the specified Log Analytics workspace
        $sharedKeys = az monitor log-analytics workspace get-shared-keys `
            --resource-group $rgName `
            --workspace-name $wsName | ConvertFrom-Json

        $WorkspaceId = $wsID
        $WorkspaceKey = $sharedKeys.primarySharedKey
        Write-Log "Obtained shared keys for workspace $wsName."

        # Get all running VMs in the subscription
        $runningVms = az vm list -d --query "[?powerState=='VM running']" | ConvertFrom-Json
        Write-Log "Retrieved running VMs."

        foreach ($runningVm in $runningVms) {
            $vmRg = $runningVm.resourceGroup
            $vmName = $runningVm.name
            $vmLocation = $runningVm.location
            $osType = $runningVm.storageProfile.osDisk.osType

            Write-Log "Processing VM: $vmName in Resource Group: $vmRg with OS type: $osType"

            # Determine the appropriate agent based on the OS type
            $extensionName = if ($osType -eq "Windows") { "OmsAgentForWindows" } else { "OmsAgentForLinux" }
            $publisher = "Microsoft.EnterpriseCloud.Monitoring"

            # Check if the extension is already installed
            $installedExtensions = az vm extension list `
                --resource-group "$vmRg" `
                --vm-name "$vmName" | ConvertFrom-Json

            $isInstalled = $installedExtensions | Where-Object { $_.name -eq $extensionName -and $_.publisher -eq $publisher }

            if ($isInstalled) {
                Write-Log "$extensionName is already installed on $vmName." -level "INFO"
            } else {
                Write-Log "Installing $extensionName on $vmName"
                az vm extension set `
                    --resource-group "$vmRg" `
                    --vm-name "$vmName" `
                    --location "$vmLocation" `
                    --publisher "$publisher" `
                    --name "$extensionName" `
                    --version "1.0" `
                    --settings "{ \"workspaceId\": \"$WorkspaceId\" }" `
                    --protected-settings "{ \"workspaceKey\": \"$WorkspaceKey\" }"
                Write-Log "Installed $extensionName on $vmName."
            }

            Write-Log "------------------------------------------"
        }
    }
    Write-Log "Script completed successfully."
} catch {
    Write-Log "An error occurred: $_" -level "ERROR"
}
