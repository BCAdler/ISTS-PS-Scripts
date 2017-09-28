<#
    This module is an attempt to emulate a dry run of the infrastructure
    deployment and all the final results from a deployment.
#>

function Start-DryHailmary {
    Param (
        # Parameters will be added as necessary to keep up-to-date with the steps above during development.
        [string]$ConfigFile = "$($ISTS_ModulePath)\ISTS-Config.yml",
        [int[]]$TeamNumbers = $null
    )
    # Initial Setup

    # Get array of team numbers
    if($TeamNumbers -eq $null) {
        $TeamNumbers = 1..$ISTS.Config.NumberOfTeams
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
    $PortGroups = New-Object System.Collections.ArrayList
    foreach($TeamNumber in $TeamNumbers) {
        foreach ($Network in $ISTS.NetworkConfig.Networks.Keys) {
            #Write-Host "Network: $Network"
            # Calculate VLAN ID
            $VLAN_ID = Invoke-Expression -Command $ISTS.NetworkConfig.Networks.$Network.VLAN_ID.Replace('$StartingVLANID', $ISTS.NetworkConfig.StartingVLANID).Replace('$TeamNumber', $TeamNumber)
            $PortGroupName = $ISTS.Templates.NetworkName.Replace('$TeamNumber', $TeamNumber).Replace('$Network', $Network).Replace('$VLAN_ID', $VLAN_ID)
            
            $PortGroups.Add((New-Object -TypeName psobject -Property @{"PortGroupName"=$PortGroupName;"VLAN"=$VLAN_ID})) | Out-Null
        }
    }

    Write-Output $PortGroups | Format-Table
    Write-Host

    # Add Team Folders
    Write-Host "Team Folder Options:" -ForegroundColor Green
    Write-Host "Parent Folder: `"Datacenter\Team Folders`""
    $Folders = New-Object System.Collections.ArrayList
    foreach($TeamNumber in $TeamNumbers) {
        $FolderName = $ISTS.Templates.FolderName.Replace('$TeamNumber', $TeamNumber)
        $Folders.Add((New-Object -TypeName psobject -Property @{"TeamNumber"=$TeamNumber;"Folder Name"=$FolderName})) | Out-Null
    }
    Write-Host $Folders
    Write-Host

    # Start vApp Deployment
    Write-Host "vApp Deployment Options:" -ForegroundColor Green
    Write-Host "Template vApp: $($ISTS.Config.TemplateVApp)"
    Write-Host "StartVApp: $($ISTS.Config.StartVAppAfterDeploy)"
    $VApps = New-Object System.Collections.ArrayList
    $StartTime = Get-Date
    Write-Host "Team Networks: $($ISTS.NetworkConfig.Networks.Keys)"
    foreach($TeamNumber in $TeamNumbers) {
        $VApps.Add((New-Object -TypeName psobject -Property (@{"vApp Name"=$ISTS.Templates.vAppName.Replace('$TeamNumber', $TeamNumber)}))) | Out-Null
    }

    Write-Host "VApps: "
    Write-Output $VApps | Format-Table
    Write-Host "VApp Deployment Start: $StartTime"
    Write-Host "VApp Deployment End: $(Get-Date)"
}
