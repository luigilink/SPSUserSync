# SPSUserSync - Release Notes

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
- Wiki documentation (`wiki/Home.md`, `wiki/Getting-Started.md`, `wiki/Configuration.md`, `wiki/Usage.md`) auto-synced to the GitHub Wiki by the existing `wiki.yml` workflow.

### Changed

- .gitignore
  - Add patterns for runtime logs and local configuration files
  - Prevent accidental commit of credentials and secrets
- .github/ISSUE_TEMPLATE/1_bug_report.yml
  - Align version and PowerShell dropdown options with the project
- README.md
  - Add Requirements section (SharePoint Server 2016/2019/SE, PowerShell 5.1, Farm Admin, AD reachability, farm property bags)
- CODE_OF_CONDUCT.md
  - Set the enforcement contact to the project maintainer's GitHub profile (@luigilink)
- README.md
  - Remove obsolete reference to farm property bags (now in `config/sync-settings.psd1`)

### Added

- Configuration scaffolding under `src/config/` (ad-domains, secrets, sync-settings — `.example.psd1` only is versioned)
- PowerShell module `src/Modules/SPSUserSync.Common/` with manifest, loader, and 7 public functions: `Add-SPSUserSyncEvent` (dedicated SPSUserSync Windows Event Log), `Clear-SPSLogFolder` (log rotation), `Get-SPSADConnection` (DirectorySearcher per domain), `Get-SPSADUser` / `Test-SPSADUser` (SP-to-AD lookup), `Get-SPSSyncSetting` (settings loader), `Initialize-SPSScript` (admin check, transcript, banner). Private helpers cover login parsing, config loading and SecureString DPAPI secret decryption.

### Changed

- src/SPSyncUserInfoList.ps1 refactored to consume the new module:
  - All 19 AD domains, bind credentials, master VM names, MySite URLs, user-exclusion patterns and claim prefix moved out of code into `src/config/*.psd1`
  - JSON output is now UTF-8 (fixes accents corruption)
  - Errors funnel into the SPSUserSync Event Log instead of `*_errlog.xml` dumps
- src/SPSyncUserProfile.ps1 refactored to consume the new module:
  - Same module-driven cleanup as SPSyncUserInfoList.ps1
  - Reads the input JSON explicitly as UTF-8
  - UPA log retention configurable via `UpaLogRetentionDays`
- Both scripts no longer carry their own version string. The single source of truth is the `ModuleVersion` field of `SPSUserSync.Common.psd1`; `Initialize-SPSScript` auto-detects it.
- The SPSUserSync Event Log header records the SPSUserSync version and the calling script name on dedicated lines so operators can filter events by version or script directly from Event Viewer or SCOM.

### Added

- `.github/workflows/release.yml` — automated release: packages `src/` and publishes a GitHub Release with `RELEASE-NOTES.md` as body, triggered by pushing a `v*` tag.

### Changed (post-commit polish)

- README.md slimmed down to badges + short description + Quick links. Detailed Requirements / Usage / Configuration content moved to the Wiki.
- README.md: fix Code of Conduct badge link casing (`CODE_OF_CONDUCT.md`).
- SECURITY.md: replace the obsolete `APP_CODE` / `ENV_NAME` farm property bag reference with a broader description of the values that must never be committed.

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
