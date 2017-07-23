<#
    This module is an attempt to emulate a dry run of the infrastructure
    deployment and all the final results from a deployment.
#>

Start-DryHailmary {
    Param (
        # Parameters will be added as necessary to keep up-to-date with the steps above during development.
        [string]$ConfigFile = "$($ISTS_ModulePath)\ISTS-Config.yaml",
        [int[]]$TeamNumbers = $null
    )
    # Initial Setup

    # Get array of team numbers
    if($TeamNumbers -eq $null) {
        $TeamNumbers = 1..$ISTS.config.NumberOfTeams
    }
    Write-Host "TeamNumbers: $TeamNumbers`n"

    # Importing config
    Import-ISTSYAMLConfig -ConfigFile $ConfigFile -ErrorAction Stop

    # vCenter Connection
    Write-Host "vCenter Connection Options:" -ForegroundColor Green
    Write-Host "Address: $($ISTS.vCenter.Address)"
    Write-Host "Username: $($ISTS.vCenter.Username)"
    Write-Host "Password: $($ISTS.vCenter.Password)"
    Write-Host

    # Add Team Accounts
    Write-Host "Team Account Options:" -ForegroundColor Green
    $AccountPassword = $ISTS.vCenter.Permissions.TeamPassword
    foreach($TeamNumber in $TeamNumbers) {
        $NewAccountName = $ISTS.Templates.Username.Replace('$TeamNumber', $TeamNumber)
        Write-Host "Team $TeamNumber Account: $NewAccountName"
        Write-Host "Team $TeamNumber Password: $AccountPassword"
        Write-Host "Team $TeamNumber Description: Team $TeamNumber's Account"
    }
    Write-Host

    # Add Team Networks
    Write-Host "Team Network Options:" -ForegroundColor Green
    Write-Host "Competition Switch: $($ISTS.vCenter.CompetitionVDSwitch)"
    foreach ($Network in $ISTS.NetworkConfig.Networks.Keys) {
            # Calculate VLAN ID
            $VLAN_ID = Invoke-Expression -Command $ISTS.NetworkConfig.Networks.$Network.VLAN_ID.Replace('$StartingVLANID', $ISTS.NetworkConfig.StartingVLANID).Replace('$TeamNumber', $TeamNumber)
            $PortGroupName = $ISTS.Templates.NetworkName.Replace('$TeamNumber', $TeamNumber).Replace('$Network', $Network).Replace('$VLAN_ID', $VLAN_ID)
            
            $PortGroups.Add([PSCustomObject]@{"PortGroupName"=$PortGroupName;"VLAN"=$VLAN_ID})
    }
    Write-Host $PortGroups
    Write-Host

    # Add Team Folders
    Write-Host "Team Folder Options:" -ForegroundColor Green
    Write-Host "Parent Folder: `"Datacenter\Team Folders`""
    foreach($TeamNumber in $TeamNumbers) {
        $FolderName = $ISTS.Templates.FolderName.Replace('$TeamNumber', $TeamNumber)
        New-Folder -Name $FolderName -Location $ParentFolder | Out-Null
        $Folders.Add([System.Management.Automation.PSCustomObject]@{"TeamNumber"=$TeamNumber;"Folder Name"=$FolderName})
    }
    Write-Host $Folders
    Write-Host

    # Start vApp Deployment
    Write-Host "vApp Deployment Options:" -ForegroundColor Green
    Write-Host "Template vApp: $($ISTS.Config.TemplateVApp)"
    Write-Host "StartVApp: $($ISTS.Config.StartVAppAfterDeploy)"
    $StartTime = Get-Date
    Write-Host "Team Networks: $($ISTS.NetworkConfig.Networks.Keys)"
    foreach($TeamNumber in $TeamNumbers) {
        $VApps.Add([System.Management.Automation.PSCustomObject]@{"vApp Name"=$ISTS.Templates.vAppName.Replace('$TeamNumber', $TeamNumber)})
    }
}
