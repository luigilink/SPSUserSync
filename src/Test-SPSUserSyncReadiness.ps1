<#
    .SYNOPSIS
    Pre-flight readiness check for an SPSUserSync deployment on a SharePoint server.

    .DESCRIPTION
    Test-SPSUserSyncReadiness.ps1 validates that a server is ready to run
    SPSyncUserInfoList.ps1 / SPSyncUserProfile.ps1 BEFORE the first real run, so
    configuration or environment mistakes surface early instead of mid-job.

    All checks are read-only and non-destructive. The script never writes to the
    User Profile Service Application, never creates the Event Log, and never
    modifies any SPUser. It only inspects:

    - Administrator rights and PowerShell version (Windows PowerShell 5.1).
    - That the SPSUserSync.Common module imports and exports its functions.
    - That the three config files exist, parse, and carry the required keys.
    - That every 'Credential' AD domain has a matching secret whose DPAPI
      SecureString decrypts under the current account and machine.
    - That each AD domain's LDAP path builds a DirectorySearcher, and
      (unless -SkipNetwork) that an LDAP bind succeeds.
    - That the SharePoint snap-in is available and the farm is reachable
      (unless -SkipSharePoint).
    - That the current account can enumerate every site collection - the exact
      permission SPSyncUserInfoList.ps1 needs. This catches a wrong service
      account or a missing Shell Admin on a content database before the first run
      (unless -SkipSharePoint).
    - That the current account can read the User Profile Service Application
      (a non-destructive profile-count read; UPA master only, unless
      -SkipNetwork).
    - That the custom 'SPSUserSync' Event Log can be used.
    - That the MySite host and the master VM share are reachable
      (unless -SkipNetwork).

    Exit code is 0 when no check failed, 1 otherwise — handy as a gate before
    enabling the scheduled tasks.

    .PARAMETER ConfigPath
    Folder containing ad-domains.psd1, secrets.psd1 and sync-settings.psd1.
    Defaults to the 'config' folder next to this script.

    .PARAMETER SkipNetwork
    Skip the LDAP bind, MySite and master-VM share reachability checks. Useful
    for a quick syntax/config-only pass from a workstation.

    .PARAMETER SkipSharePoint
    Skip the SharePoint snap-in and Get-SPFarm checks. Useful when validating
    the configuration off a SharePoint server.

    .PARAMETER SampleAccount
    Optional sAMAccountName of a real account to resolve in every AD domain
    during the read test, instead of the default "any user" probe. Handy to
    confirm a specific known user (and its attributes) is visible.

    .EXAMPLE
    .\Test-SPSUserSyncReadiness.ps1

    .EXAMPLE
    .\Test-SPSUserSyncReadiness.ps1 -SkipSharePoint -SkipNetwork

    .EXAMPLE
    .\Test-SPSUserSyncReadiness.ps1 -SampleAccount 'alicekeller'

    .NOTES
    FileName:   Test-SPSUserSyncReadiness.ps1
    Author:     Jean-Cyril DROUHIN
    Project:    https://github.com/luigilink/SPSUserSync
#>

#Requires -Version 5.1

[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingWriteHost', '',
    Justification = 'This is an interactive, operator-facing readiness tool whose purpose is colored console output. Write-Host with -ForegroundColor is intentional here, matching the SPSConfigKit Invoke-ConfigDataTest.ps1 pattern.')]
[CmdletBinding()]
param
(
    [Parameter()]
    [System.String]
    $ConfigPath,

    [Parameter()]
    [switch]
    $SkipNetwork,

    [Parameter()]
    [switch]
    $SkipSharePoint,

    [Parameter()]
    [System.String]
    $SampleAccount
)

$script:results = New-Object System.Collections.Generic.List[object]

