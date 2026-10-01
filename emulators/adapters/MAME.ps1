<#
.SYNOPSIS
    MAME (Multiple Arcade Machine Emulator) adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    Detects and manages MAME standalone emulator for arcade systems. It is DETECTED, never installed
    as a service and never started by the kit. Detection reads a snapshot (processes, ports, emulator
    folders) so tests can inject everything.

    ─── SAFETY -- READ THIS ───
    This adapter does not enforce hardware safety limits; emulator configuration is user-preference based.
    MAME ROM sets must match the MAME version exactly -- mismatched ROMs will fail to load.

    Kit deviations from the downloaded draft (deliberate, permanent):
      * The draft attempted to download MAME binaries -- the kit never downloads.
        The adapter only names official sources; a user-supplied ZIP goes through
        Install-MAMEEmulator with -PackagePath and -Approved.
      * MAME configuration is read from mame.ini in the emulator directory.
      * Shader support routes through mame.ini bgfx_screen_chains or hlsl settings.
      * Configuration suggests standard MAME settings but does not write files directly --
        routes through core configuration system.
#>

function Test-MAMEEmulator {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [hashtable] $Snapshot
    )
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-EmulatorSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-MAMEEmulatorInfo -RetroBatRoot $RetroBatRoot
    # Check by executable path
    if ($info.ExePath -and (Test-Path -LiteralPath $info.ExePath -PathType Leaf)) { return $true }
    # Check by process
    foreach ($p in $info.DetectProcesses) {
        if (@($Snapshot.Processes) -contains $p.ToLowerInvariant()) { return $true }
    }
    # Check by emulator directory
    if ($RetroBatRoot -and $info.ToolDir) {
        if (Test-Path -LiteralPath (Join-Path $RetroBatRoot "emulators\$($info.ToolDir)") -PathType Container) { return $true }
    }
    $false
}

function Get-MAMEEmulatorInfo {
    [CmdletBinding()]
    param([string] $RetroBatRoot = '')
    $toolDir = 'mame'
    $exeNames = @('mame.exe', 'mame64.exe')
    $emuPath = if ($RetroBatRoot) { Join-Path $RetroBatRoot "emulators\$toolDir" } else { '' }
    $exePath = if ($emuPath) { Get-EmulatorExecutable -EmulatorPath $emuPath -ExeNames $exeNames } else { '' }
    @{
        EmulatorType    = 'Arcade'
        ToolDir         = $toolDir
        ExePath         = $exePath
        ExeNames        = $exeNames
        DetectProcesses = @('mame')
        DetectPorts     = @()
        SettingsTargets = @(
            @{
                File    = 'mame.ini'
                Section = ''
                Values  = @{
                    window          = '0'
                    keepaspect      = '1'
                    autosave        = '1'
                    skip_gameinfo   = '1'
                }
            }
        )
        ShaderTarget    = 'emulators\mame\mame.ini'
        Links           = @{
            Official = 'https://www.mamedev.org/'
            RetroBat = 'https://wiki.retrobat.org/emulators/arcade/mame'
        }
        Notes           = 'Standard arcade emulator. MAME ROM set must match MAME version. RetroBat uses standalone MAME for arcade systems.'
    }
}

function Install-MAMEEmulator {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-MAMEEmulatorInfo -RetroBatRoot $RetroBatRoot
    $target = Join-Path $RetroBatRoot "emulators\$($info.ToolDir)"
    if (-not $PackagePath) {
        foreach ($k in $info.Links.Keys) { Write-KitLog "Official source: $k -- $($info.Links[$k])" -Level Info }
        Write-KitLog 'Emulator must be installed manually; the kit never downloads binaries.' -Level Info
        return @{ Success = $false; Message = 'Manual install required; links provided above' }
    }
    if (-not $Approved.IsPresent) { Write-KitLog 'Install requires -Approved flag.' -Level Warn; return @{ Success = $false; Message = 'Approval required' } }
    if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) { Write-KitLog "Package not found: $PackagePath" -Level Warn; return @{ Success = $false; Message = "Package missing: $PackagePath" } }
    if (-not $PSCmdlet.ShouldProcess($target, 'unpack emulator package')) { return @{ Success = $false; Message = 'Cancelled' } }
    $null = New-Item -ItemType Directory -Path $target -Force
    Write-KitLog "Package hash: $(Split-Path -Leaf $PackagePath) -- $((Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash)" -Level Info
    Expand-Archive -LiteralPath $PackagePath -DestinationPath $target -Force
    Write-KitLog "Emulator installed: $($info.ToolDir) -> $target" -Level Info
    @{ Success = $true; Target = $target }
}

function Configure-MAMEEmulator {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    Set-EmulatorsAdapterConfiguration -Names @('MAME') -RetroBatRoot $RetroBatRoot -Confirm:$false
}

function Set-MAMEInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-MAMEEmulatorInfo -RetroBatRoot $RetroBatRoot
    foreach ($p in @(Get-EmulatorsAdapterValue $info 'DetectPorts')) {
        $owner = @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name } | Select-Object -Unique)
        if ($owner.Count) { Write-KitLog "Port $p is owned by: $($owner -join ', ')" -Level Info }
    }
}