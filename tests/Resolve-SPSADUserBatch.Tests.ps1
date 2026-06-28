# Tests for the parallel AD resolution helpers (Get-SPSThrottleLimit,
# Resolve-SPSADUserBatch). These run cross-platform: the worker is exercised
# through an injected -ResolveScript, so no live Active Directory is required.
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUserSync.Common/SPSUserSync.Common.psd1'
    Import-Module -Name $modulePath -Force
}

Describe 'Get-SPSThrottleLimit' {
    It 'returns a positive integer' {
        $limit = Get-SPSThrottleLimit
        $limit | Should -BeOfType ([System.Int32])
        $limit | Should -BeGreaterThan 0
    }

    It 'never exceeds 10' {
        # The heuristic caps at 10 on 8+ logical CPUs and is 2x otherwise, so on
        # any realistic CI host it stays at or below 10.
        Get-SPSThrottleLimit | Should -BeLessOrEqual 10
    }
}

Describe 'Resolve-SPSADUserBatch' {
    BeforeAll {
        # A self-contained worker: no module / no AD needed. Echoes the login and
        # marks it resolved, so we can assert on the plumbing.
        $script:mockResolve = {
            param ($UserLogin, $ConfigPath)
            [PSCustomObject]@{
                UserLogin   = $UserLogin
                DisplayName = ($UserLogin.Split('\')[-1]).ToUpper()
                FirstName   = 'Test'
                LastName    = 'User'
                Email       = "$UserLogin@example.test"
                Country     = 'FR'
                Location    = 'PARIS'
                Resolved    = $true
                Error       = $null
            }
        }
    }

    It 'returns one result per input login' {
        $logins = 1..12 | ForEach-Object { "ZEBES\user$_" }
        $res = Resolve-SPSADUserBatch -UserLogin $logins -ThrottleLimit 4 -ResolveScript $script:mockResolve
        $res.Count | Should -Be 12
        @($res | Where-Object { $_.Resolved }).Count | Should -Be 12
    }

    It 'returns every requested login exactly once (no loss, no duplication)' {
        $logins = 1..25 | ForEach-Object { "ZEBES\user$_" }
        $res = Resolve-SPSADUserBatch -UserLogin $logins -ThrottleLimit 8 -ResolveScript $script:mockResolve
        $returned = $res.UserLogin | Sort-Object -Unique
        $returned.Count | Should -Be 25
        # every input is present
        foreach ($l in $logins) { $returned | Should -Contain $l }
    }

    It 'projects the AD attributes the worker produced' {
        $res = Resolve-SPSADUserBatch -UserLogin @('ZEBES\jdoe') -ResolveScript $script:mockResolve
        $res[0].UserLogin   | Should -Be 'ZEBES\jdoe'
        $res[0].DisplayName | Should -Be 'JDOE'
        $res[0].Email       | Should -Be 'ZEBES\jdoe@example.test'
        $res[0].Country     | Should -Be 'FR'
    }

    It 'returns an empty (non-null) list for empty input' {
        $res = Resolve-SPSADUserBatch -UserLogin @() -ResolveScript $script:mockResolve
        # The comma operator preserves the List object (rather than unwrapping to
        # $null), so .Count is callable and reports 0.
        $null -ne $res | Should -BeTrue
        $res.Count     | Should -Be 0
    }

    It 'isolates a failing login and still returns the others' {
        $boom = {
            param ($UserLogin, $ConfigPath)
            if ($UserLogin -eq 'ZEBES\bad') { throw 'LDAP down' }
            [PSCustomObject]@{
                UserLogin = $UserLogin; DisplayName = $UserLogin; FirstName = ''; LastName = ''
                Email = ''; Country = ''; Location = ''; Resolved = $true; Error = $null
            }
        }
        $res = Resolve-SPSADUserBatch -UserLogin @('ZEBES\ok', 'ZEBES\bad') -ResolveScript $boom
        $res.Count | Should -Be 2
        ($res | Where-Object { $_.UserLogin -eq 'ZEBES\ok' }).Resolved  | Should -BeTrue
        $bad = $res | Where-Object { $_.UserLogin -eq 'ZEBES\bad' }
        $bad.Resolved | Should -BeFalse
        $bad.Error    | Should -Match 'LDAP down'
    }

    It 'runs concurrently (wall time well under the sequential sum)' {
        $slow = {
            param ($UserLogin, $ConfigPath)
            Start-Sleep -Milliseconds 100
            [PSCustomObject]@{
                UserLogin = $UserLogin; DisplayName = $UserLogin; FirstName = ''; LastName = ''
                Email = ''; Country = ''; Location = ''; Resolved = $true; Error = $null
            }
        }
        $logins = 1..20 | ForEach-Object { "ZEBES\u$_" }   # 20 x 100ms = 2000ms sequential
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $res = Resolve-SPSADUserBatch -UserLogin $logins -ThrottleLimit 10 -ResolveScript $slow
        $sw.Stop()
        $res.Count | Should -Be 20
        # With throttle 10 the wall time should be ~2 batches (~200ms) plus
        # overhead — comfortably under half the 2000ms sequential cost.
        $sw.ElapsedMilliseconds | Should -BeLessThan 1000
    }
}