function Add-CheckResult {
    param
    (
        [Parameter(Mandatory = $true)] [System.String] $Section,
        [Parameter(Mandatory = $true)] [System.String] $Name,
        [Parameter(Mandatory = $true)] [ValidateSet('PASS', 'FAIL', 'WARN', 'SKIP')] [System.String] $Status,
        [Parameter()] [System.String] $Detail = ''
    )

    $script:results.Add([PSCustomObject]@{
            Section = $Section
            Name    = $Name
            Status  = $Status
            Detail  = $Detail
        })

    switch ($Status) {
        'PASS' { $color = 'Green';  $glyph = '[ OK ]' }
        'FAIL' { $color = 'Red';    $glyph = '[FAIL]' }
        'WARN' { $color = 'Yellow'; $glyph = '[WARN]' }
        'SKIP' { $color = 'DarkGray'; $glyph = '[SKIP]' }
    }
    $line = '{0}  {1}' -f $glyph, $Name
    if (-not [string]::IsNullOrEmpty($Detail)) { $line += " - $Detail" }
    Write-Host $line -ForegroundColor $color
}

function Write-Section {
    param ([System.String] $Title)
    Write-Host ''
    Write-Host "== $Title ==" -ForegroundColor Cyan
}

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' SPSUserSync - Readiness Check' -ForegroundColor Cyan
Write-Host "  Computer : $env:COMPUTERNAME" -ForegroundColor Cyan
Write-Host "  Date     : $(Get-Date -Format 'yyyy-MM-dd HH:mm')" -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# 1. Host prerequisites
# ---------------------------------------------------------------------------
Write-Section 'Host prerequisites'

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')
if ($isAdmin) {
    Add-CheckResult -Section 'Host' -Name 'Administrator rights' -Status 'PASS'
}
else {
    Add-CheckResult -Section 'Host' -Name 'Administrator rights' -Status 'FAIL' -Detail 'Re-run this script as Administrator'
}

$psv = $PSVersionTable.PSVersion
if ($psv.Major -eq 5) {
    Add-CheckResult -Section 'Host' -Name 'PowerShell version' -Status 'PASS' -Detail "$psv"
}
elseif ($psv.Major -ge 7) {
    Add-CheckResult -Section 'Host' -Name 'PowerShell version' -Status 'WARN' -Detail "$psv detected. The SharePoint snap-in requires Windows PowerShell 5.1; run the scripts with powershell.exe, not pwsh."
}
else {
    Add-CheckResult -Section 'Host' -Name 'PowerShell version' -Status 'FAIL' -Detail "$psv is not supported. Windows PowerShell 5.1 is required."
}

# ---------------------------------------------------------------------------
# 2. Module
# ---------------------------------------------------------------------------
Write-Section 'SPSUserSync.Common module'

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Definition
$modulePath = Join-Path -Path $scriptRoot -ChildPath 'Modules\SPSUserSync.Common\SPSUserSync.Common.psd1'
$moduleOk = $false
if (Test-Path -Path $modulePath) {
    try {
        Import-Module -Name $modulePath -Force -ErrorAction Stop
        $moduleOk = $true
        $exported = (Get-Command -Module SPSUserSync.Common).Count
        Add-CheckResult -Section 'Module' -Name 'Module imports' -Status 'PASS' -Detail "$exported functions exported"
        $version = (Get-Module SPSUserSync.Common).Version
        Add-CheckResult -Section 'Module' -Name 'Module version' -Status 'PASS' -Detail "$version"
    }
    catch {
        Add-CheckResult -Section 'Module' -Name 'Module imports' -Status 'FAIL' -Detail $_.Exception.Message
    }
}
else {
    Add-CheckResult -Section 'Module' -Name 'Module present' -Status 'FAIL' -Detail "Not found at $modulePath"
}

# ---------------------------------------------------------------------------
# 3. Configuration files
# ---------------------------------------------------------------------------
Write-Section 'Configuration files'

if ([string]::IsNullOrEmpty($ConfigPath)) {
    $ConfigPath = Join-Path -Path $scriptRoot -ChildPath 'config'
}

$adDomainsPath   = Join-Path -Path $ConfigPath -ChildPath 'ad-domains.psd1'
$secretsPath     = Join-Path -Path $ConfigPath -ChildPath 'secrets.psd1'
$syncSettingsPath = Join-Path -Path $ConfigPath -ChildPath 'sync-settings.psd1'

$adDomains = $null
$secrets = $null
$settings = $null

