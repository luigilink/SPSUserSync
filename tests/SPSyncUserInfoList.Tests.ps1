# Regression tests for SPSyncUserInfoList.ps1 hardening (issue #16).
#
# SPSyncUserInfoList.ps1 has a Main region that needs a live SharePoint farm, so
# we never run the whole script. Instead we extract just the classes and the two
# internal functions via the PowerShell AST and dot-source them, then exercise
# Get-SPSUniqueUsers against mocked SharePoint / AD commands. The focus is the
# v1.3.1 hardening: a failed or empty run must NOT write a JSON snapshot, must
# surface the error, and must report failure to the Main region so the report and
# the remote copy are skipped.
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $scriptPath = Join-Path -Path $repoRoot -ChildPath 'src/SPSyncUserInfoList.ps1'

    $tokens = $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)

    # Dot-source the [SPSiteUser] / [SPSDeletedUser] classes and the two internal
    # functions, without executing the Main region.
    $classAsts = $ast.FindAll({
            param($node) $node -is [System.Management.Automation.Language.TypeDefinitionAst]
        }, $true)
    foreach ($classAst in $classAsts) {
        . ([scriptblock]::Create($classAst.Extent.Text))
    }
    foreach ($fnName in 'Test-SPSUserExcluded', 'Get-SPSUniqueUsers') {
        $fnAst = $ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq $fnName
            }, $true)
        . ([scriptblock]::Create($fnAst.Extent.Text))
    }

    # Stub the SharePoint / module commands the function calls so they can be mocked.
    function Get-SPSite { param($Limit, $ErrorAction) }
    function Set-SPUser { }
    function Remove-SPUser { }
    function Get-SPSADUser { param($UserLogin) }
    function ConvertTo-SPSUserRecord { param($UserLogin, $AdUser) }
    function Resolve-SPSADUserBatch { param($UserLogin, $ThrottleLimit) }
    function Add-SPSUserSyncEvent { param($Message, $Source, $EntryType, $EventID) }

    function New-MockSite {
        param($Url, $Users)
        [PSCustomObject]@{ RootWeb = [PSCustomObject]@{ Url = $Url; SiteUsers = $Users } }
    }
    function New-MockUser {
        param($UserLogin, $DisplayName, $Email)
        [PSCustomObject]@{ UserLogin = $UserLogin; DisplayName = $DisplayName; Email = $Email }
    }
}

Describe 'Get-SPSUniqueUsers hardening (issue #16)' {
    BeforeEach {
        $script:jsonPath = Join-Path ([System.IO.Path]::GetTempPath()) ("spsus-{0}.json" -f ([guid]::NewGuid()))
        $script:delPath  = Join-Path ([System.IO.Path]::GetTempPath()) ("spsusdel-{0}.json" -f ([guid]::NewGuid()))
        $script:settings = @{ ClaimPrefix = 'i:0#.w|' }
    }
    AfterEach {
        Remove-Item -Path $script:jsonPath, $script:delPath -Force -ErrorAction SilentlyContinue
    }

    It 'writes the JSON snapshot and reports success on a healthy farm' {
        Mock Get-SPSite {
            , @(New-MockSite -Url 'https://wfe1' -Users @(
                    New-MockUser 'ZEBES\alice' 'Alice Keller' 'alice@zebes.chozo'
                    New-MockUser 'ZEBES\bob'   'Bob Stone'    'bob@zebes.chozo'
                ))
        }
        Mock Get-SPSADUser { [PSCustomObject]@{ sAMAccountName = 'x' } }
        Mock ConvertTo-SPSUserRecord {
            [PSCustomObject]@{ DisplayName = 'Resolved Name'; FirstName = 'F'; LastName = 'L'; Email = 'r@zebes.chozo'; Location = 'Paris'; Country = 'FR' }
        }
        Mock Add-SPSUserSyncEvent { }

        Get-SPSUniqueUsers -Settings $script:settings -JsonFilePath $script:jsonPath -DeletedJsonFilePath $script:delPath 6>$null | Out-Null

        $script:GetSPSUniqueUsersSucceeded | Should -BeTrue
        Test-Path -Path $script:jsonPath | Should -BeTrue
        Should -Not -Invoke Add-SPSUserSyncEvent
    }

    It 'does NOT write a JSON snapshot and raises an Error event when zero users are collected' {
        # An empty farm result is treated as a failure (almost always a rights
        # problem), never overwriting the previous good file with an empty one.
        Mock Get-SPSite { , @(New-MockSite -Url 'https://wfe1' -Users @()) }
        Mock Get-SPSADUser { }
        Mock ConvertTo-SPSUserRecord { }
        Mock Add-SPSUserSyncEvent { }

        Get-SPSUniqueUsers -Settings $script:settings -JsonFilePath $script:jsonPath -DeletedJsonFilePath $script:delPath 6>$null 2>$null | Out-Null

        $script:GetSPSUniqueUsersSucceeded | Should -BeFalse
        Test-Path -Path $script:jsonPath | Should -BeFalse
        Should -Invoke Add-SPSUserSyncEvent -Times 1 -ParameterFilter { $EntryType -eq 'Error' }
    }

    It 'surfaces an actionable ACCESS_DENIED error, writes no JSON, and reports failure' {
        # Get-SPSite returns a lazy collection; the real farm throws ACCESS_DENIED
        # while enumerating it. The hardened catch must classify it, point at the
        # Shell Admin / service account, and leave the success flag $false.
        Mock Get-SPSite { throw [System.UnauthorizedAccessException]::new('Access is denied. (E_ACCESSDENIED 0x80070005)') }
        Mock Add-SPSUserSyncEvent { }

        Get-SPSUniqueUsers -Settings $script:settings -JsonFilePath $script:jsonPath -DeletedJsonFilePath $script:delPath 6>$null 2>$null | Out-Null

        $script:GetSPSUniqueUsersSucceeded | Should -BeFalse
        Test-Path -Path $script:jsonPath | Should -BeFalse
        Should -Invoke Add-SPSUserSyncEvent -Times 1 -ParameterFilter {
            $EntryType -eq 'Error' -and $Message -match 'Shell Admin'
        }
    }
}