# SPSUserSync Wiki

**SPSUserSync** is a PowerShell toolkit to keep SharePoint Server **User Information Lists** and the **User Profile Service Application (UPA)** synchronized with **multiple Active Directory forests** — without relying on the built-in *User Profile AD Import*.

## When to use SPSUserSync

Use this toolkit when:

- Your farm spans **several AD forests**, some without two-way trust
- Your security team won't grant the broad AD permissions UPA Import requires
- You have **non-standard LDAP directories** (custom `objectClass`, alternate `uid` field)
- You need **fine-grained control** over which domains, OUs and users are synchronized
- You want a **deterministic, file-based, auditable** sync flow

## Architecture overview

```
┌──────────────────────┐      JSON       ┌──────────────────────┐
│  Application farm N  │  ─────────────► │   UPA master server  │
│  SPSyncUserInfoList  │   over SMB      │  SPSyncUserProfile   │
└──────────┬───────────┘                 └──────────┬───────────┘
           │                                        │
           ▼                                        ▼
   Active Directory                       User Profile Service
   (any number of forests)                Application (UPA)
```

1. **SPSyncUserInfoList.ps1** runs on each application farm. It walks every `SPSite`, resolves each unique `SPUser` against the right AD forest using `Get-SPSADConnection`, and writes a UTF-8 JSON snapshot. The file is then copied to the master server of the User Profile Service farm.
2. **SPSyncUserProfile.ps1** runs on the master server of the User Profile Service farm. It reads the JSON snapshot and reconciles each profile in the UPA (create / update / mark `UNKNOWN_USER`).

Both scripts share the **`SPSUserSync.Common`** PowerShell module: AD resolution, log rotation, transcript bootstrap, event logging — all centralized so there is no code duplication.

## Pages

- [Getting Started](Getting-Started) — prerequisites, installation, first run
- [Configuration](Configuration) — the three `.psd1` files explained
- [Usage](Usage) — running, scheduling, logs and troubleshooting
- [Release Process](Release-Process) — for maintainers: how to ship a new version

## Project links

- [Source repository](https://github.com/luigilink/SPSUserSync)
- [Latest release](https://github.com/luigilink/SPSUserSync/releases/latest)
- [Issues](https://github.com/luigilink/SPSUserSync/issues)
- [Changelog](https://github.com/luigilink/SPSUserSync/blob/main/CHANGELOG.md)
- [Security policy](https://github.com/luigilink/SPSUserSync/blob/main/SECURITY.md)
