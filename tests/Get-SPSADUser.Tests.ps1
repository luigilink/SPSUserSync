# Regression tests for the AD config/secret error hardening (issue #18).
#
# The goal is the distinction that a broken deployment (an undecodable secrets.psd1
# entry, a missing LdapPath/CredentialKey) must FAIL LOUD, while a runtime
# connectivity error (server not operational, referral - e.g. an external RGA-style
# directory) stays NON-fatal and simply leaves the login unresolved. These run
# cross-platform: every AD/LDAP call is mocked inside the module scope. Each mock
# builds its own searcher object inline, because a Pester mock body runs in the
# module scope and does not close over variables from the It block.
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUserSync.Common/SPSUserSync.Common.psd1'
    Import-Module -Name $modulePath -Force
}

Describe 'Get-SPSADUser configuration vs connectivity (issue #18)' {
    It 'throws SPSADConfigError when the AD connection cannot be built (bad/undecodable secret)' {
        InModuleScope SPSUserSync.Common {
            Mock ConvertFrom-SPSUserLogin { [PSCustomObject]@{ IsValid = $true; Domain = 'zcam'; Account = 'u123' } }
            Mock Get-SPSADConnection { throw "Failed to decode SecureString for secret 'zcam'." }
            Mock Add-SPSUserSyncEvent { }

            $err = $null
            try { Get-SPSADUser -UserLogin 'i:0#.w|zcam\u123' } catch { $err = $_ }
            $err | Should -Not -BeNullOrEmpty
            $err.FullyQualifiedErrorId | Should -BeLike 'SPSADConfigError*'
            Should -Invoke Add-SPSUserSyncEvent -Times 1 -ParameterFilter { $EntryType -eq 'Error' }
        }
    }

    It 'returns $null (non-fatal) when the LDAP query fails for connectivity (server not operational)' {
        InModuleScope SPSUserSync.Common {
            Mock ConvertFrom-SPSUserLogin { [PSCustomObject]@{ IsValid = $true; Domain = 'rga'; Account = 'u1' } }
            Mock Get-SPSADConnection {
                $s = [PSCustomObject]@{}
                $s | Add-Member -MemberType ScriptMethod -Name FindOne -Value { throw 'The server is not operational.' }
                $s
            }
            Mock Add-SPSUserSyncEvent { }

            # Must NOT throw (a flaky external forest never nukes the run) but must log.
            $result = Get-SPSADUser -UserLogin 'i:0#.w|rga\u1'
            $result | Should -BeNullOrEmpty
            Should -Invoke Add-SPSUserSyncEvent -Times 1 -ParameterFilter { $EntryType -eq 'Error' }
        }
    }

    It 'returns $null for a genuine not-found (search ran, matched nothing)' {
        InModuleScope SPSUserSync.Common {
            Mock ConvertFrom-SPSUserLogin { [PSCustomObject]@{ IsValid = $true; Domain = 'zebes'; Account = 'ghost' } }
            Mock Get-SPSADConnection {
                $s = [PSCustomObject]@{}
                $s | Add-Member -MemberType ScriptMethod -Name FindOne -Value { return $null }
                $s
            }
            Mock Add-SPSUserSyncEvent { }

            Get-SPSADUser -UserLogin 'i:0#.w|zebes\ghost' | Should -BeNullOrEmpty
            Should -Not -Invoke Add-SPSUserSyncEvent
        }
    }

    It 'returns the SearchResult when the user is found' {
        InModuleScope SPSUserSync.Common {
            Mock ConvertFrom-SPSUserLogin { [PSCustomObject]@{ IsValid = $true; Domain = 'zebes'; Account = 'jdoe' } }
            Mock Get-SPSADConnection {
                $s = [PSCustomObject]@{}
                $s | Add-Member -MemberType ScriptMethod -Name FindOne -Value { [PSCustomObject]@{ Marker = 'FOUND' } }
                $s
            }

            (Get-SPSADUser -UserLogin 'i:0#.w|zebes\jdoe').Marker | Should -Be 'FOUND'
        }
    }

    It 'skips a non-DOMAIN\user login without touching AD' {
        InModuleScope SPSUserSync.Common {
            Mock ConvertFrom-SPSUserLogin { [PSCustomObject]@{ IsValid = $false } }
            Mock Get-SPSADConnection { throw 'must not be called' }

            Get-SPSADUser -UserLogin 'c:0(.s|true' | Should -BeNullOrEmpty
            Should -Not -Invoke Get-SPSADConnection
        }
    }
}

Describe 'Test-SPSADUser propagates config errors, isolates the rest (issue #18)' {
    It 'returns $true when the user resolves' {
        InModuleScope SPSUserSync.Common {
            Mock Get-SPSADUser { [PSCustomObject]@{ x = 1 } }
            Test-SPSADUser -UserLogin 'i:0#.w|zebes\jdoe' | Should -BeTrue
        }
    }

    It 'returns $false when the user is genuinely not found or unreachable' {
        InModuleScope SPSUserSync.Common {
            Mock Get-SPSADUser { $null }
            Test-SPSADUser -UserLogin 'i:0#.w|zebes\ghost' | Should -BeFalse
        }
    }

    It 'propagates a configuration error instead of reporting $false' {
        InModuleScope SPSUserSync.Common {
            Mock Get-SPSADUser {
                $er = New-Object System.Management.Automation.ErrorRecord(
                    [System.InvalidOperationException]::new('secret'), 'SPSADConfigError',
                    [System.Management.Automation.ErrorCategory]::ResourceUnavailable, 'zcam')
                throw $er
            }
            { Test-SPSADUser -UserLogin 'i:0#.w|zcam\u1' } | Should -Throw
        }
    }
}

Describe 'Get-SPSADConnectionError pre-flight (issue #18)' {
    It 'returns the forests whose connection fails, one per distinct domain' {
        InModuleScope SPSUserSync.Common {
            Mock Get-SPSADConnection {
                param($DomainName, $AccountName, $ConfigPath)
                if ($DomainName -eq 'zcam') { throw "Failed to decode SecureString for secret 'zcam'." }
                [PSCustomObject]@{ ok = $true }
            }
            $logins = @('i:0#.w|zcam\a1', 'i:0#.w|zcam\a2', 'i:0#.w|zebes\b1', 'i:0#.w|zebes\b2')
            $errors = @(Get-SPSADConnectionError -UserLogin $logins)
            $errors.Count | Should -Be 1
            $errors[0].Domain | Should -Be 'zcam'
            $errors[0].Error  | Should -Match 'decode SecureString'
        }
    }

    It 'returns empty when every forest connects' {
        InModuleScope SPSUserSync.Common {
            Mock Get-SPSADConnection { [PSCustomObject]@{ ok = $true } }
            $errors = @(Get-SPSADConnectionError -UserLogin @('i:0#.w|zebes\a', 'i:0#.w|zebes\b'))
            $errors.Count | Should -Be 0
        }
    }

    It 'ignores non-DOMAIN\user logins (claims, well-known principals)' {
        InModuleScope SPSUserSync.Common {
            Mock Get-SPSADConnection { [PSCustomObject]@{ ok = $true } }
            $errors = @(Get-SPSADConnectionError -UserLogin @('c:0(.s|true', 'i:0#.w|SHAREPOINT\system'))
            # SHAREPOINT is a DOMAIN\user shape, so it IS probed; the claim login is skipped.
            Should -Invoke Get-SPSADConnection -Times 1
            $errors.Count | Should -Be 0
        }
    }
}