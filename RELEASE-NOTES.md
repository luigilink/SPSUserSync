# SPSUserSync - Release Notes

## [1.3.0] - 2026-06-28

This release adds optional parallel Active Directory resolution to
`SPSyncUserInfoList.ps1`, for large multi-forest farms where the per-user LDAP
round-trip dominates the runtime. It is opt-in and off by default, and the
generated JSON is byte-for-byte identical whether parallel resolution is on or
off (verified on a SharePoint Subscription Edition farm).

### Added

- **Parallel AD resolution** (#14). With `ParallelADResolution = $true` (new
  setting, default `$false`), the unique user logins are resolved against AD
  concurrently through a RunspacePool — Windows PowerShell 5.1 compatible, no
  `ForEach-Object -Parallel` required. `MaxParallelADQueries` sets the degree of
  parallelism (0 = auto from the CPU count). Off by default because on small
  farms the per-runspace module-import overhead is not amortized. Two new public
  helpers back it: `Resolve-SPSADUserBatch` (the RunspacePool resolver) and
  `Get-SPSThrottleLimit` (CPU-based default). A measured ~8x speedup on a 40-user
  mock with 100 ms LDAP latency.
- `ConvertTo-SPSUserRecord` (#14) — the single `Get-SPSADUser` -> record
  projection shared by both the sequential path and the parallel worker, which is
  what guarantees the identical JSON.

### Changed

- `SPSyncUserInfoList.ps1` now resolves each **unique** login against AD exactly
  once (previously once per web the user appeared in), by separating the
  user-collection, AD-resolution and JSON-building passes. This also speeds up
  the default sequential mode on farms where users span many sites. The
  user-removal walk (`Set-SPUser` / `Remove-SPUser`) is unchanged and still runs
  per web. (#14)

### Upgrade notes

- No action required: `ParallelADResolution` and `MaxParallelADQueries` are
  optional and default to the previous (sequential) behavior. Add them to
  `sync-settings.psd1` only when you want to enable parallel resolution.

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
