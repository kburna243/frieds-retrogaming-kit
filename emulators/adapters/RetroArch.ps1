<#
.SYNOPSIS
    RetroArch (Libretro frontend) adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    Detects and manages RetroArch multi-system emulator frontend. It is DETECTED, never installed
    as a service and never started by the kit. Detection reads a snapshot (processes, ports, emulator
    folders) so tests can inject everything.

    ─── SAFETY -- READ THIS ───
    This adapter does not enforce hardware safety limits; emulator configuration is user-preference based.
    RetroArch cores are separate downloads -- this adapter manages the frontend only.

    Kit deviations from the downloaded draft (deliberate, permanent):
      * The draft attempted to download RetroArch and cores -- the kit never downloads.
        The adapter only names official sources; a user-supplied ZIP goes through
        Install-RetroArchEmulator with -PackagePath and -Approved.
      * Cores are stored in emulators\retroarch\cores\.
      * Shader presets reside in emulators\retroarch\shaders\.
      * Configuration suggests standard RetroArch settings but does not write files directly --
        routes through core configuration system.
#>

function Test-RetroArchEmulator {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [hashtable] $Snapshot
    )
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-EmulatorSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-RetroArchEmulatorInfo -RetroBatRoot $RetroBatRoot
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

function Get-RetroArchEmulatorInfo {
    [CmdletBinding()]
    param([string] $RetroBatRoot = '')
    $toolDir = 'retroarch'
    $exeNames = @('retroarch.exe')
    $emuPath = if ($RetroBatRoot) { Join-Path $RetroBatRoot "emulators\$toolDir" } else { '' }
    $exePath = if ($emuPath) { Get-EmulatorExecutable -EmulatorPath $emuPath -ExeNames $exeNames } else { '' }
    @{
        EmulatorType    = 'MultiSystem'
        ToolDir         = $toolDir
        ExePath         = $exePath
        ExeNames        = $exeNames
        DetectProcesses = @('retroarch')
        DetectPorts     = @()
        SettingsTargets = @(
            @{
                File    = 'retroarch.cfg'
                Section = ''
                Values  = @{
                    video_fullscreen        = '1'
                    video_vsync             = '1'
                    input_joypad_driver     = 'xinput'
                    menu_driver             = 'ozone'
                }
            }
        )
        ShaderTarget    = 'emulators\retroarch\retroarch.cfg'
        Links           = @{
            Official = 'https://www.retroarch.com/'
            Cores    = 'https://docs.libretro.com/library/'
        }
        Notes           = 'Multi-system emulator frontend. Uses Libretro cores. Cores stored in emulators\retroarch\cores\. Shader presets in emulators\retroarch\shaders\.'
    }
}

function Install-RetroArchEmulator {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-RetroArchEmulatorInfo -RetroBatRoot $RetroBatRoot
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

function Configure-RetroArchEmulator {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    Set-EmulatorsAdapterConfiguration -Names @('RetroArch') -RetroBatRoot $RetroBatRoot -Confirm:$false
}

function Set-RetroArchInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-RetroArchEmulatorInfo -RetroBatRoot $RetroBatRoot
    foreach ($p in @(Get-EmulatorsAdapterValue $info 'DetectPorts')) {
        $owner = @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name } | Select-Object -Unique)
        if ($owner.Count) { Write-KitLog "Port $p is owned by: $($owner -join ', ')" -Level Info }
    }
}