foreach ($item in @(
        @{ Label = 'ad-domains.psd1';    Path = $adDomainsPath;    Var = 'adDomains' },
        @{ Label = 'secrets.psd1';       Path = $secretsPath;      Var = 'secrets' },
        @{ Label = 'sync-settings.psd1'; Path = $syncSettingsPath; Var = 'settings' }
    )) {
    if (Test-Path -Path $item.Path) {
        try {
            $data = Import-PowerShellDataFile -Path $item.Path -ErrorAction Stop
            Set-Variable -Name $item.Var -Value $data -Scope Script
            Add-CheckResult -Section 'Config' -Name "$($item.Label) parses" -Status 'PASS'
        }
        catch {
            Add-CheckResult -Section 'Config' -Name "$($item.Label) parses" -Status 'FAIL' -Detail $_.Exception.Message
        }
    }
    else {
        Add-CheckResult -Section 'Config' -Name "$($item.Label) present" -Status 'FAIL' -Detail "Copy $($item.Label -replace '\.psd1$','.example.psd1') and edit it"
    }
}

# Required keys in sync-settings.psd1
if ($null -ne $settings) {
    $requiredKeys = @('EnvName', 'AppCode', 'ClaimPrefix', 'MasterVM', 'MySiteUrl', 'RemoteJsonPath')
    foreach ($key in $requiredKeys) {
        if ($settings.ContainsKey($key) -and -not [string]::IsNullOrEmpty([string]$settings[$key])) {
            Add-CheckResult -Section 'Config' -Name "sync-settings.$key" -Status 'PASS' -Detail "$($settings[$key])"
        }
        else {
            Add-CheckResult -Section 'Config' -Name "sync-settings.$key" -Status 'FAIL' -Detail 'Missing or empty'
        }
    }
    foreach ($optKey in @('JsonHistoryRetentionDays', 'JsonDropThresholdPercent', 'GenerateHtmlReport')) {
        if ($settings.ContainsKey($optKey)) {
            Add-CheckResult -Section 'Config' -Name "sync-settings.$optKey" -Status 'PASS' -Detail "$($settings[$optKey])"
        }
        else {
            Add-CheckResult -Section 'Config' -Name "sync-settings.$optKey" -Status 'WARN' -Detail 'Absent; built-in default will apply (1.1.0+)'
        }
    }
    # RemoveUnresolvableUsers is destructive when enabled: surface it explicitly.
    if ($settings.ContainsKey('RemoveUnresolvableUsers') -and [bool]$settings['RemoveUnresolvableUsers']) {
        Add-CheckResult -Section 'Config' -Name 'sync-settings.RemoveUnresolvableUsers' -Status 'WARN' -Detail 'ENABLED - unresolvable users will be removed from the farm (Remove-SPUser)'
    }
    else {
        Add-CheckResult -Section 'Config' -Name 'sync-settings.RemoveUnresolvableUsers' -Status 'PASS' -Detail 'Disabled (safe default); unresolvable users are reported, not removed'
    }
}

# ---------------------------------------------------------------------------
# 4. Secrets (coverage, structure and DPAPI decryptability)
# ---------------------------------------------------------------------------
Write-Section 'Secrets'

# Determine which secrets are referenced by a Credential-mode domain.
$credentialDomains = @()
if ($null -ne $adDomains -and $adDomains.ContainsKey('Domains')) {
    foreach ($domainKey in $adDomains.Domains.Keys) {
        $entry = $adDomains.Domains[$domainKey]
        if ($entry.AuthMode -eq 'Credential') {
            $credentialDomains += [PSCustomObject]@{ Domain = $domainKey; CredentialKey = $entry.CredentialKey }
        }
    }
}
$referencedKeys = @($credentialDomains | ForEach-Object { $_.CredentialKey } | Sort-Object -Unique)

