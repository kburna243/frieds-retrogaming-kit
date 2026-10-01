function Get-FrontendsAdapterDir {
    Join-Path $script:FrontendsDir 'adapters'
}

function Get-FrontendsDefaultStatePath {
    Join-Path $script:FrontendsDir 'state.json'
}

function Get-FrontendsRetroBatRoot {
    $retroBatPath = $env:RETROBAT_PATH
    if (-not $retroBatPath) {
        $retroBatPath = Join-Path $script:KitRoot '..\RetroBat'
    }
    return $retroBatPath
}

function Get-FrontendSystemSnapshot {
    [CmdletBinding()]
    param([string] $RetroBatRoot = '')
    @{
        Processes  = @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $_.Name.ToLowerInvariant() })
        Ports      = @(try { @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | ForEach-Object { [int]$_.LocalPort }) } catch { @() })
        Frontends  = @(Get-ChildItem -Path $RetroBatRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -in @('emulators', 'roms', 'frontends') } | ForEach-Object { $_.FullName })
        Root       = $RetroBatRoot
    }
}

function Get-FrontendInstallPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RetroBatRoot,
        [Parameter(Mandatory)] [string] $FrontendName
    )
    $fePath = Join-Path $RetroBatRoot "frontends\$FrontendName"
    if (Test-Path -LiteralPath $fePath -PathType Container) { return $fePath }
    $fePath = Join-Path $RetroBatRoot "tools\$FrontendName"
    if (Test-Path -LiteralPath $fePath -PathType Container) { return $fePath }
    ''
}

function Get-FrontendExecutable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $FrontendPath,
        [Parameter(Mandatory)] [string[]] $ExeNames
    )
    foreach ($name in $ExeNames) {
        $exe = Join-Path $FrontendPath $name
        if (Test-Path -LiteralPath $exe -PathType Leaf) { return $exe }
    }
    ''
}

function Get-FrontendChecksum {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLower()
}

# Genre-routing map: which emulator for which system in which frontend
function Get-FrontendGenreRouting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $FrontendName,
        [string] $RetroBatRoot = ''
    )
    # Standard RetroBat system-to-emulator mapping (extensible per frontend)
    $routing = [ordered]@{
        'arcade'      = @{ emulator = 'MAME'; core = '' }
        'mame'        = @{ emulator = 'MAME'; core = '' }
        'model2'      = @{ emulator = 'Model2'; core = '' }
        'model3'      = @{ emulator = 'Supermodel'; core = '' }
        'teknoparrot' = @{ emulator = 'TeknoParrot'; core = '' }
        'naomi'       = @{ emulator = 'RetroArch'; core = 'flycast' }
        'dreamcast'   = @{ emulator = 'RetroArch'; core = 'flycast' }
        'psx'         = @{ emulator = 'DuckStation'; core = '' }
        'ps2'         = @{ emulator = 'PCSX2'; core = '' }
        'ps3'         = @{ emulator = 'RPCS3'; core = '' }
        'wii'         = @{ emulator = 'Dolphin'; core = '' }
        'gamecube'    = @{ emulator = 'Dolphin'; core = '' }
        'wiiu'        = @{ emulator = 'Cemu'; core = '' }
        'xbox'        = @{ emulator = 'Xemu'; core = '' }
        'snes'        = @{ emulator = 'RetroArch'; core = 'snes9x' }
        'nes'         = @{ emulator = 'RetroArch'; core = 'fceumm' }
        'genesis'     = @{ emulator = 'RetroArch'; core = 'genesis_plus_gx' }
        'n64'         = @{ emulator = 'RetroArch'; core = 'mupen64plus' }
        'gb'          = @{ emulator = 'RetroArch'; core = 'gambatte' }
        'gba'         = @{ emulator = 'RetroArch'; core = 'mgba' }
    }
    $routing
}