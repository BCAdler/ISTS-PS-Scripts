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
    param ( 
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

<# Name:        Invoke-AddDnsRecordsFromCSV
 # Description: Takes DNS records from a CSV file and adds them to a Windows Server
 # Params:      TeamNumber - int,required - The team number to use in the script
 #              VM - VirtualMachineImpl,required - the VM to run the script on
 #              GuestUser - string - Username to use to log into the VM
 #                                 - Populated by ISTS_DomainAdminUser if blank
 #              GuestPassword - string - Password to use to log into the VM
 #                                     - Populated by ISTS_DomainAdminPassword if blank
 #              RunAsync - bool - Whether to wait between starting each deployment
 # Returns:     None
 # Throws:      None
 # Note:        Powershell required on the VM guest
 #>
# Adds dns records
function Invoke-AddDnsRecordsFromCSV {
    param ( 
        [Parameter(Mandatory=$true)][int]$TeamNumber,
        [Parameter(Mandatory=$true)][VMware.VimAutomation.ViCore.Impl.V1.Inventory.VirtualMachineImpl]$VM,
        [Parameter(Mandatory=$true)]$FileName,
        [String]$GuestUser = $ISTS_DomainAdminUser,
        [SecureString]$GuestPassword =  (ConvertTo-SecureString -String $ISTS_DomainAdminPassword),
        [switch]$RunAsync = $false
    )
    if (!(Get-VCenterConnectionStatus)) { return }
    Copy-VMGuestFile -Source $ISTS_ModulePath\resource\Add-DnsRecordsFromCSV.ps1 -Destination C:\Windows\Temp -VM $VM -GuestUser $GuestUser -GuestPassword $GuestPassword -LocalToGuest -Confirm:$false -Force
    Copy-VMGuestFile -Source $FileName -Destination C:\Windows\Temp -VM $VM -GuestUser $GuestUser -GuestPassword $GuestPassword -LocalToGuest -Confirm:$false -Force
    Invoke-VMScript -ScriptText "\Windows\Temp\Add-DnsRecordsFromCSV.ps1 -TeamNumber $TeamNumber -FileName \Windows\Temp\$FileName; Remove-Item -Path \Windows\Temp\Add-DnsRecordsFromCSV.ps1;Remove-Item -Path \Windows\Temp\$FileName" -VM $VM -RunAsync:$RunAsync -Confirm:$false -GuestUser $GuestUser -GuestPassword $GuestPassword
}

<# Name:        Add-WindowsHostsToDomain
 # Description: Joins windows hosts to an AD domain
 # Params:      TeamNumber - int,required - The team number that is being joined
 #              VM - VirtualMachineImpl,required - The VM's join to the domain
 #              GuestUser - string - Username to use to log into the VM
 #                                 - Populated by ISTS_WindowsDefaultUser if blank
 #              GuestPassword - string - Password to use to log into the VM
 #                                     - Populated by ISTS_WindowsDefaultPassword if blank
 #              DomainAdminUser - string - Domain admin user name to use to join the domain
 #              DomainAdminPassword - string - Domain admin user password to use to join the domain
 #              DNSServerIP - string - The IP address of the DNS server for the team
 #              RunAsync - bool - Whether to run the joins asynchronously
 # Returns:     None
 # Throws:      None
 # Note:        Can process multiple VMs at once via pipe
 # Note:        If you want to set the DNS server statically then just assign the var, it won't be changed
 #>
function Add-WindowsHostsToDomain{
    param (
        [Parameter(Mandatory=$true)][int]$TeamNumber,
        [Parameter(Mandatory=$true,ValueFromPipeline=$true)][VMware.VimAutomation.ViCore.Impl.V1.Inventory.VirtualMachineImpl]$VM,
        [String]$GuestUser = $ISTS_WindowsDefaultUser,
        [SecureString]$GuestPassword = (ConvertTo-SecureString -String $ISTS_WindowsDefaultPassword -AsPlainText -),
        [String]$DomainAdminUser = $ISTS_DomainAdminUser,
        [SecureString]$DomainAdminPassword = (ConvertTo-SecureString -String $ISTS_DomainAdminPassword -AsPlainText),
        [String]$DNSServerIP = $ISTS_DomainControllerIPTemplate.replace("`$TeamNumber", $TeamNumber),
        [switch]$RunAsync = $false
    )
    begin {
        if (!(Get-VCenterConnectionStatus)) { return }
        $domain = $ISTS_DomainNameTemplate.replace("`$TeamNumber", $TeamNumber)
    }
    process {
        foreach ($V in $VM){
            Invoke-VMScript -ScriptText "netsh int ipv4 set dns 'Local Area Connection' static 10.2.$TeamNumber.20" -VM $V -GuestUser $GuestUser -GuestPassword $GuestPassword -Confirm:$false
            Invoke-VMScript -ScriptText "Set-DnsClientServerAddress -ServerAddress $DNSServerIP -InterfaceAlias ((Get-NetAdapter | Where {`$_.Name -Like '*Ethernet*' -or `$_.Name -Like '*Local Area Connection*'})[0])" -VM $V -GuestUser $GuestUser -GuestPassword $GuestPassword -Confirm:$false
            Invoke-VMScript -ScriptText "Add-Computer -DomainName '$domain' -Credential (New-Object System.Management.Automation.PSCredential('$DomainAdminUser@$domain',('$DomainAdminPassword' | ConvertTo-SecureString -asPlainText -Force)))" -VM $V -GuestUser $GuestUser -GuestPassword $GuestPassword -RunAsync:$RunAsync -Confirm:$false
        }
    }
}

<# Name:        Install-PBIS
 # Description: Installs PBIS on a linux host
 # Params:      OSString - string,required - Info that could help identify the OS
 #              VM - VirtualMachineImpl,required - the VM to install PBIS on
 # Returns:     $true if install succeeded, $false if not
 # Throws:      None
 # Note:        This will download PBIS from the link in the imported ISTS-Config
 #>
function Install-PBIS {
    param (
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

<# Name:        Invoke-JoinLinuxHostsToDomain
 # Description: Gathers linux system info and invokes Install-PBIS on hosts
 # Params:      TeamNumber - int,required - The team number that is being joined
 #              VM - VirtualMachineImpl,required - The VM's join to the domain
 #              GuestUser - string - Username to use to log into the VM
 #                                 - Populated by ISTS_LinuxDefaultUser if blank
 #              GuestPassword - string - Password to use to log into the VM
 #                                     - Populated by ISTS_LinuxDefaultPassword if blank
 #              DomainAdminUser - string - Domain admin user name to use to join the domain
 #              DomainAdminPassword - string - Domain admin user password to use to join the domain
 #              DNSServerIP - string - The IP address of the DNS server for the team
 #              RunAsync - bool - Whether to run the joins asynchronously
 # Returns:     None
 # Throws:      None
 # Note:        Can process multiple VMs at once via pipe
 # Note:        If you want to set the DNS server statically then just assign the var, it won't be changed
 #>
function Invoke-JoinLinuxHostsToDomain {
    param (
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
