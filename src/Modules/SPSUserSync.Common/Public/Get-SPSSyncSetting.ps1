function Get-SPSSyncSetting {
    <#
        .SYNOPSIS
        Loads and caches the sync-settings.psd1 file.

        .DESCRIPTION
        Reads sync-settings.psd1 once per module instance and caches the
        parsed hashtable. The cache is keyed on the resolved path so changing
        -ConfigPath forces a reload.

        The returned hashtable matches the structure of
        sync-settings.example.psd1 and contains at minimum:
            EnvName, AppCode, ClaimPrefix,
            ExcludedUserLogins, ExcludedUserLoginPatterns,
            MasterVM, MySiteUrl, RemoteJsonPath,
            LogRetentionDays, UpaLogRetentionDays.

        .PARAMETER ConfigPath
        Optional path to the folder containing sync-settings.psd1. Defaults
        to src/config/ next to the module.

        .EXAMPLE
        $settings = Get-SPSSyncSetting
        $remote = $settings.RemoteJsonPath -f $settings.MasterVM, $settings.AppCode
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

    $file = Join-Path -Path $ConfigPath -ChildPath 'sync-settings.psd1'

    if ($script:syncSettingsCache -and $script:syncSettingsConfigPath -eq $file) {
        return $script:syncSettingsCache
    }

    if (-not (Test-Path -Path $file)) {
        throw "Sync settings file not found at '$file'. Copy sync-settings.example.psd1 to sync-settings.psd1 and edit the values for your environment."
    }

    $script:syncSettingsCache      = Import-PowerShellDataFile -Path $file
    $script:syncSettingsConfigPath = $file

    return $script:syncSettingsCache
}
