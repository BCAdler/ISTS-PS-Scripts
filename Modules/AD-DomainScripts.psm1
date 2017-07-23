<#
    Automation functions for deploying a Windows domain.
#>

<#
    .SYNOPSIS
    Uploads an AD deployment script to the VM's passed in and executes it.

    .DESCRIPTION
    Uploads an AD deployment script to the VM's passed in and executes it.

    .PARAMETER TeamNumber
    The team number to insert.

    .PARAMETER VM
    The VM to run the script on.

    .PARAMETER GuestUser
    Username to use to log into the VM.  Populated by ISTS_DomainAdminPassword if blank.

    .PARAMETER GuestPassword
    Password to use to log into the VM.  Populated by ISTS_DomainAdminPassword if blank.

    .PARAMETER RunAsync
    Whether to wait between starting each deployment.

    .INPUTS
    None

    .OUTPUTS
    None
#>
function Invoke-DeployDomainController {
    Param ( 
        [Parameter(Mandatory=$true)][int]$TeamNumber,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Impl.V1.Inventory.VirtualMachineImpl]$VM,
        [String]$GuestUser = $ISTS_DomainAdminUser,
        [SecureString]$GuestPassword =  (ConvertTo-SecureString -String $ISTS_DomainAdminPassword),
        [switch]$RunAsync = $false
    )
    begin {
        if (!(Get-VCenterConnectionStatus)) { return }
    }
    process {
        foreach ($V in $VM){
            Copy-VMGuestFile -Source $ISTS_ModulePath\resource\Deploy-ISTSDomainController.ps1 -Destination C:\Windows\Temp -VM $V -GuestUser $GuestUser -GuestPassword $GuestPassword -LocalToGuest -Confirm:$false -Force
            $DomainName = $ISTS_DomainNameTemplate.replace("`$TeamNumber", $TeamNumber).ToUpper()
            $NetBiosName = $ISTS_NetBiosNameTemplate.replace("`$TeamNumber", $TeamNumber).ToUpper()
            Invoke-VMScript -ScriptText "\Windows\Temp\Deploy-ISTSDomainController.ps1 -DomainName $DomainName -NetBiosName $NetBiosName -InstallRoles; Remove-Item -Path \Windows\Temp\Deploy-ISTSDomainController.ps1" -VM $V -RunAsync:$RunAsync -Confirm:$false -GuestUser $GuestUser -GuestPassword $GuestPassword
        }
    }
}

<#
    .SYNOPSIS
    Takes DNS records from a CSV file and adds them to a Windows DNS Server.

    .DESCRIPTION
    Takes DNS records from a CSV file and adds them to a Windows DNS Server.

    .PARAMETER TeamNumber
    The team number(s) to use in the script.

    .PARAMETER VM
    The VM to run the script on.

    .PARAMETER FileName
    The file that contains the DNS records in CSV format.

    .PARAMETER GuestUser
    Username to use to log into the VM.  Populated by ISTS_DomainAdminUser if blank.

    .PARAMETER GuestPassword
    Password to use to log into the VM.  Populated by ISTS_DomainAdminPassword if blank.

    .PARAMETER RunAsync
    Whether to wait between starting each deployment.

    .EXAMPLE
    Invoke-AddDnsRecordsFromCSV -TeamNumber 1 -VM $vm -FileName .\DNSRecords.csv

    .EXAMPLE
    Invoke-AddDnsRecordsFromCSV -TeamNumber 1 -VM (Get-VM -Name "Team 1 - DC") -FileName .\DNSRecords.csv

    .NOTES
    Powershell required on the VM guest.
#>
function Invoke-AddDnsRecordsFromCSV {
    Param ( 
        [Parameter(Mandatory=$true)][int]$TeamNumber, # TODO: Update function to take multiple teams
        [Parameter(Mandatory=$true)][VMware.VimAutomation.ViCore.Impl.V1.Inventory.VirtualMachineImpl]$VM,
        [Parameter(Mandatory=$true)]$FileName,
        [String]$GuestUser = $ISTS_DomainAdminUser,
        [SecureString]$GuestPassword =  (ConvertTo-SecureString -String $ISTS_DomainAdminPassword),
        [switch]$RunAsync = $false
    )
    
    Copy-VMGuestFile -Source $ISTS_ModulePath\resource\Add-DnsRecordsFromCSV.ps1 -Destination C:\Windows\Temp -VM $VM -GuestUser $GuestUser -GuestPassword $GuestPassword -LocalToGuest -Confirm:$false -Force
    Copy-VMGuestFile -Source $FileName -Destination C:\Windows\Temp -VM $VM -GuestUser $GuestUser -GuestPassword $GuestPassword -LocalToGuest -Confirm:$false -Force
    Invoke-VMScript -ScriptText "\Windows\Temp\Add-DnsRecordsFromCSV.ps1 -TeamNumber $TeamNumber -FileName \Windows\Temp\$FileName; Remove-Item -Path \Windows\Temp\Add-DnsRecordsFromCSV.ps1;Remove-Item -Path \Windows\Temp\$FileName" -VM $VM -RunAsync:$RunAsync -Confirm:$false -GuestUser $GuestUser -GuestPassword $GuestPassword
}

