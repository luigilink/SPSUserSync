<#
    .SYNOPSIS
    Generates a JSON snapshot of every SharePoint Server site collection user
    enriched with the matching Active Directory attributes.

    .DESCRIPTION
    SPSyncUserInfoList.ps1 iterates over every SPSite of the local farm,
    resolves each unique SPUser against the right Active Directory forest
    (driven by ad-domains.psd1), and produces a JSON file consumed downstream
    by SPSyncUserProfile.ps1 to keep the User Profile Service Application
    synchronized.

    The script is the multi-forest alternative to the built-in User Profile
    AD Import: each application farm in scope writes its own JSON, the file
    is copied to the master VM of the User Profile Service farm, and
    SPSyncUserProfile.ps1 reconciles the profiles there.

    .PARAMETER FilterUrl
    Optional wildcard filter applied to SPSite URLs. When set, the script
    processes only matching site collections and writes a CUSTOM-tagged JSON
    file. Without this parameter, every SPSite is processed and the JSON is
    tagged with the AppCode read from sync-settings.psd1.

    .EXAMPLE
    SPSyncUserInfoList.ps1

    .EXAMPLE
    SPSyncUserInfoList.ps1 -FilterUrl '*sites/contoso*'

    .NOTES
    FileName:   SPSyncUserInfoList.ps1
    Author:     Jean-Cyril DROUHIN
    Project:    https://github.com/luigilink/SPSUserSync
#>
param
(
    [Parameter()]
    [System.String]
    $FilterUrl
)

#region Import Modules
try {
    Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath 'Modules\SPSUserSync.Common\SPSUserSync.Common.psd1') -Force -ErrorAction Stop
}
catch {
    Write-Error -Message @"
Failed to import SPSUserSync.Common module from path: $PSScriptRoot\Modules\SPSUserSync.Common
Exception: $_
"@
    Exit
}
#endregion

#region Classes
class SPSiteUser {
    [System.String]$UserLogin
    [System.String]$DisplayName
    [System.String]$FirstName
    [System.String]$LastName
    [System.String]$Email
    [System.String]$Location
    [System.String]$Country
}

class SPSDeletedUser {
    [System.String]$UserLogin
    [System.String]$Url
    [System.String]$Date
    [System.String]$TimeStamp
}
#endregion

#region internal functions
function Test-SPSUserExcluded {
    <#
        .SYNOPSIS
        Returns $true when a UserLogin matches a literal or wildcard exclusion.
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.String]
        $UserLogin,

        [Parameter()]
        [System.String[]]
        $Literals,

        [Parameter()]
        [System.String[]]
        $Patterns
    )

    if ($Literals -and ($Literals -contains $UserLogin)) {
        return $true
    }
    if ($Patterns) {
        foreach ($pattern in $Patterns) {
            if ($UserLogin -like $pattern) { return $true }
        }
    }
    return $false
}

