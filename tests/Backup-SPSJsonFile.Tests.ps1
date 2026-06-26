# Behavior tests for Backup-SPSJsonFile.
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUserSync.Common/SPSUserSync.Common.psd1'
    Import-Module -Name $modulePath -Force
}

Describe 'Backup-SPSJsonFile' {
    It 'copies an existing file into the history folder with a timestamp' {
        $source = Join-Path $TestDrive 'SPSyncUserInfoListUserList.json'
        '[]' | Set-Content -Path $source -Encoding UTF8
        $history = Join-Path $TestDrive 'history'

        $backup = Backup-SPSJsonFile -Path $source -HistoryFolder $history -TimeStamp '20260626-1300'

        $backup | Should -Not -BeNullOrEmpty
        Test-Path $backup | Should -BeTrue
        Split-Path $backup -Leaf | Should -Be 'SPSyncUserInfoListUserList-20260626-1300.json'
    }

    It 'leaves the source file in place (copy, not move)' {
        $source = Join-Path $TestDrive 'snapshot.json'
        '[]' | Set-Content -Path $source -Encoding UTF8
        $history = Join-Path $TestDrive 'history'

        $null = Backup-SPSJsonFile -Path $source -HistoryFolder $history -TimeStamp '20260626-1301'

        Test-Path $source | Should -BeTrue
    }

    It 'creates the history folder when it does not exist' {
        $source = Join-Path $TestDrive 'snapshot2.json'
        '[]' | Set-Content -Path $source -Encoding UTF8
        $history = Join-Path $TestDrive 'brand-new-history'
        Test-Path $history | Should -BeFalse

        $null = Backup-SPSJsonFile -Path $source -HistoryFolder $history -TimeStamp '20260626-1302'

        Test-Path $history | Should -BeTrue
    }

    It 'returns null and creates nothing when the source is missing' {
        $missing = Join-Path $TestDrive 'does-not-exist.json'
        $history = Join-Path $TestDrive 'history-missing'

        $backup = Backup-SPSJsonFile -Path $missing -HistoryFolder $history

        $backup | Should -BeNullOrEmpty
        Test-Path $history | Should -BeFalse
    }

    It 'preserves the file content in the backup' {
        $source = Join-Path $TestDrive 'content.json'
        $payload = '[{"UserLogin":"i:0#.w|CONTOSO\\jdoe"}]'
        $payload | Set-Content -Path $source -Encoding UTF8
        $history = Join-Path $TestDrive 'history-content'

        $backup = Backup-SPSJsonFile -Path $source -HistoryFolder $history -TimeStamp '20260626-1303'

        (Get-Content -Path $backup -Raw).Trim() | Should -Be $payload
    }
}
