# =====================================================================================
# SPSUserSync - Sync settings (example)
#
# Copy this file to sync-settings.psd1 and edit the values for your target
# environment. The real sync-settings.psd1 is gitignored to keep internal
# infrastructure details (server names, internal URLs) out of version control.
#
# EnvName  : free-form environment identifier (e.g. PROD, PPRD, DEV)
# AppCode  : free-form application code, used in JSON file names
#
# RemoteJsonPath placeholders:
#   {0} = MasterVM
#   {1} = AppCode
# =====================================================================================
@{
    EnvName = 'PROD'
    AppCode = 'CONTOSO'

    ClaimPrefix = 'i:0#.w|'

    ExcludedUserLogins = @(
        'SHAREPOINT\system'
        'c:0(.s|true'
        'c:0!.s|windows'
    )

    ExcludedUserLoginPatterns = @(
        'c:0+.w|s-1-5-21-*'         # Local Windows accounts (SID-based claim)
        '*EXAMPLEDOMAIN\*'          # Replace with any AD domain name to exclude entirely
    )
    # In addition to the entries above, SPSUserSync always excludes the classic
    # system principals 'NT AUTHORITY\*', 'BUILTIN\*' and 'SHAREPOINT\*'. These are
    # built in (never read into the JSON nor removed), so you only need to list
    # your own domains/accounts here.

    # RemoveUnresolvableUsers : when $true, a user whose AD sync fails with
    #   "Cannot get the full name or e-mail address" is removed from the web
    #   (Remove-SPUser). When $false (default), the user is reported and left in
    #   place and only the benign Set-SPUser -SyncFromAD refresh runs. Leave $false
    #   unless you specifically want SPSUserSync to prune unresolvable accounts
    #   from the farm.
    RemoveUnresolvableUsers = $false

    # SkipDisabledUsers : when $true, SPSyncUserProfile.ps1 does NOT create/update a
    #   User Profile for an account flagged Disabled in the snapshot (SPSyncUserInfoList
    #   records this from the AD userAccountControl attribute). Disabled accounts are
    #   written to the Not-Added report with reason 'DISABLED' instead. Use this when
    #   departed employees are kept as *disabled* AD accounts (and retained in the
    #   SharePoint User Information List for permission history) and you do not want
    #   profiles created for them. When $false (default), behaviour is unchanged: a
    #   disabled-but-resolvable account still gets a profile. Relies only on the
    #   universal userAccountControl bit, so it works for any directory. Note: it acts
    #   on the AccountStatus written by SPSyncUserInfoList 1.3.3+, so regenerate the
    #   JSON snapshot after upgrading for this flag to take effect.
    SkipDisabledUsers = $false

    MasterVM       = 'YOUR-MASTER-SERVER'
    MySiteUrl      = 'https://mysite.contoso.com'
    RemoteJsonPath = '\\{0}\d$\Tools\SCRIPTS\JOBS\SPSyncUserProfile\SPSyncUserInfoListUserList-{1}.json'

    LogRetentionDays    = 90
    UpaLogRetentionDays = 30

    # JSON snapshot history and reporting (added in 1.1.0)
    # JsonHistoryRetentionDays : days of timestamped JSON snapshots kept under Logs\history
    # JsonDropThresholdPercent : a snapshot losing at least this % of records vs the
    #                            previous one raises a Warning in the SPSUserSync Event Log
    # GenerateHtmlReport       : when $true, each run also writes a self-contained HTML report
    JsonHistoryRetentionDays = 90
    JsonDropThresholdPercent = 20
    GenerateHtmlReport       = $true

    # Parallel AD resolution (added in 1.3.0)
    # ParallelADResolution : when $true, SPSyncUserInfoList resolves the unique
    #                        user logins against AD concurrently (RunspacePool).
    #                        Worth it on large multi-forest farms where the LDAP
    #                        round-trip dominates; leave $false on small farms,
    #                        where the per-runspace module-import overhead is not
    #                        amortized. The resulting JSON is identical either way.
    # MaxParallelADQueries : max concurrent AD lookups. 0 (or absent) lets the
    #                        toolkit pick a value from the CPU count
    #                        (Get-SPSThrottleLimit: cap 10 on 8+ logical CPUs).
    ParallelADResolution = $false
    MaxParallelADQueries = 0
}
