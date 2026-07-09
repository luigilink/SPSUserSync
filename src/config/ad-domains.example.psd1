# =====================================================================================
# SPSUserSync - Active Directory domain configuration (example)
#
# Copy this file to ad-domains.psd1 and edit it for your environment. The real
# ad-domains.psd1 is gitignored to prevent leaking your AD topology.
#
# AuthMode = 'Default'    : no explicit credential, uses the running account
#            'Credential' : looks up CredentialKey in secrets.psd1 to bind LDAP
#
# AuthenticationType is optional and maps to
# System.DirectoryServices.AuthenticationTypes (the LDAP bind type). It defaults
# to 'Secure' (integrated Kerberos/NTLM), which suits Active Directory forests.
# A non-AD LDAP directory may instead need:
#   'None'               - a plain simple bind (username/password in the clear)
#   'SecureSocketsLayer'  - LDAPS, typically on port 636
# The value is case-insensitive and may combine flags, e.g.
# 'SecureSocketsLayer, ServerBind'. An unknown value fails the run with the list
# of valid names rather than being silently ignored. Valid names: None, Secure,
# Encryption, SecureSocketsLayer, ReadonlyServer, Anonymous, FastBind, Signing,
# Sealing, Delegation, ServerBind.
#
# LdapFilterTemplate is optional. Use it for non-Active Directory LDAP servers
# that require a custom search filter (e.g. an external partner directory). Use
# {0} for the account name. When omitted, DefaultFilterTemplate at the bottom of
# the file is used.
# =====================================================================================
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
        # Example non-Active-Directory LDAP directory: an explicit host:port and
        # base DN, a bind account from secrets.psd1, a simple bind
        # (AuthenticationType = 'None'; switch to 'SecureSocketsLayer' for LDAPS on
        # :636), and a custom objectClass / uid filter.
        'partners' = @{
            LdapPath           = 'LDAP://partners.example.com:389/o=Partners'
            AuthMode           = 'Credential'
            CredentialKey      = 'partners'
            AuthenticationType = 'None'
            LdapFilterTemplate = '(&(ObjectClass=inetOrgPerson)(uid={0}))'
        }
    }

    Default = @{
        LdapPath = 'LDAP://DC=CONTOSO;DC=COM'
        AuthMode = 'Default'
    }

    DefaultFilterTemplate = '(&(objectCategory=person)(objectClass=user)(sAMAccountName={0}))'
}
