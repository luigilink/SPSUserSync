# =====================================================================================
# SPSUserSync - Active Directory domain configuration (example)
#
# Copy this file to ad-domains.psd1 and edit it for your environment. The real
# ad-domains.psd1 is gitignored to prevent leaking your AD topology.
#
# AuthMode = 'Default'    : no explicit credential, uses the running account
#            'Credential' : looks up CredentialKey in secrets.psd1 to bind LDAP
#
# LdapFilterTemplate is optional. Use it for non-Active Directory LDAP servers
# that require a custom search filter (e.g. RGA). Use {0} for the account name.
# When omitted, DefaultFilterTemplate at the bottom of the file is used.
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