function Get-SPSUniqueUsers {
    [CmdletBinding()]
    param
    (
        [Parameter()]
        [System.String]
        $FilterUrl,

        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]
        $Settings,

        [Parameter(Mandatory = $true)]
        [System.String]
        $JsonFilePath,

        [Parameter(Mandatory = $true)]
        [System.String]
        $DeletedJsonFilePath
    )

    $tbSPSiteUsers    = New-Object -TypeName System.Collections.ArrayList
    $tbSPSDeletedUser = New-Object -TypeName System.Collections.ArrayList
    $funcStarted      = Get-Date

    # Success signal consumed by the Main region: set to $true only once a
    # non-empty JSON snapshot has actually been written. The downstream HTML report
    # and the remote copy are skipped when this stays $false, so a failed or empty
    # run never overwrites or propagates the previous good file.
    $script:GetSPSUniqueUsersSucceeded = $false

    Write-Output '--------------------------------------------------------------'
    Write-Output "Get Unique SPUser - Started at $funcStarted"

    try {
        if (-not [string]::IsNullOrEmpty($FilterUrl)) {
            $getSPSites = Get-SPSite -Limit All | Where-Object -FilterScript { $_.Url -like "$FilterUrl" }
        }
        else {
            $getSPSites = Get-SPSite -Limit All
        }

        # Built-in safety exclusions: these classic system principals are never
        # read into the JSON nor removed from a web, regardless of config. Their
        # claims forms may be listed in ExcludedUserLogins, but the classic forms
        # (e.g. 'NT AUTHORITY\authenticated users') would otherwise slip through
        # and be pruned by the SyncFromAD cleanup below on a claims-based farm.
        $builtInExcludedPatterns = @(
            'NT AUTHORITY\*'
            'BUILTIN\*'
            'SHAREPOINT\*'
        )
        $excludedLiterals = $Settings.ExcludedUserLogins
        $excludedPatterns = @()
        if ($Settings.ExcludedUserLoginPatterns) {
            $excludedPatterns += $Settings.ExcludedUserLoginPatterns
        }
        $excludedPatterns += $builtInExcludedPatterns
        $claimPrefix      = $Settings.ClaimPrefix

        # RemoveUnresolvableUsers gates the destructive cleanup below. When $false
        # (default), a user that cannot be synced from AD is reported and left in
        # place; only the benign Set-SPUser -SyncFromAD refresh runs. When $true,
        # the user is removed from the web (legacy behavior).
        $removeUnresolvableUsers = if ($null -ne $Settings.RemoveUnresolvableUsers) {
            [bool]$Settings.RemoveUnresolvableUsers
        }
        else {
            $false
        }

        # ParallelADResolution (opt-in) resolves the unique user logins against AD
        # concurrently via a RunspacePool. Off by default: on small farms the
        # per-runspace module-import overhead outweighs the saved LDAP latency.
        $parallelADResolution = if ($null -ne $Settings.ParallelADResolution) {
            [bool]$Settings.ParallelADResolution
        }
        else {
            $false
        }
        $adThrottleLimit = if ($null -ne $Settings.MaxParallelADQueries -and [int]$Settings.MaxParallelADQueries -gt 0) {
            [int]$Settings.MaxParallelADQueries
        }
        else {
            0
        }

        # Phase 1 records one snapshot per unique login (first occurrence wins), in
        # an ordinal (case-sensitive) dictionary to preserve the previous dedup.
        $uniqueUsers = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)

        $spUsersFound = 0
        foreach ($site in $getSPSites) {
            $spUsersFound += $site.RootWeb.SiteUsers.Count
            Write-Output "SPWeb Url: $($site.RootWeb.Url)"
            Write-Output "Total SPUsers: $($site.RootWeb.SiteUsers.Count)"

            $spUsers = $site.RootWeb.SiteUsers | Where-Object -FilterScript {
                -not (Test-SPSUserExcluded -UserLogin $_.UserLogin -Literals $excludedLiterals -Patterns $excludedPatterns)
            }

            foreach ($spUser in $spUsers) {
                # Phase 1: remember the first occurrence of each unique login. Its
                # SharePoint DisplayName and Email feed the JSON fallbacks in phase
                # 3; the AD resolution itself happens in phase 2.
                if (-not $uniqueUsers.Contains($spUser.UserLogin)) {
                    $uniqueUsers[$spUser.UserLogin] = [PSCustomObject]@{
                        UserLogin     = $spUser.UserLogin
                        SPDisplayName = $spUser.DisplayName
                        SPEmail       = $spUser.Email
                    }
                }

                if ([string]::IsNullOrEmpty($spUser.DisplayName) -or $spUser.UserLogin.Contains($spUser.DisplayName)) {
                    Write-Output "Synchronize user: $($spUser.UserLogin) from AD"
                    try {
                        Set-SPUser -Identity $spUser -Web $site.RootWeb -SyncFromAD -Verbose -ErrorAction Stop
                    }
                    catch [Microsoft.SharePoint.SPException] {
                        Write-Warning -Message $_.Exception.Message
                        if ($_.Exception.Message.Contains('Cannot get the full name or e-mail address of user')) {
                            if ($removeUnresolvableUsers) {
                                Write-Output "Remove user: $($spUser.UserLogin) from $($site.RootWeb.Url)"
                                Remove-SPUser -Identity $spUser -Web $site.RootWeb -Verbose -Confirm:$false
                                [void]$tbSPSDeletedUser.Add([SPSDeletedUser]@{
                                        UserLogin = $spUser.UserLogin.Replace($claimPrefix, '')
                                        Url       = $site.RootWeb.Url
                                        Date      = (Get-Date -Format yyyyMMddTHHmmss)
                                        TimeStamp = ((Get-Date).ToFileTime())
                                    })
                            }
                            else {
                                Write-Output "Unresolvable user kept (RemoveUnresolvableUsers disabled): $($spUser.UserLogin) at $($site.RootWeb.Url)"
                            }
                        }
                        else {
                            $catchMessage = @"
SPException syncing user '$($spUser.UserLogin)' from AD
SPWeb: $($site.RootWeb.Url)
Exception: $_
"@
                            Add-SPSUserSyncEvent -Message $catchMessage -Source 'Get-SPSUniqueUsers' -EntryType 'Warning'
                        }
                    }
                    catch {
                        $catchMessage = @"
Unexpected error syncing user '$($spUser.UserLogin)' from AD
SPWeb: $($site.RootWeb.Url)
Exception: $_
"@
                        Add-SPSUserSyncEvent -Message $catchMessage -Source 'Get-SPSUniqueUsers' -EntryType 'Error'
                    }
                }
            }
        }

        # Phase 2: resolve the unique logins against AD. Parallel when enabled,
        # otherwise a sequential loop — both go through ConvertTo-SPSUserRecord so
        # the projected attributes are identical. Either way each unique login is
        # resolved exactly once (previously the same login was looked up once per
        # web it appeared in).
        $uniqueLogins    = @($uniqueUsers.Keys)
        $resolvedByLogin = [System.Collections.Generic.Dictionary[System.String, System.Object]]::new([System.StringComparer]::Ordinal)
        if ($parallelADResolution -and $uniqueLogins.Count -gt 0) {
            Write-Output "Resolving $($uniqueLogins.Count) unique users against AD in parallel..."
            foreach ($resolved in (Resolve-SPSADUserBatch -UserLogin $uniqueLogins -ThrottleLimit $adThrottleLimit)) {
                $resolvedByLogin[$resolved.UserLogin] = $resolved
            }
        }
        else {
            foreach ($login in $uniqueLogins) {
                $adUser = Get-SPSADUser -UserLogin $login
                $resolvedByLogin[$login] = ConvertTo-SPSUserRecord -UserLogin $login -AdUser $adUser
            }
        }

        # Phase 3: build one JSON record per unique user (no SharePoint calls).
        # DisplayName falls back to the SharePoint display name, and the SharePoint
        # email wins over the AD mail, exactly as the sequential version did.
        foreach ($snapshot in $uniqueUsers.Values) {
            $resolved = $resolvedByLogin[$snapshot.UserLogin]

            $recordDisplayName = $resolved.DisplayName
            if ([string]::IsNullOrEmpty($recordDisplayName)) {
                $recordDisplayName = $snapshot.SPDisplayName
            }

            if ([string]::IsNullOrEmpty($snapshot.SPEmail)) {
                $recordEmail = "$($resolved.Email)"
            }
            else {
                $recordEmail = "$($snapshot.SPEmail)"
            }

            [void]$tbSPSiteUsers.Add([SPSiteUser]@{
                    UserLogin   = $snapshot.UserLogin
                    DisplayName = $recordDisplayName
                    FirstName   = $resolved.FirstName
                    LastName    = $resolved.LastName
                    Email       = $recordEmail
                    Location    = $resolved.Location
                    Country     = $resolved.Country
                })
        }

        Write-Output "$spUsersFound users found in all SPSite object"
        Write-Output "$($tbSPSiteUsers.Count) unique users added in PSObject variable"

        # Anti-clobber guard: a zero-user result almost always means a site
        # collection could not be read (wrong account / missing Shell Admin), not a
        # genuinely empty farm. Never overwrite the previous good JSON with an empty
        # snapshot: keep it in place, fail loudly, and leave the success flag $false
        # so the Main region skips the report and the remote copy.
        if ($tbSPSiteUsers.Count -eq 0) {
            $emptyMessage = @"
No users were collected from the farm; the generated snapshot would be empty.
FilterUrl: $FilterUrl
This usually means the account running this script cannot read the site
collections (check Shell Admin / the service account), not that the farm is
empty. The existing JSON file was left untouched and nothing was copied
downstream.
"@
            # -ErrorAction Continue keeps this non-terminating even when the caller
            # sets $ErrorActionPreference = 'Stop': it must not be swallowed by this
            # same try/catch, and the Main region owns the fail-fast Exit 1.
            Write-Error -Message $emptyMessage -ErrorAction Continue
            Add-SPSUserSyncEvent -Message $emptyMessage -Source 'Get-SPSUniqueUsers' -EntryType 'Error'
        }
        else {
            $tbSPSiteUsers | ConvertTo-Json | Set-Content -Path $JsonFilePath -Force -Encoding UTF8
            Write-Output "Saved Unique SPUser in file: $JsonFilePath"
            $script:GetSPSUniqueUsersSucceeded = $true
        }

        if ($tbSPSDeletedUser.Count -ne 0) {
            Write-Output "$($tbSPSDeletedUser.Count) deleted users added in PSObject variable"
            $tbSPSDeletedUser | ConvertTo-Json | Set-Content -Path $DeletedJsonFilePath -Force -Encoding UTF8
            Write-Output "Saved Deleted SPUser in file: $DeletedJsonFilePath"
        }
    }
    catch {
        $errorDetail = $_
        # ACCESS_DENIED while enumerating the site collections is the classic
        # wrong-account / missing-Shell-Admin case (E_ACCESSDENIED 0x80070005). Give
        # an actionable message instead of a raw stack trace.
        $isAccessDenied = ($errorDetail.Exception -is [System.UnauthorizedAccessException]) -or
        ("$errorDetail" -match 'Access is denied|E_ACCESSDENIED|0x80070005|UnauthorizedAccess')
        if ($isAccessDenied) {
            $runAccount = try { ([Security.Principal.WindowsIdentity]::GetCurrent()).Name } catch { $env:USERNAME }
            $catchMessage = @"
Access denied while enumerating the farm site collections in Get-SPSUniqueUsers.
FilterUrl: $FilterUrl
The account running this script ('$runAccount') cannot read every site collection.
Make sure it is a Shell Admin on every content database (Add-SPShellAdmin) and is
the correct SPSyncUserInfoList service account, then re-run.
Exception: $errorDetail
"@
        }
        else {
            $catchMessage = @"
An error occurred during Get-SPSUniqueUsers
FilterUrl: $FilterUrl
Exception: $errorDetail
"@
        }
        # Surface to the console/transcript as well as the Event Log, so an operator
        # watching the run sees the failure immediately instead of an empty screen.
        # -ErrorAction Continue keeps it non-terminating even under a caller's
        # $ErrorActionPreference = 'Stop' (the Main region handles the Exit 1).
        Write-Error -Message $catchMessage -ErrorAction Continue
        Add-SPSUserSyncEvent -Message $catchMessage -Source 'Get-SPSUniqueUsers' -EntryType 'Error'
    }

    Write-Output "Get Unique SPUser - Ended at $(Get-Date)"
    Write-Output '--------------------------------------------------------------'
}
#endregion

