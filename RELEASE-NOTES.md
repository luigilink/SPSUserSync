# SPSUserSync - Release Notes

## [1.3.3] - 2026-07-09

This release adds **AD account status detection** so departed employees are handled
correctly, and it works for **every customer** because it relies only on universal
Active Directory signals — never on a customer-specific leaver process.

Two kinds of departed accounts are now distinguished and handled:

- **Disabled** accounts (kept in AD, `userAccountControl` bit `0x2`): detected and,
  with the new opt-in `SkipDisabledUsers`, reported instead of being given a profile.
- **Deleted** accounts (no longer in AD): already not provisioned, now explicitly
  tagged so they can be told apart from an actionable configuration gap.

### Added

- **Account status on every record** — `ConvertTo-SPSUserRecord` reads
  `userAccountControl` and exposes `AccountStatus` (`Active` / `Disabled` /
  `NotFound`) and `Enabled`; `SPSyncUserInfoList.ps1` writes `AccountStatus` into the
  JSON snapshot. Universal by design: no dedicated OU, naming convention, HR feed or
  retention assumption. A resolved account with no `userAccountControl` (some non-AD
  LDAP directories) stays `Active`, exactly as before. (#21)
- **`SkipDisabledUsers`** (`sync-settings.psd1`, default `$false`) — when `$true`,
  `SPSyncUserProfile.ps1` reports `Disabled` accounts as Not Added instead of creating
  or updating their profile. Default preserves the previous behaviour. (#21)
- **`NotAddedReason`** on each Not-Added entry — `AD_NOT_FOUND`, `MISSING_ATTRIBUTES`
  or `DISABLED` — with a per-reason breakdown in the run summary, so an expected miss
  (a departed account) is easy to tell apart from an actionable one (e.g. a forest
  missing from `ad-domains.psd1`). (#21)
- The **`SPSyncUserInfoList` HTML report** gains an *AD Status* column and a
  *Disabled in AD* card (with a note pointing at `SkipDisabledUsers`), so disabled —
  departed-but-retained — accounts are visible before the profile sync runs. (#21)

### Changed

- CI: bump the GitHub Actions that ran on the deprecated Node.js 20 runtime —
  `actions/checkout` `v4`→`v7`, `actions/upload-artifact` `v4`→`v7`,
  `softprops/action-gh-release` `v2`→`v3`. CI-only; the packaged module and scripts
  are unchanged. (#22)

### Upgrade note

`SkipDisabledUsers` acts on the `AccountStatus` written by `SPSyncUserInfoList.ps1`
1.3.3+. **Regenerate the JSON snapshot after upgrading** for the flag to take effect;
a pre-1.3.3 snapshot carries no status, so no user is skipped as disabled until then.
There is no behaviour change for a correctly-deployed farm when `SkipDisabledUsers`
is left at its default `$false`.
