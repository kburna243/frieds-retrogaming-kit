<#
.SYNOPSIS
    PCSX2 (PlayStation 2) emulator adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    Detects and manages the PCSX2 PlayStation 2 emulator. It is DETECTED, never installed as a
    service and never started by the kit. Detection reads a snapshot (processes, ports, folders) so
    tests can inject everything.

    ─── SAFETY -- READ THIS ───
    This adapter does not enforce hardware limits; emulator configuration is user-preference based.
    PCSX2 requires PS2 BIOS files -- these are NOT included and the kit never downloads them.

    Kit deviations from the downloaded draft (deliberate, permanent):
      * The draft attempted to download emulator binaries -- the kit never downloads.
        The adapter only names official sources; a user-supplied ZIP goes through
        Install-PCSX2Emulator with -PackagePath and -Approved.
      * Configuration suggests INI settings but does not write files directly --
        routes through core configuration system.
      * PCSX2 does not support shader presets -- ShaderTarget is intentionally empty.
#>

function Test-PCSX2Emulator {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [hashtable] $Snapshot
    )
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-EmulatorSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-PCSX2EmulatorInfo -RetroBatRoot $RetroBatRoot
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

function Get-PCSX2EmulatorInfo {
    [CmdletBinding()]
    param([string] $RetroBatRoot = '')
    $toolDir = 'pcsx2'
    $exeNames = @('pcsx2.exe', 'pcsx2-qt.exe')
    # Resolve ExePath from RetroBatRoot if available
    $exePath = ''
    if ($RetroBatRoot) {
        $emuDir = Join-Path $RetroBatRoot "emulators\$toolDir"
        foreach ($exe in $exeNames) {
            $candidate = Join-Path $emuDir $exe
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $exePath = $candidate
                break
            }
        }
    }
    @{
        EmulatorType    = 'Console'
        ToolDir         = $toolDir
        ExePath         = $exePath
        ExeNames        = $exeNames
        DetectProcesses = @('pcsx2')
        DetectPorts     = @()
        SettingsTargets = @(
            @{
                File    = 'inis\PCSX2.ini'
                Section = 'Display'
                Values  = @{ EnableVsync = ''; Fullscreen = '' }
            },
            @{
                File    = 'inis\GS.ini'
                Section = ''
                Values  = @{ Renderer = ''; UpscaleMultiplier = '' }
            }
        )
        ShaderTarget    = ''
        Links           = @{
            Official = 'https://pcsx2.net/'
            RetroBat = 'https://wiki.retrobat.org/emulators/sony/pcsx2'
        }
        Notes           = 'PlayStation 2 emulator. Requires PS2 BIOS. Uses Qt interface. Lightgun games (Time Crisis, Vampire Night) via USB lightgun or Nuvee plugin.'
    }
}

function Install-PCSX2Emulator {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-PCSX2EmulatorInfo -RetroBatRoot $RetroBatRoot
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
    Expand-Archive -LiteralPath $PackagePath -DestinationPath $target -Force
    Write-KitLog "Emulator installed: $($info.ToolDir) -> $target" -Level Info
    @{ Success = $true; Target = $target }
}

function Configure-PCSX2Emulator {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    $changes = Set-EmulatorsAdapterConfiguration -Names @('PCSX2') -RetroBatRoot $RetroBatRoot -Confirm:$false
    @{ Configured = $changes }
}

function Set-PCSX2InterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return @{ Disabled = $true; PortsChecked = 0; Conflicts = @() } }
    $info = Get-PCSX2EmulatorInfo -RetroBatRoot $RetroBatRoot
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