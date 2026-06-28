# SPSUserSync - Release Notes

## [1.2.0] - 2026-06-28

This release makes the toolkit deployable and verifiable on a real SharePoint
server — including **Subscription Edition** — without the SharePoint Management
Shell, adds a pre-flight readiness check, and makes user removal opt-in so a sync
never prunes accounts from a live farm unless you ask it to.

> **Behavior change — user removal is now opt-in.** On a claims-based farm,
> earlier versions removed classic-format and system principals (e.g.
> `NT AUTHORITY\authenticated users`) when `Set-SPUser -SyncFromAD` could not
> resolve them. SPSUserSync now reports those users and leaves them in place by
> default. Set `RemoveUnresolvableUsers = $true` in `sync-settings.psd1` to
> restore the previous pruning behavior.

### Added

- **SharePoint command surface, edition-aware** (#6) — `Import-SPSSharePointCommand`
  loads the snap-in on SharePoint 2013/2016/2019 and the `SharePointServer` module
  on Subscription Edition (which no longer ships the snap-in), so both scripts run
  from a plain `powershell.exe` (a scheduled task) instead of requiring the
  SharePoint Management Shell. `Get-SPSInstalledProductVersion` backs the detection.
- **Pre-flight readiness check** (#7) — `Test-SPSUserSyncReadiness.ps1` validates
  Host, Module, Config, Secrets, AD, SharePoint, the Event Log and the master-VM
  share, with colored PASS/WARN/FAIL/SKIP output and a 0/1 exit code. Read-only and
  non-destructive. `Test-SPSADConnection` backs the AD section (binds, reads one
  user, reports which key attributes are populated); `-SkipNetwork` /
  `-SkipSharePoint` allow a config-only pass from a workstation.
- **Unresolved-user audit in the HTML report** (#5) — rows whose identity did not
  resolve from AD (no display name, or a display name equal to the de-claimed
  login) are highlighted in amber, counted in a new **Unresolved** card, and
  explained by a legend pointing to `RemoveUnresolvableUsers`. The UserProfile
  report highlights `UNKNOWN_USER` rows the same way.
- `RemoveUnresolvableUsers` setting (default `$false`) in
  `sync-settings.example.psd1` (#4).

### Changed

- **User removal is opt-in** (#4) — see the behavior change above. The classic
  system principals `NT AUTHORITY\*`, `BUILTIN\*` and `SHAREPOINT\*` are now always
  excluded from processing, so they are never written to the JSON nor removed
  (previously only their claims forms were excluded).
- Both `SPSyncUserInfoList.ps1` and `SPSyncUserProfile.ps1` load the SharePoint
  command surface via `Import-SPSSharePointCommand` at startup (#6).
- The release ZIP now contains the **contents** of `src/` at its root, so the
  archive extracts straight into the deployment folder with no manual move (#8).

### Fixed

- The `Logs` folder (transcript, rotation logs, deleted-user snapshots, HTML
  reports) is written next to the **calling script** again, instead of inside the
  module folder where it was wiped on every module redeploy (#3).

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
