Clear-Host

Register-PSRepository `
    -Name 'IKT-PSRepository' `
    -SourceLocation '\\Spiktn3222.sp.nk.lokal\abteilungsshares$\IKT\Abteilungsstruktur\Second_Level\Powershell\IKT-PSRepository' `
    -PublishLocation '\\Spiktn3222.sp.nk.lokal\abteilungsshares$\IKT\Abteilungsstruktur\Second_Level\Powershell\IKT-PSRepository' `
    -InstallationPolicy Trusted
 Get-PSRepository | Format-List *