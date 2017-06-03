<#
    Root module for ISTS scripts.  Contains general functions that aid in the setup of the module environment.
#>

# Get the path the module is running in
$ISTS_ModulePath = Split-Path -parent $PSCommandPath

<# Name:        Start-ISTSDeployFromCSV
 # Description: Programatically clones, configures, snapshots, and starts VMs in parallel
 # Params:      FileName - string,required - The CSV file name to deploy from
 #              TeamNumbers - int[],required - The teams to deploy to
 #              StartOnCompletion - bool - Whether to start the VM when the process is finished
 #              TakeBaseSnapshot - bool - Whether to take a base snapshot of the VM when the process is finished
 # Returns:     None
 # Throws:      None
 # Note:        If you don't want this script to deploy networks then provide a bogus network name
 #>


function Start-DeployFromCSV {
    Param (
        [Parameter(Mandatory=$true)][string]$FileName,
        [Parameter(Mandatory=$true)][int[]]$TeamNumbers,
        [switch]$StartOnCompletion = [bool]$ISTS_StartOnCompletion,
        [switch]$TakeBaseSnapshot = [bool]$ISTS_TakeBaseSnapshot
    )
    if (!(Get-VCenterConnectionStatus)) { return }
    $taskTab = @{}
    $nameNetwork = @{}
    $vms = Import-Csv $FileName 
    foreach ($vm in $vms) {
        $Template = $null
        $Template = Get-Template -Name $_.TemplateName -ErrorAction SilentlyContinue

        if ($Template -eq $null){
            $Template = Get-VM -Name $_.TemplateName -ErrorAction SilentlyContinue
        }

        if ($Template -is [System.Array]){
            $Template = $Template[0]
        }

        if ($Template -eq $null){
            Write-Warning "No template named $($_.TemplateName), skipping" 
        } 
        else {

            foreach ($TeamNumber in $TeamNumbers) {
                Write-Progress -Activity "Deploying VMs (0/$($taskTab.Count))" -PercentComplete 0
                $VMFolder = Get-Folder -Name ($ISTS_TeamFolderTemplate.Replace("`$TeamNumber", $TeamNumber))
                #$ResourcePool = Get-ResourcePool -Name ($ISTS_TeamResourcePoolTemplate.Replace("`$TeamNumber", $TeamNumber))
                $NetworkName = $ISTS_TeamNetworkTemplate.Replace("`$NetworkID", $_.NetworkID).Replace("`$TeamNumber", $TeamNumber)
                $VMName = $ISTS_TeamVMNameTemplate
                $tmp = $_.TemplateName
                $ISTS_TeamVmNameReplace.Split(",") | ForEach-Object { 
                    if ($tmp.Contains($_)){
                        $tmp = $tmp.TemplateName.Replace($_, "")
                    }
                }
                $VMName = $VMName.Replace("`$TeamNumber", $TeamNumber).Replace("`$TemplateName", $tmp)
                $ID = $null
                try {
                    if (!$NetAdaptersOnly){
                        if ($Template.GetType().fullname -like "*TemplateImpl"){
                            $ID = (New-VM -Template $Template -Name $VMName -Location $VMFolder -RunAsync).Id
                            $taskTab[$ID] = $VMName
                        } elseif ($Template.getType().fullname -like "*VirtualMachineImpl") {
                            $ID = (New-VM -VM $Template -Name $VMName -Location $VMFolder -RunAsync).Id
                            $taskTab[$ID] = $VMName
                        } else { continue }
                    }
                } catch {
                    if ($ID -ne $null){
                        $taskTab.Remove($ID)
                    }
                    continue
                }
                Write-Host -ForegroundColor Yellow "Deploying $VMName to $($VMFolder.Name)"
                $nameNetwork[$VMName] = $NetworkName
            } 
        }
    }
    # adapted from http://www.lucd.info/2010/02/21/about-async-tasks-the-get-task-cmdlet-and-a-hash-table/
    # Set netadapter on each completed VM
    $runningTasks = $taskTab.Count
    $initialTasks = $runningTasks
    while($runningTasks -gt 0){
        Get-Task | ForEach-Object {
            if($taskTab.ContainsKey($_.Id) -and $_.State -eq "Success"){
                $VM = Get-VM $taskTab[$_.Id]
                $percent = 100*($initialTasks-$runningTasks)/$initialTasks
                $activity = "Deploying VMs ($($initialTasks-$runningTasks)/$initialTasks)"
                $status = "Configuring $($VM.Name)"
                Write-Progress $activity -PercentComplete $percent -Status $status -CurrentOperation "Setting network adapter"
                Get-NetworkAdapter -VM $VM | Set-NetworkAdapter -NetworkName $nameNetwork[$taskTab[$_.Id]] -Confirm:$false -RunAsync:(!$TakeBaseSnapshot) | Out-Null
                if ($TakeBaseSnapshot){
                    Write-Progress $activity -PercentComplete $percent -Status $status -CurrentOperation "Taking base snapshot"
                    New-Snapshot -Name "base" -Confirm:$false -VM $VM | Out-Null
                }
                if ($StartOnCompletion){
                    Write-Progress $activity -PercentComplete $percent -Status $status -CurrentOperation "Starting VM"
                    Start-VM -VM $VM -RunAsync | Out-Null
                }
                Write-Host -ForegroundColor Green "Finished deploying $($VM.Name)"
                $taskTab.Remove($_.Id)
                $runningTasks--
            }
            elseif($taskTab.ContainsKey($_.Id) -and $_.State -eq "Error"){
                Write-Host -ForegroundColor Red "Error deploying $($taskTab[$_.Id])"
                $taskTab.Remove($_.Id)
                $runningTasks--
            }
        }
        Write-Progress "Deploying VMs ($($initialTasks-$runningTasks)/$initialTasks)" -PercentComplete (100*($initialTasks-$runningTasks)/$initialTasks) -Status "Deploying"
        Start-Sleep -Seconds 1
    }
}

