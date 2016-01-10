﻿# PowerCLI script skeleton

 param ( #add script params here
    [Parameter(Mandatory=$true)][String]$VCenterServerAddress,
    [Parameter(Mandatory=$true)][int]$TeamNumber,
    [String]$VCenterUser,
    [String]$VCenterPassword
)

begin { #define functions in here
    Add-PSSnapin vmware.vimautomation.core -ErrorAction Stop
    if ($VCenterUser -and $VCenterPassword){
        $VcenterPassword = 
        Connect-VIServer -Server $VCenterServerAddress -Protocol Https -Force -ErrorAction Stop -User $VCenterUser -Password $VCenterPassword
    } else {
        Connect-VIServer -Server $VCenterServerAddress -Protocol Https -Force -ErrorAction Stop
    }
}

process { #define main function in here
    $GuestUser = "Administrator"
    $GuestPassword = "Netsys1!"
    $VMS = Get-VM | Where {$_.Name -contains "ADDNS" -and $_.Folder.Name -eq "ISTS-Test"}
    foreach ($VM in $VMS){
        Copy-VMGuestFile -Source .\Deploy-ISTSDomain.ps1 -Destination C:\Windows\Temp -VM $VM -GuestUser $GuestUser -GuestPassword $GuestPassword -LocalToGuest -Confirm:$false -Force
        Invoke-VMScript -ScriptText "\Windows\Temp\Deploy-ISTSDomain.ps1 -TeamNumber $TeamNumber -InstallRoles" -VM $VM -Confirm:$false -GuestUser $GuestUser -GuestPassword $GuestPassword
        Invoke-VMScript -ScriptText "Remove-Item -Path \Windows\Temp\Deploy-ISTSDomain.ps1" -VM $VM -Confirm:$false -GuestUser $GuestUser -GuestPassword $GuestPassword
    }
}