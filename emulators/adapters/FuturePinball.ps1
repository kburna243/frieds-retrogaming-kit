<#
.SYNOPSIS
    Future Pinball + BAM (Better Arcade Mode) adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    Detects and manages Future Pinball with BAM for virtual pinball cabinets. It is DETECTED, never
    installed as a service and never started by the kit. Detection reads a snapshot (processes, ports,
    emulator folders) so tests can inject everything.

    ─── SAFETY -- READ THIS ───
    This adapter does not enforce hardware safety limits; emulator configuration is user-preference based.
    BAM (Better Arcade Mode) is a third-party modification -- the user is responsible for compatibility.

    Kit deviations from the downloaded draft (deliberate, permanent):
      * The draft attempted to download Future Pinball / BAM -- the kit never downloads.
        The adapter only names official sources; a user-supplied ZIP goes through
        Install-FuturePinballEmulator with -PackagePath and -Approved.
      * BAM is launched via FPLoader.exe (not Future Pinball.exe) for cabinet features.
      * No shader support (ShaderTarget = '') -- BAM handles rendering internally.
      * Configuration targets BAM\BAM.cfg for cabinet mode and Future Pinball\fp.ini for general settings.
      * Configuration suggests standard settings but does not write files directly --
        routes through core configuration system.
#>

function Test-FuturePinballEmulator {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [hashtable] $Snapshot
    )
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-EmulatorSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-FuturePinballEmulatorInfo -RetroBatRoot $RetroBatRoot
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

function Get-FuturePinballEmulatorInfo {
    [CmdletBinding()]
    param([string] $RetroBatRoot = '')
    $toolDir = 'Future Pinball'
    $exeNames = @('Future Pinball.exe', 'FPLoader.exe')
    $emuPath = if ($RetroBatRoot) { Join-Path $RetroBatRoot "emulators\$toolDir" } else { '' }
    $exePath = if ($emuPath) { Get-EmulatorExecutable -EmulatorPath $emuPath -ExeNames $exeNames } else { '' }
    @{
        EmulatorType    = 'Pinball'
        ToolDir         = $toolDir
        ExePath         = $exePath
        ExeNames        = $exeNames
        DetectProcesses = @('future pinball')
        DetectPorts     = @()
        SettingsTargets = @(
            @{
                File    = 'BAM\BAM.cfg'
                Section = ''
                Values  = @{
                    ForceFullscreen = '1'
                    CabinetMode     = '1'
                }
            },
            @{
                File    = 'Future Pinball\fp.ini'
                Section = ''
                Values  = @{
                    FullScreen = '1'
                }
            }
        )
        ShaderTarget    = ''
        Links           = @{
            Official = 'https://futurepinball.com/'
            BAM      = 'https://www.ravarcade.pl/'
            RetroBat = 'https://wiki.retrobat.org/emulators/pinball/future-pinball'
        }
        Notes           = 'Future Pinball with BAM (Better Arcade Mode) for cabinet features: force feedback, DOF, PUP packs, head tracking. FPLoader.exe is the BAM launcher. Tables are .fpt files.'
    }
}

function Install-FuturePinballEmulator {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-FuturePinballEmulatorInfo -RetroBatRoot $RetroBatRoot
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

function Configure-FuturePinballEmulator {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    Set-EmulatorsAdapterConfiguration -Names @('FuturePinball') -RetroBatRoot $RetroBatRoot -Confirm:$false
}

function Set-FuturePinballInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-FuturePinballEmulatorInfo -RetroBatRoot $RetroBatRoot
    foreach ($p in @(Get-EmulatorsAdapterValue $info 'DetectPorts')) {
        $owner = @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name } | Select-Object -Unique)
        if ($owner.Count) { Write-KitLog "Port $p is owned by: $($owner -join ', ')" -Level Info }
    }
}