#region Main
# ===================================================================================
#
# SPSyncUserInfoList Script - MAIN Region
#
# ===================================================================================
Clear-Host

# Bootstrap: admin check, transcript, banner (version read from the module manifest)
try {
    $ctx = Initialize-SPSScript -ScriptName 'SPSyncUserInfoList' -ScriptRoot $PSScriptRoot
}
catch {
    Write-Error -Message $_.Exception.Message
    Exit
}

# Load settings
try {
    $settings = Get-SPSSyncSetting
}
catch {
    $catchMessage = @"
An error occurred while loading sync-settings.psd1
Exception: $_
"@
    Add-SPSUserSyncEvent -Message $catchMessage -Source 'Get-SPSSyncSetting' -EntryType 'Error'
    Stop-Transcript | Out-Null
    Exit
}

# Rotate old logs
Clear-SPSLogFolder -Path $ctx.LogFolder -Retention $settings.LogRetentionDays

# Load the SharePoint command surface (PSSnapin on 2013/2016/2019,
# SharePointServer module on Subscription Edition)
try {
    $spLoad = Import-SPSSharePointCommand
    Write-Output "SharePoint commands loaded via: $spLoad"
}
catch {
    $catchMessage = @"
An error occurred while loading the SharePoint command surface
Exception: $_
"@
    Add-SPSUserSyncEvent -Message $catchMessage -Source 'Import-SPSSharePointCommand' -EntryType 'Error'
    Stop-Transcript | Out-Null
    Exit
}

