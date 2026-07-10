# SPSUserSync - Release Notes

## [1.3.4] - 2026-07-10

This is a **performance** release for `SPSyncUserProfile.ps1`, with no change in
behaviour: the same profiles are created and updated, and the same JSON files and
HTML report are produced.

On a large (~100k-user) farm, a full profile reconciliation took over an hour. A
transcript analysis showed the time was spent almost entirely in the per-user loop,
and that the loop rebuilt the User Profile service context and `UserProfileManager`
**on every single user** — the dominant cost, and the cause of a steady throughput
decay over the run (object churn / GC pressure).

### Changed

- **The `UserProfileManager` is now built once and reused for the whole run**
  (#24), instead of being reconstructed for every user inside `Add-SPSUserProfile`.
  This removes the dominant per-user cost and the associated memory churn.
- **The per-user transcript output is condensed to a single status line** —
  `[UPDATE] DOMAIN\user (changed: WorkEmail, Country)`, `[CREATE]`, `[INFO]` or
  `[UNKNOWN_USER]` — replacing the previous ~14-line before/after dump. On a
  ~100k-user run this cuts a multi-million-line, tens-of-MB transcript down to one
  line per user and removes the corresponding synchronous I/O. (#24)

### Added

- **End-of-run timing summary** in `SPSyncUserProfile.ps1`: users processed, wall
  time, average milliseconds per user, and the CREATE / UPDATE / INFO /
  UNKNOWN_USER breakdown — so each run's performance is visible directly in the
  log. (#24)

### Upgrade note

No configuration change is required and the output files are unchanged. Simply
deploy the new version; the next `SPSyncUserProfile.ps1` run is faster and its log
is far smaller, ending with the new timing summary.