# Pass A - coverage: every Credential domain must map to a secret entry.
if ($null -eq $adDomains -or -not $adDomains.ContainsKey('Domains')) {
    Add-CheckResult -Section 'Secrets' -Name 'Domain -> secret coverage' -Status 'SKIP' -Detail 'ad-domains.psd1 unavailable'
}
elseif ($credentialDomains.Count -eq 0) {
    Add-CheckResult -Section 'Secrets' -Name 'Credential-mode domains' -Status 'PASS' -Detail 'None declared; no secrets required'
}
else {
    foreach ($cd in $credentialDomains) {
        $name = "Domain '$($cd.Domain)' -> secret '$($cd.CredentialKey)'"
        if ($null -eq $secrets -or -not $secrets.ContainsKey($cd.CredentialKey)) {
            Add-CheckResult -Section 'Secrets' -Name $name -Status 'FAIL' -Detail 'Referenced key not found in secrets.psd1'
        }
        else {
            Add-CheckResult -Section 'Secrets' -Name $name -Status 'PASS' -Detail 'Mapped'
        }
    }
}

# Pass B - validity: every entry actually present in secrets.psd1 is structurally
# sound and its password decrypts under this account/machine. Orphan entries (not
# referenced by any domain) are surfaced as warnings, not failures.
if ($null -ne $secrets) {
    if ($secrets.Keys.Count -eq 0) {
        Add-CheckResult -Section 'Secrets' -Name 'secrets.psd1 entries' -Status 'PASS' -Detail 'File is empty (no credentials stored)'
    }
    foreach ($key in $secrets.Keys) {
        $secret = $secrets[$key]
        $isReferenced = $referencedKeys -contains $key
        $label = if ($isReferenced) { "Secret '$key'" } else { "Secret '$key' (orphan)" }

        if ([string]::IsNullOrEmpty($secret.Username)) {
            Add-CheckResult -Section 'Secrets' -Name $label -Status 'FAIL' -Detail 'Username is empty'
            continue
        }
        if ([string]::IsNullOrEmpty($secret.PasswordSecure) -or $secret.PasswordSecure -like 'PASTE-*') {
            if ($isReferenced) {
                Add-CheckResult -Section 'Secrets' -Name $label -Status 'FAIL' -Detail 'PasswordSecure is still a placeholder'
            }
            else {
                Add-CheckResult -Section 'Secrets' -Name $label -Status 'WARN' -Detail 'PasswordSecure is a placeholder (orphan entry, not used by any domain)'
            }
            continue
        }
        try {
            $secure = ConvertTo-SecureString -String $secret.PasswordSecure -ErrorAction Stop
            $cred = New-Object System.Management.Automation.PSCredential($secret.Username, $secure)
            $plainLength = $cred.GetNetworkCredential().Password.Length
            if ($plainLength -eq 0) {
                Add-CheckResult -Section 'Secrets' -Name $label -Status 'FAIL' -Detail 'Decrypts to an empty password'
            }
            elseif ($isReferenced) {
                Add-CheckResult -Section 'Secrets' -Name $label -Status 'PASS' -Detail "DPAPI decrypt OK (user: $($secret.Username))"
            }
            else {
                Add-CheckResult -Section 'Secrets' -Name $label -Status 'WARN' -Detail "Valid but not referenced by any domain (user: $($secret.Username))"
            }
        }
        catch {
            Add-CheckResult -Section 'Secrets' -Name $label -Status 'FAIL' -Detail 'SecureString will not decrypt under this account/machine. Regenerate with ConvertFrom-SecureString here.'
        }
    }
}

# ---------------------------------------------------------------------------
# 5. Active Directory connectivity
# ---------------------------------------------------------------------------
Write-Section 'Active Directory'

