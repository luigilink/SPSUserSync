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

    Write-Output '--------------------------------------------------------------'
    Write-Output "Get Unique SPUser - Started at $funcStarted"

    try {
        if (-not [string]::IsNullOrEmpty($FilterUrl)) {
            $getSPSites = Get-SPSite -Limit All | Where-Object -FilterScript { $_.Url -like "$FilterUrl" }
        }
        else {
            $getSPSites = Get-SPSite -Limit All -ErrorAction SilentlyContinue
        }

        $excludedLiterals = $Settings.ExcludedUserLogins
        $excludedPatterns = $Settings.ExcludedUserLoginPatterns
        $claimPrefix      = $Settings.ClaimPrefix

        $spUsersFound = 0
        foreach ($site in $getSPSites) {
            $spUsersFound += $site.RootWeb.SiteUsers.Count
            Write-Output "SPWeb Url: $($site.RootWeb.Url)"
            Write-Output "Total SPUsers: $($site.RootWeb.SiteUsers.Count)"

            $spUsers = $site.RootWeb.SiteUsers | Where-Object -FilterScript {
                -not (Test-SPSUserExcluded -UserLogin $_.UserLogin -Literals $excludedLiterals -Patterns $excludedPatterns)
            }

            foreach ($spUser in $spUsers) {
                # Reset per-iteration variables to avoid leakage from the previous user
                $spUserCountry     = $null
                $spUserLocation    = $null
                $spUserFirstName   = $null
                $spUserLastName    = $null
                $spUserMailfromAD  = $null
                $spUserDisplayName = $null

                $adUser = Get-SPSADUser -UserLogin $spUser.UserLogin
                if ($null -ne $adUser) {
                    $spUserCountry     = "$($adUser.Properties['co'])".ToUpper()
                    $spUserLocation    = "$($adUser.Properties['l'])".ToUpper()
                    $spUserFirstName   = "$($adUser.Properties['givenname'])"
                    $spUserLastName    = "$($adUser.Properties['sn'])"
                    $spUserMailfromAD  = "$($adUser.Properties['mail'])"
                    $spUserDisplayName = "$($adUser.Properties['displayname'])"
                    if ([string]::IsNullOrEmpty($spUserDisplayName) -and -not [string]::IsNullOrEmpty($spUserFirstName) -and -not [string]::IsNullOrEmpty($spUserLastName)) {
                        $spUserDisplayName = "$spUserFirstName $spUserLastName"
                    }
                }
                # Fallback to the SharePoint DisplayName when AD did not provide one
                if ([string]::IsNullOrEmpty($spUserDisplayName)) {
                    $spUserDisplayName = $spUser.DisplayName
                }

                if ([string]::IsNullOrEmpty($spUser.Email)) {
                    $spUserEmail = "$spUserMailfromAD"
                }
                else {
                    $spUserEmail = "$($spUser.Email)"
                }

                if ($tbSPSiteUsers.Count -eq 0 -or -not ($tbSPSiteUsers.UserLogin.Contains($spUser.UserLogin))) {
                    [void]$tbSPSiteUsers.Add([SPSiteUser]@{
                            UserLogin   = $spUser.UserLogin
                            DisplayName = $spUserDisplayName
                            FirstName   = $spUserFirstName
                            LastName    = $spUserLastName
                            Email       = $spUserEmail
                            Location    = $spUserLocation
                            Country     = $spUserCountry
                        })
                }

                if ([string]::IsNullOrEmpty($spUser.DisplayName) -or $spUser.UserLogin.Contains($spUser.DisplayName)) {
                    Write-Output "Synchronize user: $($spUser.UserLogin) from AD"
                    try {
                        Set-SPUser -Identity $spUser -Web $site.RootWeb -SyncFromAD -Verbose -ErrorAction Stop
                    }
                    catch [Microsoft.SharePoint.SPException] {
                        Write-Warning -Message $_.Exception.Message
                        if ($_.Exception.Message.Contains('Cannot get the full name or e-mail address of user')) {
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

        Write-Output "$spUsersFound users found in all SPSite object"
        Write-Output "$($tbSPSiteUsers.Count) unique users added in PSObject variable"
        $tbSPSiteUsers | ConvertTo-Json | Set-Content -Path $JsonFilePath -Force -Encoding UTF8
        Write-Output "Saved Unique SPUser in file: $JsonFilePath"

        if ($tbSPSDeletedUser.Count -ne 0) {
            Write-Output "$($tbSPSDeletedUser.Count) deleted users added in PSObject variable"
            $tbSPSDeletedUser | ConvertTo-Json | Set-Content -Path $DeletedJsonFilePath -Force -Encoding UTF8
            Write-Output "Saved Deleted SPUser in file: $DeletedJsonFilePath"
        }
    }
    catch {
        $catchMessage = @"
An error occurred during Get-SPSUniqueUsers
FilterUrl: $FilterUrl
Exception: $_
"@
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
    $ctx = Initialize-SPSScript -ScriptName 'SPSyncUserInfoList'
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

# Generate the JSON
if ([string]::IsNullOrEmpty($FilterUrl)) {
    Get-SPSUniqueUsers -Settings $settings -JsonFilePath $pathJsonFile -DeletedJsonFilePath $pathUserDeletedFile
}
else {
    Get-SPSUniqueUsers -FilterUrl $FilterUrl -Settings $settings -JsonFilePath $pathJsonFile -DeletedJsonFilePath $pathUserDeletedFile
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
