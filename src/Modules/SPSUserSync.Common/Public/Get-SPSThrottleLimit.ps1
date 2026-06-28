function Get-SPSThrottleLimit {
    <#
        .SYNOPSIS
        Computes a sensible default degree of parallelism for the host.

        .DESCRIPTION
        Returns a throttle limit derived from the number of logical processors,
        following the same heuristic as SPSWakeUp: cap at 10 on machines with 8
        or more logical CPUs, otherwise use 2x the logical CPU count (minimum 2).

        The processor count is read from [System.Environment]::ProcessorCount,
        which is cross-platform (Windows PowerShell 5.1 and PowerShell 7), so the
        helper is testable off a SharePoint server.

        .EXAMPLE
        $limit = Get-SPSThrottleLimit
        # 8-core box -> 10 ; 4-core box -> 8
    #>
    [CmdletBinding()]
    [OutputType([System.Int32])]
    param ()

    $logical = [System.Environment]::ProcessorCount
    if ($logical -ge 8) {
        return 10
    }
    return [System.Math]::Max(2, 2 * $logical)
}
