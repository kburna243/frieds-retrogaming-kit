# Pads common: state path, RetroBat root resolution across packages, the (single) cabinet file pads writes.

function Get-PadDefaultStatePath {
    [CmdletBinding()]
    param()
    Join-Path $script:PadsDir 'install-state.json'
}

# One cabinet, one RetroBat: pads reads its own state key first, then falls back to the lightgun state
# exactly like the arcade package does. No second discovery, no guessing of a RetroBat folder.
function Get-PadRetroBatRoot {
    [CmdletBinding()]
    param([string] $StatePath = (Get-PadDefaultStatePath))
    $root = [string](Get-KitStateValue -Path $StatePath -Key 'RetroBatRoot')
    if (-not $root) { $root = [string](Get-KitStateValue -Path (Get-LightgunDefaultStatePath) -Key 'RetroBatRoot') }
    $root
}

function Get-PadAdapterDir {
    [CmdletBinding()]
    param()
    Join-Path $script:PadsDir 'adapters'
}

# The files a pad may touch. Deliberately ONE entry: a gamepad needs no emulator-side configuration,
# RetroBat's own controller auto-mapping (retrobat.ini [Controllers]) decides whether pads are used at
# all. mame.ini / Emulator.ini / Supermodel.ini stay with the arcade package, where the devices that
# need them live - writing them from here would be a second, uncoordinated opinion about the same keys.
# The path is resolved through lightgun's own resolver, so "retrobat.ini" means the same file as in the
# lightgun and arcade suites. Existence is checked here (NOT like arcade's mame.ini handling, which
# passes the joined path through): pads never creates a cabinet file, a missing retrobat.ini is a
# warning and zero changes, never a new file with invented content.
function Get-PadAdapterFiles {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RetroBatRoot)
    $gun = Get-LightgunAdapterFiles -RetroBatRoot $RetroBatRoot
    [pscustomobject]@{
        RetroBatIni = if (Test-Path -LiteralPath $gun.RetroBatIni -PathType Leaf) { $gun.RetroBatIni } else { $null }
    }
}
