function Get-SPSConfigRoot {
    <#
        .SYNOPSIS
        Resolves the default location of the config folder.

        .DESCRIPTION
        The config folder lives in src/config/, one level up from the module
        root. This helper centralizes that path resolution so every
        Get-SPS*Config function uses the same default.

        Callers can always override by passing -ConfigPath to the public
        accessors (Get-SPSSyncSetting, Get-SPSADConnection, ...). The helper
        result is not cached: it is cheap and the override would otherwise
        be ignored.

        .EXAMPLE
        Get-SPSConfigRoot
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param ()

    if ([string]::IsNullOrEmpty($script:ModuleRoot)) {
        throw "Module is not loaded correctly: `$script:ModuleRoot is not set. Re-import SPSUserSync.Common."
    }

    $srcRoot = Split-Path -Parent (Split-Path -Parent $script:ModuleRoot)
    return Join-Path -Path $srcRoot -ChildPath 'config'
}
