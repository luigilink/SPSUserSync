# SPSUserSync - Release Notes

## [2.0.0] - 2026-09-01

This is a **breaking** release that makes SPSUserSync **SharePoint Server
Subscription Edition (SE) only**. SharePoint Server 2016 and 2019 both reached
**end of support on 14 July 2026**; the toolkit no longer carries the deprecated
snap-in load path used by those versions.

There is no configuration change when running on Subscription Edition: deploy the
new version and run as usual.

### Removed

- **Support for SharePoint Server 2016 and 2019** (#28). SPSUserSync is now
  Subscription Edition only.
- The deprecated `Microsoft.SharePoint.PowerShell` **PSSnapin** load path and the
  product-version detection that selected it. `Import-SPSSharePointCommand` now
  imports the `SharePointServer` module only (idempotent), keeping a clear
  "SharePoint not installed" guard. `Test-SPSUserSyncReadiness.ps1` no longer
  prints a 2013 / 2016-2019 / SE version label — it reports the build number.

### Changed

- **BREAKING:** SPSUserSync targets **SharePoint Server Subscription Edition**
  exclusively. Running it on SharePoint 2016/2019 is no longer supported.
- Documentation (README, wiki) updated to state Subscription Edition only and to
  reference the `SharePointServer` module instead of the snap-in.

### Migration

- Environments still running SharePoint Server 2016 or 2019 must stay on the
  previous major release, **v1.3.4**
  (https://github.com/luigilink/SPSUserSync/releases/tag/v1.3.4), which retains the
  PSSnapin path.
