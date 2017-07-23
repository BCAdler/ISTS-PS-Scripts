<#
    Helper functions used for automation of general infrastructure tasks.
#>

<#
    .SYNOPSIS
    Connects to vCenter from config or prompt.

    .DESCRIPTION
    Connects to vCenter from config or prompt.

    .PARAMETER ISTS_VCenterCred
    Parameter description

    .EXAMPLE
    An example

    .NOTES
    Throws error if already connected.
#>
function Connect-VCenter {
    Param (
        [PSCredential]$vCenterCred = $null
    )
    # If credential parameter is null, get connection parameters from config
    if($vCenterCred = $null) {
        $vCenterPass = ConvertTo-SecureString -String $ISTS.vCenter.Password -AsPlainText -Force
        $vCenterCred = New-Object System.Management.Automation.PSCredential($ISTS.vcenter.username, $vCenterPass)
    }

    try { #make sure we aren't already connected
        $server = (Get-VIAccount -ErrorAction SilentlyContinue)[0].Server.Name
        Write-Warning "It looks like you are already connected to the server at `"$server`", disconnect with Disconnect-VIServer and then try again"
    } catch { 
        Connect-VIServer -Server $ISTS.vCenter.Address -Protocol Https -Force -ErrorAction Stop -Credential $ISTS_VCenterCred
    }
}

<#
    .SYNOPSIS
    Run a simple test to see if the VCenter server is connected.

    .DESCRIPTION
    Run a simple test to see if the VCenter server is connected.

    .EXAMPLE
    An example

    .OUTPUTS
    Returns $true if vcenter is connected, $false if not.

    .NOTES
    Throws error if check fails.
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

<#
    .SYNOPSIS
    Creates snapshots for all of the VM belonging to the specified teams.

    .DESCRIPTION
    Creates snapshots for all of the VM belonging to the specified teams.

    .PARAMETER TeamNumbers
    Team numbers to take snapshots for.

    .PARAMETER SnapshotName
    Name of the snapshots to take.

    .PARAMETER SnapshotDescription
    Description of the snapshots to take.

    .PARAMETER VMName
    Use this to if you only want to take snapshots of a specific VM for each team.

    .EXAMPLE
    An example

    .NOTES
    General notes
#>
function New-Snapshots {
    Param (
        [Parameter(Mandatory=$true)][int[]]$TeamNumbers,
        [Parameter(Mandatory=$true)][string]$SnapshotName,
        [string]$SnapshotDescription = "",
        [string]$VMName = ""
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

<#
    .SYNOPSIS
    Reverts team VMs to the specific snapshot specified.

    .DESCRIPTION
    Reverts team VMs to the specific snapshot specified. Automatically runs asynchronously without confirmation.

    .PARAMETER TeamNumbers
    Team numbers to revert the specified snapshot for.

    .PARAMETER SnapshotName
    Name of the snapshot to revert the VMs to.

    .PARAMETER VMName
    Use this to if you only want to rever to the snapshot of a specific VM for each team.

    .EXAMPLE
    An example

    .NOTES
    General notes
#>
function Reset-Snapshots {
    Param (
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

<#
    .SYNOPSIS
    Permanently deletes all of the VMs matching the name specified.

    .DESCRIPTION
    Permanently deletes all of the VMs matching the name specified.  Will go through entire vCenter looking for VMs matching using the logic (*$VM).

    .PARAMETER VM
    Name of the VM to delete from disk for every team.

    .EXAMPLE
    An example

    .NOTES
    Generally used when there is a deployment issue found in a single VM for all of the teams.
#>
function Remove-AllTeamVMFromDisk {
    Param (
        [Parameter(Mandatory=$true)][string]$VM
    )
    # TODO: Exclude any VMs belonging to Team 0.
    $vms = Get-VM -Name "*$VM"
    foreach ($vm in $vms) {
        Write-Host $vm.Name -ForegroundColor Red
    }

    $PromptTitle = "ALL TEAM VM DELETION!"
    $PromptMessage = "Verify you would like to delete ALL of the VMs listed above."
    if(!Invoke-ISTSConfirmPrompt -Title $PromptTitle -Message $PromptMessage) {
        return
    }

    Write-Host "Stopping and Destroying all `"$VM`" VMs" -ForegroundColor Red
    
    $task = Stop-VM -VM $vms -Kill -RunAsync -Confirm:$false
    Wait-Task -Task $task

    Write-Host "Deleting all `"$VM`" VMs from disk" -ForegroundColor Red
    $task = Remove-VM -VM $vms -DeletePermanently -RunAsync -Confirm:$false
    Wait-Task -Task $task
}

<#
    .SYNOPSIS
    PREMATURE FUNCTION
    Sets the networking on the specified team numbers.

    .DESCRIPTION
    PREMATURE FUNCTION
    Sets the networking on the specified team numbers.

    .PARAMETER TeamNumbers
    List of team numbers to set the VM networking for.

    .EXAMPLE
    An example

    .NOTES
    This function is currently incomplete but will be finished at some point.
#>
function Set-MassVMNetworking {
    Param (
        [Parameter(Mandatory=$true)][int[]]$TeamNumbers
    )

    # Get Team Network CSV 
    $TeamNetworksCsv = Import-Csv .\vlan_info_final.csv
    $ProdVMs = "Web","DB","Win8"
    $CorpVMs = "AD","Mail","Kali","Parrot","VOIP"

    foreach ($i in $TeamNumbers) {
        # Get all VMs in the new vApp
        $vms = Get-VApp -Name "Team $i" | Get-VM
        foreach($vm in $vms) {
            if($CorpVMs -contains $vm.Name.Split('-').Trim()[1]) {
                $PortGroup = Get-VDPortGroup -Name ($TeamNetworksCsv.Purpose -like "Team $i Corp*")
            }
            elseif($ProdVMs -contains $vm.Name.Split('-').Trim()[1]) {
                $PortGroup = Get-VDPortGroup -Name ($TeamNetworksCsv.Purpose -like "Team $i Prod*")
            }

            # Change VM port group
            $vm | Get-NetworkAdapter | Set-NetworkAdapter -Portgroup $PortGroup -Confirm:$false -RunAsync
        }
    }
}

<#
    .SYNOPSIS
    Sets the names for the specified teams. To be used after deployment.

    .DESCRIPTION
    Sets the names for the specified teams. To be used after deployment.

    .PARAMETER TeamNumbers
    List of team numbers to rename VMs for.

    .EXAMPLE
    An example

    .NOTES
    Based off of the VM naming format "Team 0 - Function"
#>
function Set-VMName {
    Param (
        [Parameter(Mandatory=$true)][int[]]$TeamNumbers
    )
    foreach ($i in $TeamNumbers) {
        $vms = Get-VApp -Name "Team $i" | Get-VM
        foreach($vm in $vms) {
            Set-VM -VM $vm -Name "Team $i - $($vm.Name.Split('-').Trim()[1])" -Confirm:$false -RunAsync
        }
    }
}

<#
    .SYNOPSIS
    DEPRECATED - Use Start-ISTSVAppDeployment
    Clones a VM from a template into all of the team vApps available.

    .DESCRIPTION
    DEPRECATED - Use Start-ISTSVAppDeployment
    Clones a VM from a template into all of the team vApps available.

    .PARAMETER VMName
    Parameter description

    .PARAMETER VMTemplate
    Parameter description

    .EXAMPLE
    An example

    .NOTES
    DEPRECATED - Use Start-ISTSVAppDeployment
#>
function New-VMClone {
    Param (
        [Parameter(Mandatory=$true)][string]$VMName,
        [Parameter(Mandatory=$true)][string]$VMTemplate
    )
    $template = Get-Template -Name $VMTemplate

    $vapps = Get-VApp -Name Team*

    foreach($vapp in $vapps) {
        New-VM -Template $template -VApp $vapp -Name "$($vapp.Name) - $VMName"
    } 
}
