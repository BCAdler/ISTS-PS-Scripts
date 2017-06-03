<#
    Functions to automate deploying of virtualized infrastructure.
#>

<# Name:        Deploy-ISTSvApps
 # Description: Clones Team 0 / Template vApp to other teams and configures the VMs
 # Params:      TeamNumbers     - int[] - Team numbers to create vApp for
 #              TemplateVApp    - string - Name of vApp to use as template
 #              PathToTeamNetworkCsv - string - Path to CSV for Team Networks
 #                                              Defaults to same directory as module
 # Returns:     None
 # Throws:      None
 #>
function Start-VAppDeployment {
    Param (
        [Parameter(Mandatory=$true)][int[]]$TeamNumbers,
        [Parameter(Mandatory=$true)][string]$TemplateVAppName,
        [string]$OverrideDatastore,
        [switch]$StartVApp,
        [string]$PathToTeamNetworkCsv = "$ISTS_ModulePath/vlan_info_final.csv"
    )
    
    Import-Module -Name VMware.VimAutomation.Vds
    $StartTime = Get-Date

    # Get Team Network CSV 
    $TeamNetworksCsv = Import-Csv $PathToTeamNetworkCsv
    $ProdVMs = "Web","DB","Win8"
    $CorpVMs = "AD","Mail","Kali","Parrot","VOIP"

    # Get vApp object from given name
    $TemplateVApp = Get-VApp -Name $TemplateVAppName
    $Location = Get-Cluster
    if($Location -eq $null) {
        $Location = $(Get-VMHost)[0]
    }
    
    foreach($i in $TeamNumbers) {
        # Get Datastore Cluster or Datastore with most free space.        
        $Datastores = Get-Datastore
        $Datastore = $Datastores[0]
        foreach($store in $Datastores) {
            if($store.FreeSpaceGB -gt $Datastore.FreeSpaceGB -and $store.Name -ne "santres") {
                $Datastore = $store
            }
        }

        if((Get-VApp -Name "Team $i") -eq $null) {
            # Start cloning of template vApp and wait until it is done to continue.
            Write-Host "Starting Team $i vApp Cloning..." -ForegroundColor Yellow
            $CloneTask = New-VApp -Name "Team $i" -Location $Location -VApp $TemplateVApp -Datastore $Datastore
            if(!$?) {
                Write-Host "Cloning vApp Failed..." -ForegroundColor Red -BackgroundColor Black
                exit
            }
            Wait-Task -Task $CloneTask
            Write-Host "Team $i vApp Cloning Complete" -ForegroundColor Green
        }
        else {
            Write-Host "vApp `"Team $i`" Already Exists...  Continuing" -ForegroundColor Yellow
        }
        
        Write-Host "`nRenaming and Configuring Networking for Team $i's VMs." -ForegroundColor Yellow

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
            $vm | Get-NetworkAdapter | Set-NetworkAdapter -Portgroup $PortGroup -Confirm:$false

            # Change VM name
            Set-VM -VM $vm -Name "Team $i - $($vm.Name.Split('-').Trim()[1])" -Confirm:$false
        }
        
        # Start new vApp if $StartVApp switch is $true
        if($StartVApp) {
            Start-VApp -VApp (Get-VApp -Name "Team $i") -RunAsync
            Write-Host "Team $i vApp starting." -ForegroundColor Yellow
        }
        Write-Host "Configuration for Team $i complete!" -ForegroundColor Green
        Write-Host "Script Start: $StartTime"
        Write-Host "Script End: $(Get-Date)"

        #$vms=Get-VM
        #$sw=Get-VirtualPortGroup
    }
}

<# Name:        Add-ISTSVMFolders
 # Description: Mass adds organizational folders based on team numbers
 # Params:      TeamNumbers - int[],required - List of team folders to add
 #              ParentFolder - FolderImpl,required - Folder to place created folders under
 # Returns:     None
 # Throws:      None
 # Note:        Uses ISTS_TeamFolderTemplate to name the folders
 #>