<#
    .SYNOPSIS
    Joins Windows hosts to an AD domain.

    .DESCRIPTION
    Joins Windows hosts to an AD domain.

    .PARAMETER TeamNumber
    The team number that is being joined

    .PARAMETER VM
    The VM's join to the domain

    .PARAMETER GuestUser
    Username to use to log into the VM.  Populated by ISTS_WindowsDefaultUser if blank.

    .PARAMETER GuestPassword
    Password to use to log into the VM.  Populated by ISTS_WindowsDefaultPassword if blank.

    .PARAMETER DomainAdminUser
    Domain admin user name to use to join the domain.

    .PARAMETER DomainAdminPassword
    Domain admin user password to use to join the domain.

    .PARAMETER DNSServerIP
    The IP address of the DNS server for the team.

    .PARAMETER RunAsync
    Whether to run the joins asynchronously.

    .EXAMPLE # TODO: include example for Add-WindowsHostsToDomain
    An example

    .NOTES
    Can process multiple VMs at once via pipe. 
    If you want to set the DNS server statically then just assign the var, it won't be changed.
#>
function Add-WindowsHostsToDomain{
    Param (
        [Parameter(Mandatory=$true)][int]$TeamNumber,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Impl.V1.Inventory.VirtualMachineImpl]$VM,
        [String]$GuestUser = $ISTS.Config.Domain.GuestUser,
        [SecureString]$GuestPassword = (ConvertTo-SecureString -String $ISTS.Config.Domain.GuestPassword -AsPlainText -),
        [String]$DomainAdminUser = $ISTS.Config.Domain.DomainAdmin,
        [SecureString]$DomainAdminPassword = (ConvertTo-SecureString -String $ISTS.Config.Domain.DomainPassword -AsPlainText),
        #[String]$DNSServerIP = $ISTS_DomainControllerIPTemplate.replace("`$TeamNumber", $TeamNumber),
        [switch]$RunAsync = $false
    )
    begin {
        if (!(Get-VCenterConnectionStatus)) { return }
        $domain = $ISTS.Templates.ADDomain('$TeamNumber', $TeamNumber)
    }
    process {
        foreach ($V in $VM){
            Invoke-VMScript -ScriptText "netsh int ipv4 set dns 'Local Area Connection' static 10.2.$TeamNumber.20" -VM $V -GuestUser $GuestUser -GuestPassword $GuestPassword -Confirm:$false
            #Invoke-VMScript -ScriptText "Set-DnsClientServerAddress -ServerAddress $DNSServerIP -InterfaceAlias ((Get-NetAdapter | Where {`$_.Name -Like '*Ethernet*' -or `$_.Name -Like '*Local Area Connection*'})[0])" -VM $V -GuestUser $GuestUser -GuestPassword $GuestPassword -Confirm:$false
            Invoke-VMScript -ScriptText "Add-Computer -DomainName '$domain' -Credential (New-Object System.Management.Automation.PSCredential('$DomainAdminUser@$domain',('$DomainAdminPassword' | ConvertTo-SecureString -asPlainText -Force)))" -VM $V -GuestUser $GuestUser -GuestPassword $GuestPassword -RunAsync:$RunAsync -Confirm:$false
        }
    }
}

<#
    .SYNOPSIS
    Installs PBIS on a Linux host.

    .DESCRIPTION
    Installs PBIS on a Linux host.

    .PARAMETER OSString
    Info that could help identify the OS.

    .PARAMETER VM
    The VM to install PBIS on.

    .EXAMPLE # TODO: Include example for Install-PBIS
    An example

    .OUTPUTS
    Returns $true if install succeeded, $false if not.

    .NOTES
    This will download PBIS from the link in the imported ISTS-Config.
