<#
.SYNOPSIS
    Pinball Arcade + Arcooda Cabinet Mode adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    Detects and manages Pinball Arcade by FarSight Studios with Arcooda Cabinet Mode for virtual
    pinball cabinets. It is DETECTED, never installed as a service and never started by the kit.
    Detection reads a snapshot (processes, ports, emulator folders) so tests can inject everything.

    ─── SAFETY -- READ THIS ───
    This adapter does not enforce hardware safety limits; emulator configuration is user-preference based.
    Arcooda Cabinet Mode requires a paid unlock key -- the user must purchase it separately from Arcooda.
    Tables are purchased as Steam DLC and must be legally owned.

    Kit deviations from the downloaded draft (deliberate, permanent):
      * The draft attempted to download Pinball Arcade -- the kit never downloads.
        The adapter only names official sources; a user-supplied ZIP goes through
        Install-PinballArcadeEmulator with -PackagePath and -Approved.
      * Arcooda Cabinet Mode unlocks real DMD output, backglass, and cabinet controls.
      * No shader support (ShaderTarget = '') -- Arcooda mode handles display output.
      * Configuration targets Settings.ini for cabinet mode and fullscreen.
      * The Steam version is required; Arcooda key is entered after installation.
      * Configuration suggests standard settings but does not write files directly --
        routes through core configuration system.
#>

function Test-PinballArcadeEmulator {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [hashtable] $Snapshot
    )
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-EmulatorSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-PinballArcadeEmulatorInfo -RetroBatRoot $RetroBatRoot
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

function Get-PinballArcadeEmulatorInfo {
    [CmdletBinding()]
    param([string] $RetroBatRoot = '')
    $toolDir = 'Pinball Arcade'
    $exeNames = @('PinballArcade.exe', 'PinballArcadeCabinet.exe')
    $emuPath = if ($RetroBatRoot) { Join-Path $RetroBatRoot "emulators\$toolDir" } else { '' }
    $exePath = if ($emuPath) { Get-EmulatorExecutable -EmulatorPath $emuPath -ExeNames $exeNames } else { '' }
    @{
        EmulatorType    = 'Pinball'
        ToolDir         = $toolDir
        ExePath         = $exePath
        ExeNames        = $exeNames
        DetectProcesses = @('pinballarcade')
        DetectPorts     = @()
        SettingsTargets = @(
            @{
                File    = 'PinballArcade\Settings.ini'
                Section = ''
                Values  = @{
                    CabinetMode = '1'
                    FullScreen  = '1'
                }
            }
        )
        ShaderTarget    = ''
        Links           = @{
            Steam   = 'https://store.steampowered.com/app/238260/Pinball_Arcade/'
            Arcooda = 'https://www.arcooda.com/pinball-arcade-cabinet-mode/'
        }
        Notes           = 'Pinball Arcade by FarSight Studios. Arcooda Cabinet Mode enables real DMD output, backglass, and cabinet controls. Requires Steam version + Arcooda key. Tables purchased as DLC.'
    }
}

function Install-PinballArcadeEmulator {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-PinballArcadeEmulatorInfo -RetroBatRoot $RetroBatRoot
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

function Configure-PinballArcadeEmulator {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    Set-EmulatorsAdapterConfiguration -Names @('PinballArcade') -RetroBatRoot $RetroBatRoot -Confirm:$false
}

function Set-PinballArcadeInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-PinballArcadeEmulatorInfo -RetroBatRoot $RetroBatRoot
    foreach ($p in @(Get-EmulatorsAdapterValue $info 'DetectPorts')) {
        $owner = @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name } | Select-Object -Unique)
        if ($owner.Count) { Write-KitLog "Port $p is owned by: $($owner -join ', ')" -Level Info }
    }
}