function Import-SPSSharePointCommand {
    <#
        .SYNOPSIS
        Loads the SharePoint Subscription Edition command surface.

        .DESCRIPTION
        SharePoint Server Subscription Edition ships the `SharePointServer`
        PowerShell module and no longer registers the legacy
        `Microsoft.SharePoint.PowerShell` PSSnapin. This function imports that
        module. It is idempotent: if the module is already loaded, it does nothing.
        Running the SPSUserSync scripts through plain `powershell.exe` (e.g. a
        scheduled task) therefore does not require launching them from the
        SharePoint Management Shell.

        Returns the loading mechanism used: 'SharePointServer'. Throws when
        SharePoint is not installed on the host.

        SharePoint Server 2016 and 2019 reached end of support on 14 July 2026 and
        are no longer supported: use the previous major release (v1.3.4) on those
        versions.

        .EXAMPLE
        Import-SPSSharePointCommand
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param ()

    # Guard: Get-SPSInstalledProductVersion returns $null when SharePoint is not
    # installed (Microsoft.SharePoint.dll not found), so fail with a clear message
    # instead of a cryptic module-import error.
    if ($null -eq (Get-SPSInstalledProductVersion)) {
        throw 'SharePoint is not installed on this server (Microsoft.SharePoint.dll not found). Run this on a SharePoint server.'
    }

    if (-not (Get-Module -Name SharePointServer)) {
        Import-Module -Name SharePointServer -Verbose:$false -WarningAction SilentlyContinue -DisableNameChecking
    }
    return 'SharePointServer'
}
