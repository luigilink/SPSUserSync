# =====================================================================================
# SPSUserSync - Secrets configuration (example)
#
# Copy this file to secrets.psd1 and replace the placeholders with real values. The
# real secrets.psd1 is gitignored and MUST NEVER be committed to version control.
#
# Each entry's key (e.g. 'fabrikam', 'partners') corresponds to the CredentialKey
# property of the matching domain entry in ad-domains.psd1.
#
# PasswordSecure values MUST be SecureString strings encrypted with the current
# user's DPAPI key. Generate them on the target server, signed in as the account
# that will run the scheduled task, with:
#
#   PS> Read-Host -AsSecureString -Prompt 'Password' | ConvertFrom-SecureString
#
# Paste the resulting string between the single quotes below. The encrypted value
# can only be decrypted by the same user account on the same machine.
# =====================================================================================
@{
    'fabrikam' = @{
        Username       = 'FABRIKAM\svc_sps_bind'
        PasswordSecure = 'PASTE-ConvertFrom-SecureString-OUTPUT-HERE'
    }
    'partners' = @{
        Username       = 'uid=svc_sps_bind,ou=Service Accounts,o=Partners'
        PasswordSecure = 'PASTE-ConvertFrom-SecureString-OUTPUT-HERE'
    }
}
