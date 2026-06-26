# Usage

This page describes how to run, schedule and troubleshoot the two SPSUserSync scripts.

## Running the scripts

### `SPSyncUserInfoList.ps1`

Generates the JSON snapshot of every `SPUser` enriched with the matching Active Directory attributes. Runs on every **application farm** in scope.

```powershell
# Full farm pass (all SPSite objects)
.\SPSyncUserInfoList.ps1

# Restrict to specific SPSite URLs (wildcards supported)
.\SPSyncUserInfoList.ps1 -FilterUrl '*sites/contoso*'
```

| Parameter | Type | Description |
|---|---|---|
| `-FilterUrl` | `string` | Optional wildcard filter on `SPSite.Url`. When provided, the JSON is written with the suffix `-CUSTOM` to avoid clashing with the full-farm snapshot. |

**Outputs**

- `SPSyncUserInfoListUserList.json` — the snapshot consumed by `SPSyncUserProfile.ps1`. Written UTF-8.
- `SPSyncUserInfoListUserList-CUSTOM.json` — same, when `-FilterUrl` is used.
- `Logs\SPSyncUserDeletedListYYYYMMDD-HHMM.json` — users removed during the run because SharePoint reported `Cannot get the full name or e-mail address of user`.
- `Logs\SPSyncUserInfoListYYYYMMDD-HHMM.log` — full transcript.
- The JSON is copied to the master server through `RemoteJsonPath`.

### `SPSyncUserProfile.ps1`

Reconciles the User Profile Service Application from a previously generated JSON. Runs on the **UPA master server**.

```powershell
.\SPSyncUserProfile.ps1 -InputFile 'D:\Tools\SCRIPTS\JOBS\SPSyncUserProfile\SPSyncUserInfoListUserList-CONTOSO.json'
```

| Parameter | Type | Description |
|---|---|---|
| `-InputFile` | `string` | Absolute path of the JSON file to consume. Mandatory. |

**Outputs**

- `Logs\SPSyncUserAddedInUSPListYYYYMMDD-HHMM.json` — per-user record (`AccountName`, `Status` = `CREATE` / `UPDATE` / `INFO` / `UNKNOWN_USER`).
- `Logs\SPSyncUserNotAddedInUSPListYYYYMMDD-HHMM.json` — input entries that lacked `FirstName`, `LastName` or `Email`.
- `Logs\SPSyncUserProfileYYYYMMDD-HHMM.log` — full transcript.

## Scheduling

### Application farm script

A typical schedule runs `SPSyncUserInfoList.ps1` **several times a day** on every application farm. Example via Windows Task Scheduler:

| Field | Value |
|---|---|
| Run as | Farm Admin service account (member of local Administrators) |
| Trigger | Daily, every 6 hours (00:00 / 06:00 / 12:00 / 18:00) |
| Action | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\Tools\SCRIPTS\JOBS\SPSUserSync\SPSyncUserInfoList.ps1"` |
| Run whether user is logged on or not | Yes |
| Run with highest privileges | Yes |

### UPA master server script

Schedule `SPSyncUserProfile.ps1` shortly after each application farm run, e.g. 30 minutes later, so each new JSON has time to land via SMB:

