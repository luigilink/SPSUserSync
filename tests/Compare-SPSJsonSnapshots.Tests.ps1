# Behavior tests for Compare-SPSJsonSnapshots (pure function).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUserSync.Common/SPSUserSync.Common.psd1'
    Import-Module -Name $modulePath -Force

    function New-SPSTestSnapshot {
        param ([int] $Count, [string] $Path)
        if ($Count -le 0) {
            '[]' | Set-Content -Path $Path -Encoding UTF8
            return
        }
        $records = 1..$Count | ForEach-Object {
            [pscustomobject]@{ UserLogin = "i:0#.w|CONTOSO\u$_"; DisplayName = "User $_" }
        }
        $records | ConvertTo-Json | Set-Content -Path $Path -Encoding UTF8
    }
}

Describe 'Compare-SPSJsonSnapshots' {
    It 'flags a 30% drop when the threshold is 20%' {
        $prev = Join-Path $TestDrive 'prev.json'; New-SPSTestSnapshot -Count 100 -Path $prev
        $curr = Join-Path $TestDrive 'curr.json'; New-SPSTestSnapshot -Count 70  -Path $curr

        $result = Compare-SPSJsonSnapshots -CurrentPath $curr -PreviousPath $prev -DropThresholdPercent 20

        $result.CurrentCount  | Should -Be 70
        $result.PreviousCount | Should -Be 100
        $result.Delta         | Should -Be -30
        $result.DropPercent   | Should -Be 30
        $result.IsAnomalous   | Should -BeTrue
    }

    It 'does not flag the same 30% drop when the threshold is 40%' {
        $prev = Join-Path $TestDrive 'prev.json'; New-SPSTestSnapshot -Count 100 -Path $prev
        $curr = Join-Path $TestDrive 'curr.json'; New-SPSTestSnapshot -Count 70  -Path $curr

        $result = Compare-SPSJsonSnapshots -CurrentPath $curr -PreviousPath $prev -DropThresholdPercent 40

        $result.DropPercent | Should -Be 30
        $result.IsAnomalous | Should -BeFalse
    }

    It 'never flags growth as anomalous' {
        $prev = Join-Path $TestDrive 'prev.json'; New-SPSTestSnapshot -Count 70  -Path $prev
        $curr = Join-Path $TestDrive 'curr.json'; New-SPSTestSnapshot -Count 100 -Path $curr

        $result = Compare-SPSJsonSnapshots -CurrentPath $curr -PreviousPath $prev -DropThresholdPercent 20

        $result.Delta       | Should -Be 30
        $result.DropPercent | Should -Be 0
        $result.IsAnomalous | Should -BeFalse
    }

    It 'treats a drop exactly at the threshold as anomalous' {
        $prev = Join-Path $TestDrive 'prev.json'; New-SPSTestSnapshot -Count 100 -Path $prev
        $curr = Join-Path $TestDrive 'curr.json'; New-SPSTestSnapshot -Count 80  -Path $curr

        $result = Compare-SPSJsonSnapshots -CurrentPath $curr -PreviousPath $prev -DropThresholdPercent 20

        $result.DropPercent | Should -Be 20
        $result.IsAnomalous | Should -BeTrue
    }

    It 'is not anomalous when the previous snapshot was empty' {
        $prev = Join-Path $TestDrive 'prev.json'; New-SPSTestSnapshot -Count 0  -Path $prev
        $curr = Join-Path $TestDrive 'curr.json'; New-SPSTestSnapshot -Count 50 -Path $curr

        $result = Compare-SPSJsonSnapshots -CurrentPath $curr -PreviousPath $prev -DropThresholdPercent 20

        $result.PreviousCount | Should -Be 0
        $result.IsAnomalous   | Should -BeFalse
    }
}
