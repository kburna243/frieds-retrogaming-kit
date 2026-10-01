<#
.SYNOPSIS
    RPCS3 (PlayStation 3) emulator adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    Detects and manages the RPCS3 emulator for PlayStation 3 systems. It is DETECTED, never
    installed as a service and never started by the kit. Detection reads a snapshot (processes,
    ports, emulator folders) so tests can inject everything.

    ─── SAFETY -- READ THIS ───
    This adapter does not enforce hardware safety limits; emulator configuration is user-preference
    based. RPCS3 requires an official PS3 firmware file (PS3UPDAT.PUP) -- the user must supply this
    legally from their own console. The kit never distributes firmware or copyrighted system files.
    RPCS3 is CPU-intensive and needs strong hardware for playable performance.

    Kit deviations from the downloaded draft (deliberate, permanent):
      * The draft attempted to download RPCS3 binaries -- the kit never downloads.
        The adapter only names official sources; a user-supplied ZIP goes through
        Install-RPCS3Emulator with -PackagePath and -Approved.
      * Configuration targets config.yml with resolution, vsync, and renderer settings
        and routes through the core configuration system.
      * No shader support -- RPCS3 does not expose a shader preset pipeline.
      * Game-specific custom configs (custom_configs/*.yml) are user-managed; the adapter
        only notes their location.
#>

function Test-RPCS3Emulator {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [hashtable] $Snapshot
    )
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-EmulatorSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-RPCS3EmulatorInfo -RetroBatRoot $RetroBatRoot
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

function Get-RPCS3EmulatorInfo {
    [CmdletBinding()]
    param([string] $RetroBatRoot = '')
    $toolDir = 'rpcs3'
    $exeNames = @('rpcs3.exe')
    $emuPath = if ($RetroBatRoot) { Join-Path $RetroBatRoot "emulators\$toolDir" } else { '' }
    $exePath = if ($emuPath) { Get-EmulatorExecutable -EmulatorPath $emuPath -ExeNames $exeNames } else { '' }
    @{
        EmulatorType    = 'Console'
        ToolDir         = $toolDir
        ExePath         = $exePath
        ExeNames        = $exeNames
        DetectProcesses = @('rpcs3')
        DetectPorts     = @()
        SettingsTargets = @(
            @{
                File    = 'config.yml'
                Section = 'Video'
                Values  = @{
                    Resolution = '1920x1080'
                    VSync      = '1'
                    Renderer   = 'Vulkan'
                }
            }
        )
        ShaderTarget    = ''
        Links           = @{
            Official = 'https://rpcs3.net/'
            RetroBat = 'https://wiki.retrobat.org/emulators/sony/rpcs3'
        }
        Notes           = 'PlayStation 3 emulator. Requires PS3 firmware (PS3UPDAT.PUP). Game-specific custom configs in custom_configs/*.yml. CPU-intensive -- needs strong hardware.'
    }
}

function Install-RPCS3Emulator {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-RPCS3EmulatorInfo -RetroBatRoot $RetroBatRoot
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

function Configure-RPCS3Emulator {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    $changes = Set-EmulatorsAdapterConfiguration -Names @('RPCS3') -RetroBatRoot $RetroBatRoot -Confirm:$false
    @{ Configured = $changes }
}

function Set-RPCS3InterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return @{ Disabled = $true; PortsChecked = 0; Conflicts = @() } }
    $info = Get-RPCS3EmulatorInfo -RetroBatRoot $RetroBatRoot
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