function Add-VMFolders {
    Param (
        [Parameter(Mandatory=$true)][int[]]$TeamNumbers,
        [Parameter(ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Impl.V1.Inventory.FolderImpl]$ParentFolder
    )
    if (!(Get-VCenterConnectionStatus)) { return } # TODO: look into this 
    if (!$ParentFolder) {
        $message = "No parent folder specified. Create folders in the root of the first datacenter ($((Get-Datacenter)[0]))?"
        if (!(Invoke-ConfirmPrompt -Message $message)) {
            return
        }
    }

    $TeamNumbers | ForEach-Object {
        $fname = $ISTS_TeamFolderTemplate.Replace("`$TeamNumber", $_)
        $topdcfolder = get-view (get-view -ViewType datacenter -Filter @{"name"=(Get-Datacenter)[0].Name}).VmFolder
        Write-Host "Creating folder $fname"
        if ($ParentFolder) {
            New-Folder -Name $fname -Location $ParentFolder | Out-Null
        } else {
            $topdcfolder.CreateFolder($fname) | Out-Null
        }
    }
}

<# Name:        Add-ISTSResourcePools
 # Description: Mass adds resource pools based on team numbers
 # Params:      TeamNumbers - int[],required - List of team resource pools to add
 #              ParentPool - ResourcePoolImpl,required - Pool to place created pools under
 # Returns:     None
 # Throws:      None
 # Note:        Uses ISTS_TeamResourcePoolTemplate to name the resource pools
 #>
function Add-ResourcePools {
    Param (
        [Parameter(Mandatory=$true)][int[]]$TeamNumbers,
        [Parameter(ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Impl.V1.Inventory.ResourcePoolImpl]$ParentPool
    )
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

<# Name:        Add-ISTSNetworks
 # Description: Mass adds networks based on names, team numbers, and VLAN mappings
 # Params:      TeamNumbers - int[],required - List of teams to add networks for
 #              NetworkNames - string[],required - List of network names to add
 #              ParentDVSwitchName - string - Name of the parent DVSwitch
 #                                          - Gets default from ISTS_ParentDVSwitch
 #              VlanIDMappings - string - VLAN ID mapping string for users/networks
 #                                      - Gets default from ISTS_VlanIDMappings
 # Returns:     None
 # Throws:      None
 # Note:        Check out how VlanIDMappings are set up in the example config
 # Note:        Uses ISTS_TeamNetworkTemplate from the config to name networks
 #>
function Add-Networks {
    Param (
        [Parameter(Mandatory=$true)][int[]]$TeamNumbers,
        [Parameter(Mandatory=$true)][string[]]$NetworkNames,
        [string]$ParentDVSwitchName = $ISTS_ParentDVSwitchName,
        [string]$VlanIDMappings = $ISTS_VlanIDMappings
    )
    $VDSwitch = Get-VDSwitch -Name $ParentDVSwitchName -ErrorAction Stop
    foreach ($Team in $TeamNumbers) {
        foreach ($NetID in $NetworkNames) {
            $NetName = $ISTS_TeamNetworkTemplate.Replace("`$TeamNumber", $Team).Replace("`$NetworkID", $NetID)
            $VlanID = [int]($VlanIDMappings.split(' ') | Where-Object {$_.Split(":")[0] -eq $Team -and $_.Split(":")[1] -eq $NetID}).split(":")[2]
            New-VDPortGroup -VDSwitch $VDSwitch -Name "$NetName" -VLanId $VlanID
        }
    }

}

function Add-TeamPermissions {
    Param (
        [Parameter(Mandatory=$true)][int[]]$TeamNumbers,
        [string]$RoleName = "BlueTeam",
        [string]$vCenterDomainName = "VSPHERE.LOCAL",
        [Switch]$CreateAccounts = $false
    )
    
    if($CreateAccounts) {
        Write-Host "Creating Team Accounts..." -ForegroundColor Yellow
        Write-Host "Not Implemented Yet But Will Be Soon......" -ForegroundColor Yellow

    }

    foreach($i in $TeamNumbers) {
        # Regex Meaning: vApp name with "Team $i" that matches the number and then anything after the number or nothing
        #                Fixes issues where "Team $i*" will match "Team 1" and "Team 10."
        $vapps = Get-VApp | Where-Object { $_.Name -match "Team \b${i}\b(?:.*)?" }

        foreach($vapp in $vapps) {
            $role = Get-VIRole -Name "$RoleName"
            Write-Host "Assigning User: Team$i with Role: $role to: $($vapp.Name)"
            New-VIPermission -Entity $vapp -Role $role -Principal "$vCenterDomainName\team$i"
        }
    }
}
