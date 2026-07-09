function ConvertTo-SPSUserRecord {
    <#
        .SYNOPSIS
        Projects a Get-SPSADUser result into the standard SPSUserSync record shape.

        .DESCRIPTION
        Both the sequential path in SPSyncUserInfoList.ps1 and the parallel
        Resolve-SPSADUserBatch worker need to turn the raw Active Directory entry
        returned by Get-SPSADUser into the same flat record (DisplayName,
        FirstName, LastName, Email, Country, Location). Centralizing that
        projection here guarantees both code paths produce byte-for-byte identical
        output, so turning parallel resolution on or off never changes the JSON.

        Country and Location are upper-cased, mirroring the original inline logic.
        When AD provides no displayName but does provide givenName and sn, the
        display name falls back to "givenName sn". When the entry is $null (user
        not found in AD), every attribute is left $null and Resolved is $false.

        The account state is exposed via two additive fields, derived only from the
        universal userAccountControl attribute so the classification is identical
        for every directory (no customer-specific convention required):
        - AccountStatus : 'Active' (found, ACCOUNTDISABLE bit not set), 'Disabled'
          (found, userAccountControl 0x2 set) or 'NotFound' (null AD entry).
        - Enabled       : $true only for an 'Active' account.
        A resolved account whose entry carries no userAccountControl (e.g. some
        non-AD LDAP directories) is treated as Active/Enabled, preserving the
        pre-1.3.3 behaviour.

        .PARAMETER UserLogin
        The SharePoint user login this record represents (carried through as-is).

        .PARAMETER AdUser
        The object returned by Get-SPSADUser (a DirectoryServices.SearchResult),
        or $null when the user could not be resolved.

        .OUTPUTS
        A PSCustomObject: UserLogin, DisplayName, FirstName, LastName, Email,
        Country, Location, Resolved, Enabled, AccountStatus, Error.

        .EXAMPLE
        $record = ConvertTo-SPSUserRecord -UserLogin 'i:0#.w|CONTOSO\jdoe' -AdUser (Get-SPSADUser -UserLogin 'i:0#.w|CONTOSO\jdoe')
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $UserLogin,

        [Parameter()]
        [AllowNull()]
        $AdUser
    )

    $record = [PSCustomObject]@{
        UserLogin     = $UserLogin
        DisplayName   = $null
        FirstName     = $null
        LastName      = $null
        Email         = $null
        Country       = $null
        Location      = $null
        Resolved      = $false
        Enabled       = $false
        AccountStatus = 'NotFound'
        Error         = $null
    }

    if ($null -eq $AdUser) {
        return $record
    }

    $record.Country     = "$($AdUser.Properties['co'])".ToUpper()
    $record.Location    = "$($AdUser.Properties['l'])".ToUpper()
    $record.FirstName   = "$($AdUser.Properties['givenname'])"
    $record.LastName    = "$($AdUser.Properties['sn'])"
    $record.Email       = "$($AdUser.Properties['mail'])"
    $record.DisplayName = "$($AdUser.Properties['displayname'])"
    if ([string]::IsNullOrEmpty($record.DisplayName) -and
        -not [string]::IsNullOrEmpty($record.FirstName) -and
        -not [string]::IsNullOrEmpty($record.LastName)) {
        $record.DisplayName = "$($record.FirstName) $($record.LastName)"
    }

    # Account status from userAccountControl (bit 0x2 = ACCOUNTDISABLE). This is a
    # universal AD attribute, so the active/disabled distinction works for every
    # directory without any customer-specific convention. A resolved entry that
    # carries no userAccountControl (some non-AD LDAP directories) stays Active,
    # the pre-1.3.3 behaviour. NB: [Int32]::TryParse (2-arg) is used rather than a
    # wider [Enum] overload, for Windows PowerShell 5.1 / .NET Framework support.
    $record.AccountStatus = 'Active'
    $record.Enabled       = $true
    $uacRaw = $AdUser.Properties['useraccountcontrol']
    if ($null -ne $uacRaw) {
        $uacInt = 0
        if ([System.Int32]::TryParse("$(@($uacRaw)[0])", [ref] $uacInt) -and (($uacInt -band 0x2) -ne 0)) {
            $record.AccountStatus = 'Disabled'
            $record.Enabled       = $false
        }
    }

    $record.Resolved = $true

    return $record
}
