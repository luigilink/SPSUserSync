# Change log for SPSUserSync

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.3.0] - 2026-06-28

### Added

- Optional parallel AD resolution in `SPSyncUserInfoList.ps1` for large multi-forest farms. When `ParallelADResolution = $true` (new setting, default `$false`), the unique user logins are resolved against Active Directory concurrently through a RunspacePool (Windows PowerShell 5.1 compatible, no `ForEach-Object -Parallel` needed), with the degree of parallelism from `MaxParallelADQueries` (0 = auto from the CPU count). Two new public helpers back it: `Resolve-SPSADUserBatch` (the RunspacePool resolver) and `Get-SPSThrottleLimit` (CPU-based default). A measured ~8x speedup on a 40-user mock with 100 ms LDAP latency. (#14)
- `ConvertTo-SPSUserRecord` (public) — single projection from a `Get-SPSADUser` result to the flat SPSUserSync record (DisplayName/FirstName/LastName/Email/Country/Location), shared by both the sequential path and the parallel worker so the generated JSON is byte-for-byte identical regardless of `ParallelADResolution`. (#14)

### Changed

- `SPSyncUserInfoList.ps1` now resolves each **unique** login against AD exactly once. Previously a user present in N webs was looked up N times; the user-collection pass is now separated from the AD-resolution pass (and the JSON-building pass), which also speeds up the default sequential mode on farms where users appear in many sites. The user-removal walk (`Set-SPUser` / `Remove-SPUser`) is unchanged and still runs per web. (#14)

## [1.2.1] - 2026-06-28

### Fixed

- `SPSyncUserProfile.ps1` processed **no** eligible users at all (the run reported "N users do not meet Prerequisites", wrote no `SPSyncUserAddedInUSPList` file and logged no error). `Add-SPSUserProfile`'s mandatory `-ResultCollection` parameter rejected the **empty** `ArrayList` on the first loop iteration (`Cannot bind argument to parameter 'ResultCollection' because it is an empty collection.`), and a script-scoped `Trap { Continue }` swallowed the terminating error and abandoned the whole batch. Added `[AllowEmptyCollection()]` to the parameter, wrapped the per-user call in `try/catch` (so one failing user is logged and the batch continues), and removed the misleading `Trap`. (#13)

### Added

- `Test-SPSUserSyncReadiness.ps1` now verifies that the current account can **read the User Profile Service Application** (a non-destructive profile-count read via `UserProfileManager`, on the UPA master only). This catches the missing **Manage Profiles** permission that makes `SPSyncUserProfile.ps1` fail at runtime with *"ProfileDBCacheServiceClient.GetUserData threw exception: Access is denied."* — PASS with the profile count, WARN (pointing to the permission/farm-account prerequisite) when the read is denied. (#11)

### Changed

- Documentation: the prerequisites now state that the account running `SPSyncUserProfile.ps1` must be able to manage profiles on the UPA — either the **farm account** or an account granted **Administrator** of the UPA with the **Manage Profiles** permission. (#10)

## [1.2.0] - 2026-06-28

### Added

- `Get-SPSInstalledProductVersion` (public) — reads the installed SharePoint version from `Microsoft.SharePoint.dll`, returning `$null` (silently) when SharePoint is not installed. (#6)
- `Import-SPSSharePointCommand` (public) — version-aware loader for the SharePoint command surface: `Add-PSSnapin Microsoft.SharePoint.PowerShell` on SharePoint 2013/2016/2019, `Import-Module SharePointServer` on **Subscription Edition** (which no longer ships the snap-in). Idempotent; lets the scripts run from plain `powershell.exe` (a scheduled task) without the SharePoint Management Shell. (#6)
- `Test-SPSADConnection` (public) — proves an AD domain is actually usable, not just that a searcher can be built: it binds (for `Credential` domains this validates the stored secret really works, not just that it decrypts), reads one user (generic "any user" probe via the domain's own filter, or a specific `-SampleAccount`), and reports which of the attributes SPSUserSync relies on (givenName, sn, mail, co, l, displayName) are populated. Returns a result object and never throws on a failed bind. (#7)
- `src/Test-SPSUserSyncReadiness.ps1` — pre-flight readiness check to run on a SharePoint server before the first real run. Read-only and non-destructive; verifies Administrator rights and PowerShell 5.1, that the `SPSUserSync.Common` module imports, that the three config files exist/parse/carry the required keys, that secrets are sound (every `Credential` domain maps to a secret, and **every entry in secrets.psd1** has a username, is not a placeholder, decrypts under the current account, and is not an empty password — orphan entries not referenced by any domain are surfaced as warnings), that each AD domain binds and a user with its key attributes can be read (via `Test-SPSADConnection`, unless `-SkipNetwork`; an optional `-SampleAccount` looks up a specific user), that SharePoint is installed and its commands load (edition-aware) and the farm is reachable (unless `-SkipSharePoint`), that the `SPSUserSync` Event Log is usable, and that the master-VM share is reachable. Colored output with a PASS/WARN/FAIL/SKIP summary and an exit code (0 ok, 1 on any failure). (#7)
- New `RemoveUnresolvableUsers` setting in `sync-settings.example.psd1` (default `$false`). Gates the `Remove-SPUser` cleanup in `SPSyncUserInfoList.ps1`: when `$false`, a user that cannot be synced from AD is reported and left in place (only the benign `Set-SPUser -SyncFromAD` refresh runs); set it to `$true` to restore the previous behavior of pruning unresolvable accounts from the farm. (#4)
- The HTML report (`Export-SPSUserReport`) now flags **unresolved users** as a pre-removal audit. In the UserInfoList report, rows whose identity did not resolve from AD (no display name, or a display name equal to the de-claimed login — the signature of a failed `Set-SPUser -SyncFromAD`) are highlighted in amber, counted in a new **Unresolved** summary card, and explained by a legend that points to the `RemoveUnresolvableUsers` setting. The UserProfile report highlights `UNKNOWN_USER` rows the same way (amber card and rows). `Get-SPSReportCardHtml` gained an optional `-Tone 'warn'` to render a card in the warning palette. (#5)

### Changed

- `SPSyncUserInfoList.ps1` and `SPSyncUserProfile.ps1` now load the SharePoint command surface via `Import-SPSSharePointCommand` at startup, so they work on **SharePoint Subscription Edition** (SharePointServer module) as well as 2013/2016/2019 (snap-in), and no longer depend on being launched from the SharePoint Management Shell. (#6)
- `.github/workflows/release.yml` — the release ZIP now contains the **contents** of `src/` (config/, Modules/, the scripts) at its root instead of a wrapping `src/` folder, so the archive extracts straight into the deployment folder with no manual move. (#8)
- **Behavior change — user removal is now opt-in.** `SPSyncUserInfoList.ps1` no longer removes unresolvable users by default; it reports them and runs only the `Set-SPUser -SyncFromAD` refresh. Set `RemoveUnresolvableUsers = $true` in `sync-settings.psd1` to restore the previous pruning behavior. On a claims-based farm the old default removed classic-format duplicates and system principals (it would attempt to remove e.g. `NT AUTHORITY\authenticated users`), which mutated the live farm unexpectedly. (#4)
- `SPSyncUserInfoList.ps1` now always excludes the classic system principals `NT AUTHORITY\*`, `BUILTIN\*` and `SHAREPOINT\*` from processing (in addition to the configured `ExcludedUserLogins` / `ExcludedUserLoginPatterns`), so these are never written to the JSON nor removed. Previously only the claims forms (e.g. `c:0!.s|windows`) were excluded, so the classic forms slipped through and were pruned. (#4)

### Fixed

- `Initialize-SPSScript` now writes the `Logs` folder (transcript, rotation logs, deleted-user snapshots, HTML reports) next to the **calling script** instead of inside the module folder. Module functions run in the module session state, so the previous `Get-Variable -Scope 1` caller lookup resolved to the module directory (`Modules\SPSUserSync.Common\Logs`), where logs would be wiped on every module redeploy. The function now takes an explicit `-ScriptRoot` parameter (the entry-point scripts pass their `$PSScriptRoot`) and falls back to a `Get-PSCallStack` walk that correctly crosses the module boundary. (#3)

## [1.1.0] - 2026-06-26

### Added

- JSON snapshot history and anomaly detection (`SPSyncUserInfoList.ps1`):
  - `Backup-SPSJsonFile` — archives the previous `SPSyncUserInfoListUserList.json` to `Logs\history\` with a timestamp before each regeneration.
  - `Compare-SPSJsonSnapshots` — pure function returning `CurrentCount`, `PreviousCount`, `Delta`, `DropPercent`, `ThresholdPercent`, `IsAnomalous`.
  - The script now archives the previous snapshot, regenerates, then raises a **Warning** in the SPSUserSync Event Log when the user count drops by at least `JsonDropThresholdPercent` (helps catch an unreachable AD forest or a bad exclusion before the UPA reconciliation runs).
  - History snapshots are rotated using the existing `Clear-SPSLogFolder` with `-Extension '*.json'`.
- New settings in `sync-settings.example.psd1` (backward-compatible defaults applied when absent):
  - `JsonHistoryRetentionDays` (default 90)
  - `JsonDropThresholdPercent` (default 20)
  - `GenerateHtmlReport` (default `$true`)
- Self-contained HTML reporting:
  - `Export-SPSUserReport` — generates a single dependency-free HTML report (no CDN, works offline) for either dataset via `-ReportType UserInfoList|UserProfile`. Summary cards plus an interactive table (live search, column sort, pagination) rendered by embedded vanilla JavaScript. All AD-sourced values are HTML-encoded and rendered via `textContent`, so names/emails cannot inject markup.
  - `SPSyncUserInfoList.ps1` writes `SPSyncUserInfoListReport-*.html` (total users, email coverage, top countries, top AD domains).
  - `SPSyncUserProfile.ps1` writes `SPSyncUserProfileReport-*.html` (counts by Status: CREATE / UPDATE / INFO / UNKNOWN_USER).
  - Reports are rotated with the existing `Clear-SPSLogFolder` using `-Extension '*.html'`, and can be disabled by setting `GenerateHtmlReport = $false`.
- Pester test suite under `tests/` (39 tests, cross-platform):
  - `SPSUserSync.Common.Tests.ps1` — module import, manifest validity, public/private surface, parameter contracts
  - `Compare-SPSJsonSnapshots.Tests.ps1` — drop detection, threshold edges, growth, empty-previous
  - `Backup-SPSJsonFile.Tests.ps1` — timestamped copy, copy-not-move, folder creation, missing source, content preservation
  - `Export-SPSUserReport.Tests.ps1` — both report types, empty dataset, and an HTML-injection safety test
  - `Private.Tests.ps1` — `ConvertFrom-SPSUserLogin`, `ConvertTo-SPSHtmlEncoded`, `Get-SPSJsonRecordCount` via `InModuleScope`
- `.github/workflows/pester.yml` — runs Pester and PSScriptAnalyzer on pull requests touching `src/`, `tests/` or the analyzer settings.
- `PSScriptAnalyzerSettings.psd1` — analyzer configuration (Error+Warning, with `PSUseSingularNouns` disabled for the deliberately plural `Compare-SPSJsonSnapshots` / `Get-SPSUniqueUsers`).
- `.gitattributes` and `.editorconfig` — encode the project's text conventions.

### Changed

- All PowerShell files (`*.ps1`, `*.psm1`, `*.psd1`) are now stored as **UTF-8 with BOM** and checked out with **CRLF**, so Windows PowerShell 5.1 reads any non-ASCII content correctly instead of falling back to the ANSI code page. YAML, Markdown and JSON keep LF and no BOM.
- Renamed two private report helpers to non-state-changing verbs (`New-SPSReportCard` -> `Get-SPSReportCardHtml`, `New-SPSReportTopList` -> `Get-SPSReportTopListHtml`) to satisfy PSScriptAnalyzer.

## [1.0.0] - 2026-06-26

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
  - `wiki/Release-Process.md` — maintainer checklist for shipping a new version (versioning policy, step-by-step release, tag-recovery procedure)
  - `wiki/_Sidebar.md` — global navigation sidebar rendered on every wiki page

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
