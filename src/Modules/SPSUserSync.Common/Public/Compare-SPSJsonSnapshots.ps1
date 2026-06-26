function Compare-SPSJsonSnapshots {
    <#
        .SYNOPSIS
        Compares the record count of two JSON snapshots and flags an abnormal drop.

        .DESCRIPTION
        Compare-SPSJsonSnapshots loads the current and previous JSON snapshots produced
        by SPSyncUserInfoList.ps1, counts their records, and computes the percentage
        drop from the previous to the current snapshot.

        It is a pure function: it returns a result object and never writes to the Event
        Log. The caller decides whether to raise a warning based on the IsAnomalous
        flag. This keeps the function easy to unit-test.

        A drop is considered anomalous when the previous snapshot was non-empty and the
        current snapshot lost at least -DropThresholdPercent of its records. Growth (the
        current snapshot being larger) never sets IsAnomalous.

        .PARAMETER CurrentPath
        Path of the freshly generated JSON snapshot.

        .PARAMETER PreviousPath
        Path of the previous snapshot (typically the file returned by Backup-SPSJsonFile).

        .PARAMETER DropThresholdPercent
        Minimum percentage loss that flags the comparison as anomalous. Defaults to 20.

        .OUTPUTS
        PSCustomObject with CurrentCount, PreviousCount, Delta, DropPercent,
        ThresholdPercent and IsAnomalous.

        .EXAMPLE
        $cmp = Compare-SPSJsonSnapshots -CurrentPath $new -PreviousPath $previous -DropThresholdPercent 20
        if ($cmp.IsAnomalous) { Add-SPSUserSyncEvent -Message '...' -Source 'Get-SPSUniqueUsers' -EntryType 'Warning' }
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $CurrentPath,

        [Parameter(Mandatory = $true)]
        [System.String]
        $PreviousPath,

        [Parameter()]
        [ValidateRange(0, 100)]
        [System.Int32]
        $DropThresholdPercent = 20
    )

    $currentCount  = Get-SPSJsonRecordCount -Path $CurrentPath
    $previousCount = Get-SPSJsonRecordCount -Path $PreviousPath

    $delta = $null
    $dropPercent = 0
    $isAnomalous = $false

    if ($null -ne $currentCount -and $null -ne $previousCount) {
        $delta = $currentCount - $previousCount
        if ($previousCount -gt 0 -and $currentCount -lt $previousCount) {
            $dropPercent = [Math]::Round((($previousCount - $currentCount) / $previousCount) * 100, 2)
            if ($dropPercent -ge $DropThresholdPercent) {
                $isAnomalous = $true
            }
        }
    }

    return [PSCustomObject]@{
        CurrentCount     = $currentCount
        PreviousCount    = $previousCount
        Delta            = $delta
        DropPercent      = $dropPercent
        ThresholdPercent = $DropThresholdPercent
        IsAnomalous      = $isAnomalous
    }
}
