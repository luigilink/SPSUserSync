# Configuration

SPSUserSync stores its configuration in three PowerShell data files under `src/config/`. Only the `*.example.psd1` templates are versioned in the repository — the real files are gitignored and must be created locally on each target server.

| File | Purpose |
|---|---|
| `ad-domains.psd1` | List of Active Directory forests and how to query each one |
| `secrets.psd1` | SecureString DPAPI-encrypted bind credentials per domain |
| `sync-settings.psd1` | Environment-specific settings (server names, MySite URL, exclusion patterns, retention windows) |

---

## `ad-domains.psd1`

Maps each NetBIOS-style domain name to its LDAP path, authentication mode and optional custom filter template.

```powershell
@{
    Domains = @{
        'contoso' = @{
            LdapPath = 'LDAP://DC=CONTOSO;DC=COM'
            AuthMode = 'Default'
        }
        'fabrikam' = @{
            LdapPath      = 'LDAP://DC=FABRIKAM;DC=LOCAL'
            AuthMode      = 'Credential'
            CredentialKey = 'fabrikam'
        }
        'partners' = @{
            LdapPath           = 'LDAP://partners.example.com:636/o=Partners'
            AuthMode           = 'Credential'
            CredentialKey      = 'partners'
            LdapFilterTemplate = '(&(ObjectClass=person)(uid={0}))'
        }
    }

    Default = @{
        LdapPath = 'LDAP://DC=CONTOSO;DC=COM'
        AuthMode = 'Default'
    }

    DefaultFilterTemplate = '(&(objectCategory=person)(objectClass=user)(sAMAccountName={0}))'
}
```

### Fields

| Field | Required | Description |
|---|---|---|
| `Domains.<key>` | yes | The key is the **NetBIOS-style domain name** as found in `DOMAIN\user` logins (case-insensitive). |
| `LdapPath` | yes | The `LDAP://` URI to bind to. Use `LDAPS://...:636/` for SSL. |
| `AuthMode` | yes | `Default` (no explicit credential, uses the running account) or `Credential` (looks up `CredentialKey` in `secrets.psd1`). |
| `CredentialKey` | when `AuthMode = 'Credential'` | Key into `secrets.psd1` for the bind credential. |
| `AuthenticationType` | no | Optional `[System.DirectoryServices.AuthenticationTypes]` value, e.g. `None`, `Secure`, `SecureSocketsLayer`. Defaults to `Secure`. Set to `None` for anonymous-bind directories. |
| `LdapFilterTemplate` | no | Custom LDAP filter for non-AD directories. Use `{0}` as the account-name placeholder. Falls back to `DefaultFilterTemplate` when omitted. |
| `Default` | yes | Fallback entry when a `DOMAIN\user` login uses a domain key that is not declared above. |
| `DefaultFilterTemplate` | yes | Filter used for any domain that does not declare its own `LdapFilterTemplate`. |

### Adding a new forest

1. Add an entry under `Domains` with the right `LdapPath`.
2. If the forest needs an explicit bind account, set `AuthMode = 'Credential'` and pick a `CredentialKey`.
3. Add a matching entry in `secrets.psd1` (see below).

---

## `secrets.psd1`

Holds the bind credentials referenced by `CredentialKey` in `ad-domains.psd1`. **Never** commit this file.

```powershell
@{
    'fabrikam' = @{
        Username       = 'FABRIKAM\svc_sps_bind'
        PasswordSecure = '01000000d08c9ddf01...'
    }
    'partners' = @{
        Username       = 'uid=svc_sps_bind,ou=Service Accounts,o=Partners'
        PasswordSecure = '01000000d08c9ddf01...'
    }
}
```

### Fields

| Field | Description |
|---|---|
| `<key>` | Must match a `CredentialKey` value from `ad-domains.psd1`. |
| `Username` | Bind user. Format depends on the directory (`DOMAIN\user` for Active Directory, `uid=...,ou=...,o=...` for OpenLDAP-style directories). |
| `PasswordSecure` | Output of `Read-Host -AsSecureString \| ConvertFrom-SecureString`. DPAPI-encrypted. |

