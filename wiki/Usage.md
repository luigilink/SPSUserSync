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

## JSON history and anomaly detection

*(SPSyncUserInfoList.ps1, 1.1.0+)*

Before each regeneration, the previous `SPSyncUserInfoListUserList.json` is archived to `Logs\history\` with a timestamp (e.g. `SPSyncUserInfoListUserList-20260626-1300.json`). These snapshots are rotated using `JsonHistoryRetentionDays` (default 90).

After the new snapshot is written, the script compares its record count against the archived one. If the user count drops by at least `JsonDropThresholdPercent` (default 20%), a **Warning** is written to the SPSUserSync Event Log under the source `Compare-SPSJsonSnapshots`:

```
Abnormal drop detected in the generated user snapshot.
Previous count: 11210
Current count: 4120
Drop: 63,25% (threshold: 20%)
```

This is an early-warning signal: a sudden drop usually means an AD forest was unreachable during the run, or an exclusion pattern was mis-configured. Investigate before `SPSyncUserProfile.ps1` consumes the file, since a truncated snapshot would otherwise propagate to the User Profile Service Application. Growth (the snapshot getting larger) never raises a warning.

## HTML reports

*(both scripts, 1.1.0+)*

When `GenerateHtmlReport = $true` (the default), each run also writes a self-contained HTML report under `Logs\`:

- `SPSyncUserInfoListReport-YYYYMMDD-HHMM.html` — total users, email coverage, top countries and top AD domains, plus a searchable/sortable/paginated table of every user.
- `SPSyncUserProfileReport-YYYYMMDD-HHMM.html` — counts by reconciliation `Status` (CREATE / UPDATE / INFO / UNKNOWN_USER), plus the per-account table.

The reports are **dependency-free** (no CDN, no internet required) so they open on isolated SharePoint servers, and they are rotated with the same retention as the transcripts (`LogRetentionDays` / `UpaLogRetentionDays`). Set `GenerateHtmlReport = $false` to skip them.

> **Privacy:** the reports embed personal data (display names, email addresses). They live in the local `Logs\` folder at the same sensitivity as the JSON snapshots — handle, share and retain them accordingly.

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

The value in `secrets.psd1` was generated by a different account or on a different server (DPAPI SecureStrings are bound to the machine **and** the account that created them). Regenerate it under the account that runs the scheduled task **on this server**. See [Configuration → Generating a SecureString](Configuration#generating-a-securestring).

Since 1.3.2 this is treated as a **fail-fast configuration error**, not a per-user miss:

- `SPSyncUserInfoList.ps1` stops with a clear error naming the affected forest(s) and writes **no** JSON (it never ships a snapshot with a whole forest blanked out).
- `SPSyncUserProfile.ps1` **pre-flights** every credential-mode forest referenced by the input JSON before the user loop, and stops with `Exit 1` if any secret cannot be decoded on this server. This prevents the earlier silent symptom where a broken secret downgraded every affected user to `UNKNOWN_USER` (and swelled the *Not Added* list) one Event-Log line at a time.

Run `Test-SPSUserSyncReadiness.ps1` **on each server** (application farms **and** the UPA master), signed in as the service account, to confirm every forest's secret decodes and binds before enabling the scheduled tasks.

> A **connectivity** error (an LDAP server that is *not operational* or returns a *referral*, e.g. an external directory reachable from an application farm but not from the UPA master) is different: it is **not** fatal. The affected login is logged and left unresolved so the rest of the run continues, and the readiness check flags the forest so you can decide.

### LDAP bind fails: "The server is not operational" or "A referral was returned"

```
[FAIL]  Domain 'rga' LDAP bind - Exception calling "FindOne" ...: "The server is not operational."
[FAIL]  Domain 'contoso' LDAP bind - Exception calling "FindOne" ...: "A referral was returned from the server."
```

These are **connectivity** problems (the secret, if any, decoded fine — the directory itself could not be queried), most common with an external or specially-configured forest:

- **The server is not operational** — the `LdapPath` host is unreachable from *this* server. Check the `LdapPath` value, DNS, routing/firewall to the directory, and the port (389/636, or 3268/3269 for a global catalog). Confirm with `Test-NetConnection <host> -Port 389`. Note that a directory reachable from an application farm is not necessarily reachable from the UPA master.
- **A referral was returned** — the bind hit a server that does not hold the queried partition and returned an LDAP referral. Point `LdapPath` at a concrete DC or a **global catalog** (`GC://` or port 3268) for that forest instead of a serverless/domain-only path.

A connectivity error is **not** fatal to the run: the affected logins are logged and left unresolved, and the readiness check reports the forest as `FAIL` so you can fix it before the next run. Fix the `LdapPath`/routing, then re-run `Test-SPSUserSyncReadiness.ps1` to confirm the bind.

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
