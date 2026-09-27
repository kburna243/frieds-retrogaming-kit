# Arcade common: state paths, RetroBat root resolution across packages, adapter file targets.

function Get-ArcadeDefaultStatePath {
    [CmdletBinding()]
    param()
    Join-Path $script:ArcadeDir 'install-state.json'
}

# The arcade step needs the same RetroBat folder the lightgun suite already found: arcade state first,
# then the lightgun state — one cabinet, one RetroBat, no second discovery.
function Get-ArcadeRetroBatRoot {
    [CmdletBinding()]
    param([string] $StatePath = (Get-ArcadeDefaultStatePath))
    $root = [string](Get-KitStateValue -Path $StatePath -Key 'RetroBatRoot')
    if (-not $root) { $root = [string](Get-KitStateValue -Path (Get-LightgunDefaultStatePath) -Key 'RetroBatRoot') }
    $root
}

function Get-ArcadeAdapterDir {
    [CmdletBinding()]
    param()
    Join-Path $script:ArcadeDir 'adapters'
}

# Which cabinet files an arcade adapter may touch. Paths come from lightgun's own resolvers
# (Get-LightgunAdapterFiles, Get-LightgunModel2Path) so mame.ini, retrobat.ini, Emulator.ini and
# Supermodel.ini mean exactly the same file as in the lightgun suite. Every entry is $null when the
# file is absent, and the configuration writes only into files that actually exist.
function Get-ArcadeAdapterFiles {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RetroBatRoot)
    $gun = Get-LightgunAdapterFiles -RetroBatRoot $RetroBatRoot
    $m2  = Get-LightgunModel2Path -RetroBatRoot $RetroBatRoot
    [pscustomobject]@{
        MameIni       = $gun.MameIni
        RetroBatIni   = $gun.RetroBatIni
        Model2Ini     = if (Test-Path -LiteralPath $m2.Model2Ini -PathType Leaf) { $m2.Model2Ini } else { $null }
        SupermodelIni = if (Test-Path -LiteralPath $m2.SupermodelIni -PathType Leaf) { $m2.SupermodelIni } else { $null }
    }
}
