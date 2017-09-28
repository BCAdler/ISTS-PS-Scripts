# Example CSV Format
# Purpose,VLAN ID,IP Address,Subnet
# P2P Router_VLAN20,20,10.0.0.1,10.0.0.0/24

# May need to change csv file name
$csv=Import-Csv vlan_info_final.csv
foreach ($row in $csv){
    $purpose=$row.'Purpose'
    $vlan = $row.'VLAN ID'
    $ip=$row.'IP Address'

    # May need to change switch name
    Get-VDSwitch -Name "MainSwitch" | New-VDPortgroup -VLANId $vlan -Name $purpose
}
