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

## [1.3.2] - 2026-07-08

This is a hardening release that makes a broken or mis-deployed `secrets.psd1`
**fail fast and loud** instead of silently degrading the result. It follows a
field case where a `secrets.psd1` that could not be decoded on the User Profile
master server (DPAPI SecureStrings are bound to the machine and account that
created them) caused thousands of real users to be skipped as `UNKNOWN_USER`,
with the only trace being one Event-Log line per user.

There is no behaviour change for a correctly-deployed farm; the generated JSON
and the profile updates are unchanged.

### Fixed

- **AD configuration/secret errors are no longer mistaken for "user absent"**
  (#18). `Get-SPSADConnection` and `Get-SPSADUser` now distinguish a build-time
  misconfiguration (missing `LdapPath`, missing `CredentialKey`, or an
  undecodable/missing secret) — which throws a terminating `SPSADConfigError` —
  from a genuine lookup miss, which still returns `$null`. Previously every
  failure, including an undecodable DPAPI secret, was logged only to the Event
  Log and returned as `$null`, so a broken forest silently produced empty-name
  records and, on the profile side, `UNKNOWN_USER` downgrades.
- **`SPSyncUserProfile.ps1` pre-flights the AD configuration** (#18) once per
  credential-mode forest present in the input JSON, before the user loop, and
  stops with `Exit 1` and an actionable message when a forest's secret cannot be
  decoded on this server — instead of silently skipping every affected user.
- **`SPSyncUserInfoList.ps1` fails the run loudly** (#18) when a forest cannot be
  resolved because of a configuration/secret error, naming the affected
  forest(s), rather than writing a JSON with a whole forest blanked out.

### Added

- **`AuthenticationType` per domain in `ad-domains.psd1`** (#20) — maps to
  `System.DirectoryServices.AuthenticationTypes` and is passed as the LDAP bind
  type, so a non-Active-Directory directory can be configured entirely from the
  file: `'None'` for a plain simple bind, `'SecureSocketsLayer'` for LDAPS on
  port 636, and so on. It defaults to `'Secure'` (integrated Kerberos/NTLM),
  unchanged for existing AD forests, and is now honoured on `Default`-mode
  domains too (previously only `Credential`-mode). The value is case-insensitive
  and may combine flags (e.g. `'SecureSocketsLayer, ServerBind'`); an unknown
  value fails the run with the list of valid names instead of silently falling
  back. `ad-domains.example.psd1` gains a documented non-AD directory example.
- `Get-SPSADConnectionError` (#18) — a fast, query-free pre-flight that decodes
  each referenced forest's secret (without issuing an LDAP search) and returns
  the forests that fail. It backs the new `SPSyncUserProfile.ps1` pre-flight and
  is reusable in your own checks.

### Changed

- **Connectivity errors stay non-fatal** (#18). An LDAP server that is *not
  operational* or returns a *referral* (for example an external directory
  reachable from an application farm but not from the UPA master) is deliberately
  not treated as a configuration error: the affected login is logged and left
  unresolved so the rest of the run continues, and `Test-SPSUserSyncReadiness.ps1`
  flags the forest so you can fix the LDAP path/routing. Only deterministic,
  fixable configuration/secret errors abort the run.

### Upgrade notes

Drop-in replacement for 1.3.1 — no configuration change required. Before enabling
the scheduled tasks, run `Test-SPSUserSyncReadiness.ps1` **on each server**
(application farms and the UPA master), signed in as the service account, to
confirm every forest's secret decodes and binds. With 1.3.2 a forest whose secret
cannot be decoded now stops the run explicitly (exit code `1`) instead of silently
producing empty profiles.