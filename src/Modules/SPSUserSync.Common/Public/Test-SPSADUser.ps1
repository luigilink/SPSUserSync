function Test-SPSADUser {
    <#
        .SYNOPSIS
        Returns $true when the SharePoint user login resolves to an AD entry.

        .DESCRIPTION
        Thin wrapper around Get-SPSADUser that returns a boolean. Use it in
        SPSyncUserProfile.ps1 when you only need to know whether the user
        still exists in Active Directory before calling CreateUserProfile.

        .PARAMETER UserLogin
        The raw SharePoint user login, in claim or DOMAIN\user form.

        .PARAMETER ConfigPath
        Optional override for the folder containing ad-domains.psd1 and
        secrets.psd1.

        .EXAMPLE
        if (Test-SPSADUser -UserLogin 'i:0#.w|CONTOSO\jdoe') { ... }
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $UserLogin,

        [Parameter()]
        [System.String]
        $ConfigPath
    )

    return ($null -ne (Get-SPSADUser -UserLogin $UserLogin -ConfigPath $ConfigPath))
}
