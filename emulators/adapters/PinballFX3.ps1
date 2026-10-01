<#
.SYNOPSIS
    Pinball FX3 (Zen Studios) adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    Detects and manages Pinball FX3 by Zen Studios with Cabinet Mode for virtual pinball cabinets.
    It is DETECTED, never installed as a service and never started by the kit. Detection reads a
    snapshot (processes, ports, emulator folders) so tests can inject everything.

    ─── SAFETY -- READ THIS ───
    This adapter does not enforce hardware safety limits; emulator configuration is user-preference based.
    Cabinet Mode is a paid feature -- the user must unlock it through Zen Studios. Tables are purchased
    as DLC and must be legally owned. Also check Pinball FX (newer version) for compatibility.

    Kit deviations from the downloaded draft (deliberate, permanent):
      * The draft attempted to download Pinball FX3 -- the kit never downloads.
        The adapter only names official sources; a user-supplied ZIP goes through
        Install-PinballFX3Emulator with -PackagePath and -Approved.
      * Cabinet Mode supports DMD output, backglass display, and controller mapping.
      * No shader support (ShaderTarget = '') -- FX3 handles rendering internally.
      * Configuration targets the user AppData folder for cabinet mode settings.
      * Configuration suggests standard settings but does not write files directly --
        routes through core configuration system.
#>

function Test-PinballFX3Emulator {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [hashtable] $Snapshot
    )
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-EmulatorSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-PinballFX3EmulatorInfo -RetroBatRoot $RetroBatRoot
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

function Get-PinballFX3EmulatorInfo {
    [CmdletBinding()]
    param([string] $RetroBatRoot = '')
    $toolDir = 'Pinball FX3'
    $exeNames = @('Pinball FX3.exe', 'PinballFX3.exe')
    $emuPath = if ($RetroBatRoot) { Join-Path $RetroBatRoot "emulators\$toolDir" } else { '' }
    $exePath = if ($emuPath) { Get-EmulatorExecutable -EmulatorPath $emuPath -ExeNames $exeNames } else { '' }
    @{
        EmulatorType    = 'Pinball'
        ToolDir         = $toolDir
        ExePath         = $exePath
        ExeNames        = $exeNames
        DetectProcesses = @('pinball fx3')
        DetectPorts     = @()
        SettingsTargets = @(
            @{
                File    = '%USERPROFILE%\AppData\Local\Pinball FX3\cabinet_settings.ini'
                Section = ''
                Values  = @{
                    CabinetMode       = '1'
                    FullScreen        = '1'
                    BackglassEnabled  = '1'
                }
            }
        )
        ShaderTarget    = ''
        Links           = @{
            Steam    = 'https://store.steampowered.com/app/442120/Pinball_FX3/'
            Zen      = 'https://zenstudios.com/'
            RetroBat = 'https://wiki.retrobat.org/emulators/pinball/pinball-fx3'
        }
        Notes           = 'Pinball FX3 by Zen Studios. Cabinet Mode supports DMD output, backglass, and controller mapping. Tables purchased as DLC. Also check Pinball FX (newer version) compatibility.'
    }
}

function Install-PinballFX3Emulator {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-PinballFX3EmulatorInfo -RetroBatRoot $RetroBatRoot
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

function Configure-PinballFX3Emulator {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    Set-EmulatorsAdapterConfiguration -Names @('PinballFX3') -RetroBatRoot $RetroBatRoot -Confirm:$false
}

function Set-PinballFX3InterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-PinballFX3EmulatorInfo -RetroBatRoot $RetroBatRoot
    foreach ($p in @(Get-EmulatorsAdapterValue $info 'DetectPorts')) {
        $owner = @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name } | Select-Object -Unique)
        if ($owner.Count) { Write-KitLog "Port $p is owned by: $($owner -join ', ')" -Level Info }
    }
}