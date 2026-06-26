function Add-SPSUserSyncEvent {
    <#
        .SYNOPSIS
        Writes an event to the dedicated SPSUserSync Windows Event Log.

        .DESCRIPTION
        Add-SPSUserSyncEvent writes an entry to the custom 'SPSUserSync' Windows
        Event Log under the specified Source. The Source typically matches the
        name of the calling function, which makes filtering and SCOM monitoring
        straightforward.

        When the Source does not exist yet, the function creates it under the
        SPSUserSync log. When the log itself does not exist, it is created on
        first use. Creating event sources requires administrative privileges,
        so this function is expected to be called from a script running as
        Administrator (which SPSUserSync scripts already validate).

        Each event message is prefixed with a header containing the script
        version, the current user and the computer name to ease cross-server
        correlation.

        .PARAMETER Message
        The event message body. The header is prepended automatically.

        .PARAMETER Source
        Identifier of the event source. Use the name of the calling function
        for consistency (e.g. 'Get-SPSADUser', 'Add-SPSUserProfile').

        .PARAMETER EntryType
        Severity of the event. Defaults to Information.

        .PARAMETER EventID
        Numeric event identifier. Defaults to 1.

        .EXAMPLE
        Add-SPSUserSyncEvent -Message 'JSON file written' -Source 'Get-SPSUniqueUsers'

        .EXAMPLE
        Add-SPSUserSyncEvent -Message $_.Exception.Message -Source 'Get-SPSADUser' -EntryType 'Error' -EventID 3000
    #>
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $Message,

        [Parameter(Mandatory = $true)]
        [System.String]
        $Source,

        [Parameter()]
        [ValidateSet('Error', 'Information', 'FailureAudit', 'SuccessAudit', 'Warning')]
        [System.String]
        $EntryType = 'Information',

        [Parameter()]
        [System.UInt32]
        $EventID = 1
    )

    $LogName = 'SPSUserSync'

    if ([System.Diagnostics.EventLog]::SourceExists($Source)) {
        $sourceLogName = [System.Diagnostics.EventLog]::LogNameFromSourceName($Source, '.')
        if ($LogName -ne $sourceLogName) {
            Write-Verbose -Message "[ERROR] Specified source {$Source} already exists on log {$sourceLogName}"
            return
        }
    }
    else {
        if ([System.Diagnostics.EventLog]::Exists($LogName) -eq $false) {
            $null = New-EventLog -LogName $LogName -Source $Source
        }
        else {
            [System.Diagnostics.EventLog]::CreateEventSource($Source, $LogName)
        }
    }

    try {
        $scriptVersion = if ($script:spsUserSyncVersion) {
            $script:spsUserSyncVersion
        }
        else {
            # Fallback when Add-SPSUserSyncEvent is called before Initialize-SPSScript
            # (e.g. an exception during early bootstrap). Read the module manifest
            # version directly so the event still records something meaningful.
            $autoVersion = $MyInvocation.MyCommand.Module.Version
            if ($null -eq $autoVersion) {
                $autoVersion = (Get-Module -Name SPSUserSync.Common -ErrorAction SilentlyContinue).Version
            }
            if ($null -ne $autoVersion) { $autoVersion.ToString() } else { 'unknown' }
        }
        $userName       = if ($script:currentUser) { $script:currentUser } else { ([Security.Principal.WindowsIdentity]::GetCurrent()).Name }
        $callerScript   = if ($script:scriptName)  { $script:scriptName }  else { 'unknown' }
        $headerMessage = @"
SPSUserSync Version: $scriptVersion
Script: $callerScript
User: $userName
ComputerName: $($env:COMPUTERNAME)
--------------------------------------------------------------
"@
        Write-EventLog -LogName $LogName -Source $Source -EventId $EventID -Message ($headerMessage + "`r`n" + $Message) -EntryType $EntryType
    }
    catch {
        Write-Error -Message @"
SPSUserSync Version: $scriptVersion
Script: $callerScript
An error occurred while writing to Event Log in Source: $Source
User: $userName
ComputerName: $($env:COMPUTERNAME)
Exception: $_
"@
    }
}
