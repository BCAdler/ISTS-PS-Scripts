<#
    Module used to fully deploy the ISTS infrastructure from start to finish using the YAML config.
    If there are any errors in the steps below, execution stops as it cannot continue without the previous step.

    Steps:
        1:  Import YAML config using Import-ISTSYAMLConfig
        2:  Connect to vCenter using settings from config.
        3:  Create team accounts on vCenter that they can use to access their infrastructure.
        4:  Create team networks/portgroups on Competition Distributed Switch
        5:  Create team folders that will show up in "VMs and Templates"
        6:  Deploy team vApps from template vApp
        7:  Set permissions on all team objects to restrict what they can access in vCenter.
#>

function Start-Hailmary {
    Param (
        # Parameters will be added as necessary to keep up-to-date with the steps above during development.
        [string]$ConfigFile = "$($ISTS_ModulePath)\ISTS-Config.yaml"
    )
    # Initial Setup

    # Get array of team numbers
    $TeamNumbers = 1..$ISTS.config.NumberOfTeams

    # Numbers below correspond to the steps as outlined above
    # 1
    Import-ISTSYAMLConfig -ConfigFile $ConfigFile -ErrorAction Stop

    # 2
    $vCenterPass = ConvertTo-SecureString -String $ISTS.vcenter.password -AsPlainText -Force
    $vCenterCred = New-Object System.Management.Automation.PSCredential($ISTS.vcenter.username, $vCenterPass)
    Connect-VIServer -Server $ISTS.vcenter.address -Credential $vCenterCred -ErrorAction Stop

    # 3
    Add-ISTSTeamAccounts -TeamNumbers $TeamNumbers

    # 4
    Add-ISTSNetworks -TeamNumbers $TeamNumbers

    # 5
    # Make parent folder for teams
    $ParentFolder = New-Folder -Name "Team Folders" -Location Get-Datacenter[0]
    Add-ISTSVMFolders -TeamNumbers $TeamNumbers -ParentFolder $ParentFolder    

    # 6
    # If StartVAppAfterDeploy -like yes, add switch to vApp deployment
    if($ISTS.Config.StartVAppAfterDeploy -like "yes") {
        Start-ISTSVAppDeployment -TeamNumbers $TeamNumbers -StartVApp:$true
    }
    else {
        Start-ISTSVAppDeployment -TeamNumbers $TeamNumbers
    }

    # 7
    Add-ISTSTeamPermissions -TeamNumbers $TeamNumbers
}
