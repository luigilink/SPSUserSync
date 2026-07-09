function Get-SPSADUser {
    <#
        .SYNOPSIS
        Resolves a SharePoint user login to the corresponding Active Directory entry.

        .DESCRIPTION
        Parses the SharePoint user login (claim or DOMAIN\user form), looks up
        the matching forest configuration via Get-SPSADConnection and runs an
        LDAP search.

        Three outcomes, kept deliberately distinct:
        - Found: returns the first DirectoryServices.SearchResult.
        - Not found / skipped / unreachable: returns $null when the search ran but
          matched nothing, when the login is not in DOMAIN\user form (claim groups,
          federated principals, well-known accounts), or when the LDAP query fails
          for a connectivity reason (server not operational, referral) - the login
          is logged and left unresolved so the run isolates it and continues.
        - Configuration/secret error: throws a terminating error with the
          FullyQualifiedErrorId 'SPSADConfigError' when the AD connection cannot be
          BUILT (missing LdapPath, missing CredentialKey, or an undecodable
          secrets.psd1 entry). This is a deterministic, fixable deployment error, so
          it is NOT returned as $null - a broken secret is never mistaken for a
          missing user.

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

    # Build the AD connection. A throw here (including an undecodable secrets.psd1
    # entry surfaced by Get-SPSSecret) means the lookup could NOT be performed: a
    # configuration/secret problem, not a missing user. Surface it as a terminating
    # SPSADConfigError so callers never mistake it for "user not found".
    $searcher = $null
    try {
        $searcher = Get-SPSADConnection -DomainName $parsed.Domain -AccountName $parsed.Account -ConfigPath $ConfigPath -ErrorAction Stop
    }
    catch {
        $configMessage = @"
Active Directory lookup could not be performed for user '$UserLogin' (configuration/secret error).
Domain: $($parsed.Domain)
Account: $($parsed.Account)
Exception: $($_.Exception.Message)
"@
        Add-SPSUserSyncEvent -Message $configMessage -Source 'Get-SPSADUser' -EntryType 'Error'
        $errorRecord = New-Object System.Management.Automation.ErrorRecord(
            [System.InvalidOperationException]::new($configMessage, $_.Exception),
            'SPSADConfigError',
            [System.Management.Automation.ErrorCategory]::ResourceUnavailable,
            $parsed.Domain
        )
        $PSCmdlet.ThrowTerminatingError($errorRecord)
    }

    if ($null -eq $searcher) {
        # Get-SPSADConnection returns $null only for a domain that is not configured
        # and has no Default entry: nothing to query, treat as a skipped login.
        Write-Verbose -Message "No AD connection for domain '$($parsed.Domain)'; skipping '$UserLogin'."
        return $null
    }

    # The connection is valid; a failure now is an LDAP/query/bind error (server
    # unreachable, referral, bad path). This is a CONNECTIVITY problem, not a
    # deployment/secret one: it can be transient and can affect only one external
    # directory (e.g. a partner LDAP reachable from an application farm but not from
    # the UPA master). Keep it NON-fatal - log it and return $null so the run
    # isolates this login and continues, exactly as before. Only the connection-BUILD
    # failure above (missing LdapPath / CredentialKey / undecodable secret) is fatal,
    # so a flaky forest never nukes a whole multi-forest run. (Distinguishing a whole
    # forest being unreachable and trusting the JSON on the profile side is a
    # separate, opt-in refinement tracked for a later release.)
    try {
        $adUser = $searcher.FindOne()
    }
    catch {
        $queryMessage = @"
Active Directory query failed for user '$UserLogin' (connectivity error; login left unresolved).
Domain: $($parsed.Domain)
Account: $($parsed.Account)
Exception: $($_.Exception.Message)
"@
        Add-SPSUserSyncEvent -Message $queryMessage -Source 'Get-SPSADUser' -EntryType 'Error'
        return $null
    }

    # SearchResult when found, $null when the search ran but matched nothing.
    return $adUser
}
