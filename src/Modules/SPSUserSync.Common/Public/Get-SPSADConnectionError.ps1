function Get-SPSADConnectionError {
    <#
        .SYNOPSIS
        Validates the Active Directory configuration for the forests referenced by a
        set of user logins, returning the ones that cannot be connected.

        .DESCRIPTION
        Get-SPSADConnectionError derives the distinct domains from the supplied
        SharePoint user logins and, for each, tries to build an AD connection via
        Get-SPSADConnection. Building the connection decodes the matching
        secrets.psd1 entry (the DPAPI failure that binds a secret to the machine and
        account that created it), so this is a fast, query-free pre-flight: no LDAP
        search is issued.

        It returns one object per forest that FAILED, with its Domain and the Error
        message. An empty result means every referenced forest can be connected.

        Use it before a bulk run (e.g. the SPSyncUserProfile pre-flight) to fail fast
        with a clear list of misconfigured forests, instead of letting a broken
        secret silently downgrade every affected user.

        .PARAMETER UserLogin
        The SharePoint user logins to inspect (claim or DOMAIN\user form). Distinct
        domains are derived from them; non-DOMAIN\user logins are ignored.

        .PARAMETER ConfigPath
        Optional override for the folder containing ad-domains.psd1 and secrets.psd1.

        .EXAMPLE
        $errors = Get-SPSADConnectionError -UserLogin $users.UserLogin
        if ($errors.Count -ne 0) { throw "Broken forests: $($errors.Domain -join ', ')" }
    #>
    [CmdletBinding()]
    [OutputType([System.Object[]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.String[]]
        $UserLogin,

        [Parameter()]
        [System.String]
        $ConfigPath
    )

    $domains = [System.Collections.Generic.HashSet[System.String]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($login in $UserLogin) {
        if ([string]::IsNullOrEmpty($login)) { continue }
        $tail = ($login -split '\|')[-1]
        if ($tail -match '\\') {
            [void]$domains.Add(($tail -split '\\')[0])
        }
    }

    $errors = [System.Collections.Generic.List[System.Object]]::new()
    foreach ($domain in $domains) {
        try {
            $connectionParams = @{
                DomainName  = $domain
                AccountName = 'spsusersync-preflight'
                ErrorAction = 'Stop'
            }
            if (-not [string]::IsNullOrEmpty($ConfigPath)) {
                $connectionParams['ConfigPath'] = $ConfigPath
            }
            $null = Get-SPSADConnection @connectionParams
        }
        catch {
            $errors.Add([PSCustomObject]@{
                    Domain = $domain
                    Error  = $_.Exception.Message
                })
        }
    }

    return $errors.ToArray()
}
