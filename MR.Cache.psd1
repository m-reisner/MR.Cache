@{
    RootModule        = 'MR.Cache.psm1'
    ModuleVersion     = '1.0.0'
    CompatiblePSEditions = @('Core')
    GUID              = 'b4a6a9e1-6c0b-4ab2-9d8e-f2157c023999'
    Author            = 'm-reisner'
    CompanyName       = 'Community'
    Copyright         = '(c) 2025 m-reisner'
    Description       = 'ScriptBlock-basierter Cache mit TTL, Statistiken und Hash-Indexierung für PowerShell.'
    PowerShellVersion = '7.0'

    FunctionsToExport = @(
        'Use-MRCache',
        'Clear-MRCache',
        'Get-MRCacheStats'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData       = @{
        PSData = @{
            Tags        = @('cache', 'performance', 'development', 'scriptblock')
            ProjectUri  = 'https://github.com/m-reisner/MR.Cache'
            LicenseUri  = 'https://opensource.org/licenses/MIT'
            ReleaseNotes = 'Initial release 1.0.0'
        }
    }
}
