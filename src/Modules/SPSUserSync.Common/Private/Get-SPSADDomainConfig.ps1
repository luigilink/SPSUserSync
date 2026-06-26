function Get-SPSADDomainConfig {
    <#
        .SYNOPSIS
        Loads and caches the AD domain configuration from ad-domains.psd1.

        .DESCRIPTION
        Reads the ad-domains.psd1 file once per module instance and caches
        the result in $script:adDomainConfigCache so repeated calls are free.
        The cache key includes the resolved path so changing -ConfigPath
        forces a reload.

        The returned hashtable matches the structure of ad-domains.psd1:
            @{
                Domains               = @{ <domain> = @{ LdapPath; AuthMode; ... } }
                Default               = @{ LdapPath; AuthMode; ... }
                DefaultFilterTemplate = '...'
            }

        .PARAMETER ConfigPath
        Optional path to the folder containing ad-domains.psd1. Defaults to
        src/config/ next to the module.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [Parameter()]
        [System.String]
        $ConfigPath
    )

    if ([string]::IsNullOrEmpty($ConfigPath)) {
        $ConfigPath = Get-SPSConfigRoot
    }

    $file = Join-Path -Path $ConfigPath -ChildPath 'ad-domains.psd1'

    if ($script:adDomainConfigCache -and $script:adDomainConfigPath -eq $file) {
        return $script:adDomainConfigCache
    }

    if (-not (Test-Path -Path $file)) {
        throw "AD domain configuration not found at '$file'. Copy ad-domains.example.psd1 to ad-domains.psd1 and edit the values."
    }

    $script:adDomainConfigCache = Import-PowerShellDataFile -Path $file
    $script:adDomainConfigPath  = $file

    return $script:adDomainConfigCache
}