# Resolve output paths
$scriptRootPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
if ([string]::IsNullOrEmpty($FilterUrl)) {
    $appCode      = $settings.AppCode
    $pathJsonFile = Join-Path -Path $scriptRootPath -ChildPath 'SPSyncUserInfoListUserList.json'
}
else {
    $appCode      = 'CUSTOM'
    $pathJsonFile = Join-Path -Path $scriptRootPath -ChildPath 'SPSyncUserInfoListUserList-CUSTOM.json'
}
$pathUserDeletedFile = Join-Path -Path $ctx.LogFolder -ChildPath ('SPSyncUserDeletedList' + (Get-Date -Format yyyyMMdd-HHmm) + '.json')

# New 1.1.0 settings with backward-compatible defaults (older sync-settings.psd1 may omit them)
$historyRetention = if ($null -ne $settings.JsonHistoryRetentionDays) { $settings.JsonHistoryRetentionDays } else { 90 }
$dropThreshold    = if ($null -ne $settings.JsonDropThresholdPercent) { $settings.JsonDropThresholdPercent } else { 20 }
$pathHistoryFolder = Join-Path -Path $ctx.LogFolder -ChildPath 'history'

# Archive the previous snapshot before it is overwritten, so we keep a history and
# can detect an abnormal drop in the user count after regeneration.
$previousSnapshot = Backup-SPSJsonFile -Path $pathJsonFile -HistoryFolder $pathHistoryFolder
if ($null -ne $previousSnapshot) {
    Write-Output "Previous snapshot archived to: $previousSnapshot"
}

