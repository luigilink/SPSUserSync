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
    $fnAst = $ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -eq 'Add-SPSUserProfile'
        }, $true)
    . ([scriptblock]::Create($fnAst.Extent.Text))
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
