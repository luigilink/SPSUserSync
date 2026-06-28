# SPSUserSync - Release Notes

## [1.2.1] - 2026-06-28

A small follow-up to 1.2.0, with one important fix to the User Profile
reconciliation script plus a documentation/readiness improvement around UPA
permissions.

### Fixed

- `SPSyncUserProfile.ps1` processed **no** eligible users at all — the run
  reported "N users do not meet Prerequisites", wrote no
  `SPSyncUserAddedInUSPList` file and logged no error, so it looked like a silent
  no-op. `Add-SPSUserProfile`'s mandatory `-ResultCollection` parameter rejected
  the **empty** `ArrayList` on the first loop iteration, and a script-scoped
  `Trap { Continue }` swallowed the terminating error and abandoned the whole
  batch. Added `[AllowEmptyCollection()]`, wrapped the per-user call in
  `try/catch` (one failing user is logged and the batch continues), and removed
  the misleading `Trap`. (#13)

### Added

- The readiness check (`Test-SPSUserSyncReadiness.ps1`) now verifies the current
  account can **read the User Profile Service Application** — a non-destructive
  profile-count read via `UserProfileManager`, on the UPA master only. This
  catches the missing **Manage Profiles** permission that otherwise makes
  `SPSyncUserProfile.ps1` fail at runtime with *"ProfileDBCacheServiceClient.GetUserData
  threw exception: Access is denied."* PASS reports the profile count; WARN points
  to the permission / farm-account prerequisite when the read is denied. (#11)

### Changed

- The prerequisites now document that the account running `SPSyncUserProfile.ps1`
  must be able to manage profiles on the UPA — either the **farm account** or an
  account granted **Administrator** of the UPA with the **Manage Profiles**
  permission. (#10)

A full list of changes in each version can be found in the [change log](CHANGELOG.md)
