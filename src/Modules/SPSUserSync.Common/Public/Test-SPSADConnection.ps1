function Test-SPSADConnection {
    <#
        .SYNOPSIS
        Verifies that an AD domain binds and that a user (and its attributes) can be read.

        .DESCRIPTION
        Test-SPSADConnection goes one step further than simply building a
        DirectorySearcher: it actually runs a search to confirm that

        1. the LDAP bind succeeds (for 'Credential' domains this proves the stored
           secret is valid, not just decryptable), and
        2. the account used can READ at least one user object, and
        3. the attributes SPSUserSync depends on (givenName, sn, mail, co, l,
           displayName) are present on that object.

        By default it runs a generic probe that matches any user, reusing the
        domain's own LDAP filter template with '*' as the account placeholder (so it
        works for Active Directory and for custom directories such as RGA-style
        'uid=*' filters alike). Pass -SampleAccount to instead resolve one specific,
        known account and confirm its attributes.

        The function never throws on a failed bind: it captures the error in the
        returned object so callers (e.g. the readiness check) can render it.

        .PARAMETER DomainName
        Domain key as declared in ad-domains.psd1.

        .PARAMETER SampleAccount
        Optional sAMAccountName (or directory uid) of a real account to look up
        instead of the generic "any user" probe.

        .PARAMETER ConfigPath
        Optional override for the folder containing ad-domains.psd1 and secrets.psd1.

        .OUTPUTS
        PSCustomObject with Domain, BindSucceeded, UserFound, SampleAccount,
        FoundAccount, Attributes (hashtable attr -> [bool] populated),
        MissingKeyAttributes (string[]) and Error.

        .EXAMPLE
        $r = Test-SPSADConnection -DomainName 'zebes'
        if ($r.BindSucceeded -and $r.UserFound) { 'AD readable' }

        .EXAMPLE
        Test-SPSADConnection -DomainName 'zebes' -SampleAccount 'alicekeller'
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $DomainName,

        [Parameter()]
        [System.String]
        $SampleAccount,

        [Parameter()]
        [System.String]
        $ConfigPath
    )

    $keyAttributes = @('givenName', 'sn', 'mail', 'co', 'l', 'displayName')

    $result = [PSCustomObject]@{
        Domain               = $DomainName
        BindSucceeded        = $false
        UserFound            = $false
        SampleAccount        = $SampleAccount
        FoundAccount         = $null
        Attributes           = @{}
        MissingKeyAttributes = @()
        Error                = $null
    }

    $accountName = if (-not [string]::IsNullOrEmpty($SampleAccount)) { $SampleAccount } else { '*' }

    try {
        $searcher = Get-SPSADConnection -DomainName $DomainName -AccountName $accountName -ConfigPath $ConfigPath
        if ($null -eq $searcher) {
            $result.Error = 'Get-SPSADConnection returned null (check LDAP path / credential configuration)'
            return $result
        }

        # FindOne triggers the (otherwise lazy) LDAP bind. Bad credentials throw here.
        $found = $searcher.FindOne()
        $result.BindSucceeded = $true

        if ($null -ne $found) {
            $result.UserFound = $true
            if ($found.Properties['sAMAccountName'] -and $found.Properties['sAMAccountName'].Count -gt 0) {
                $result.FoundAccount = "$($found.Properties['sAMAccountName'][0])"
            }
            $missing = @()
            foreach ($attr in $keyAttributes) {
                $populated = [bool]($found.Properties[$attr.ToLower()] -and $found.Properties[$attr.ToLower()].Count -gt 0)
                $result.Attributes[$attr] = $populated
                if (-not $populated) { $missing += $attr }
            }
            $result.MissingKeyAttributes = $missing
        }
    }
    catch {
        $result.Error = $_.Exception.Message
    }

    return $result
}