if ($moduleOk -and $null -ne $adDomains -and $adDomains.ContainsKey('Domains')) {
    foreach ($domainKey in $adDomains.Domains.Keys) {
        $searcher = $null
        try {
            $searcher = Get-SPSADConnection -DomainName $domainKey -AccountName 'spsusersync-readiness-probe' -ConfigPath $ConfigPath -ErrorAction Stop
        }
        catch {
            Add-CheckResult -Section 'AD' -Name "Domain '$domainKey' connection" -Status 'FAIL' -Detail $_.Exception.Message
            continue
        }
        if ($null -eq $searcher) {
            Add-CheckResult -Section 'AD' -Name "Domain '$domainKey' connection" -Status 'FAIL' -Detail 'Get-SPSADConnection returned null (check LDAP path / credential)'
            continue
        }
        if ($SkipNetwork) {
            Add-CheckResult -Section 'AD' -Name "Domain '$domainKey' searcher built" -Status 'PASS' -Detail 'LDAP bind skipped (-SkipNetwork)'
            continue
        }

        $probe = Test-SPSADConnection -DomainName $domainKey -SampleAccount $SampleAccount -ConfigPath $ConfigPath
        if (-not [string]::IsNullOrEmpty($probe.Error)) {
            Add-CheckResult -Section 'AD' -Name "Domain '$domainKey' LDAP bind" -Status 'FAIL' -Detail $probe.Error
            continue
        }
        if (-not $probe.BindSucceeded) {
            Add-CheckResult -Section 'AD' -Name "Domain '$domainKey' LDAP bind" -Status 'FAIL' -Detail 'Bind did not succeed'
            continue
        }
        if (-not $probe.UserFound) {
            Add-CheckResult -Section 'AD' -Name "Domain '$domainKey' read test" -Status 'WARN' -Detail 'Bind OK but no user matched. Check the LdapPath search base (empty OU?) or the sample account.'
            continue
        }

        $who = if (-not [string]::IsNullOrEmpty($probe.FoundAccount)) { $probe.FoundAccount } else { 'a user' }
        Add-CheckResult -Section 'AD' -Name "Domain '$domainKey' LDAP bind + read" -Status 'PASS' -Detail "Resolved $who"
        if ($probe.MissingKeyAttributes.Count -eq 0) {
            Add-CheckResult -Section 'AD' -Name "Domain '$domainKey' attributes" -Status 'PASS' -Detail 'givenName, sn, mail, co, l, displayName all readable'
        }
        else {
            Add-CheckResult -Section 'AD' -Name "Domain '$domainKey' attributes" -Status 'WARN' -Detail "Empty on the sampled user: $($probe.MissingKeyAttributes -join ', ') (fine if expected; mail/sn/givenName drive the profile)"
        }
    }
}
else {
    Add-CheckResult -Section 'AD' -Name 'AD checks' -Status 'SKIP' -Detail 'Module or ad-domains.psd1 unavailable'
}

# ---------------------------------------------------------------------------
# 6. SharePoint
# ---------------------------------------------------------------------------
Write-Section 'SharePoint'

