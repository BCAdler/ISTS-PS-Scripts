# PowerCLI script skeleton

 Param ( # add script params here
    [Parameter(Mandatory=$true)][String]$VCenterServerAddress,
    [Parameter(Mandatory=$true)][PSCredential]$VCenterCred
)

begin { # define functions in here
    Add-PSSnapin vmware.vimautomation.core -ErrorAction Stop
    if (!$global:DefaultVIServer){ # make sure we aren't already connected
        if ($VCenterCred){ 
            Connect-VIServer -Server $VCenterServerAddress -Protocol Https -Force -ErrorAction Stop -Credential $VCenterCred
        } else {
            Write-Host "Enter your credentials to connect to vCenter:" -ForegroundColor Yellow
            $VCenterCred = Get-Credential
            Connect-VIServer -Server $VCenterServerAddress -Protocol Https -Force -ErrorAction Stop -Credential $VCenterCred
        }
    }
}

process { # define main function in here
    foreach ($Folder in Get-Folder){
        Write-Host "A folder: $($Folder.Name)"
    }
    Write-Host "If folders were displayed above, this probably works"
}
