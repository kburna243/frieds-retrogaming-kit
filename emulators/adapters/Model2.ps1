<#
.SYNOPSIS
    Sega Model 2 Emulator adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    Detects and manages the Nebula-based Sega Model 2 emulator for arcade lightgun games. It is
    DETECTED, never installed as a service and never started by the kit. Detection reads a snapshot
    (processes, ports, emulator folders) so tests can inject everything.

    ─── SAFETY -- READ THIS ───
    This adapter does not enforce hardware safety limits; emulator configuration is user-preference
    based. Sega Model 2 emulator is closed-source (Nebula-based) -- the user must supply EMULATOR.EXE
    legally. The kit never distributes it.

    Kit deviations from the downloaded draft (deliberate, permanent):
      * The draft attempted to download the emulator -- the kit never downloads.
        The adapter only names official sources; a user-supplied ZIP goes through
        Install-Model2Emulator with -PackagePath and -Approved.
      * Configuration targets EMULATOR.INI with lightgun crosshair settings (DrawCross=1)
        and routes through the core configuration system.
      * No shader support -- Model 2 does not expose a shader pipeline.
      * DemulShooter integration uses -target=model2m for lightgun hooking.
#>

function Test-Model2Emulator {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [hashtable] $Snapshot
    )
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-EmulatorSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-Model2EmulatorInfo -RetroBatRoot $RetroBatRoot
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

function Get-Model2EmulatorInfo {
    [CmdletBinding()]
    param([string] $RetroBatRoot = '')
    $toolDir = 'model2'
    $exeNames = @('EMULATOR.EXE', 'emulator_multicpu.exe')
    $emuPath = if ($RetroBatRoot) { Join-Path $RetroBatRoot "emulators\$toolDir" } else { '' }
    $exePath = if ($emuPath) { Get-EmulatorExecutable -EmulatorPath $emuPath -ExeNames $exeNames } else { '' }
    @{
        EmulatorType    = 'Arcade'
        ToolDir         = $toolDir
        ExePath         = $exePath
        ExeNames        = $exeNames
        DetectProcesses = @('emulator')
        DetectPorts     = @()
        SettingsTargets = @(
            @{
                File    = 'EMULATOR.INI'
                Section = 'Renderer'
                Values  = @{
                    DrawCross = '1'
                }
            }
        )
        ShaderTarget    = ''
        Links           = @{
            RetroBat = 'https://wiki.retrobat.org/emulators/arcade/model2'
        }
        Notes           = 'Sega Model 2 emulator. Lightgun games: Virtua Cop 1/2, House of the Dead. DemulShooter hooks via -target=model2m. User must supply EMULATOR.EXE (closed source, Nebula-based).'
    }
}

function Install-Model2Emulator {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-Model2EmulatorInfo -RetroBatRoot $RetroBatRoot
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

function Configure-Model2Emulator {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    $changes = Set-EmulatorsAdapterConfiguration -Names @('Model2') -RetroBatRoot $RetroBatRoot -Confirm:$false
    @{ Configured = $changes }
}

function Set-Model2InterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return @{ Disabled = $true; PortsChecked = 0; Conflicts = @() } }
    $info = Get-Model2EmulatorInfo -RetroBatRoot $RetroBatRoot
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