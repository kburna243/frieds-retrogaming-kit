<#
.SYNOPSIS
    Freezy's DMD Extensions (dmdext) output-middleware adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    DMD Extensions mirrors an emulator's dot-matrix display (Visual Pinball / FP / FX via the
    dmdext process or the injected dmddevice.dll) onto a real DMD panel - PIN2DMD, ZeDMD, PinDMDv3 -
    or a window. It is DETECTED, never installed as a service and never started by the kit. Detection
    reads a snapshot (processes, ports, devices, tools folder) so tests can inject everything.

    Kit deviations from the downloaded draft (deliberate, permanent):
      * The draft scraped the GitHub API, downloaded the release ZIP and Unblock-File'd it into
        tools\dmdext - the kit never downloads. The adapter only names the official source; a
        user-supplied ZIP goes through Install-DmdExtensionsSoftware with -PackagePath and -Approved.
      * MameOutput is EMPTY on purpose: the DMD frame path does not run over the mame.ini "output"
        key (no Win32 output messages, no TCP events). The core truth-guards the mode list, so an
        empty MameOutput contributes no mode and can never raise an OutputModeConflict - verified
        against modules\Adapters.ps1 before this line was written.
      * BoardMatchIds is EMPTY because the draft's board list was a false-positive minefield, and
        every entry is gone:
          - 303A:1001 is Espressif's generic USB VID - the lightgun package claims exactly that
            signature for the OpenFIRE gun (lightgun\adapters\OpenFire.ps1). Collision: never DMD
            evidence.
          - 1A86:7523 (CH340), 0403:6014 (FTDI), 0483:5740 (STM32 CDC) are bare serial-cable chip
            IDs - they match every USB-serial adapter in the house, not a DMD.
          Board evidence must name the device, not the wire, so dmdext is identified by process and
          by its tools\dmdext folder only.
      * SettingsTargets is EMPTY with full intent: DmdDevice.ini belongs to the PINBALL package -
        step 08-Screens and pinball\modules\Screens.ps1 own [VPinMAME.DMD] / [FP.DMD] with golden
        tests. A second writer for the same file is forbidden; v1 writes nothing here.
      * The draft's machine-scope DMDDEVICE_CONFIG environment variable is out: it was unverified
        (dmdext finds DmdDevice.ini next to the DLL/exe by default) and a system-wide intervention
        the kit does not make.
#>

function Test-DmdExtensionsHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [hashtable] $Snapshot)
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-OutputSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-DmdExtensionsAdapterInfo
    foreach ($p in @(Get-OutputAdapterValue $info 'DetectProcesses')) {
        if (@($Snapshot.Processes) -contains $p.ToLowerInvariant()) { return $true }
    }
    foreach ($port in @(Get-OutputAdapterValue $info 'DetectPorts')) {
        if (@($Snapshot.Ports) -contains [int]$port) { return $true }
    }
    foreach ($d in @($Snapshot.Devices | Where-Object { $_ })) {
        $id = (Get-LightgunDeviceId $d).ToUpperInvariant()
        foreach ($m in @(Get-OutputAdapterValue $info 'BoardMatchIds')) { if ($id -like $m.ToUpperInvariant()) { return $true } }
    }
    $toolDir = [string](Get-OutputAdapterValue $info 'ToolDir')
    if ($RetroBatRoot -and $toolDir) {
        if (Test-Path -LiteralPath (Join-Path $RetroBatRoot "tools\$toolDir") -PathType Container) { return $true }
    }
    $false
}

function Get-DmdExtensionsAdapterInfo {
    @{
        ToolDir         = 'dmdext'                            # the portable dmdext lives in tools\dmdext (draft agrees - this is the folder a person installs to)
        DetectProcesses = @('dmdext')                         # without .exe, case-insensitive
        DetectPorts     = @()                                 # mirror/DMD path owns no TCP port
        BoardMatchIds   = @()                                 # 303A:1001 = OpenFIRE collision, CH340/FTDI/STM32-CDC = generic cable VIDs - all rejected, see header
        MameOutput      = ''                                  # the DMD is NOT fed by the mame.ini output key - empty stays out of the modes list (core truth-guard verified)
        SettingsTargets = @()                                 # DmdDevice.ini belongs to the pinball package (step 08-Screens) - double writer forbidden, v1 writes nothing
        Links           = @{ 'Freezy DMD Extensions' = 'https://github.com/freezy/dmd-extensions' }
        Notes           = 'dmdext mirror window; DmdDevice.ini belongs to the pinball package (step 08-Screens).'
    }
}

# Deliberately does NOT download: the kit only names the official source. The user fetches the ZIP
# and passes it as -PackagePath; with -Approved the kit unpacks it into tools\dmdext. Without a
# package nothing happens beyond the hint - and dmdext is never registered as a service or started.
function Install-DmdExtensionsSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-DmdExtensionsAdapterInfo
    $target = Join-Path $RetroBatRoot "tools\$($info.ToolDir)"
    if (-not $PackagePath) {
        foreach ($k in $info.Links.Keys) { Write-KitLog (Get-KitText 'Output.Adapter.SoftwareLink' -f $k, $info.Links[$k]) }
        Write-KitLog (Get-KitText 'Output.Adapter.NoService') -Level Info
        return $false
    }
    if (-not $Approved.IsPresent) { Write-KitLog (Get-KitText 'Output.Adapter.NeedsApproval') -Level Warn; return $false }
    if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) { Write-KitLog (Get-KitText 'Output.Adapter.PackageMissing' -f $PackagePath) -Level Warn; return $false }
    if (-not $PSCmdlet.ShouldProcess($target, 'unpack middleware package')) { return $false }
    $null = New-Item -ItemType Directory -Path $target -Force
    Write-KitLog (Get-KitText 'Output.Adapter.PackageHash' -f (Split-Path -Leaf $PackagePath), (Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash)
    Expand-Archive -LiteralPath $PackagePath -DestinationPath $target -Force
    Write-KitLog (Get-KitText 'Output.Adapter.SoftwareInstalled' -f $info.ToolDir, $target)
    $true
}

function Configure-DmdExtensionsProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    # Routes through the core on purpose: with MameOutput = '' and SettingsTargets = @() the core
    # touches neither mame.ini nor any settings file - that IS the configuration contract of v1
    # (DmdDevice.ini is the pinball package's file, see header). Never hand-write anything here.
    Set-OutputMiddlewareConfiguration -Names @('DmdExtensions') -RetroBatRoot $RetroBatRoot -Confirm:$false
}

# Interference shield, kit style, kept minimal like the template: dmdext owns no port (the loop is
# contract shape, inert by design) and listens to no Win32 broadcast. The real interference on the
# DMD side is a SECOND dmdext instance fighting for the same panel - the shield counts the running
# instances read-only and reports; it never kills anything.
function Set-DmdExtensionsInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-DmdExtensionsAdapterInfo
    foreach ($p in @(Get-OutputAdapterValue $info 'DetectPorts')) {
        $owner = @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name } | Select-Object -Unique)
        if ($owner.Count) { Write-KitLog (Get-KitText 'Output.Shield.PortOwner' -f $p, ($owner -join ', ')) -Level Info }
    }
    # Read-only glance at rival DMD claimants (report only, no action):
    $instances = @(Get-Process -Name 'dmdext' -ErrorAction SilentlyContinue)
    if ($instances.Count -gt 1) {
        Write-KitLog (Get-KitText 'Output.Shield.RivalListener' -f 'DMD panel frames', ('dmdext x ' + $instances.Count)) -Level Info
    }
}