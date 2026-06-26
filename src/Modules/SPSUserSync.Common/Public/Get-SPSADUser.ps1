function Get-SPSADUser {
    <#
        .SYNOPSIS
        Resolves a SharePoint user login to the corresponding Active Directory entry.

        .DESCRIPTION
        Parses the SharePoint user login (claim or DOMAIN\user form), looks up
        the matching forest configuration via Get-SPSADConnection and runs an
        LDAP search. Returns the first DirectoryServices.SearchResult or $null
        when the user cannot be resolved.

        Non-DOMAIN\user logins (claim groups, federated principals, well-known
        accounts) are skipped and return $null without firing an LDAP query
        that could otherwise match an unrelated user.

        .PARAMETER UserLogin
        The raw SharePoint user login, in claim or DOMAIN\user form.

        .PARAMETER ConfigPath
        Optional override for the folder containing ad-domains.psd1 and
        secrets.psd1.

        .EXAMPLE
        $adUser = Get-SPSADUser -UserLogin 'i:0#.w|CONTOSO\jdoe'
        if ($adUser) { $adUser.Properties['mail'] }
    #>
    [CmdletBinding()]
    [OutputType([System.DirectoryServices.SearchResult])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $UserLogin,

        [Parameter()]
        [System.String]
        $ConfigPath
    )

    $parsed = ConvertFrom-SPSUserLogin -UserLogin $UserLogin
    if (-not $parsed.IsValid) {
        Write-Verbose -Message "UserLogin '$UserLogin' is not in DOMAIN\user format, skipping AD lookup."
        return $null
    }

    try {
        $searcher = Get-SPSADConnection -DomainName $parsed.Domain -AccountName $parsed.Account -ConfigPath $ConfigPath
        if ($null -eq $searcher) {
            return $null
        }

        $adUser = $searcher.FindOne()
        if ($null -ne $adUser) {
            return $adUser
        }
        return $null
    }
    catch {
        $catchMessage = @"
An error occurred during AD lookup for user '$UserLogin'
Domain: $($parsed.Domain)
Account: $($parsed.Account)
Exception: $_
"@
        Add-SPSUserSyncEvent -Message $catchMessage -Source 'Get-SPSADUser' -EntryType 'Error'
        return $null
    }
}
