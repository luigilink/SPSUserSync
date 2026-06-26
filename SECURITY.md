# Security Policy

## Supported Versions

The following SPSUserSync versions are currently supported with security updates:

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

## Reporting a Vulnerability

SPSUserSync is used in production SharePoint Server farms to synchronize identity data across Active Directory forests. We take vulnerabilities in this toolkit seriously.

### How to report

**Please do not open a public GitHub issue for security vulnerabilities.**

Use the **GitHub Security Advisories** form (preferred):

<https://github.com/luigilink/SPSUserSync/security/advisories/new>

This keeps the report private until a coordinated disclosure is published.

### What to include

When reporting a vulnerability, please include as much of the following information as possible:

- A description of the vulnerability and its potential impact
- Steps to reproduce the issue (PowerShell version, SharePoint Server version, AD topology)
- Any relevant log output, with **sensitive data redacted** (account names, domain names, internal URLs, IPs)
- Suggested mitigation or fix, if available

### Response timeline

- **Acknowledgement**: within 5 business days
- **Initial assessment**: within 10 business days
- **Disclosure**: coordinated with the reporter once a fix is available

## Credentials and Active Directory

This toolkit interacts with multiple Active Directory forests and may handle service-account credentials in non-trivial ways.

**Never commit any of the following to a public or private repository:**

- LDAP bind account passwords (plain or NTLM hashes)
- DPAPI-encrypted SecureString values produced by `ConvertFrom-SecureString` (they look opaque but are decryptable by the same user account on the same machine)
- Production Active Directory domain controller names, LDAP paths, or internal IPs
- Internal SharePoint server hostnames and URLs (e.g. `MasterVM`, `MySiteUrl`, `RemoteJsonPath` values)
- Any customer-specific value placed in your real `src/config/*.psd1` files (`ad-domains.psd1`, `secrets.psd1`, `sync-settings.psd1`)

The project's `.gitignore` excludes the following paths by default:

- `src/config/secrets.psd1`
- `src/config/ad-domains.psd1`
- `src/config/sync-settings.psd1`
- `src/config/*.local.psd1`

Always review the output of `git status` before any `git push`, especially after editing files under `src/config/`.

If you discover credentials inadvertently committed to this repository, please report it via the form above and **rotate the affected credentials immediately**.