#>
function Install-PBIS {
    Param (
        [Parameter(Mandatory=$true)][String]$OSString,
        [Parameter(Mandatory=$true)][VMware.VimAutomation.ViCore.Impl.V1.Inventory.VirtualMachineImpl]$VM
    )
    if (!(Get-VCenterConnectionStatus)) { return }
    Write-Host "Trying to match $($VM.Name)"
    if ($OSString -imatch "ubuntu" -or $OSString -imatch "debian"){
        Write-Host "Matched Debian/Ubuntu"
        $URL = $ISTS_PbisDebURL
    } elseif ($OSString -imatch "suse" -or $OSString -imatch "centos" -or $OSString -imatch "fedora" -or $OSString -imatch ".el") {
        Write-Host "Matched RHEL-based distribution"
        $URL = $ISTS_PbisRpmURL
    } else {
        Write-Warning "Host not matched"
        return $false
    }

    $Filename = $URL.Split("/")[-1]
    if (!(Test-Path .\data\$Filename)){
        New-Item -ItemType Directory -Force -Path $ISTS_ModulePath\data
        Invoke-WebRequest $URL -OutFile $ISTS_ModulePath\data\$Filename
    }
    Copy-VMGuestFile -Source $ISTS_ModulePath\data\$Filename -Destination /tmp -LocalToGuest -VM $VM -GuestUser $GuestUser -GuestPassword $GuestPassword -Force
    Invoke-VMScript -ScriptText "chmod +x /tmp/$Filename;/tmp/$Filename -- --dont-join --no-legacy install;rm /tmp/$Filename" -GuestUser $GuestUser -GuestPassword $GuestPassword -VM $VM -Confirm:$false
    return $true
}

<#
    .SYNOPSIS
    Gathers linux system info and invokes Install-PBIS on hosts.

    .DESCRIPTION
    Gathers linux system info and invokes Install-PBIS on hosts.

    .PARAMETER TeamNumber
    The team number that is being joined.

    .PARAMETER VM
    Parameter description

    .PARAMETER GuestUser
    Username to use to log into the VM.  Populated by ISTS_LinuxDefaultUser if blank.

    .PARAMETER GuestPassword
    Password to use to log into the VM.  Populated by ISTS_LinuxDefaultPassword if blank.

    .PARAMETER DomainAdminUser
    Domain admin user name to use to join the domain.

    .PARAMETER DomainAdminPassword
    Domain admin user password to use to join the domain.

    .PARAMETER DNSServerIP
    The IP address of the DNS server for the team.

    .PARAMETER RunAsync
    Whether to run the joins asynchronously.

    .EXAMPLE # TODO: Include example for Invoke-JoinLinuxHostsToDomain
    An example

    .NOTES
    Can process multiple VMs at once via pipe.
    If you want to set the DNS server statically then just assign the var, it won't be changed.
#>
function Invoke-JoinLinuxHostsToDomain {
    Param (
        [Parameter(Mandatory=$true)][int]$TeamNumber,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Impl.V1.Inventory.VirtualMachineImpl]$VM,
        [String]$GuestUser = $ISTS_LinuxDefaultUser,
        [String]$GuestPassword = $ISTS_LinuxDefaultPassword,
        [String]$DomainAdminUser = $ISTS_DomainAdminUser,
        [String]$DomainAdminPassword = $ISTS_DomainAdminPassword,
        [String]$DNSServerIP = $ISTS_DomainControllerIPTemplate.replace("`$TeamNumber", $TeamNumber),
        [switch]$RunAsync = $false
    )
    begin {
        if (!(Get-VCenterConnectionStatus)) { return }
    }
    process {
        foreach ($V in $VM){
            $OSString = (Invoke-VMScript -ScriptText "uname -a;cat /etc/issue" -GuestUser $GuestUser -GuestPassword $GuestPassword -VM $V).ScriptOutput
            if (Install-PBIS -OSString $OSString -VM $V){
                $domain = $ISTS_DomainNameTemplate.replace("`$TeamNumber", $TeamNumber).ToUpper()
                Invoke-VMScript -ScriptText "echo nameserver $DNSServerIP > /etc/resolv.conf; /opt/pbis/bin/domainjoin-cli join $domain $DomainAdminUser $DomainAdminPassword" -VM $V -GuestUser $GuestUser -GuestPassword $GuestPassword -RunAsync:$RunAsync -Confirm:$false
            }
        }
    }
}
