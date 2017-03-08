param (
    [Parameter(Mandatory=$true)][int[]]$TeamNumbers
)
$ROLE_NAME = "BlueTeam"

foreach($i in $TeamNumbers) {
    $vms = Get-VM -Name "Team $i *"
    foreach($vm in $vms) {
        $role = Get-VIRole -Name "$ROLE_NAME"
        Write-Host "Assigning Role $role to: $($vm.Name)"
        New-VIPermission -Entity $vm -Role $role -Principal "WHITETEAM.VSPHERE\Team$i"
    }
}
