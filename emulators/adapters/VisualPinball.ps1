<#
.SYNOPSIS
    Visual Pinball VPX (Visual Pinball X) adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    Detects and manages Visual Pinball X for virtual pinball cabinets. It is DETECTED, never installed
    as a service and never started by the kit. Detection reads a snapshot (processes, ports, emulator
    folders) so tests can inject everything.

    ─── SAFETY -- READ THIS ───
    This adapter does not enforce hardware safety limits; emulator configuration is user-preference based.
    Visual Pinball requires VPinMAME for ROM-based tables -- ROMs are user-supplied and must be legally owned.

    Kit deviations from the downloaded draft (deliberate, permanent):
      * The draft attempted to download Visual Pinball -- the kit never downloads.
        The adapter only names official sources; a user-supplied ZIP goes through
        Install-VisualPinballEmulator with -PackagePath and -Approved.
      * VPinballX.exe and VPinballX64.exe are the standard launchers; VPinball995.exe for legacy tables.
      * No shader support (ShaderTarget = '') -- VPX handles rendering internally.
      * Configuration targets VPinballX.ini for playfield/DMD and DmdDevice.ini for DMD output.
      * PinUP Popper is the recommended frontend for cabinet management.
      * Configuration suggests standard settings but does not write files directly --
        routes through core configuration system.
#>

function Test-VisualPinballEmulator {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [hashtable] $Snapshot
    )
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-EmulatorSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-VisualPinballEmulatorInfo -RetroBatRoot $RetroBatRoot
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

function Get-VisualPinballEmulatorInfo {
    [CmdletBinding()]
    param([string] $RetroBatRoot = '')
    $toolDir = 'Visual Pinball'
    $exeNames = @('VPinballX.exe', 'VPinballX64.exe', 'VPinball995.exe')
    $emuPath = if ($RetroBatRoot) { Join-Path $RetroBatRoot "emulators\$toolDir" } else { '' }
    $exePath = if ($emuPath) { Get-EmulatorExecutable -EmulatorPath $emuPath -ExeNames $exeNames } else { '' }
    @{
        EmulatorType    = 'Pinball'
        ToolDir         = $toolDir
        ExePath         = $exePath
        ExeNames        = $exeNames
        DetectProcesses = @('vpinballx')
        DetectPorts     = @()
        SettingsTargets = @(
            @{
                File    = 'VPinballX.ini'
                Section = 'Playfield'
                Values  = @{
                    FullScreen = '1'
                }
            },
            @{
                File    = 'VPinballX.ini'
                Section = 'DMD'
                Values  = @{
                    Enabled = '1'
                }
            },
            @{
                File    = 'DmdDevice.ini'
                Section = ''
                Values  = @{
                    enabled = 'true'
                }
            }
        )
        ShaderTarget    = ''
        Links           = @{
            Official = 'https://github.com/vpinball/vpinball'
            VPU      = 'https://vpuniverse.com/'
            RetroBat = 'https://wiki.retrobat.org/emulators/pinball/visual-pinball'
        }
        Notes           = 'Visual Pinball X -- the standard for virtual pinball cabinets. Requires VPinMAME for ROM-based tables. DmdDevice.dll for DMD output. Tables are .vpx files. PinUP Popper is the recommended frontend.'
    }
}

function Install-VisualPinballEmulator {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-VisualPinballEmulatorInfo -RetroBatRoot $RetroBatRoot
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

function Configure-VisualPinballEmulator {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    Set-EmulatorsAdapterConfiguration -Names @('VisualPinball') -RetroBatRoot $RetroBatRoot -Confirm:$false
}

function Set-VisualPinballInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-VisualPinballEmulatorInfo -RetroBatRoot $RetroBatRoot
    foreach ($p in @(Get-EmulatorsAdapterValue $info 'DetectPorts')) {
        $owner = @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name } | Select-Object -Unique)
        if ($owner.Count) { Write-KitLog "Port $p is owned by: $($owner -join ', ')" -Level Info }
    }
}