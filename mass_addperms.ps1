$ROLE_NAME = "BlueTeam"

$csv = Import-Csv -Path '.\team_users.csv' -Header name, teamid

Foreach($user in $csv) {
    $vms = Get-VM -name "Team $($user.teamid) *"
    Foreach($vm in $vms) {
        $role = Get-VIRole -Name "$ROLE_NAME"
        Write-Host "Assigning Role $($role) to: $($vm.Name)"
        New-VIPermission -Entity ($vm) -Role ($role) -Principal "WHITETEAM.VSPHERE\$($user.name)"
    }
}
