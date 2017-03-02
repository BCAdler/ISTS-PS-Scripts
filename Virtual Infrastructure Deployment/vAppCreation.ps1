Import-Module -Name VMware.VimAutomation.Core

function New-TeamFolders {
    for ($i = 0; $i -lt 11; $i++) {
        (Get-View (Get-View -viewtype datacenter -filter @{"name"="WhiteTeam"}).vmfolder).CreateFolder("Team$i")
    }
}

function Move-TeamVMs {
    for ($i = 0; $i -lt 11; $i++) {
        $folder = (Get-View -viewtype folder -Filter @{"name"="Team$i"})
        Get-VM -Name "Team $i*" | Move-VM -Destination $folder[$i]
    }
}

function New-TeamVApps {
    for ($i = 0; $i -lt 11; $i++) {
        New-VApp 
    }
}

