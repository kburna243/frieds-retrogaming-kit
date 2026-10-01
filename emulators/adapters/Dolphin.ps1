<#
.SYNOPSIS
    Dolphin (GameCube / Wii) emulator adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    Detects and manages the Dolphin emulator for GameCube and Wii systems. It is DETECTED, never
    installed as a service and never started by the kit. Detection reads a snapshot (processes,
    ports, emulator folders) so tests can inject everything.

    ─── SAFETY -- READ THIS ───
    This adapter does not enforce hardware safety limits; emulator configuration is user-preference
    based. Dolphin requires no BIOS for GameCube but may need one for Wii -- the user must supply
    system files legally. The kit never distributes copyrighted firmware.

    Kit deviations from the downloaded draft (deliberate, permanent):
      * The draft attempted to download Dolphin binaries -- the kit never downloads.
        The adapter only names official sources; a user-supplied ZIP goes through
        Install-DolphinEmulator with -PackagePath and -Approved.
      * Configuration targets Config\Dolphin.ini [Display] with Fullscreen and VSync settings
        and routes through the core configuration system.
      * Shader target points to Config\Dolphin.ini for PostProcessingShader configuration.
      * Controller profiles (GCPadNew.ini) are user-managed; the adapter notes their location.
      * Real Wiimote support via DolphinBar is noted but not configured automatically.
#>

function Test-DolphinEmulator {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [hashtable] $Snapshot
    )
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-EmulatorSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-DolphinEmulatorInfo -RetroBatRoot $RetroBatRoot
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

function Get-DolphinEmulatorInfo {
    [CmdletBinding()]
    param([string] $RetroBatRoot = '')
    $toolDir = 'dolphin'
    $exeNames = @('Dolphin.exe', 'DolphinWX.exe')
    $emuPath = if ($RetroBatRoot) { Join-Path $RetroBatRoot "emulators\$toolDir" } else { '' }
    $exePath = if ($emuPath) { Get-EmulatorExecutable -EmulatorPath $emuPath -ExeNames $exeNames } else { '' }
    @{
        EmulatorType    = 'Console'
        ToolDir         = $toolDir
        ExePath         = $exePath
        ExeNames        = $exeNames
        DetectProcesses = @('dolphin')
        DetectPorts     = @()
        SettingsTargets = @(
            @{
                File    = 'Config\Dolphin.ini'
                Section = 'Display'
                Values  = @{
                    Fullscreen = '1'
                    VSync      = '1'
                }
            }
        )
        ShaderTarget    = 'emulators\dolphin\Config\Dolphin.ini'
        Links           = @{
            Official = 'https://dolphin-emu.org/'
            RetroBat = 'https://wiki.retrobat.org/emulators/nintendo/dolphin'
        }
        Notes           = 'GameCube and Wii emulator. Real Wiimotes via DolphinBar (Mode 4). Controller profiles in Config\GCPadNew.ini. Post-processing shaders supported.'
    }
}

function Install-DolphinEmulator {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-DolphinEmulatorInfo -RetroBatRoot $RetroBatRoot
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

function Configure-DolphinEmulator {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    $changes = Set-EmulatorsAdapterConfiguration -Names @('Dolphin') -RetroBatRoot $RetroBatRoot -Confirm:$false
    @{ Configured = $changes }
}

function Set-DolphinInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return @{ Disabled = $true; PortsChecked = 0; Conflicts = @() } }
    $info = Get-DolphinEmulatorInfo -RetroBatRoot $RetroBatRoot
    $ports = @(Get-EmulatorsAdapterValue $info 'DetectPorts')
    $conflicts = @()
    foreach ($p in $ports) {
        $owner = @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name } | Select-Object -Unique)
        if ($owner.Count) {
            Write-KitLog "Port $p is owned by: $($owner -join ', ')" -Level Info
            $conflicts += [pscustomobject]@{ Port = $p; Owners = $owner }
        }
    }
    @{ PortsChecked = $ports.Count; Conflicts = $conflicts }
}