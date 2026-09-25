# DuckStation & PCSX2 guided audit (step 14) [W6]:
#   No automated binding: guided check and report only.
#   Guide text: Automatic Mapping to XInput-0 in the emulator GUI, then audit existing settings.
#   Konami games note: Die Hard Trilogy (SLUS-00119) and Crypt Killer (SLUS-00335) do NOT support GunCon,
#   they require Justifier (Pointer-0, Trigger=XInput-0/B, ShootOffscreen=XInput-0/A).
#   Flycast remains omitted [W9] (Flycast only supports raw mouse, no pad axes, DemulShooter only outputs).

function Get-LightgunDuckStationPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RetroBatRoot)
    $dsDir = Join-Path $RetroBatRoot 'emulators\duckstation'
    $pcsx2Dir = Join-Path $RetroBatRoot 'emulators\pcsx2'
    $pcsx2Ini = Join-Path $pcsx2Dir 'inis\PCSX2.ini'
    if (-not (Test-Path -LiteralPath $pcsx2Ini -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $pcsx2Dir 'PCSX2.ini') -PathType Leaf)) {
        $pcsx2Ini = Join-Path $pcsx2Dir 'PCSX2.ini'
    }
    [pscustomobject]@{
        DuckStationDir         = $dsDir
        DuckStationSettings    = Join-Path $dsDir 'settings.ini'
        DuckStationGameSettings = Join-Path $dsDir 'gamesettings'
        Pcsx2Dir               = $pcsx2Dir
        Pcsx2Ini               = $pcsx2Ini
    }
}

# Audits DuckStation settings.ini and per-game settings for Konami lightgun games.
function Get-LightgunDuckStationAudit {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RetroBatRoot)
    $paths = Get-LightgunDuckStationPath -RetroBatRoot $RetroBatRoot
    $hasSettings = Test-Path -LiteralPath $paths.DuckStationSettings -PathType Leaf

    $pad1Type = $null; $pad2Type = $null
    $rawInput = $null
    $pad1Trigger = $null; $pad2Trigger = $null

    if ($hasSettings) {
        $currentSec = $null
        foreach ($line in [IO.File]::ReadAllLines($paths.DuckStationSettings)) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^\[([^\]]+)\]') { $currentSec = $Matches[1].Trim(); continue }
            $eq = $trimmed.IndexOf('=')
            if ($eq -gt 0) {
                $k = $trimmed.Substring(0, $eq).Trim()
                $v = $trimmed.Substring($eq + 1).Trim()
                if ($currentSec -eq 'InputSources' -and $k -eq 'RawInput') { $rawInput = $v }
                if ($currentSec -eq 'Pad1' -and $k -eq 'Type') { $pad1Type = $v }
                if ($currentSec -eq 'Pad2' -and $k -eq 'Type') { $pad2Type = $v }
                if ($currentSec -eq 'Pad1' -and $k -eq 'Trigger') { $pad1Trigger = $v }
                if ($currentSec -eq 'Pad2' -and $k -eq 'Trigger') { $pad2Trigger = $v }
            }
        }
    }

    # Konami games check: Die Hard Trilogy (SLUS-00119), Crypt Killer (SLUS-00335)
    $konamiGames = @(
        @{ Serial = 'SLUS-00119'; Title = 'Die Hard Trilogy' },
        @{ Serial = 'SLUS-00335'; Title = 'Crypt Killer' }
    )
    $konamiAudit = New-Object Collections.Generic.List[object]
    foreach ($g in $konamiGames) {
        $ini = Join-Path $paths.DuckStationGameSettings "$($g.Serial).ini"
        $hasIni = Test-Path -LiteralPath $ini -PathType Leaf
        $usesJustifier = $false
        $useGameSettings = $false
        if ($hasIni) {
            $cSec = $null
            foreach ($line in [IO.File]::ReadAllLines($ini)) {
                $trimmed = $line.Trim()
                if ($trimmed -match '^\[([^\]]+)\]') { $cSec = $Matches[1].Trim(); continue }
                $eq = $trimmed.IndexOf('=')
                if ($eq -gt 0) {
                    $k = $trimmed.Substring(0, $eq).Trim()
                    $v = $trimmed.Substring($eq + 1).Trim()
                    if ($cSec -eq 'ControllerPorts' -and $k -eq 'UseGameSettingsForController' -and $v -eq 'true') { $useGameSettings = $true }
                    if ($cSec -match '^Pad' -and $k -eq 'Type' -and $v -eq 'Justifier') { $usesJustifier = $true }
                }
            }
        }
        $konamiAudit.Add([pscustomobject]@{
            Serial          = $g.Serial
            Title           = $g.Title
            HasGameSettings = $hasIni
            UsesJustifier   = $usesJustifier
            Valid           = $hasIni -and $useGameSettings -and $usesJustifier
        })
    }

    [pscustomobject]@{
        DuckStationFound = Test-Path -LiteralPath $paths.DuckStationDir -PathType Container
        HasSettings      = $hasSettings
        Pad1Type         = $pad1Type
        Pad2Type         = $pad2Type
        Pad1Trigger      = $pad1Trigger
        Pad2Trigger      = $pad2Trigger
        RawInput         = $rawInput
        KonamiAudit      = $konamiAudit.ToArray()
    }
}

# Audits PCSX2 configuration.
function Get-LightgunPcsx2Audit {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RetroBatRoot)
    $paths = Get-LightgunDuckStationPath -RetroBatRoot $RetroBatRoot
    $hasIni = Test-Path -LiteralPath $paths.Pcsx2Ini -PathType Leaf

    $hasGunCon2 = $false
    if ($hasIni) {
        $content = [IO.File]::ReadAllText($paths.Pcsx2Ini)
        if ($content -match '(?i)guncon|pointer-') { $hasGunCon2 = $true }
    }

    [pscustomobject]@{
        Pcsx2Found  = Test-Path -LiteralPath $paths.Pcsx2Dir -PathType Container
        HasIni      = $hasIni
        IniPath     = $paths.Pcsx2Ini
        HasGunCon2  = $hasGunCon2
    }
}
