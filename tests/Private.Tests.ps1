# Tests for the private helpers via InModuleScope.
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUserSync.Common/SPSUserSync.Common.psd1'
    Import-Module -Name $modulePath -Force
}

Describe 'ConvertFrom-SPSUserLogin' {
    It 'parses a claims DOMAIN\user login' {
        InModuleScope SPSUserSync.Common {
            $r = ConvertFrom-SPSUserLogin -UserLogin 'i:0#.w|CONTOSO\jdoe'
            $r.IsValid | Should -BeTrue
            $r.Domain  | Should -Be 'CONTOSO'
            $r.Account | Should -Be 'jdoe'
        }
    }

    It 'parses a plain DOMAIN\user login' {
        InModuleScope SPSUserSync.Common {
            $r = ConvertFrom-SPSUserLogin -UserLogin 'CONTOSO\admin'
            $r.IsValid | Should -BeTrue
            $r.Domain  | Should -Be 'CONTOSO'
            $r.Account | Should -Be 'admin'
        }
    }

    It 'marks a claim without a backslash as invalid' {
        InModuleScope SPSUserSync.Common {
            (ConvertFrom-SPSUserLogin -UserLogin 'c:0(.s|true').IsValid | Should -BeFalse
        }
    }

    It 'marks an empty login as invalid' {
        InModuleScope SPSUserSync.Common {
            (ConvertFrom-SPSUserLogin -UserLogin '').IsValid | Should -BeFalse
        }
    }

    It 'honors a custom claim prefix' {
        InModuleScope SPSUserSync.Common {
            $r = ConvertFrom-SPSUserLogin -UserLogin 'x:y|FABRIKAM\bob' -ClaimPrefix 'x:y|'
            $r.Domain  | Should -Be 'FABRIKAM'
            $r.Account | Should -Be 'bob'
        }
    }
}

Describe 'ConvertTo-SPSHtmlEncoded' {
    It 'encodes the five significant HTML characters' {
        InModuleScope SPSUserSync.Common {
            ConvertTo-SPSHtmlEncoded -Value '&'  | Should -Be '&amp;'
            ConvertTo-SPSHtmlEncoded -Value '<'  | Should -Be '&lt;'
            ConvertTo-SPSHtmlEncoded -Value '>'  | Should -Be '&gt;'
            ConvertTo-SPSHtmlEncoded -Value '"'  | Should -Be '&quot;'
            ConvertTo-SPSHtmlEncoded -Value "'"  | Should -Be '&#39;'
        }
    }

    It 'neutralizes a script breakout sequence' {
        InModuleScope SPSUserSync.Common {
            ConvertTo-SPSHtmlEncoded -Value '</script>' | Should -Be '&lt;/script&gt;'
        }
    }

    It 'returns an empty string for null or empty input' {
        InModuleScope SPSUserSync.Common {
            ConvertTo-SPSHtmlEncoded -Value ''   | Should -Be ''
            ConvertTo-SPSHtmlEncoded -Value $null | Should -Be ''
        }
    }

    It 'leaves plain text unchanged' {
        InModuleScope SPSUserSync.Common {
            ConvertTo-SPSHtmlEncoded -Value 'DOE John' | Should -Be 'DOE John'
        }
    }
}

Describe 'Get-SPSJsonRecordCount' {
    It 'returns null when the file does not exist' {
        InModuleScope SPSUserSync.Common -Parameters @{ Drive = $TestDrive } {
            param($Drive)
            Get-SPSJsonRecordCount -Path (Join-Path $Drive 'nope.json') | Should -BeNullOrEmpty
        }
    }

    It 'returns 0 for an empty array' {
        InModuleScope SPSUserSync.Common -Parameters @{ Drive = $TestDrive } {
            param($Drive)
            $p = Join-Path $Drive 'empty.json'
            '[]' | Set-Content -Path $p -Encoding UTF8
            Get-SPSJsonRecordCount -Path $p | Should -Be 0
        }
    }

    It 'counts the records in an array' {
        InModuleScope SPSUserSync.Common -Parameters @{ Drive = $TestDrive } {
            param($Drive)
            $p = Join-Path $Drive 'three.json'
            (1..3 | ForEach-Object { [pscustomobject]@{ n = $_ } }) | ConvertTo-Json | Set-Content -Path $p -Encoding UTF8
            Get-SPSJsonRecordCount -Path $p | Should -Be 3
        }
    }

    It 'counts a single object as 1' {
        InModuleScope SPSUserSync.Common -Parameters @{ Drive = $TestDrive } {
            param($Drive)
            $p = Join-Path $Drive 'single.json'
            ([pscustomobject]@{ n = 1 }) | ConvertTo-Json | Set-Content -Path $p -Encoding UTF8
            Get-SPSJsonRecordCount -Path $p | Should -Be 1
        }
    }

    It 'returns 0 for invalid JSON' {
        InModuleScope SPSUserSync.Common -Parameters @{ Drive = $TestDrive } {
            param($Drive)
            $p = Join-Path $Drive 'bad.json'
            'not json {' | Set-Content -Path $p -Encoding UTF8
            Get-SPSJsonRecordCount -Path $p | Should -Be 0
        }
    }
}
