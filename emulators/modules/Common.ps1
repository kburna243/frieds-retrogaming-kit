function Get-EmulatorsAdapterDir {
    Join-Path $script:EmulatorsDir 'adapters'
}

function Get-EmulatorsDefaultStatePath {
    Join-Path $script:EmulatorsDir 'state.json'
}

function Get-EmulatorsRetroBatRoot {
    $retroBatPath = $env:RETROBAT_PATH
    if (-not $retroBatPath) {
        $retroBatPath = Join-Path $script:KitRoot '..\RetroBat'
    }
    return $retroBatPath
}

function Get-EmulatorSystemSnapshot {
    [CmdletBinding()]
    param([string] $RetroBatRoot = '')
    @{
        Processes = @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $_.Name.ToLowerInvariant() })
        Ports     = @(try { @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | ForEach-Object { [int]$_.LocalPort }) } catch { @() })
        Emulators = @(Get-ChildItem -Path $RetroBatRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -in @('emulators', 'roms') } | ForEach-Object { $_.FullName })
        Root      = $RetroBatRoot
    }
}

function Get-EmulatorInstallPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RetroBatRoot,
        [Parameter(Mandatory)] [string] $EmulatorName
    )
    # Standard RetroBat layout: emulators/<name>/ or roms/<system>/
    $emuPath = Join-Path $RetroBatRoot "emulators\$EmulatorName"
    if (Test-Path -LiteralPath $emuPath -PathType Container) { return $emuPath }
    # Fallback: check roms subfolders for emulator-specific configs
    $romsPath = Join-Path $RetroBatRoot 'roms'
    if (Test-Path -LiteralPath $romsPath -PathType Container) {
        $matches = @(Get-ChildItem -LiteralPath $romsPath -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "*$EmulatorName*" })
        if ($matches.Count) { return $matches[0].FullName }
    }
    ''
}

function Get-EmulatorConfigPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RetroBatRoot,
        [Parameter(Mandatory)] [string] $EmulatorName,
        [string] $ConfigFile = ''
    )
    $emuPath = Get-EmulatorInstallPath -RetroBatRoot $RetroBatRoot -EmulatorName $EmulatorName
    if (-not $emuPath) { return '' }
    if ($ConfigFile) {
        $cfg = Join-Path $emuPath $ConfigFile
        if (Test-Path -LiteralPath $cfg -PathType Leaf) { return $cfg }
    }
    $emuPath
}

function Get-EmulatorExecutable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $EmulatorPath,
        [Parameter(Mandatory)] [string[]] $ExeNames
    )
    foreach ($name in $ExeNames) {
        $exe = Join-Path $EmulatorPath $name
        if (Test-Path -LiteralPath $exe -PathType Leaf) { return $exe }
    }
    ''
}

function Test-EmulatorFileIntegrity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [string] $ExpectedHash = ''
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    if ($ExpectedHash) {
        $actual = (Get-FileHash -Algorithm SHA256 -Path $Path).Hash
        return $actual -eq $ExpectedHash
    }
    $true
}

function Get-EmulatorChecksum {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLower()
}