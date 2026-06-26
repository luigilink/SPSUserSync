function Clear-SPSLogFolder {
    <#
        .SYNOPSIS
        Deletes old log files from a folder based on a retention window.

        .DESCRIPTION
        Clear-SPSLogFolder removes files older than the requested number of
        days from the specified folder. The retention window is evaluated
        against each file's LastWriteTime.

        The function emits banner lines on stdout so it stays visible inside
        the Start-Transcript output produced by SPSUserSync scripts.

        .PARAMETER Path
        Directory to scan. Subdirectories are scanned recursively.

        .PARAMETER Retention
        Number of days to keep. Files older than this are deleted. Defaults
        to 90 days.

        .PARAMETER Extension
        File name pattern to filter on. Defaults to '*.log'.

        .EXAMPLE
        Clear-SPSLogFolder -Path 'D:\Tools\Logs' -Retention 30
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Path,

        [Parameter()]
        [System.UInt32]
        $Retention = 90,

        [Parameter()]
        [System.String]
        $Extension = '*.log'
    )

    if (-not (Test-Path -Path $Path)) {
        return
    }

    $Now = Get-Date
    $LastWrite = $Now.AddDays(-$Retention)

    $files = Get-ChildItem -Path $Path -Include $Extension -Recurse |
        Where-Object -FilterScript { $_.LastWriteTime -le $LastWrite }

    Write-Output '--------------------------------------------------------------'
    if ($files) {
        Write-Output "Cleaning log files in $Path ..."
        foreach ($file in $files) {
            if ($null -ne $file) {
                Write-Output "Deleting file $file ..."
                Remove-Item $file.FullName | Out-Null
            }
        }
    }
    else {
        Write-Output "$Path - No needs to delete log files"
    }
    Write-Output '--------------------------------------------------------------'
}
