function Initialize-SPSScript {
    <#
        .SYNOPSIS
        Common bootstrap for SPSUserSync scripts: admin check, transcript, banner.

        .DESCRIPTION
        Initialize-SPSScript performs the boilerplate that the SPSUserSync
        entry-point scripts (SPSyncUserInfoList.ps1, SPSyncUserProfile.ps1)
        share:

        - Validates the current process is running with Administrator rights
          (required to write to a custom Event Log on first use, and to call
          most SharePoint cmdlets).
        - Sets the host window title.
        - Computes log-folder paths and creates the folder if missing.
        - Starts a transcript file in that log folder.
        - Prints a banner with script name, version, start time, current user,
          PowerShell version and target server.
        - Exposes the script-scoped variables ``$pathLogFolder``,
          ``$pathLogFile``, ``$currentUser``, ``$spsUserSyncVersion``,
          ``$DateStarted`` and ``$scriptName`` inside the module so
          ``Add-SPSUserSyncEvent`` can read them without explicit parameters.

        Returns a PSCustomObject with LogFolder, LogFile, CurrentUser, Version,
        DateStarted and ServerTarget so the caller can use these values without
        reaching into module-scoped variables.

        .PARAMETER ScriptName
        Short name of the script (e.g. 'SPSyncUserInfoList'). Used in the
        banner, log file name and window title.

        .PARAMETER Version
        Optional script version string. When omitted, Initialize-SPSScript
        reads the SPSUserSync.Common module manifest version so every
        consumer reports the same single source of truth. The repository
        bumps that one ModuleVersion at release time and the scripts pick
        it up automatically.

        .PARAMETER LogFolder
        Folder where the transcript and rotation logs are written. Defaults
        to a 'Logs' folder next to the caller script.

        .EXAMPLE
        $ctx = Initialize-SPSScript -ScriptName 'SPSyncUserInfoList'
        Clear-SPSLogFolder -Path $ctx.LogFolder -Retention 90
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSCustomObject])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $ScriptName,

        [Parameter()]
        [System.String]
        $Version,

        [Parameter()]
        [System.String]
        $LogFolder
    )

    if ([string]::IsNullOrEmpty($Version)) {
        $moduleVersion = $MyInvocation.MyCommand.Module.Version
        if ($null -eq $moduleVersion) {
            $moduleVersion = (Get-Module -Name SPSUserSync.Common -ErrorAction SilentlyContinue).Version
        }
        if ($null -ne $moduleVersion) {
            $Version = $moduleVersion.ToString()
        }
        else {
            $Version = 'unknown'
        }
    }

    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
        throw "You do not have Administrator rights to run $ScriptName. Please re-run this script as an Administrator."
    }

    if ([string]::IsNullOrEmpty($LogFolder)) {
        $callerInvocation = (Get-Variable -Name MyInvocation -Scope 1 -ErrorAction SilentlyContinue).Value
        if ($callerInvocation -and $callerInvocation.MyCommand.Definition) {
            $callerRoot = Split-Path -Parent $callerInvocation.MyCommand.Definition
        }
        else {
            $callerRoot = Get-Location | Select-Object -ExpandProperty Path
        }
        $LogFolder = Join-Path -Path $callerRoot -ChildPath 'Logs'
    }

    if (-not (Test-Path -Path $LogFolder)) {
        $null = New-Item -Path $LogFolder -ItemType Directory -Force
    }

    $dateStarted  = Get-Date
    $currentUser  = ([Security.Principal.WindowsIdentity]::GetCurrent()).Name
    $psVersion    = ($host).Version.ToString()
    $serverTarget = $env:COMPUTERNAME
    $pathLogFile  = Join-Path -Path $LogFolder -ChildPath ($ScriptName + (Get-Date -Format yyyyMMdd-HHmm) + '.log')

    $script:pathLogFolder      = $LogFolder
    $script:pathLogFile        = $pathLogFile
    $script:currentUser        = $currentUser
    $script:spsUserSyncVersion = $Version
    $script:DateStarted        = $dateStarted
    $script:scriptName         = $ScriptName

    $Host.UI.RawUI.WindowTitle = "$ScriptName script running on $serverTarget"

    Start-Transcript -Path $pathLogFile -IncludeInvocationHeader | Out-Null

    Write-Output '-----------------------------------------------'
    Write-Output "| Automated Script   - Configuration $ScriptName $Version |"
    Write-Output "| Started on         - $dateStarted by $currentUser |"
    Write-Output "| PowerShell Version - $psVersion |"
    Write-Output "| SharePoint Server  - $serverTarget |"
    Write-Output '-----------------------------------------------'

    return [PSCustomObject]@{
        LogFolder    = $LogFolder
        LogFile      = $pathLogFile
        CurrentUser  = $currentUser
        Version      = $Version
        DateStarted  = $dateStarted
        ServerTarget = $serverTarget
    }
}