if ($SkipSharePoint) {
    Add-CheckResult -Section 'SharePoint' -Name 'SharePoint checks' -Status 'SKIP' -Detail '-SkipSharePoint'
}
else {
    $spVersion = $null
    if ($moduleOk) {
        $spVersion = Get-SPSInstalledProductVersion
    }

    if ($null -eq $spVersion) {
        Add-CheckResult -Section 'SharePoint' -Name 'SharePoint installed' -Status 'FAIL' -Detail 'Microsoft.SharePoint.dll not found (run this on a SharePoint server, or use -SkipSharePoint)'
    }
    else {
        $build = "$($spVersion.ProductMajorPart).$($spVersion.ProductMinorPart).$($spVersion.ProductBuildPart).$($spVersion.ProductPrivatePart)"
        $edition = if ($spVersion.ProductMajorPart -eq 15) { 'SharePoint 2013' }
        elseif ($spVersion.ProductBuildPart -le 12999) { 'SharePoint 2016/2019' }
        else { 'SharePoint Subscription Edition' }
        Add-CheckResult -Section 'SharePoint' -Name 'SharePoint installed' -Status 'PASS' -Detail "$edition (build $build)"

        try {
            $loadedVia = Import-SPSSharePointCommand
            Add-CheckResult -Section 'SharePoint' -Name 'SharePoint commands load' -Status 'PASS' -Detail "via $loadedVia"
        }
        catch {
            Add-CheckResult -Section 'SharePoint' -Name 'SharePoint commands load' -Status 'FAIL' -Detail $_.Exception.Message
        }

        try {
            $farm = Get-SPFarm -ErrorAction Stop
            Add-CheckResult -Section 'SharePoint' -Name 'Farm access' -Status 'PASS' -Detail "Build $($farm.BuildVersion)"
        }
        catch {
            Add-CheckResult -Section 'SharePoint' -Name 'Farm access' -Status 'FAIL' -Detail 'Get-SPFarm failed (not a farm member, or missing rights)'
        }

        # Site collection enumeration - the permission SPSyncUserInfoList.ps1
        # actually depends on. Get-SPFarm above only proves config-database access;
        # walking every SPSite forces a read of every CONTENT database, which is
        # what throws ACCESS_DENIED (E_ACCESSDENIED 0x80070005) when the running
        # account is not a Shell Admin on each content DB / is the wrong service
        # account. Reproducing it here surfaces that mistake BEFORE the first real
        # run instead of during it. Read-only: only each site Url is read, no web is
        # opened and no user is touched.
        try {
            $allSiteUrls = @(Get-SPSite -Limit All -ErrorAction Stop | Select-Object -ExpandProperty Url)
            $siteCount = $allSiteUrls.Count
            if ($siteCount -eq 0) {
                Add-CheckResult -Section 'SharePoint' -Name 'Site collection enumeration' -Status 'WARN' -Detail 'Get-SPSite -Limit All returned no site collection (unexpected on a populated farm)'
            }
            else {
                Add-CheckResult -Section 'SharePoint' -Name 'Site collection enumeration' -Status 'PASS' -Detail "Can enumerate $siteCount site collection(s)"
            }
        }
        catch {
            $enumMessage = $_.Exception.Message
            if ($null -ne $_.Exception.InnerException) {
                $enumMessage = $_.Exception.InnerException.Message
            }
            if ($enumMessage -match 'Access is denied|denied|E_ACCESSDENIED|0x80070005|UnauthorizedAccess') {
                $enumAccount = try { ([Security.Principal.WindowsIdentity]::GetCurrent()).Name } catch { $env:USERNAME }
                Add-CheckResult -Section 'SharePoint' -Name 'Site collection enumeration' -Status 'FAIL' -Detail "Access denied enumerating site collections. The account '$enumAccount' must be a Shell Admin on every content database (Add-SPShellAdmin) and the correct SPSyncUserInfoList service account. This is the exact permission SPSyncUserInfoList.ps1 needs."
            }
            else {
                Add-CheckResult -Section 'SharePoint' -Name 'Site collection enumeration' -Status 'FAIL' -Detail "Get-SPSite -Limit All failed: $enumMessage"
            }
        }

        if (-not $SkipNetwork -and $null -ne $settings -and -not [string]::IsNullOrEmpty($settings.MySiteUrl)) {
            $mySiteObject = $null
            try {
                $mySiteObject = Get-SPSite $settings.MySiteUrl -ErrorAction Stop
                Add-CheckResult -Section 'SharePoint' -Name 'MySite host reachable' -Status 'PASS' -Detail $mySiteObject.Url
            }
            catch {
                Add-CheckResult -Section 'SharePoint' -Name 'MySite host reachable' -Status 'WARN' -Detail "Could not open $($settings.MySiteUrl) (only needed on the UPA master server)"
            }

            # Non-destructive UPA probe (UPA master only): prove the current
            # account can READ the User Profile Service Application. This is the
            # permission whose absence makes SPSyncUserProfile.ps1 fail with
            # 'ProfileDBCacheServiceClient.GetUserData threw exception: Access is
            # denied.' We only read the profile count; no profile is ever
            # created, updated or deleted.
            if ($null -ne $mySiteObject) {
                try {
                    $upaContext = Get-SPServiceContext -Site $mySiteObject -ErrorAction Stop
                    $upaManager = New-Object -TypeName Microsoft.Office.Server.UserProfiles.UserProfileManager($upaContext)
                    $profileCount = $upaManager.Count
                    Add-CheckResult -Section 'SharePoint' -Name 'User Profile Service access' -Status 'PASS' -Detail "Can read the UPA ($profileCount profiles)"
                }
                catch {
                    $upaMessage = $_.Exception.Message
                    if ($null -ne $_.Exception.InnerException) {
                        $upaMessage = $_.Exception.InnerException.Message
                    }
                    if ($upaMessage -match 'Access is denied') {
                        Add-CheckResult -Section 'SharePoint' -Name 'User Profile Service access' -Status 'WARN' -Detail "Access denied reading the UPA. The account needs Manage Profiles on the User Profile Service Application (or the farm account). Required only on the UPA master server."
                    }
                    else {
                        Add-CheckResult -Section 'SharePoint' -Name 'User Profile Service access' -Status 'WARN' -Detail "Could not read the UPA: $upaMessage (only needed on the UPA master server)"
                    }
                }
            }
        }
    }
}

