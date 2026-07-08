# SPSUserSync - Release Notes

## [1.3.1] - 2026-07-08

This is a hardening release for `SPSyncUserInfoList.ps1`. It does not change the
generated JSON for a correctly-permissioned account, but it makes a **wrong
service account** (or a missing Shell Admin) fail loudly and early instead of
silently. It follows a field case where the script was launched with an
under-privileged account and produced no output and no visible error at all.

### Fixed

- **No more silent ACCESS_DENIED runs** (#16). `Get-SPSite -Limit All` no longer
  uses `-ErrorAction SilentlyContinue`. When the running account cannot enumerate
  the farm site collections, the `ACCESS_DENIED` (`E_ACCESSDENIED 0x80070005`) is
  now surfaced to the **console/transcript** as well as the Windows Event Log,
  with an actionable message pointing at the Shell Admin / correct service
  account. Previously the error reached only the Event Log, so the operator saw an
  almost-empty screen while the script kept running and then emitted two confusing
  secondary errors on a JSON file that was never written.
- **No more overwriting/copying an empty snapshot** (#16). When zero users are
  collected — almost always a rights problem rather than a genuinely empty farm —
  the previous good `SPSyncUserInfoListUserList.json` is left untouched, an
  explicit error is raised, and the HTML report and the remote copy are **skipped**
  (the script exits `1`) instead of pushing empty or stale data to the User
  Profile farm.

### Added

- **Readiness site-collection enumeration check** (#16). `Test-SPSUserSyncReadiness.ps1`
  now walks `Get-SPSite -Limit All` and **FAILs** on `ACCESS_DENIED`, pointing at
  the Shell Admin / service account prerequisite. This is the exact permission
  `SPSyncUserInfoList.ps1` depends on, and it plugs the gap left by the previous
  `Get-SPFarm`-only check (which only proves config-database access, while the
  real run reads every content database). Run the readiness check as the service
  account before enabling the scheduled task to catch a wrong account up front.
- **Regression tests** (#16) for `Get-SPSUniqueUsers`: healthy farm writes the JSON
  and reports success; zero users writes no JSON and raises an Error event;
  `ACCESS_DENIED` surfaces an actionable Error and writes no JSON.

### Upgrade notes

Drop-in replacement for 1.3.0 — no configuration change required. If you rely on a
scheduled task, make sure the account it runs under is a **Shell Admin** on every
content database (`Add-SPShellAdmin`); with 1.3.1 a wrong account now fails the run
explicitly (exit code `1`) instead of silently producing nothing.