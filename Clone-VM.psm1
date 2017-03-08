function New-ISTSVMClone {
    param (
        [Parameter(Mandatory=$true)][string]$VMName,
        [Parameter(Mandatory=$true)][string]$VMTemplate
    )
    $template = Get-Template -Name $VMTemplate

    $vapps = Get-VApp -Name Team*

    foreach($vapp in $vapps) {
        New-VM -Template $template -VApp $vapp -Name "$($vapp.Name) - $VMName"
    } 
}

function Set-MassVMNetworking {
    param (
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

function Set-ISTSVMName {
    param (
        [Parameter(Mandatory=$true)][int[]]$TeamNumbers
    )
    foreach ($i in $TeamNumbers) {
        $vms = Get-VApp -Name "Team $i" | Get-VM
        foreach($vm in $vms) {
            Set-VM -VM $vm -Name "Team $i - $($vm.Name.Split('-').Trim()[1])" -Confirm:$false -RunAsync
        }
    }
}

function Remove-AllTeamVMFromDisk {
    param (
        [Parameter(Mandatory=$true)][string]$VM
    )

    Write-Host "Stopping and Destroying all `"$VM`" VMs" -ForegroundColor Red
    $vms = Get-VM -Name "*$VM"
    $task = Stop-VM -VM $vms -Kill -RunAsync -Confirm:$false
    Wait-Task -Task $task

    Write-Host "Deleting all `"$VM`" VMs from disk" -ForegroundColor Red
    $task = Remove-VM -VM $vms -DeletePermanently -RunAsync -Confirm:$false
    Wait-Task -Task $task
}