# ---------------------------------------------------------------------------
# 7. Event Log
# ---------------------------------------------------------------------------
Write-Section 'Event Log'

try {
    if ([System.Diagnostics.EventLog]::Exists('SPSUserSync')) {
        Add-CheckResult -Section 'EventLog' -Name "Custom 'SPSUserSync' log" -Status 'PASS' -Detail 'Already exists'
    }
    elseif ($isAdmin) {
        Add-CheckResult -Section 'EventLog' -Name "Custom 'SPSUserSync' log" -Status 'PASS' -Detail 'Does not exist yet; will be created on first run (admin confirmed)'
    }
    else {
        Add-CheckResult -Section 'EventLog' -Name "Custom 'SPSUserSync' log" -Status 'FAIL' -Detail 'Does not exist and current user is not admin to create it'
    }
}
catch {
    Add-CheckResult -Section 'EventLog' -Name "Custom 'SPSUserSync' log" -Status 'WARN' -Detail $_.Exception.Message
}

# ---------------------------------------------------------------------------
# 8. Master VM share (SPSyncUserInfoList only)
# ---------------------------------------------------------------------------
Write-Section 'Master VM share'

if ($SkipNetwork) {
    Add-CheckResult -Section 'Share' -Name 'Master VM share' -Status 'SKIP' -Detail '-SkipNetwork'
}
elseif ($null -ne $settings -and -not [string]::IsNullOrEmpty($settings.RemoteJsonPath) -and -not [string]::IsNullOrEmpty($settings.MasterVM)) {
    try {
        $remotePath = $settings.RemoteJsonPath -f $settings.MasterVM, $settings.AppCode
        $remoteDir = Split-Path -Path $remotePath -Parent
        if (Test-Path -Path $remoteDir -ErrorAction Stop) {
            Add-CheckResult -Section 'Share' -Name 'Remote JSON folder reachable' -Status 'PASS' -Detail $remoteDir
        }
        else {
            Add-CheckResult -Section 'Share' -Name 'Remote JSON folder reachable' -Status 'WARN' -Detail "$remoteDir not reachable (only needed on application farms)"
        }
    }
    catch {
        Add-CheckResult -Section 'Share' -Name 'Remote JSON folder reachable' -Status 'WARN' -Detail $_.Exception.Message
    }
}
else {
    Add-CheckResult -Section 'Share' -Name 'Master VM share' -Status 'SKIP' -Detail 'RemoteJsonPath / MasterVM not configured'
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
$pass = @($script:results | Where-Object Status -eq 'PASS').Count
$fail = @($script:results | Where-Object Status -eq 'FAIL').Count
$warn = @($script:results | Where-Object Status -eq 'WARN').Count
$skip = @($script:results | Where-Object Status -eq 'SKIP').Count

Write-Host ''
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ' Summary' -ForegroundColor Cyan
Write-Host '============================================================' -ForegroundColor Cyan
Write-Host ("  PASS : {0}" -f $pass) -ForegroundColor Green
Write-Host ("  WARN : {0}" -f $warn) -ForegroundColor Yellow
Write-Host ("  FAIL : {0}" -f $fail) -ForegroundColor Red
Write-Host ("  SKIP : {0}" -f $skip) -ForegroundColor DarkGray
Write-Host ''

if ($fail -gt 0) {
    Write-Host "Readiness check FAILED: resolve the $fail failed item(s) above before running SPSUserSync." -ForegroundColor Red
    exit 1
}
elseif ($warn -gt 0) {
    Write-Host "Readiness check passed with warnings. Review the $warn warning(s); they are usually role-specific (application farm vs UPA master)." -ForegroundColor Yellow
    exit 0
}
else {
    Write-Host 'Readiness check PASSED. This server is ready to run SPSUserSync.' -ForegroundColor Green
    exit 0
}