# Generate the JSON
if ([string]::IsNullOrEmpty($FilterUrl)) {
    Get-SPSUniqueUsers -Settings $settings -JsonFilePath $pathJsonFile -DeletedJsonFilePath $pathUserDeletedFile
}
else {
    Get-SPSUniqueUsers -FilterUrl $FilterUrl -Settings $settings -JsonFilePath $pathJsonFile -DeletedJsonFilePath $pathUserDeletedFile
}

# Guard: stop here when the snapshot was not produced (for example the running
# account cannot enumerate the site collections). Running the compare, report and
# copy steps against a missing snapshot only emits confusing secondary errors, and
# copying the previous file would push stale data to the User Profile farm. Fail
# loudly and skip the rest.
if (-not $script:GetSPSUniqueUsersSucceeded) {
    $failMessage = @"
User snapshot was NOT generated for AppCode '$appCode'.
The most common cause is that the account running this script cannot enumerate the
farm site collections (ACCESS_DENIED). Make sure it is a Shell Admin on every
content database (Add-SPShellAdmin) and is the correct SPSyncUserInfoList service
account, then re-run. See the error above and the Windows Event Log 'SPSUserSync'
for details. The HTML report and the remote copy were skipped.
"@
    Write-Error -Message $failMessage -ErrorAction Continue
    Add-SPSUserSyncEvent -Message $failMessage -Source 'SPSyncUserInfoList' -EntryType 'Error'

    Write-Output '-----------------------------------------------'
    Write-Output '| Automated Script - Configuration SPSyncUserInfoList (FAILED)'
    Write-Output "| Started on       - $($ctx.DateStarted) |"
    Write-Output "| Completed on     - $(Get-Date) |"
    Write-Output '-----------------------------------------------'
    Stop-Transcript | Out-Null
    Exit 1
}

