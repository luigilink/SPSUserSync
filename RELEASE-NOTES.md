# SPSUserSync - Release Notes

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

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
