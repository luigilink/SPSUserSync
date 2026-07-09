# Regression tests for SPSyncUserProfile.ps1 internal functions.
#
# Add-SPSUserProfile is a script-internal function, so we extract it from the
# script via the PowerShell AST and dot-source just that function definition,
# without running the script's Main region (which needs a live SharePoint farm).
BeforeAll {
    $repoRoot   = Split-Path -Path $PSScriptRoot -Parent
    $scriptPath = Join-Path -Path $repoRoot -ChildPath 'src/SPSyncUserProfile.ps1'

    $tokens = $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
    foreach ($fnName in 'Add-SPSUserProfile', 'Split-SPSProfileUser') {
        $fnAst = $ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq $fnName
            }, $true)
        . ([scriptblock]::Create($fnAst.Extent.Text))
    }

    function New-JsonUser {
        param($UserLogin, $FirstName, $LastName, $Email, $AccountStatus)
        $o = [PSCustomObject]@{
            UserLogin = $UserLogin; DisplayName = "$FirstName $LastName"
            FirstName = $FirstName; LastName = $LastName; Email = $Email
            Location  = 'PARIS'; Country = 'FR'
        }
        if ($PSBoundParameters.ContainsKey('AccountStatus')) {
            $o | Add-Member -NotePropertyName 'AccountStatus' -NotePropertyValue $AccountStatus
        }
        $o
    }
}

Describe 'Add-SPSUserProfile parameter contract' {
    It 'declares ResultCollection as mandatory' {
        $p = (Get-Command Add-SPSUserProfile).Parameters['ResultCollection']
        $attr = $p.Attributes.Where{ $_ -is [System.Management.Automation.ParameterAttribute] }[0]
        $attr.Mandatory | Should -BeTrue
    }

    It 'allows an empty ResultCollection (regression: empty ArrayList on first loop pass)' {
        # A mandatory parameter rejects an empty collection unless AllowEmptyCollection
        # is present. Without it, the first eligible user threw a terminating binding
        # error ("Cannot bind argument to parameter 'ResultCollection' because it is an
        # empty collection.") that aborted the whole foreach, so no user was processed.
        $p = (Get-Command Add-SPSUserProfile).Parameters['ResultCollection']
        $hasAllowEmpty = [bool]($p.Attributes | Where-Object { $_ -is [System.Management.Automation.AllowEmptyCollectionAttribute] })
        $hasAllowEmpty | Should -BeTrue
    }
}

Describe 'Split-SPSProfileUser' {
    It 'routes a fully-resolved active user to Eligible' {
        $res = Split-SPSProfileUser -User @(New-JsonUser 'ZEBES\a' 'Ann' 'Fox' 'ann@x' 'Active')
        $res.Eligible.Count | Should -Be 1
        $res.NotAdded.Count | Should -Be 0
    }

    It 'routes a user missing Email to NotAdded with reason MISSING_ATTRIBUTES' {
        $res = Split-SPSProfileUser -User @(New-JsonUser 'ZEBES\a' 'Ann' 'Fox' '' 'Active')
        $res.Eligible.Count            | Should -Be 0
        $res.NotAdded.Count            | Should -Be 1
        $res.NotAdded[0].NotAddedReason | Should -Be 'MISSING_ATTRIBUTES'
    }

    It 'tags an unresolved (empty-attribute, NotFound) user as AD_NOT_FOUND' {
        $res = Split-SPSProfileUser -User @(New-JsonUser 'ZEBES\ghost' '' '' '' 'NotFound')
        $res.NotAdded.Count             | Should -Be 1
        $res.NotAdded[0].NotAddedReason | Should -Be 'AD_NOT_FOUND'
    }

    It 'provisions a disabled-but-complete user by default (SkipDisabledUsers = $false)' {
        $res = Split-SPSProfileUser -User @(New-JsonUser 'ZEBES\d' 'Dan' 'Vega' 'dan@x' 'Disabled')
        $res.Eligible.Count | Should -Be 1
        $res.NotAdded.Count | Should -Be 0
    }

    It 'skips a disabled user and tags it DISABLED when SkipDisabledUsers = $true' {
        $res = Split-SPSProfileUser -User @(New-JsonUser 'ZEBES\d' 'Dan' 'Vega' 'dan@x' 'Disabled') -SkipDisabledUsers $true
        $res.Eligible.Count             | Should -Be 0
        $res.NotAdded.Count             | Should -Be 1
        $res.NotAdded[0].NotAddedReason | Should -Be 'DISABLED'
    }

    It 'still provisions active users when SkipDisabledUsers = $true' {
        $res = Split-SPSProfileUser -User @(
            New-JsonUser 'ZEBES\a' 'Ann' 'Fox'  'ann@x' 'Active'
            New-JsonUser 'ZEBES\d' 'Dan' 'Vega' 'dan@x' 'Disabled'
        ) -SkipDisabledUsers $true
        $res.Eligible.Count             | Should -Be 1
        $res.Eligible[0].UserLogin      | Should -Be 'ZEBES\a'
        $res.NotAdded[0].NotAddedReason | Should -Be 'DISABLED'
    }

    It 'is backward compatible with pre-1.3.3 snapshots (no AccountStatus) even with SkipDisabledUsers = $true' {
        # Old JSON has no AccountStatus property: a complete user must still be
        # provisioned (never mistaken for disabled).
        $res = Split-SPSProfileUser -User @(New-JsonUser 'ZEBES\a' 'Ann' 'Fox' 'ann@x') -SkipDisabledUsers $true
        $res.Eligible.Count | Should -Be 1
        $res.NotAdded.Count | Should -Be 0
    }

    It 'accepts an empty input set' {
        $res = Split-SPSProfileUser -User @() -SkipDisabledUsers $true
        $res.Eligible.Count | Should -Be 0
        $res.NotAdded.Count | Should -Be 0
    }
}
