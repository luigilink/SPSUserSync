# SPSUserSync - Release Notes

## [1.2.1] - 2026-06-28

A small follow-up to 1.2.0. No functional change to the sync itself: this
release documents a User Profile Service permission prerequisite and teaches the
readiness check to verify it, so the gap is caught before the first run instead
of mid-job on the master farm.

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
