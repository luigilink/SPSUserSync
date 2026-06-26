function Get-SPSSecret {
    <#
        .SYNOPSIS
        Loads secrets.psd1 and returns a PSCredential for the requested key.

        .DESCRIPTION
        Reads the secrets.psd1 file once per module instance, caches the
        parsed hashtable, and on each call decrypts the SecureString stored
        under the requested CredentialKey to build a PSCredential.

        SecureString values must be created with ConvertFrom-SecureString,
        which uses DPAPI keyed by the current user account on the current
        machine. As a result, secrets.psd1 is only usable by the same Windows
        account that generated its values.

        Returns $null if secrets.psd1 is missing or the key is not present.
        That allows scripts to keep running for domains that do not require
        explicit credentials (AuthMode = 'Default').

        .PARAMETER CredentialKey
        Key under the root hashtable of secrets.psd1.

        .PARAMETER ConfigPath
        Optional path to the folder containing secrets.psd1. Defaults to
        src/config/ next to the module.

        .EXAMPLE
        $cred = Get-SPSSecret -CredentialKey 'fabrikam'
    #>
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'CredentialKey',
        Justification = 'CredentialKey is a lookup key into secrets.psd1, not a password. The actual secret is decrypted from a DPAPI SecureString and returned as a PSCredential.')]
    [OutputType([System.Management.Automation.PSCredential])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $CredentialKey,

        [Parameter()]
        [System.String]
        $ConfigPath
    )

    if ([string]::IsNullOrEmpty($ConfigPath)) {
        $ConfigPath = Get-SPSConfigRoot
    }

    $file = Join-Path -Path $ConfigPath -ChildPath 'secrets.psd1'

    if (-not $script:secretsCache -or $script:secretsConfigPath -ne $file) {
        if (-not (Test-Path -Path $file)) {
            Write-Verbose -Message "Secrets file not found at '$file'. Credential-mode domains will not be usable."
            $script:secretsCache      = @{}
            $script:secretsConfigPath = $file
        }
        else {
            $script:secretsCache      = Import-PowerShellDataFile -Path $file
            $script:secretsConfigPath = $file
        }
    }

    if (-not $script:secretsCache.ContainsKey($CredentialKey)) {
        Write-Verbose -Message "Secret entry '$CredentialKey' not found in '$file'."
        return $null
    }

    $entry = $script:secretsCache[$CredentialKey]

    if ([string]::IsNullOrEmpty($entry.Username)) {
        throw "Secret entry '$CredentialKey' has no Username defined in '$file'."
    }
    if ([string]::IsNullOrEmpty($entry.PasswordSecure) -or $entry.PasswordSecure -like 'PASTE-*') {
        throw "Secret entry '$CredentialKey' has no real PasswordSecure value in '$file'. Generate one with: Read-Host -AsSecureString | ConvertFrom-SecureString"
    }

    try {
        $secureString = ConvertTo-SecureString -String $entry.PasswordSecure -ErrorAction Stop
    }
    catch {
        throw "Failed to decode SecureString for secret '$CredentialKey'. The value must be the output of ConvertFrom-SecureString on the current user account and machine. Original error: $($_.Exception.Message)"
    }

    return New-Object System.Management.Automation.PSCredential($entry.Username, $secureString)
}