# Compare the fresh snapshot against the previous one and warn on an abnormal drop
if ($null -ne $previousSnapshot) {
    $comparison = Compare-SPSJsonSnapshots -CurrentPath $pathJsonFile -PreviousPath $previousSnapshot -DropThresholdPercent $dropThreshold
    Write-Output "Snapshot comparison: previous=$($comparison.PreviousCount) current=$($comparison.CurrentCount) delta=$($comparison.Delta) drop=$($comparison.DropPercent)%"
    if ($comparison.IsAnomalous) {
        $warnMessage = @"
Abnormal drop detected in the generated user snapshot.
Previous count: $($comparison.PreviousCount)
Current count: $($comparison.CurrentCount)
Drop: $($comparison.DropPercent)% (threshold: $($comparison.ThresholdPercent)%)
Previous snapshot: $previousSnapshot
Current snapshot: $pathJsonFile
Review before SPSyncUserProfile.ps1 consumes this file.
"@
        Add-SPSUserSyncEvent -Message $warnMessage -Source 'Compare-SPSJsonSnapshots' -EntryType 'Warning'
    }
}

# Rotate archived snapshots in the history folder
Clear-SPSLogFolder -Path $pathHistoryFolder -Retention $historyRetention -Extension '*.json'

# Generate the HTML report
$generateHtml = if ($null -ne $settings.GenerateHtmlReport) { $settings.GenerateHtmlReport } else { $true }
if ($generateHtml) {
    try {
        $reportFile = Join-Path -Path $ctx.LogFolder -ChildPath ('SPSyncUserInfoListReport-' + (Get-Date -Format yyyyMMdd-HHmm) + '.html')
        $null = Export-SPSUserReport -InputFile $pathJsonFile -ReportType 'UserInfoList' -OutputFile $reportFile `
            -EnvName $settings.EnvName -AppCode $appCode -ClaimPrefix $settings.ClaimPrefix -Version $ctx.Version
        Write-Output "HTML report written to: $reportFile"
        Clear-SPSLogFolder -Path $ctx.LogFolder -Retention $settings.LogRetentionDays -Extension '*.html'
    }
    catch {
        $catchMessage = @"
Failed to generate the HTML report
Source: $pathJsonFile
Exception: $_
"@
        Add-SPSUserSyncEvent -Message $catchMessage -Source 'Export-SPSUserReport' -EntryType 'Warning'
    }
}

# Copy JSON to the master VM of the User Profile Service farm
try {
    $remotePathJson = $settings.RemoteJsonPath -f $settings.MasterVM, $appCode
    Write-Output "Copy the file: $pathJsonFile"
    Write-Output "To the destination file: $remotePathJson"
    Copy-Item -Path $pathJsonFile -Destination $remotePathJson -Force -ErrorAction Stop
}
catch {
    $catchMessage = @"
An error occurred while copying JSON to master VM
Source: $pathJsonFile
Destination: $remotePathJson
Exception: $_
"@
    Add-SPSUserSyncEvent -Message $catchMessage -Source 'Copy-Item' -EntryType 'Error'
}

Trap { Continue }
$DateEnded = Get-Date
Write-Output '-----------------------------------------------'
Write-Output '| Automated Script - Configuration SPSyncUserInfoList'
Write-Output "| Started on       - $($ctx.DateStarted) |"
Write-Output "| Completed on     - $DateEnded |"
Write-Output '-----------------------------------------------'
Stop-Transcript
Exit
#endregion
