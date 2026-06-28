# Behavior tests for Export-SPSUserReport, including HTML-injection safety.
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $modulePath = Join-Path -Path $repoRoot -ChildPath 'src/Modules/SPSUserSync.Common/SPSUserSync.Common.psd1'
    Import-Module -Name $modulePath -Force
}

Describe 'Export-SPSUserReport (UserInfoList)' {
    BeforeAll {
        $records = @(
            [pscustomobject]@{ UserLogin = 'i:0#.w|CONTOSO\jdoe';  DisplayName = 'DOE John';      Email = 'john.doe@contoso.com'; Country = 'FR' }
            [pscustomobject]@{ UserLogin = 'i:0#.w|CONTOSO\hmar';  DisplayName = 'MARTIN Helene';  Email = 'h.martin@contoso.com';  Country = 'FR' }
            [pscustomobject]@{ UserLogin = 'i:0#.w|FABRIKAM\nom';  DisplayName = 'NO Email';        Email = '';                     Country = 'US' }
        )
        $output = Join-Path $TestDrive 'info.html'
        $null = Export-SPSUserReport -InputObject $records -ReportType 'UserInfoList' -OutputFile $output -EnvName 'PROD' -AppCode 'CONTOSO' -Version '1.1.0'
        $html = Get-Content -Path $output -Raw
    }

    It 'writes the output file' {
        Test-Path $output | Should -BeTrue
    }

    It 'includes the report title' {
        $html | Should -BeLike '*User Information List Report*'
    }

    It 'includes the metadata line with environment and app code' {
        $html | Should -BeLike '*Environment: PROD*'
        $html | Should -BeLike '*AppCode: CONTOSO*'
    }

    It 'computes the email coverage cards' {
        # 3 total, 2 with email, 1 without
        $html | Should -BeLike '*Total users*'
        $html | Should -BeLike '*With email*'
        $html | Should -BeLike '*Without email*'
    }

    It 'embeds the dataset for the interactive table' {
        $html | Should -BeLike '*id="spsReportData"*'
        $html | Should -BeLike '*john.doe@contoso.com*'
    }

    It 'does not flag any row when every user resolved from AD' {
        # jdoe / hmar have real display names; "NO Email" differs from its login,
        # so none of the three is unresolved (no flagged row in the payload).
        $html | Should -Not -BeLike '*"_flag":"unresolved"*'
    }
}

Describe 'Export-SPSUserReport unresolved flagging (UserInfoList)' {
    BeforeAll {
        $records = @(
            [pscustomobject]@{ UserLogin = 'i:0#.w|CONTOSO\jdoe';   DisplayName = 'DOE John';    Email = 'john.doe@contoso.com'; Country = 'FR' }
            [pscustomobject]@{ UserLogin = 'CONTOSO\svc';           DisplayName = 'CONTOSO\svc'; Email = '';                     Country = '' }
            [pscustomobject]@{ UserLogin = 'i:0#.w|CONTOSO\bob';    DisplayName = 'CONTOSO\bob'; Email = '';                     Country = '' }
            [pscustomobject]@{ UserLogin = 'i:0#.w|CONTOSO\noname'; DisplayName = '';            Email = '';                     Country = '' }
        )
        $output = Join-Path $TestDrive 'flag.html'
        $null = Export-SPSUserReport -InputObject $records -ReportType 'UserInfoList' -OutputFile $output -ClaimPrefix 'i:0#.w|'
        $html = Get-Content -Path $output -Raw
    }

    It 'adds an Unresolved summary card' {
        $html | Should -BeLike '*Unresolved*'
    }

    It 'renders the Unresolved card with the warn tone' {
        # 3 of 4 records (svc, bob, noname) are unresolved, so the card is amber.
        $html | Should -BeLike '*class="card warn"*'
    }

    It 'flags the unresolved rows in the embedded payload' {
        $html | Should -BeLike '*"_flag":"unresolved"*'
    }

    It 'counts every unresolved form, including a de-claimed login match' {
        # svc (classic == login), bob (claims, de-claimed == display) and noname
        # (empty display) are unresolved; jdoe is not. The card value proves the
        # de-claim comparison caught bob -> exactly 3.
        $html | Should -BeLike '*>3</div><div class="card-label">Unresolved</div>*'
    }

    It 'shows the legend note referencing the removal setting' {
        $html | Should -BeLike '*highlighted below*'
        $html | Should -BeLike '*RemoveUnresolvableUsers*'
    }
}

Describe 'Export-SPSUserReport (UserProfile)' {
    It 'renders a card per status' {
        $records = @(
            [pscustomobject]@{ AccountName = 'CONTOSO\jdoe'; Status = 'UPDATE';       WorkEmail = 'a@contoso.com'; Date = '20260626T130000' }
            [pscustomobject]@{ AccountName = 'CONTOSO\hmar'; Status = 'CREATE';       WorkEmail = 'b@contoso.com'; Date = '20260626T130001' }
            [pscustomobject]@{ AccountName = 'FABRIKAM\gh';  Status = 'UNKNOWN_USER'; WorkEmail = '';              Date = '20260626T130002' }
        )
        $output = Join-Path $TestDrive 'profile.html'
        $null = Export-SPSUserReport -InputObject $records -ReportType 'UserProfile' -OutputFile $output

        $html = Get-Content -Path $output -Raw
        $html | Should -BeLike '*Reconciliation Report*'
        $html | Should -BeLike '*Total processed*'
        $html | Should -BeLike '*UNKNOWN_USER*'
        # The UNKNOWN_USER row is highlighted via the shared _flag mechanism.
        $html | Should -BeLike '*"_flag":"unresolved"*'
    }

    It 'produces a valid file even for an empty dataset' {
        $output = Join-Path $TestDrive 'empty.html'
        $null = Export-SPSUserReport -InputObject @() -ReportType 'UserProfile' -OutputFile $output
        Test-Path $output | Should -BeTrue
        (Get-Content -Path $output -Raw) | Should -BeLike '*Total processed*'
    }
}

Describe 'Export-SPSUserReport HTML-injection safety' {
    It 'does not emit an executable script breakout from a malicious DisplayName' {
        $records = @(
            [pscustomobject]@{ UserLogin = 'i:0#.w|FABRIKAM\evil'; DisplayName = '</script><script>alert(1)</script>'; Email = 'evil@fabrikam.com'; Country = 'US' }
        )
        $output = Join-Path $TestDrive 'xss.html'
        $null = Export-SPSUserReport -InputObject $records -ReportType 'UserInfoList' -OutputFile $output
        $html = Get-Content -Path $output -Raw

        # The raw breakout sequence must not survive into the document...
        $html | Should -Not -BeLike '*</script><script>alert(1)</script>*'
        # ...but its neutralized form must be present in the embedded data block.
        $html | Should -BeLike '*\u003cscript\u003ealert(1)*'
    }
}
