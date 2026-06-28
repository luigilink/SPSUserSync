# Tests for module loading and the public surface of SPSUserSync.Common.
$repoRoot   = Split-Path -Path $PSScriptRoot -Parent
$modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUserSync.Common/SPSUserSync.Common.psd1'

BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUserSync.Common/SPSUserSync.Common.psd1'
    Import-Module -Name $modulePath -Force
}

Describe 'SPSUserSync.Common module' {
    It 'imports without error' {
        Get-Module -Name SPSUserSync.Common | Should -Not -BeNullOrEmpty
    }

    It 'has a valid manifest' {
        { Test-ModuleManifest -Path $modulePath -ErrorAction Stop } | Should -Not -Throw
    }

    It 'exports exactly the expected public functions' {
        $expected = @(
            'Add-SPSUserSyncEvent'
            'Backup-SPSJsonFile'
            'Clear-SPSLogFolder'
            'Compare-SPSJsonSnapshots'
            'ConvertTo-SPSUserRecord'
            'Export-SPSUserReport'
            'Get-SPSADConnection'
            'Get-SPSADUser'
            'Get-SPSInstalledProductVersion'
            'Get-SPSSyncSetting'
            'Get-SPSThrottleLimit'
            'Import-SPSSharePointCommand'
            'Initialize-SPSScript'
            'Resolve-SPSADUserBatch'
            'Test-SPSADConnection'
            'Test-SPSADUser'
        )
        $actual = (Get-Command -Module SPSUserSync.Common).Name | Sort-Object
        $actual | Should -Be ($expected | Sort-Object)
    }

    It 'does not export private helpers' {
        $private = @(
            'ConvertFrom-SPSUserLogin'
            'ConvertTo-SPSHtmlEncoded'
            'Get-SPSJsonRecordCount'
            'Get-SPSConfigRoot'
            'Get-SPSADDomainConfig'
            'Get-SPSSecret'
        )
        foreach ($name in $private) {
            Get-Command -Name $name -Module SPSUserSync.Common -ErrorAction SilentlyContinue |
                Should -BeNullOrEmpty
        }
    }
}

Describe 'Public function contracts' {
    It 'Compare-SPSJsonSnapshots has mandatory CurrentPath and PreviousPath' {
        $cmd = Get-Command -Name Compare-SPSJsonSnapshots -Module SPSUserSync.Common
        $cmd.Parameters['CurrentPath'].Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -BeTrue
        $cmd.Parameters['PreviousPath'].Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -BeTrue
    }

    It 'Export-SPSUserReport restricts ReportType with a ValidateSet' {
        $cmd = Get-Command -Name Export-SPSUserReport -Module SPSUserSync.Common
        $validate = $cmd.Parameters['ReportType'].Attributes.Where{ $_.TypeId.Name -eq 'ValidateSetAttribute' }
        $validate | Should -Not -BeNullOrEmpty
        $validate[0].ValidValues | Should -Contain 'UserInfoList'
        $validate[0].ValidValues | Should -Contain 'UserProfile'
    }

    It 'Backup-SPSJsonFile has mandatory Path and HistoryFolder' {
        $cmd = Get-Command -Name Backup-SPSJsonFile -Module SPSUserSync.Common
        $cmd.Parameters['Path'].Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -BeTrue
        $cmd.Parameters['HistoryFolder'].Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -BeTrue
    }

    It 'Get-SPSInstalledProductVersion returns a FileVersionInfo output type' {
        $cmd = Get-Command -Name Get-SPSInstalledProductVersion -Module SPSUserSync.Common
        $cmd.OutputType.Type.FullName | Should -Contain 'System.Diagnostics.FileVersionInfo'
    }

    It 'Get-SPSInstalledProductVersion returns null off a SharePoint server' -Skip:($env:OS -eq 'Windows_NT' -and (Test-Path 'C:\Program Files\Common Files\microsoft shared\Web Server Extensions')) {
        Get-SPSInstalledProductVersion | Should -BeNullOrEmpty
    }

    It 'Import-SPSSharePointCommand throws when SharePoint is not installed' -Skip:($env:OS -eq 'Windows_NT' -and (Test-Path 'C:\Program Files\Common Files\microsoft shared\Web Server Extensions')) {
        { Import-SPSSharePointCommand -ErrorAction Stop } | Should -Throw '*SharePoint is not installed*'
    }

    It 'Test-SPSADConnection has mandatory DomainName and optional SampleAccount' {
        $cmd = Get-Command -Name Test-SPSADConnection -Module SPSUserSync.Common
        $cmd.Parameters['DomainName'].Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -BeTrue
        $cmd.Parameters.Keys | Should -Contain 'SampleAccount'
        $cmd.Parameters['SampleAccount'].Attributes.Where{ $_.TypeId.Name -eq 'ParameterAttribute' }[0].Mandatory | Should -BeFalse
    }
}
