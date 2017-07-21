<#
    Functions to automate deploying of virtualized infrastructure.
#>

<#
    .SYNOPSIS
    Clones Team 0 / Template vApp to other teams and configures the VMs.

    .DESCRIPTION
    Clones Team 0 / Template vApp to other teams and configures the VMs.

    .PARAMETER TeamNumbers
    Team numbers to create vApp for.

    .PARAMETER TemplateVAppName
    Name of vApp to use as template.

    .PARAMETER OverrideDatastore
    Parameter description

    .PARAMETER StartVApp
    Specified whether to start vApp automatically after deployment.

    .PARAMETER PathToTeamNetworkCsv
    Path to CSV for Team Networks.

    .EXAMPLE
    An example

    .NOTES
    General notes
#>
function Start-VAppDeployment {
    Param (
        [Parameter(Mandatory=$true)][int[]]$TeamNumbers,
        [string]$TemplateVAppName = $ISTS.Config.TemplateVApp,
        [string]$OverrideDatastore,
        [switch]$StartVApp
    )
    # Time how long it takes to deploy a team
    $StartTime = Get-Date

    # Initial Config Variables
    # Get Team Networks 
    $TeamNetworks = $ISTS.NetworkConfig.Networks.Keys
    # Get template vApp object from its name
    $TemplateVApp = Get-VApp -Name $TemplateVAppName

    # Get Host Cluster or single host
    $Location = Get-Cluster
    if($Location -eq $null) {
        $Location = $(Get-VMHost)[0]
    }
    
    foreach($TeamNumber in $TeamNumbers) {
        # Get Datastore Cluster or Datastore with most free space.  
        $Datastore = Get-DatastoreCluster
        if($Datastore -eq $null) {
            $Datastores = Get-Datastore
            $Datastore = $Datastores[0]
            foreach($store in $Datastores) {
                if($store.FreeSpaceGB -gt $Datastore.FreeSpaceGB) {
                    $Datastore = $store
                }
            }
        }

        $VAppName = $ISTS.Templates.vAppName.Replace('$TeamNumber', $TeamNumber)
        if((Get-VApp -Name $VAppName) -eq $null) {
            # Start cloning of template vApp and wait until it is done to continue.
            Write-Host "Starting $VAppName vApp Cloning..." -ForegroundColor Yellow
            $CloneTask = New-VApp -Name $VAppName -Location $Location -VApp $TemplateVApp -Datastore $Datastore
            if(!$?) {
                Write-Host "Cloning vApp Failed..." -ForegroundColor Red -BackgroundColor Black
                exit
            }
            Wait-Task -Task $CloneTask
            Write-Host "$VAppName vApp Cloning Complete" -ForegroundColor Green
        }
        else {
            Write-Host "vApp `"$VAppName`" Already Exists...  Continuing" -ForegroundColor Yellow
        }
        
        Write-Host "`nRenaming and Configuring Networking for $VAppName's VMs." -ForegroundColor Yellow

        # Get all VMs in the new vApp
        $VMs = Get-VApp -Name $VAppName | Get-VM

        # For all VMs in new vApp, assign each to their respective team's network
        foreach($VM in $VMs) {
            foreach($TeamNetwork in $TeamNetworks) {
                $Net = $ISTS.NetworkConfig.Networks.$TeamNetwork
                if($Net.VMs -contains $VM.Name.Split('-').Trim()[1]) {
                    # Get network name template from config and input variables.  Using * at end to avoid VLAN calculation which isn't necesary here.
                    $PortGroupName = "$($ISTS.Templates.NetworkName.Replace('$TeamNumber', $TeamNumber).Replace('$Network', $TeamNetwork))*"
                    $PortGroup = Get-VDPortGroup -Name $PortGroupName
                    continue
                }
            }

            # Change VM port group
            $VM | Get-NetworkAdapter | Set-NetworkAdapter -Portgroup $PortGroup -Confirm:$false

            # Change VM name
            $VMName = $ISTS.Templates.VMName.Replace('$TeamNumber', $TeamNumber).Replace('$VMName', $VM.Name.Split('-').Trim()[1])
            Set-VM -VM $VM -Name $VMName -Confirm:$false
        }
        
        # Start new vApp if $StartVApp switch is $true
        if($StartVApp) {
            Start-VApp -VApp (Get-VApp -Name $VAppName) -RunAsync
            Write-Host "$VAppName vApp starting." -ForegroundColor Yellow
        }
        Write-Host "Configuration for $VAppName complete!" -ForegroundColor Green
        Write-Host "Script Start: $StartTime" -ForegroundColor Green
        Write-Host "Script End: $(Get-Date)" -ForegroundColor Green
    }
}

<#
    .SYNOPSIS
    Mass adds organizational folders based on team numbers.

    .DESCRIPTION
    Mass adds organizational folders based on team numbers.

    .PARAMETER TeamNumbers
    List of team numbers to add folders for.

    .PARAMETER ParentFolder
    Folder to place created folders under.

    .EXAMPLE
    An example

    .NOTES
    General notes
#>
function Add-VMFolders {
    Param (
        [Parameter(Mandatory=$true)][int[]]$TeamNumbers,
        [Parameter(ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Impl.V1.Inventory.FolderImpl]$ParentFolder
    )
    
    # Remove this statement and have the parameter $ParentFolder default to Get-Datacenter[0].  Must change the type to VIContainer.
    if (!$ParentFolder) {
        $message = "No parent folder specified. Create folders in the root of the first datacenter ($((Get-Datacenter)[0]))?"
        if (!(Invoke-ConfirmPrompt -Message $message)) {
            return
        }
    }

    foreach($TeamNumber in $TeamNumbers) {
        $FolderName = $ISTS.Templates.FolderName.Replace('$TeamNumber', $TeamNumber)
        New-Folder -Name $FolderName -Location $ParentFolder | Out-Null
    }
}

<#
    .SYNOPSIS
    Mass adds resource pools based on team numbers.
    DEPRECATED: Should use Start-ISTSVAppDeployment.

    .DESCRIPTION
    Mass adds resource pools based on team numbers

    .PARAMETER TeamNumbers
    List of team numbers to add resource pools for.

    .PARAMETER ParentPool
    Pool to place created pools under.

    .EXAMPLE
    An example

    .NOTES
    Uses ISTS_TeamResourcePoolTemplate to name the resource pools.
#>
function Add-ResourcePools {
    Param (
        [Parameter(Mandatory=$true)][int[]]$TeamNumbers,
        [Parameter(ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Impl.V1.Inventory.ResourcePoolImpl]$ParentPool
    )
    Write-Warning -Message "This function is DEPRECATED and you should be using Start-ISTSVAppDeployment"

    if (!(Get-VCenterConnectionStatus)) { return }
    if (!$ParentPool){
        if (!(Invoke-ConfirmPrompt -Message "No parent resource pool specified. Create resource pools in the root of the first cluster ($((Get-Cluster)[0]))?")){
            return
        }
    }
    $TeamNumbers | ForEach-Object {
        $pname = $ISTS_TeamResourcePoolTemplate.Replace("`$TeamNumber", $_)
        Write-Host "Creating pool $pname"
        if ($ParentPool){
            New-ResourcePool -Name $pname -Location $ParentPool | Out-Null
        } else {
            New-ResourcePool -Name $pname -Location (Get-Cluster)[0] | Out-Null
        }
    }
}

<#
    .SYNOPSIS
    Mass adds networks based on names, team numbers, and VLAN mappings.

    .DESCRIPTION
    Mass adds networks based on names, team numbers, and VLAN mappings.

    .PARAMETER TeamNumbers
    List of team numbers to add networks for.

    .PARAMETER DVSwitchName
    Name of the DVSwitch to add the portgroups to.  Gets default from $ISTS.vCenter.CompetitionVDSwitch

    .EXAMPLE
    Add-Networks -TeamNumbers 1,2,3,4,5,6,7,8,9,10

    .EXAMPLE
    Add-Networks -TeamNumbers 1,2,3,4 -DVSwitchName CompetitionSwitch

    .NOTES
    Check out how networks are set up in the example config.
#>
function Add-Networks {
    Param (
        [Parameter(Mandatory=$true)][int[]]$TeamNumbers,
        [string]$DVSwitchName = $ISTS.vCenter.CompetitionVDSwitch
    )
    # Get VDSwitch for Competition use.  If switch isn't found, STOP execution.
    $VDSwitch = Get-VDSwitch -Name $ParentDVSwitchName -ErrorAction Stop

    # Iterate through each team given to setup their network(s)
    foreach ($TeamNumber in $TeamNumbers) {
        # Iterate through each network to create for the team
        foreach ($Network in $ISTS.NetworkConfig.Networks.Keys) {
            # Calculate VLAN ID
            $VLAN_ID = Invoke-Expression -Command $ISTS.NetworkConfig.Networks.$Network.VLAN_ID.Replace('$StartingVLANID', $ISTS.NetworkConfig.StartingVLANID).Replace('$TeamNumber', $TeamNumber)

            $PortGroupName = $ISTS.Templates.NetworkName.Replace('$TeamNumber', $TeamNumber).Replace('$Network', $Network).Replace('$VLAN_ID', $VLAN_ID)
            New-VDPortGroup -VDSwitch $VDSwitch -Name $PortGroupName -VLanId $VLAN_ID -RunAsync
        }
    }
}

<#
    .SYNOPSIS
    Configures permissions for each team vApp.  Can be set to do folders and port groups as well.

    .DESCRIPTION
    Configures permissions for each team vApp so users cannot see each others vApps or VMs.  Can be set to do folders and port groups as well

    .PARAMETER TeamNumbers
    List of team numbers to congigure permissions for.

    .PARAMETER RoleName
    Name of the role used to assign permissions to teams.  Same name as configured in vCenter.

    .PARAMETER DomainName
    Domain name used for the team accounts.  May be the vCenter SSO domain or the AD domain name depending on where the user accounts were created.

    .PARAMETER FolderPermissions
    Switch used to optionally set team permissions on their folder.

    .PARAMETER FolderPermissions
    Switch used to optionally set team permissions on their port groups.

    .EXAMPLE
    An example

    .NOTES
    Functions to add team permissions to folders and port groups are added on as extra in the case of automation.
#>
function Add-TeamPermissions {
    Param (
        [Parameter(Mandatory=$true)][int[]]$TeamNumbers,
        [string]$RoleName = $ISTS.vCenter.Permissions.TeamRoleName,
        [string]$DomainName = $ISTS.vCenter.SSO_Domain,
        [switch]$FolderPermissions,
        [switch]$PortGroupPermissions
    )
    # Initial Config Options
    # Get domain name
    $SSO_Domain = $ISTS.vCenter.SSO_Domain

    # Get role to be assigned
    $Role = Get-VIRole -Name $RoleName
    
    foreach($TeamNumber in $TeamNumbers) {
        # Set permissions on vApps

        # Regex Meaning: vApp name with "Team $i" that matches the number and then anything after the number or nothing
        #                Fixes issues where "Team $i*" will match "Team 1" and "Team 10."
        #$vApps = Get-VApp | Where-Object { $_.Name -match "Team \b${TeamNumber}\b(?:.*)?" }

        
        $Username = $ISTS.Templates.Username.Replace('$TeamNumber', $TeamNumber)
        $Principal = Get-VIAccount -Name "$Username@$SSO_Domain" -User
        foreach($Network in $ISTS.NetworkConfig.Networks.Keys) {
            if($ISTS.NetworkConfig.Networks[$Network].TeamAccess -eq 'no') {
                continue
            }

            $vAppName = ($ISTS.Templates.vAppName.Replace('$TeamNumber', $TeamNumber)).Replace('$Network', $Network)
            $vApp = Get-VApp -Name $vAppName

            Write-Host "Assigning User: $Username@$SSO_Domain with Role: $Role to: $($vApp.Name)"
            New-VIPermission -Entity $vApp -Role $Role -Principal $Principal
        }

        # Optionally set permissions on folders
        if($FolderPermissions) {
            $FolderName = $ISTS.Templates.FolderName.Replace('$TeamNumber', $TeamNumber)
            $Folder = Get-Folder -Name $FolderName
            New-VIPermission -Entity $Folder -Role $Role -Principal $Principal -Propagate $false
        }

        # Optionally set permissions on port groups
        if($PortGroupPermissions) {
            # Iterate through each network
            foreach ($Network in $ISTS.NetworkConfig.Networks.Keys) {
                if($ISTS.NetworkConfigs.Networks.$Network.TeamAccess -eq 'no') {
                    continue
                }

                $PortGroupName = "$ISTS.Templates.NetworkName.Replace('$TeamNumber', $TeamNumber).Replace('$Network', $Network)*"
                $PortGroup = Get-VDPortgroup -Name $PortGroupName
                New-VIPermission -Entity $PortGroup -Role $Role -Principal $Principal
            }
        }
    }
}

<#
    .SYNOPSIS
    Adds team accounts to vCenter so users can log into their environment.

    .DESCRIPTION
    Adds team accounts to vCenter so users can log into their environment.

    .PARAMETER TeamNumbers
    List of team numbers to add accounts for for.

    .EXAMPLE
    Add-TeamAccounts -TeamNumbers 1,2,3,4,5,6,7,8,9,10

    .NOTES
    Uses YAML config to retrieve user properties such as Username and password.
#>
function Add-TeamAccounts {
    Param (
        [Parameter(Mandatory=$true)][int[]]$TeamNumbers
    )
    foreach($TeamNumber in $TeamNumbers) {
        $NewAccountName = $ISTS.Templates.Username.Replace('$TeamNumber', $TeamNumber)
        New-VMHostAccount -Id $NewAccountName -Password $ISTS.vCenter.Permissions.TeamPassword -Description "Team $TeamNumber's Account"
    }
}

# TODO: Make Add-Host function to add a new host to vCenter and fully configure it
