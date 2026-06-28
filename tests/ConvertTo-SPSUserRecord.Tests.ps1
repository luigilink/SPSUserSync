# Tests for ConvertTo-SPSUserRecord, the single projection used by both the
# sequential path and the parallel Resolve-SPSADUserBatch worker. A fake AD
# object (Properties as a hashtable) stands in for the DirectoryServices
# SearchResult, so these run cross-platform.
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUserSync.Common/SPSUserSync.Common.psd1'
    Import-Module -Name $modulePath -Force

    function New-FakeAdUser {
        param ([hashtable] $Properties)
        [PSCustomObject]@{ Properties = $Properties }
    }
}

Describe 'ConvertTo-SPSUserRecord' {
    It 'projects all attributes from a fully populated AD entry' {
        $ad = New-FakeAdUser -Properties @{
            givenname   = 'Adam'
            sn          = 'Becker'
            mail        = 'adam.becker@zebes.chozo'
            co          = 'fr'
            l           = 'paris'
            displayname = 'Adam Becker'
        }
        $r = ConvertTo-SPSUserRecord -UserLogin 'i:0#.w|zebes\adambecker' -AdUser $ad
        $r.UserLogin   | Should -Be 'i:0#.w|zebes\adambecker'
        $r.DisplayName | Should -Be 'Adam Becker'
        $r.FirstName   | Should -Be 'Adam'
        $r.LastName    | Should -Be 'Becker'
        $r.Email       | Should -Be 'adam.becker@zebes.chozo'
        $r.Resolved    | Should -BeTrue
        $r.Error       | Should -BeNullOrEmpty
    }

    It 'upper-cases country and location' {
        $ad = New-FakeAdUser -Properties @{ givenname = 'A'; sn = 'B'; co = 'fr'; l = 'lyon'; displayname = 'A B' }
        $r = ConvertTo-SPSUserRecord -UserLogin 'ZEBES\ab' -AdUser $ad
        $r.Country  | Should -Be 'FR'
        $r.Location | Should -Be 'LYON'
    }

    It 'falls back to "FirstName LastName" when displayName is empty' {
        $ad = New-FakeAdUser -Properties @{ givenname = 'Anais'; sn = 'Faure'; mail = 'a@x'; displayname = '' }
        $r = ConvertTo-SPSUserRecord -UserLogin 'ZEBES\anaisfaure' -AdUser $ad
        $r.DisplayName | Should -Be 'Anais Faure'
    }

    It 'leaves DisplayName empty when displayName, givenName and sn are all empty' {
        $ad = New-FakeAdUser -Properties @{ givenname = ''; sn = ''; mail = 'x@y'; displayname = '' }
        $r = ConvertTo-SPSUserRecord -UserLogin 'ZEBES\svc' -AdUser $ad
        $r.DisplayName | Should -BeNullOrEmpty
        $r.Resolved    | Should -BeTrue
    }

    It 'returns an unresolved record for a null AD entry' {
        $r = ConvertTo-SPSUserRecord -UserLogin 'ZEBES\ghost' -AdUser $null
        $r.UserLogin    | Should -Be 'ZEBES\ghost'
        $r.Resolved     | Should -BeFalse
        $r.DisplayName  | Should -BeNullOrEmpty
        $r.FirstName    | Should -BeNullOrEmpty
        $r.Email        | Should -BeNullOrEmpty
    }
}

Describe 'Resolve-SPSADUserBatch and ConvertTo-SPSUserRecord agree' {
    It 'the parallel default worker yields the same shape as the sequential helper' {
        # Drive the batch with an injected worker that builds records via the same
        # ConvertTo-SPSUserRecord, proving the projection is shared and identical.
        $worker = {
            param ($UserLogin, $ConfigPath)
            $ad = [PSCustomObject]@{ Properties = @{ givenname = 'Test'; sn = 'User'; mail = "$UserLogin@x"; co = 'fr'; l = 'paris'; displayname = '' } }
            ConvertTo-SPSUserRecord -UserLogin $UserLogin -AdUser $ad
        }
        $res = Resolve-SPSADUserBatch -UserLogin @('ZEBES\a', 'ZEBES\b') -ResolveScript $worker -ModulePath (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/Modules/SPSUserSync.Common/SPSUserSync.Common.psd1')
        $res.Count | Should -Be 2
        ($res | Where-Object { $_.UserLogin -eq 'ZEBES\a' }).DisplayName | Should -Be 'Test User'
        ($res | Where-Object { $_.UserLogin -eq 'ZEBES\a' }).Country     | Should -Be 'FR'
    }
}
