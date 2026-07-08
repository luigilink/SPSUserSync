function Get-SPSADConnection {
    <#
        .SYNOPSIS
        Builds a DirectorySearcher pre-configured for a given AD domain and account.

        .DESCRIPTION
        Resolves the requested domain against ad-domains.psd1, retrieves the
        right LDAP path, authentication mode and (optionally) bind credentials
        from secrets.psd1, and returns a ready-to-use
        System.DirectoryServices.DirectorySearcher.

        The search filter is built from the per-domain LdapFilterTemplate when
        present, otherwise from DefaultFilterTemplate at the root of
        ad-domains.psd1. Both templates accept {0} as the placeholder for the
        account name.

        Throws on a hard misconfiguration (config file unreadable, a configured
        domain with no LdapPath, or a Credential-mode domain whose CredentialKey
        or secret is missing/undecodable) so the caller can surface a clear
        configuration error instead of silently treating it as "user not found".
        Returns $null only for the benign case of a domain that is not configured
        and for which no Default entry exists (a login to skip).

        .PARAMETER DomainName
        Domain key as it appears in ad-domains.psd1 (case-insensitive). When
        the key is unknown, the 'Default' entry is used.

        .PARAMETER AccountName
        The sAMAccountName (or LDAP uid for custom directories) to search for.

        .PARAMETER ConfigPath
        Optional override for the folder containing ad-domains.psd1 and
        secrets.psd1.

        .EXAMPLE
        $searcher = Get-SPSADConnection -DomainName 'contoso' -AccountName 'jdoe'
        $adUser = $searcher.FindOne()
    #>
    [CmdletBinding()]
    [OutputType([System.DirectoryServices.DirectorySearcher])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $DomainName,

        [Parameter(Mandatory = $true)]
        [System.String]
        $AccountName,

        [Parameter()]
        [System.String]
        $ConfigPath
    )

    try {
        $config = Get-SPSADDomainConfig -ConfigPath $ConfigPath
    }
    catch {
        throw "Get-SPSADConnection: unable to load the AD domain configuration. $($_.Exception.Message)"
    }

    $domainKey   = $DomainName.ToLower()
    $domainEntry = $null

    if ($config.Domains.ContainsKey($domainKey)) {
        $domainEntry = $config.Domains[$domainKey]
    }
    elseif ($config.Default) {
        Write-Verbose -Message "Domain '$DomainName' not found in ad-domains.psd1. Falling back to the Default entry."
        $domainEntry = $config.Default
    }
    else {
        Write-Warning -Message "Domain '$DomainName' not found in ad-domains.psd1 and no Default entry is defined."
        return $null
    }

    if ([string]::IsNullOrEmpty($domainEntry.LdapPath)) {
        throw "Domain '$DomainName' has no LdapPath defined in ad-domains.psd1."
    }

    $authMode      = if ($domainEntry.AuthMode) { $domainEntry.AuthMode } else { 'Default' }
    $authTypeName  = if ($domainEntry.AuthenticationType) { $domainEntry.AuthenticationType } else { 'Secure' }
    $authType      = [System.DirectoryServices.AuthenticationTypes]::$authTypeName

    $directoryEntry = $null
    if ($authMode -eq 'Credential') {
        if ([string]::IsNullOrEmpty($domainEntry.CredentialKey)) {
            throw "Domain '$DomainName' uses AuthMode 'Credential' but no CredentialKey is defined in ad-domains.psd1."
        }

        # Get-SPSSecret throws on an undecodable/placeholder/no-Username secret; a
        # $null here means the CredentialKey is absent from secrets.psd1 entirely.
        $credential = Get-SPSSecret -CredentialKey $domainEntry.CredentialKey -ConfigPath $ConfigPath
        if ($null -eq $credential) {
            throw "Domain '$DomainName' requires credential '$($domainEntry.CredentialKey)' but it is missing from secrets.psd1."
        }

        $plainPassword = $credential.GetNetworkCredential().Password
        $directoryEntry = New-Object System.DirectoryServices.DirectoryEntry(
            $domainEntry.LdapPath,
            $credential.UserName,
            $plainPassword,
            $authType
        )
    }
    else {
        $directoryEntry = New-Object System.DirectoryServices.DirectoryEntry $domainEntry.LdapPath
    }

    $filterTemplate = if (-not [string]::IsNullOrEmpty($domainEntry.LdapFilterTemplate)) {
        $domainEntry.LdapFilterTemplate
    }
    elseif (-not [string]::IsNullOrEmpty($config.DefaultFilterTemplate)) {
        $config.DefaultFilterTemplate
    }
    else {
        '(&(objectCategory=person)(objectClass=user)(sAMAccountName={0}))'
    }

    $searcher = New-Object System.DirectoryServices.DirectorySearcher($directoryEntry)
    $searcher.Filter = $filterTemplate -f $AccountName
    $searcher.PageSize = 10
    $searcher.SearchScope = 'Subtree'

    return $searcher
}
