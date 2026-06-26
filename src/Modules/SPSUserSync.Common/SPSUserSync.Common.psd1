@{
    RootModule        = 'SPSUserSync.Common.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '97e2ce6d-509f-4916-846e-da2d5780765e'
    Author            = 'Jean-Cyril DROUHIN'
    CompanyName       = 'luigilink'
    Copyright         = '(c) Jean-Cyril DROUHIN. All rights reserved.'
    Description       = 'Shared functions for the SPSUserSync toolkit (AD lookups, event logging, log rotation, script initialization).'

    PowerShellVersion = '5.1'

    FunctionsToExport = @(
        'Add-SPSUserSyncEvent'
        'Clear-SPSLogFolder'
        'Get-SPSADConnection'
        'Get-SPSADUser'
        'Get-SPSSyncSetting'
        'Initialize-SPSScript'
        'Test-SPSADUser'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags         = @('SharePoint', 'SharePointServer', 'ActiveDirectory', 'UserProfile', 'Sync')
            LicenseUri   = 'https://github.com/luigilink/SPSUserSync/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/luigilink/SPSUserSync'
            ReleaseNotes = 'https://github.com/luigilink/SPSUserSync/blob/main/RELEASE-NOTES.md'
        }
    }
}
