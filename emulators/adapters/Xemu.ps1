<#
.SYNOPSIS
    Xemu (Original Xbox) emulator adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    Detects and manages the Xemu Original Xbox emulator. It is DETECTED, never installed as a service
    and never started by the kit. Detection reads a snapshot (processes, ports, folders) so tests
    can inject everything.

    ─── SAFETY -- READ THIS ───
    This adapter does not enforce hardware limits; emulator configuration is user-preference based.
    Xemu requires MCPX boot ROM, flash ROM (BIOS), and a hard disk image -- these are NOT included
    and the kit never downloads them.

    Kit deviations from the downloaded draft (deliberate, permanent):
      * The draft attempted to download emulator binaries -- the kit never downloads.
        The adapter only names official sources; a user-supplied ZIP goes through
        Install-XemuEmulator with -PackagePath and -Approved.
      * Configuration suggests TOML settings but does not write files directly --
        routes through core configuration system.
      * Shader target points to xemu.toml [video] section for shader integration.
#>

function Test-XemuEmulator {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [hashtable] $Snapshot
    )
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-EmulatorSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-XemuEmulatorInfo -RetroBatRoot $RetroBatRoot
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

function Get-XemuEmulatorInfo {
    [CmdletBinding()]
    param([string] $RetroBatRoot = '')
    $toolDir = 'xemu'
    $exeNames = @('xemu.exe')
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
        DetectProcesses = @('xemu')
        DetectPorts     = @()
        SettingsTargets = @(
            @{
                File    = 'xemu.toml'
                Section = 'video'
                Values  = @{ fullscreen = ''; vsync = ''; scale = '' }
            }
        )
        ShaderTarget    = 'emulators\xemu\xemu.toml'
        Links           = @{
            Official = 'https://xemu.app/'
            RetroBat = 'https://wiki.retrobat.org/emulators/microsoft/xemu'
        }
        Notes           = 'Original Xbox emulator. Requires MCPX boot ROM, flash ROM (BIOS), and hard disk image. TOML-based configuration.'
    }
}

function Install-XemuEmulator {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-XemuEmulatorInfo -RetroBatRoot $RetroBatRoot
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

function Configure-XemuEmulator {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    $changes = Set-EmulatorsAdapterConfiguration -Names @('Xemu') -RetroBatRoot $RetroBatRoot -Confirm:$false
    @{ Configured = $changes }
}

function Set-XemuInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return @{ Disabled = $true; PortsChecked = 0; Conflicts = @() } }
    $info = Get-XemuEmulatorInfo -RetroBatRoot $RetroBatRoot
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