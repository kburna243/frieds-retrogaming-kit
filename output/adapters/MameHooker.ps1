<#
.SYNOPSIS
    MAMEHooker (Classic, Howard Casto) output-middleware adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    MAMEHooker receives MAME's Win32 output messages and drives LEDs / lamps / relays on LED-Wiz style
    boards. It is DETECTED, never installed as a service and never started by the kit. Detection reads
    a snapshot (processes, ports, devices, tools folder) so tests can inject everything.

    Kit deviations from the downloaded draft (deliberate, permanent):
      * The draft downloaded mamehook5.1.zip from dragonking.arcadecontrols.com — the kit never
        downloads. The adapter only names the official source; a user-supplied ZIP goes through
        Install-MameHookerSoftware with -PackagePath and -Approved.
      * SettingsTargets is EMPTY in v1: the kit does not manage MAMEHooker.ini yet. The profile syntax
        (scom/pac lines per emulator profile) belongs to a later PR — until then MAMEHooker.ini stays
        entirely in the user's hands and nothing is written.
      * BoardMatchIds is tightened: the draft matched the naked VID_D209 (that is Ultimarc — AimTrak
        lightguns report under it!) and VID_FAFA (dubious — genuine LED-Wiz boards enumerate as
        VID_0DFA&PID_0001). Ultimarc boards are captured by the I-PAC/AimTrak adapters of the other
        adapter classes, not here, so this adapter only claims the LED-Wiz signature.
      * MameHooker listens to Win32 messages, not TCP — DetectPorts is empty by design. The shield
        only REPORTS rival Win32 message listeners (e.g. LEDBlinky); it never kills anything.
#>

function Test-MameHookerHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [hashtable] $Snapshot)
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-OutputSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-MameHookerAdapterInfo
    foreach ($p in $info.DetectProcesses) {
        if (@($Snapshot.Processes) -contains $p.ToLowerInvariant()) { return $true }
    }
    foreach ($port in $info.DetectPorts) {
        if (@($Snapshot.Ports) -contains [int]$port) { return $true }
    }
    foreach ($d in @($Snapshot.Devices | Where-Object { $_ })) {
        $id = (Get-LightgunDeviceId $d).ToUpperInvariant()
        foreach ($m in $info.BoardMatchIds) { if ($id -like $m.ToUpperInvariant()) { return $true } }
    }
    if ($RetroBatRoot -and $info.ToolDir) {
        if (Test-Path -LiteralPath (Join-Path $RetroBatRoot "tools\$($info.ToolDir)") -PathType Container) { return $true }
    }
    $false
}

function Get-MameHookerAdapterInfo {
    @{
        ToolDir         = 'MAMEHooker'
        DetectProcesses = @('MameHooker', 'Mamehooker51')   # without .exe, case-insensitive
        DetectPorts     = @()                               # Win32 message receiver — it owns no TCP port
        # Tight board signature, no naked VIDs: genuine LED-Wiz boards enumerate as 0DFA/0001.
        # The draft's VID_D209 (Ultimarc — AimTrak!) and VID_FAFA (dubious) are gone on purpose;
        # Ultimarc hardware is identified by the I-PAC/AimTrak lightgun adapters, not by this one.
        BoardMatchIds   = @('USB\VID_0DFA&PID_0001*')
        MameOutput      = 'windows'                         # mame.ini: output = windows (Win32 messages)
        # v1 manages no settings file (see header): MAMEHooker.ini stays untouched by the kit.
        SettingsTargets = @()
        Links           = @{ 'MAMEHooker (Howard Casto)' = 'http://forum.arcadecontrols.com/' }
        Notes           = 'Win32 output; run it before MAME starts.'
    }
}

# Deliberately does NOT download: the kit only names the official source. The user fetches the ZIP and
# passes it as -PackagePath; with -Approved the kit unpacks it into tools\MAMEHooker. Without a package
# nothing happens beyond the hint — and MAMEHooker is never registered as a service or started.
function Install-MameHookerSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-MameHookerAdapterInfo
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

function Configure-MameHookerProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    Set-OutputMiddlewareConfiguration -Names @('MameHooker') -RetroBatRoot $RetroBatRoot -Confirm:$false
}

# Interference shield, kit style: MAMEHooker shares the Win32 output messages with any other listener
# (LEDBlinky is the classic rival — two consumers mean dropped lamp events). The shield only REPORTS
# rivals by name; it never kills a process and MAMEHooker owns no port, so the port loop stays empty.
function Set-MameHookerInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-MameHookerAdapterInfo
    foreach ($p in $info.DetectPorts) {
        $owner = @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name } | Select-Object -Unique)
        if ($owner.Count) { Write-KitLog (Get-KitText 'Output.Shield.PortOwner' -f $p, ($owner -join ', ')) -Level Info }
    }
    # Read-only glance at rival Win32 message listeners (report only, no action):
    $rivals = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.Name -in @('LEDBlinky', 'LEDBlinkyService', 'DirectOutput') } | ForEach-Object { $_.Name } | Select-Object -Unique)
    if ($rivals.Count) { Write-KitLog (Get-KitText 'Output.Shield.RivalListener' -f 'Win32 output messages', ($rivals -join ', ')) -Level Info }
}
