# Change log for SPSUserSync

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- README.md
  - Add code_of_conduct.md badge
- Add CODE_OF_CONDUCT.md file
- Add Issue Templates files:
  - 1_bug_report.yml
  - 2_feature_request.yml
  - 3_documentation_request.yml
  - 4_improvement_request.yml
  - config.yml
- Add RELEASE-NOTES.md file
- Add CHANGELOG.md file
- Add CONTRIBUTING.md file
- Add SECURITY.md file
- Wiki documentation under `wiki/` (rendered by the existing `wiki.yml` workflow):
  - `wiki/Home.md` — landing page, project overview, when to use SPSUserSync, architecture diagram
  - `wiki/Getting-Started.md` — prerequisites, installation, first-time configuration, first run, verification
  - `wiki/Configuration.md` — detailed reference for `ad-domains.psd1`, `secrets.psd1`, `sync-settings.psd1`
  - `wiki/Usage.md` — running and scheduling both scripts, Event Log filters, troubleshooting

### Changed

- .gitignore
  - Add patterns for runtime logs (`**/Logs/`, `*_errlog.xml`)
  - Add patterns for local configuration files and secrets (`config/credentials.psd1`, `config/ad-domains.psd1`, `config/*.local.psd1`)
  - Add patterns for JetBrains IDE (`.idea/`)
  - Add patterns for Pester test artifacts
- .github/ISSUE_TEMPLATE/1_bug_report.yml
  - Align version dropdown with current project versions (1.0.x)
  - Align PowerShell version options with supported runtimes (5.1, 7.x)
- README.md
  - Add Requirements section (SharePoint Server 2016/2019/SE, PowerShell 5.1, Farm Admin, AD reachability, farm property bags)
- CODE_OF_CONDUCT.md
  - Set the enforcement contact to the project maintainer's GitHub profile (@luigilink)
- README.md
  - Remove obsolete reference to farm property bags `APP_CODE` and `ENV_NAME`. These values are now read from `config/sync-settings.psd1`.

### Added

- Configuration scaffolding under `src/config/`:
  - `ad-domains.example.psd1` — Active Directory domains and authentication mode
  - `secrets.example.psd1` — SecureString DPAPI-encrypted credentials per domain
  - `sync-settings.example.psd1` — environment-specific settings (EnvName, AppCode, MySite URL, master VM, exclusion patterns, log retention)
- PowerShell module `src/Modules/SPSUserSync.Common/`:
  - Manifest `SPSUserSync.Common.psd1` (PowerShell 5.1)
  - Loader `SPSUserSync.Common.psm1` (dot-sources `Public/*.ps1` and `Private/*.ps1`)
  - `Public/Add-SPSUserSyncEvent.ps1` — writes events to a dedicated `SPSUserSync` Windows Event Log
  - `Public/Clear-SPSLogFolder.ps1` — rotates old log files based on a retention window
  - `Public/Get-SPSADConnection.ps1` — builds a DirectorySearcher pre-configured for a domain (lazy loads ad-domains.psd1 and secrets.psd1)
  - `Public/Get-SPSADUser.ps1` — resolves a SharePoint claims login to the matching AD entry
  - `Public/Test-SPSADUser.ps1` — boolean wrapper around Get-SPSADUser
  - `Public/Get-SPSSyncSetting.ps1` — loads sync-settings.psd1 with caching
  - `Public/Initialize-SPSScript.ps1` — common bootstrap: admin check, transcript, banner, returns a PSCustomObject with LogFolder/LogFile/CurrentUser/Version/DateStarted/ServerTarget
  - `Private/ConvertFrom-SPSUserLogin.ps1` — parses claim/DOMAIN\\user logins
  - `Private/Get-SPSConfigRoot.ps1` — resolves the default config folder location
  - `Private/Get-SPSADDomainConfig.ps1` — cached loader for ad-domains.psd1
  - `Private/Get-SPSSecret.ps1` — decrypts SecureString DPAPI credentials from secrets.psd1

### Changed

- src/SPSyncUserInfoList.ps1 (refactor, version now read from the module manifest):
  - Consume `SPSUserSync.Common`: drop the duplicated AD switch (19 domains), bind credentials, log helpers, admin check and banner
  - Drop the ENV_NAME/APP_CODE farm property bag lookups (now read from `sync-settings.psd1`)
  - Drop the PPRD/PROD master VM hardcoded switch (now `MasterVM` in settings)
  - Drop the hardcoded user-exclusion list (now `ExcludedUserLogins` / `ExcludedUserLoginPatterns` in settings)
  - Drop the hardcoded claim prefix (now `ClaimPrefix` in settings)
  - Drop the hardcoded `$SPSyncUserInfoListVer` variable: the version is read once from the `SPSUserSync.Common` manifest by `Initialize-SPSScript`
  - Output JSON files in **UTF-8** instead of the previous code-page (fixes accents corruption)
  - Replace `Write-LogException` XML dumps with `Add-SPSUserSyncEvent` Event Log entries
  - Carry over the bug fixes from in-tree 1.0.4 patches: per-iteration reset of AD variables, AD-sourced DisplayName, `Contains("")` guard, claim-only login skip
- src/SPSyncUserProfile.ps1 (refactor, version now read from the module manifest):
  - Consume `SPSUserSync.Common`: drop the duplicated AD switch, log helpers, admin check and banner
  - Drop the ENV_NAME farm property bag lookup and the PPRD/PROD MySite URL switch (now `MySiteUrl` in `sync-settings.psd1`)
  - Drop the hardcoded `$SPSyncUserProfileVer` variable: the version is read from the module manifest
  - Read the input JSON explicitly as UTF-8
  - Use `UpaLogRetentionDays` from settings (defaults to 30 if absent)
  - Replace `Write-LogException` XML dumps with `Add-SPSUserSyncEvent` Event Log entries
- src/Modules/SPSUserSync.Common/Public/Initialize-SPSScript.ps1:
  - `-Version` parameter is now optional; when omitted, the function auto-detects the version from the `SPSUserSync.Common` manifest (single source of truth for the whole repo)
  - Stores the calling script name in the module-scoped `$scriptName` so `Add-SPSUserSyncEvent` can include it in the Event Log header
- src/Modules/SPSUserSync.Common/Public/Add-SPSUserSyncEvent.ps1:
  - Event Log header now includes the SPSUserSync version, calling script name, user and computer name on dedicated lines (filterable in Event Viewer / SCOM)
  - Version falls back to the module manifest when `Initialize-SPSScript` has not run yet (early-error scenarios), avoiding the previous `unknown` placeholder

### Added

- .github/workflows/release.yml — packages `src/` into `SPSUserSync-vX.Y.Z.zip` and publishes a GitHub Release using `RELEASE-NOTES.md` as the body, triggered by pushing a `v*` tag.

### Changed (post-commit polish)

- README.md slimmed down to badges + short description + Quick links. Detailed Requirements / Usage / Configuration content moved to the Wiki for easier maintenance.
- README.md: fix `CODE_OF_CONDUCT.md` badge link (the file is uppercased on disk; the lowercase link would 404 on case-sensitive hosts).
- SECURITY.md: replace the obsolete `APP_CODE` / `ENV_NAME` farm property bag reference with a broader description of the customer-specific values that must never be committed (server hostnames, MySite URLs, real `src/config/*.psd1` values, DPAPI-encrypted SecureString values).