| Field | Value |
|---|---|
| Trigger | Daily, every 6 hours (00:30 / 06:30 / 12:30 / 18:30) |
| Action | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File "D:\Tools\SCRIPTS\JOBS\SPSUserSync\SPSyncUserProfile.ps1" -InputFile "D:\Tools\SCRIPTS\JOBS\SPSyncUserProfile\SPSyncUserInfoListUserList-CONTOSO.json"` |

If you have several application farms with different `AppCode` values, schedule one action per JSON file.

## Logs

### Windows Event Log

SPSUserSync writes structured events to a dedicated log:

> **Event Viewer → Applications and Services Logs → SPSUserSync**

Each event header records:

```
SPSUserSync Version: 1.0.0
Script: SPSyncUserInfoList
User: DOMAIN\svc_sps_bind
ComputerName: SPS-APP-01
```

The event **Source** is the **name of the calling function** (`Get-SPSUniqueUsers`, `Add-SPSUserProfile`, `Get-SPSADUser`...), which makes Event Viewer filters very precise. Recommended filters:

- `EntryType = Error` to surface anything that needs investigation.
- `Source = Add-SPSUserProfile` to focus on UPA reconciliation issues.
- Text contains `Script: SPSyncUserInfoList` (or `SPSyncUserProfile`) to scope by script.
- Text contains `Version: 1.0.0` to spot servers running an outdated build.

### Transcripts

Every run produces a transcript file under the script's `Logs\` folder. Useful for ad-hoc inspection of a single run. Files are rotated automatically using `LogRetentionDays` / `UpaLogRetentionDays` from `sync-settings.psd1`.

### JSON output files

The per-run JSON files (`SPSyncUserAddedInUSPList*.json`, `SPSyncUserDeletedList*.json`, `SPSyncUserNotAddedInUSPList*.json`) are also rotated using the same retention settings.

## Troubleshooting

### Module fails to import

```
Failed to import SPSUserSync.Common module from path: ...
```

- Confirm the `Modules\SPSUserSync.Common\` folder lives **next to** the script.
- Confirm the running account has read access to that folder.
- Run `Test-ModuleManifest .\Modules\SPSUserSync.Common\SPSUserSync.Common.psd1` to confirm the manifest is valid.

### Sync settings file not found

```
Sync settings file not found at '...\config\sync-settings.psd1'.
Copy sync-settings.example.psd1 to sync-settings.psd1 and edit the values...
```

You forgot to create the real `sync-settings.psd1`. See [Configuration](Configuration#sync-settingspsd1).

### Failed to decode SecureString

```
Failed to decode SecureString for secret 'fabrikam'.
The value must be the output of ConvertFrom-SecureString on the current user account and machine.
```

The value in `secrets.psd1` was generated by a different account or on a different server. Regenerate it under the account that runs the scheduled task on this server. See [Configuration → Generating a SecureString](Configuration#generating-a-securestring).

### Domain '...' not found in ad-domains.psd1

```
Domain 'somedomain' not found in ad-domains.psd1. Falling back to the Default entry.
```

A `SPUser.UserLogin` referenced a domain key you have not declared. Either:

- Add the domain to `ad-domains.psd1`, or
- Add the login to `ExcludedUserLogins` / `ExcludedUserLoginPatterns` in `sync-settings.psd1` if you want to ignore it on purpose.

### `Get-SPSite` requires SharePoint Management Shell

The two scripts depend on the `Microsoft.SharePoint.PowerShell` snap-in. The scheduled task action must run via `powershell.exe` (Windows PowerShell 5.1), not `pwsh.exe`. The snap-in is loaded automatically by the scripts when needed; no manual `Add-PSSnapin` is necessary on SharePoint 2016+.

### `Set-SPUser -SyncFromAD` keeps failing with `Cannot get the full name or e-mail address of user`

That exception means the SPUser cannot be matched in AD anymore — the account was deleted or moved. SPSUserSync handles this case automatically by calling `Remove-SPUser` and recording the entry in the `SPSyncUserDeletedList` JSON. No action required unless the volume of deletions seems abnormal.

## Reading the output JSON

The JSON snapshot is an array of records, one per unique `SPUser`:

```json
[
    {
        "UserLogin": "i:0#.w|CONTOSO\\jdoe",
        "DisplayName": "DOE John",
        "FirstName": "John",
        "LastName": "DOE",
        "Email": "john.doe@contoso.com",
        "Location": "PARIS",
        "Country": "FR"
    }
]
```

Convert back to PowerShell objects with:

```powershell
$users = Get-Content -Path '.\SPSyncUserInfoListUserList.json' -Raw -Encoding UTF8 | ConvertFrom-Json
$users | Where-Object Country -eq 'FR' | Measure-Object
```
