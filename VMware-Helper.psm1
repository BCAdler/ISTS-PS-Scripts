<#
    Helper functions used for automation of general infrastructure tasks.
#>

<# Name:        Connect-ISTSVCenter
 # Description: Connects to vcenter from config or prompt
 # Params:      None
 # Returns:     None
 # Throws:      Error if already connected
 # Note:        Creds from the config file are stored as plaintext in memory! Be careful! 
 #>
function Connect-VCenter {
    param (
        [PSCredential]$ISTS_VCenterCred
    )
    try { #make sure we aren't already connected
        $server = (Get-VIAccount -ErrorAction SilentlyContinue)[0].Server.Name
        Write-Warning "It looks like you are already connected to the server at `"$server`", disconnect with Disconnect-VIServer and then try again"
    } catch { 
        if ($ISTS_VCenterCred){
            #Write-Warning "These credentials are stored in memory in plain text, just so you know"
            Connect-VIServer -Server $ISTS_VCenterServerAddress -Protocol Https -Force -ErrorAction Stop -Credential $ISTS_VCenterCred
        } else {
            Connect-VIServer -Server $ISTS_VCenterServerAddress -Protocol Https -Force -ErrorAction Stop
        }
    }
}

<# Name:        Get-VCenterConnectionStatus
 # Description: Run a simple test to see if the VCenter server is connected
 # Params:      None
 # Returns:     $true if vcenter is connected, $false if not
 # Throws:      Error if check fails
 #>
function Get-VCenterConnectionStatus {
    try {
        $server = (Get-VIAccount -ErrorAction SilentlyContinue)[0].Server.Name
        return $true
    } catch { 
        Write-Error "The vCenter Server is NOT connected, run Connect-ISTSVCenter to connect"
        return $false
    }
}

<# Name:        New-ISTSSnapshots
 # Description: Clones Team 0 / Template vApp to other teams and configures the VMs
 # Params:      TeamNumbers     - int[] - Team numbers to create vApp for
 #              TemplateVApp    - string - Name of vApp to use as template
 #              PathToTeamNetworkCsv - string - Path to CSV for Team Networks
 #                                              Defaults to same directory as module
 # Returns:     None
 # Throws:      None
 #>
function New-Snapshots {
    param (
        [Parameter(Mandatory=$true)][int[]]$TeamNumbers,
        [Parameter(Mandatory=$true)][string]$SnapshotName,
        [string]$VMName = "",
        [string]$SnapshotDescription = ""
    )

    foreach($i in $TeamNumbers) {
        if($VMName -eq ""){
            $vms = Get-VApp -Name "Team $i" | Get-VM
        }
        else {
            $vms = Get-VApp -Name "Team $i" | Get-VM -Name $VMName
        }
        foreach($vm in $vms) {
            New-Snapshot -VM $vm -Name $SnapshotName -Description $SnapshotDescription -RunAsync
        }
    }
}

<# Name:        New-ISTSSnapshots
 # Description: Clones Team 0 / Template vApp to other teams and configures the VMs
 # Params:      TeamNumbers     - int[] - Team numbers to create vApp for
 #              TemplateVApp    - string - Name of vApp to use as template
 #              PathToTeamNetworkCsv - string - Path to CSV for Team Networks
 #                                              Defaults to same directory as module
 # Returns:     None
 # Throws:      None
 #>
function Reset-Snapshots {
    param (
        [Parameter(Mandatory=$true)][int[]]$TeamNumbers,
        [Parameter(Mandatory=$true)][string]$SnapshotName,
        [string]$VMName = ""
    )

    foreach($i in $TeamNumbers) {
        if($VMName -eq ""){
            $vms = Get-VApp -Name "Team $i" | Get-VM
        }
        else {
            $vms = Get-VApp -Name "Team $i" | Get-VM -Name "* $VMName"
        }
        foreach($vm in $vms) {
            Set-VM -VM $vm -Snapshot (Get-Snapshot -VM $vm -Name $SnapshotName) -RunAsync -Confirm:$false
            Write-Host "VM: " + $vm.Name + "`tState: "+ $vm.PowerState
        }
    }
}
