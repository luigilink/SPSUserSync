function Get-SPSJsonRecordCount {
    <#
        .SYNOPSIS
        Returns the number of records in a JSON snapshot file.

        .DESCRIPTION
        Loads a UTF-8 JSON file and returns the count of top-level records. A single
        object (not wrapped in an array) counts as 1. Returns:

        - $null when the file does not exist (so the caller can tell "missing" apart
          from "empty"),
        - 0 when the file is empty, whitespace, or parses to null,
        - the record count otherwise.

        Parsing errors are swallowed and reported as 0 so a corrupt snapshot does not
        crash the comparison; the anomaly detection downstream will flag the resulting
        drop.

        .PARAMETER Path
        Path of the JSON file to inspect.
    #>
    [CmdletBinding()]
    [OutputType([System.Object])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path
    )

    if (-not (Test-Path -Path $Path)) {
        return $null
    }

    try {
        $content = Get-Content -Path $Path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($content)) {
            return 0
        }
        $data = $content | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $data) {
            return 0
        }
        return @($data).Count
    }
    catch {
        Write-Verbose -Message "Get-SPSJsonRecordCount: failed to parse '$Path' ($($_.Exception.Message)). Returning 0."
        return 0
    }
}
