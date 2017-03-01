#Example CSV Format
#Purpose,VLAN ID,IP Address,Subnet
#P2P Router_VLAN20,20,10.0.0.1,10.0.0.0/24

#May need to change csv file name
$all=Import-Csv vlan_info_final.csv
ForEach($line in $all){
$purpose=$line.'Purpose'
$vlan = $line.'VLAN ID'
$ip=$line.'IP Address'

#May need to change switch name
Get-VDSwitch -Name "MainSwitch" | New-VDPortgroup -VLANId $vlan -Name $purpose
}