### Generating a SecureString

Run on the **target server** under the **same Windows account** that will execute the scheduled task:

```powershell
Read-Host -AsSecureString -Prompt 'Password' | ConvertFrom-SecureString
```

Paste the output between the single quotes of the `PasswordSecure` value.

> ⚠️ **DPAPI binding**: the encrypted value is only readable by the user account / machine pair that created it. Switching the scheduled task to a different account or server requires regenerating the value.

---

## `sync-settings.psd1`

Environment-specific knobs read by both scripts.

```powershell
@{
    EnvName = 'PROD'
    AppCode = 'CONTOSO'

    ClaimPrefix = 'i:0#.w|'

    ExcludedUserLogins = @(
        'SHAREPOINT\system'
        'c:0(.s|true'
        'c:0!.s|windows'
    )

    ExcludedUserLoginPatterns = @(
        'c:0+.w|s-1-5-21-*'
        '*EXAMPLEDOMAIN\*'
    )

    MasterVM       = 'SPS-UPA-MASTER'
    MySiteUrl      = 'https://mysite.contoso.com'
    RemoteJsonPath = '\\{0}\d$\Tools\SCRIPTS\JOBS\SPSyncUserProfile\SPSyncUserInfoListUserList-{1}.json'

    LogRetentionDays    = 90
    UpaLogRetentionDays = 30
}
```

### Fields

| Field | Used by | Description |
|---|---|---|
| `EnvName` | both | Free-form environment identifier (`PROD`, `PPRD`, `DEV`). Surfaced in Event Log headers. |
| `AppCode` | `SPSyncUserInfoList` | Free-form application code; appears in the generated JSON file name (`SPSyncUserInfoListUserList-<AppCode>.json`). |
| `ClaimPrefix` | both | Prefix stripped from claims-formatted logins (default: `i:0#.w\|`). |
| `ExcludedUserLogins` | `SPSyncUserInfoList` | **Exact** `SPUser.UserLogin` values to exclude from the JSON. |
| `ExcludedUserLoginPatterns` | `SPSyncUserInfoList` | PowerShell `-like` wildcard patterns to exclude. |
| `MasterVM` | `SPSyncUserInfoList` | Hostname of the User Profile Service master server. Substituted as `{0}` in `RemoteJsonPath`. |
| `MySiteUrl` | `SPSyncUserProfile` | URL of the MySite host on the UPA master farm. |
| `RemoteJsonPath` | `SPSyncUserInfoList` | UNC template used to copy the JSON to the UPA master server. `{0}` = `MasterVM`, `{1}` = `AppCode`. |
| `LogRetentionDays` | `SPSyncUserInfoList` | Days of `*.log` history to keep next to the script. |
| `UpaLogRetentionDays` | `SPSyncUserProfile` | Same, for the UPA master server. |

### Customizing the exclusion list

`ExcludedUserLogins` matches **exactly**. `ExcludedUserLoginPatterns` uses PowerShell wildcards (`*`, `?`). The two are OR'd together: a SPUser whose `UserLogin` matches **either** is skipped.

Common patterns:

- `'c:0+.w|s-1-5-21-*'` — exclude every local Windows account claim.
- `'*FOREIGNDOMAIN\*'` — exclude an entire AD domain when you don't want to manage its users in the UPA.
- `'c:0o.c|federateddirectoryclaimprovider|*'` — exclude federated-claim groups.

---

## Where these files live

By default, both scripts and the module expect `*.psd1` files at:

```
<install-folder>\config\ad-domains.psd1
<install-folder>\config\secrets.psd1
<install-folder>\config\sync-settings.psd1
```

The resolution is performed by `Get-SPSConfigRoot` (a private module helper) which uses the module's own location to find the `config/` folder. If you need a non-default location, every public loader function accepts an override `-ConfigPath` parameter.
