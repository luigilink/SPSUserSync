function ConvertFrom-SPSUserLogin {
    <#
        .SYNOPSIS
        Parses a SharePoint claims login into its DOMAIN/Account components.

        .DESCRIPTION
        SharePoint user logins are usually stored as claims, e.g.
        'i:0#.w|DOMAIN\user'. This helper strips the configured claim prefix
        (default 'i:0#.w|') and splits the remaining DOMAIN\Account pair so
        the rest of the module can resolve the user against the correct AD
        forest.

        Returns a PSCustomObject with Domain, Account, Raw and IsValid
        properties. IsValid is $false when the input is empty, when no
        backslash is found (typical of group claims, federated claims,
        system accounts), or when either component is empty after parsing.

        .PARAMETER UserLogin
        The raw SharePoint user login (claim form accepted).

        .PARAMETER ClaimPrefix
        Prefix to strip before splitting. Defaults to 'i:0#.w|'.

        .EXAMPLE
        ConvertFrom-SPSUserLogin -UserLogin 'i:0#.w|CONTOSO\jdoe'
        # Domain='CONTOSO' Account='jdoe' IsValid=$true
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [System.String]
        $UserLogin,

        [Parameter()]
        [System.String]
        $ClaimPrefix = 'i:0#.w|'
    )

    $result = [PSCustomObject]@{
        Raw     = $UserLogin
        Domain  = $null
        Account = $null
        IsValid = $false
    }

    if ([string]::IsNullOrEmpty($UserLogin)) {
        return $result
    }

    $stripped = $UserLogin
    if (-not [string]::IsNullOrEmpty($ClaimPrefix) -and $stripped.StartsWith($ClaimPrefix)) {
        $stripped = $stripped.Substring($ClaimPrefix.Length)
    }

    $parts = $stripped.Split('\')
    if ($parts.Count -lt 2) {
        return $result
    }

    $result.Domain  = $parts[0]
    $result.Account = $parts[1]

    if (-not [string]::IsNullOrEmpty($result.Domain) -and -not [string]::IsNullOrEmpty($result.Account)) {
        $result.IsValid = $true
    }

    return $result
}
