function Resolve-SPSADUserBatch {
    <#
        .SYNOPSIS
        Resolves a batch of SharePoint user logins against Active Directory in
        parallel, using a RunspacePool (Windows PowerShell 5.1 compatible).

        .DESCRIPTION
        SPSyncUserInfoList.ps1 resolves every SharePoint site user against AD one
        at a time. On large multi-forest farms the per-user LDAP round-trip is the
        dominant cost, and those lookups are independent and side-effect free, so
        they parallelize well.

        Resolve-SPSADUserBatch takes a list of *unique* user logins (the caller
        deduplicates them first, in the SharePoint thread, because SPSite/SPWeb
        objects are not thread-safe), resolves them concurrently through a
        RunspacePool, and returns one result object per input login with the AD
        attributes SPSUserSync relies on (DisplayName, FirstName, LastName, Email,
        Country, Location) plus Resolved/Error. When a lookup fails because of a
        configuration or secret problem (Get-SPSADUser throws 'SPSADConfigError',
        e.g. an undecodable secrets.psd1 entry), the result also carries
        ConfigError = $true so the caller can fail the whole run loudly instead of
        shipping a JSON with an empty-name forest.

        Only the AD resolution runs in parallel. Reading SharePoint users and
        writing them back (Set-SPUser / Remove-SPUser) stays sequential in the
        caller, on the SharePoint thread.

        Windows PowerShell 5.1 has no ForEach-Object -Parallel, so this uses a
        RunspacePool directly. Each runspace imports the SPSUserSync.Common module
        (via the InitialSessionState) so Get-SPSADUser is available inside the
        worker scriptblock.

        .PARAMETER UserLogin
        The unique SharePoint user logins to resolve (claim or DOMAIN\user form).
        An empty array is allowed and yields an empty result list.

        .PARAMETER ConfigPath
        Optional override for the folder containing ad-domains.psd1 and
        secrets.psd1, forwarded to Get-SPSADUser inside each runspace.

        .PARAMETER ThrottleLimit
        Maximum number of concurrent runspaces. Defaults to Get-SPSThrottleLimit
        when 0 or omitted.

        .PARAMETER ModulePath
        Path to the SPSUserSync.Common module manifest to import into each
        runspace. Defaults to the manifest this function was loaded from, so the
        worker scriptblock can call Get-SPSADUser. Ignored when -ResolveScript is
        self-contained (e.g. in tests).

        .PARAMETER ResolveScript
        Advanced/testing hook. A scriptblock with the signature
        param($UserLogin, $ConfigPath) that returns one result object for a login.
        Defaults to a block that calls Get-SPSADUser and extracts the AD
        attributes. Tests inject a self-contained block to validate the parallel
        plumbing without a live directory.

        .OUTPUTS
        System.Collections.Generic.List[System.Management.Automation.PSObject]
        One object per input login: UserLogin, DisplayName, FirstName, LastName,
        Email, Country, Location, Resolved, Enabled, AccountStatus, Error.

        .EXAMPLE
        $resolved = Resolve-SPSADUserBatch -UserLogin $uniqueLogins
        $byLogin  = @{}
        foreach ($r in $resolved) { $byLogin[$r.UserLogin] = $r }
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[System.Management.Automation.PSObject]])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.String[]]
        $UserLogin,

        [Parameter()]
        [System.String]
        $ConfigPath,

        [Parameter()]
        [System.Int32]
        $ThrottleLimit = 0,

        [Parameter()]
        [System.String]
        $ModulePath,

        [Parameter()]
        [System.Management.Automation.ScriptBlock]
        $ResolveScript
    )

    $results = [System.Collections.Generic.List[System.Management.Automation.PSObject]]::new()
    if ($null -eq $UserLogin -or $UserLogin.Count -eq 0) {
        return , $results
    }

    if ($ThrottleLimit -le 0) {
        $ThrottleLimit = Get-SPSThrottleLimit
    }

    # Default worker: resolve one login via Get-SPSADUser and project it through
    # ConvertTo-SPSUserRecord, the same helper the sequential path uses, so the
    # JSON is byte-for-byte identical whether resolution runs in parallel or not.
    if ($null -eq $ResolveScript) {
        $ResolveScript = {
            param ($UserLogin, $ConfigPath)

            try {
                $lookupParams = @{ UserLogin = $UserLogin }
                if (-not [string]::IsNullOrEmpty($ConfigPath)) {
                    $lookupParams['ConfigPath'] = $ConfigPath
                }
                $adUser = Get-SPSADUser @lookupParams
                ConvertTo-SPSUserRecord -UserLogin $UserLogin -AdUser $adUser
            }
            catch {
                [PSCustomObject]@{
                    UserLogin     = $UserLogin
                    DisplayName   = $null
                    FirstName     = $null
                    LastName      = $null
                    Email         = $null
                    Country       = $null
                    Location      = $null
                    Resolved      = $false
                    Enabled       = $false
                    AccountStatus = 'NotFound'
                    Error         = $_.Exception.Message
                    ConfigError   = ($_.FullyQualifiedErrorId -like 'SPSADConfigError*')
                }
            }
        }

        # Only the default worker needs the module imported in each runspace.
        if ([string]::IsNullOrEmpty($ModulePath)) {
            $ModulePath = $MyInvocation.MyCommand.Module.Path
        }
    }

    $pool = $null
    $jobs = [System.Collections.Generic.List[object]]::new()
    try {
        $initialState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        if (-not [string]::IsNullOrEmpty($ModulePath)) {
            $initialState.ImportPSModule($ModulePath)
        }

        $pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $ThrottleLimit, $initialState, $Host)
        $pool.Open()

        foreach ($login in $UserLogin) {
            $worker = [System.Management.Automation.PowerShell]::Create()
            $null = $worker.AddScript($ResolveScript)
            $null = $worker.AddParameter('UserLogin', $login)
            $null = $worker.AddParameter('ConfigPath', $ConfigPath)
            $worker.RunspacePool = $pool
            $jobs.Add([PSCustomObject]@{
                    Login  = $login
                    Pipe   = $worker
                    Handle = $worker.BeginInvoke()
                })
        }

        foreach ($job in $jobs) {
            try {
                $output = $job.Pipe.EndInvoke($job.Handle)
                foreach ($item in $output) {
                    $results.Add($item)
                }
            }
            catch {
                $results.Add([PSCustomObject]@{
                        UserLogin     = $job.Login
                        DisplayName   = $null
                        FirstName     = $null
                        LastName      = $null
                        Email         = $null
                        Country       = $null
                        Location      = $null
                        Resolved      = $false
                        Enabled       = $false
                        AccountStatus = 'NotFound'
                        Error         = $_.Exception.Message
                        ConfigError   = ($_.FullyQualifiedErrorId -like 'SPSADConfigError*')
                    })
            }
            finally {
                $job.Pipe.Dispose()
            }
        }
    }
    finally {
        if ($null -ne $pool) {
            $pool.Close()
            $pool.Dispose()
        }
    }

    return , $results
}
