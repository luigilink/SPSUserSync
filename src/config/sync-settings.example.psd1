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

    MasterVM       = 'YOUR-MASTER-SERVER'
    MySiteUrl      = 'https://mysite.contoso.com'
    RemoteJsonPath = '\\{0}\d$\Tools\SCRIPTS\JOBS\SPSyncUserProfile\SPSyncUserInfoListUserList-{1}.json'

    LogRetentionDays    = 90
    UpaLogRetentionDays = 30
}
