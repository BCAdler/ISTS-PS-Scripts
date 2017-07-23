<#
    This module is an attempt to emulate a dry run of the infrastructure
    deployment and all the final results from a deployment.
#>

Start-DryHailmary {
    Param (
        # Parameters will be added as necessary to keep up-to-date with the steps above during development.
        [string]$ConfigFile = "$($ISTS_ModulePath)\ISTS-Config.yaml",
        [int[]]$TeamNumbers = $null
    )
    # Initial Setup

    # Get array of team numbers
    if($TeamNumbers -eq $null) {
        $TeamNumbers = 1..$ISTS.config.NumberOfTeams
    }
}