<# Name:        Import-ISTSConfig
 # Description: Sets variables for use in the script (prefixed by ISTS_)
 # Params:      ConfigFile - The path to the configuration file to load
 # Returns:     None
 # Throws:      None
 #>
function Import-Config {
    Param (
        [string]$ConfigFile = "$($ISTS_ModulePath)\ISTS-Scripts.conf"
    )
    foreach ($line in Get-Content $ConfigFile){
        if ($line[0] -ne "#"){
            $splitline = $line.split("=")
            $varName = $splitline[0].Trim()
            $varValue = $splitline[1..($splitline.length - 1)].TrimStart() -join "="
            Set-Variable -Name ISTS_$varName -Value $varValue -Scope Script
        }
    }
}

<# Name:        Import-ISTSYAMLConfig
 # Description: Sets variables for use in the script (prefixed by ISTS_) in YAML
 # Params:      ConfigFile - The path to the configuration file to load
 # Returns:     None
 # Throws:      None
 #>
function Import-YAMLConfig {
    #TODO: Make sections in YAML meaningful.  Break up config into sections
    #       and append it to variables under it such as vCenterIP.  "Section"+"Variable"
    Param (
        [string]$ConfigFile = "$($ISTS_ModulePath)\ISTS-Scripts.conf"
    )
    foreach ($line in Get-Content $ConfigFile){
        $line = $line.Trim()
        if ($line[0] -ne "#" -and $line[0] -eq "-"){
            
            $splitline = $line.split(":")
            $varName = $splitline[0].TrimStart('- ').Trim()
            $varValue = $splitline[1..($splitline.length - 1)].TrimStart() -join "="
            Set-Variable -Name ISTS_$varName -Value $varValue -Scope Script
        }
    }
}

<# Name:        Invoke-ConfirmPrompt
 # Description: Creates a prompt for the user
 # Params:      Title - string - The title of the prompt
 #              Message - string - The prompt message/question
 #              YesPrompt - string - What to display next to the yes option
 #              NoPrompt - string - What to display next to the no option
 #              OnYes - string - What to print if the user says yes
 #              OnNo - string - What to print if the user says no
 # Returns:     $true if the user answers with yes, $false if no
 # Throws:      None
 #>
function Invoke-ConfirmPrompt {
    Param(
        [string]$Title = "Continue?",
        [string]$Message = "",
        [string]$YesPrompt = "Continue",
        [string]$NoPrompt = "Exit",
        [string]$OnYes = "Continuing",
        [string]$OnNo = "Aborting"
    )
   
    $yes = New-Object System.Management.Automation.Host.ChoiceDescription "&Yes", $YesPrompt
    $no = New-Object System.Management.Automation.Host.ChoiceDescription "&No", $NoPrompt
    $options = [System.Management.Automation.Host.ChoiceDescription[]]($yes, $no)
    $result = $host.ui.PromptForChoice($Title, $Message, $options, 0) 
    switch ($result) {
        0 { Write-Host $OnYes; return $true }
        1 { Write-Host -ForegroundColor Red $OnNo; return $false }
    }
}

#### Initial config and startup ####
Import-Config $ISTS_ModulePath\ISTS-Scripts.conf
