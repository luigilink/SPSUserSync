# Getting Started

This page walks you through installing **SPSUserSync** and running it for the first time on a SharePoint Server farm.

## Prerequisites

| Requirement | Detail |
|---|---|
| SharePoint Server | **2016**, **2019**, or **Subscription Edition** |
| PowerShell | **5.1** (Windows PowerShell) on every server in scope |
| Privileges | The account running the scripts must be a **Farm Administrator** and member of the local **Administrators** group on the server |
| Active Directory | Network reachability to every AD forest you want to synchronize (LDAP/389 or LDAPS/636) |
| Disk space | A `Logs/` folder is created next to each script (transcripts + per-error JSON files) |

## Installation

1. **Download** the latest release ZIP from the [Releases page](https://github.com/luigilink/SPSUserSync/releases/latest).
2. **Extract** the `src/` folder onto every SharePoint server in scope. A common location is `D:\Tools\SCRIPTS\JOBS\SPSUserSync\`.
3. The extracted tree looks like this:

   ```
   SPSUserSync\
   ├── SPSyncUserInfoList.ps1        ← runs on application farms
   ├── SPSyncUserProfile.ps1         ← runs on the UPA master server
   ├── Modules\
   │   └── SPSUserSync.Common\       ← shared module, auto-loaded
   └── config\
       ├── ad-domains.example.psd1
       ├── secrets.example.psd1
       └── sync-settings.example.psd1
   ```

## First-time configuration

The toolkit ships with `*.example.psd1` templates. You must copy each one to its real name and edit the values for your environment. The real `*.psd1` files are gitignored and must **never** be checked into version control.

```powershell
cd D:\Tools\SCRIPTS\JOBS\SPSUserSync\config
Copy-Item ad-domains.example.psd1     ad-domains.psd1
Copy-Item secrets.example.psd1        secrets.psd1
Copy-Item sync-settings.example.psd1  sync-settings.psd1
```

See the [Configuration](Configuration) page for the meaning of every field.

## Generating SecureString credentials

For each AD domain that requires explicit bind credentials (`AuthMode = 'Credential'`), generate a DPAPI-encrypted SecureString **on the target server** while signed in as the **same Windows account** that will run the scheduled task:

```powershell
Read-Host -AsSecureString -Prompt 'Password' | ConvertFrom-SecureString
```

Paste the resulting string into `secrets.psd1` under the matching `CredentialKey`:

```powershell
@{
    'fabrikam' = @{
        Username       = 'FABRIKAM\svc_sps_bind'
        PasswordSecure = '01000000d08c9ddf...'   # output of ConvertFrom-SecureString
    }
}
```

> ⚠️ **DPAPI binding**: a `PasswordSecure` value is only readable by the **same user account on the same machine** that produced it. You must regenerate it for every server and every service account.

## First run

### Application farm (snapshot generation)

```powershell
cd D:\Tools\SCRIPTS\JOBS\SPSUserSync
.\SPSyncUserInfoList.ps1
```

Expected output:

- `SPSyncUserInfoListUserList.json` written next to the script (UTF-8)
- File copied to the master server using the `RemoteJsonPath` configured in `sync-settings.psd1`
- A transcript saved under `Logs\SPSyncUserInfoListYYYYMMDD-HHMM.log`
- Events written under **Event Viewer → Applications and Services Logs → SPSUserSync**

### UPA master server (profile reconciliation)

```powershell
cd D:\Tools\SCRIPTS\JOBS\SPSUserSync
.\SPSyncUserProfile.ps1 -InputFile 'D:\Tools\SCRIPTS\JOBS\SPSyncUserProfile\SPSyncUserInfoListUserList-CONTOSO.json'
```

Expected output:

- `Logs\SPSyncUserAddedInUSPListYYYYMMDD-HHMM.json` — list of profiles created/updated
- `Logs\SPSyncUserNotAddedInUSPListYYYYMMDD-HHMM.json` — list of input entries missing FirstName / LastName / Email
- A transcript saved under `Logs\SPSyncUserProfileYYYYMMDD-HHMM.log`
- Events written under **Event Viewer → Applications and Services Logs → SPSUserSync**

## Verifying the install

After the first run, in **Event Viewer → Applications and Services Logs → SPSUserSync**, look for entries with:

```
SPSUserSync Version: 1.0.0
Script: SPSyncUserInfoList
User: DOMAIN\svc_sps_bind
ComputerName: SPS-APP-01
```

If you see warnings or errors, head to the [Usage page](Usage) for troubleshooting.

## Next steps

- Read the [Configuration page](Configuration) to fine-tune AD domains, exclusion patterns and retention windows.
- Read the [Usage page](Usage) to schedule both scripts and learn how to read the logs.
