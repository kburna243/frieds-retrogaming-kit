<#
.SYNOPSIS
    Hook of the Reaper (HoTR) output-middleware adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    Hook of the Reaper receives MAME's Win32 output messages and drives gun feedback — rumble and, its
    signature feature, the fire solenoid. It is DETECTED, never installed as a service and never
    started by the kit. Detection reads a snapshot (processes, ports, devices, tools folder) so tests
    can inject everything.

    ─── SAFETY — READ THIS ───
    Solenoid protection is ENFORCED, not optional: without a max-open-time limit a feedback solenoid
    held on by continuous fire ("Dauerfeuer") draws stall current until the COIL BURNS OUT. The two
    Safety values below — SolenoidMaxOpenTime = 200 (ms) and SolenoidProtection = 1 — sit in the
    adapter's Safety hashtable, which the core module always writes over Values on every Configure
    run. They are NEVER user-editable through this adapter, and no other file may relax them.

    Kit deviations from the downloaded draft (deliberate, permanent):
      * The draft downloaded the Win64 ZIP from the vendor site — the kit never downloads. The adapter
        only names the official source; a user-supplied ZIP goes through Install-HookOfTheReaperSoftware
        with -PackagePath and -Approved.
      * The draft overwrote settings.ini wholesale (Set-Content -Force) — the kit edits only files that
        ALREADY exist, through the backup/WhatIf path in Set-OutputMiddlewareConfiguration.
      * BoardMatchIds is tightened: VID_16C0 alone is not HoTR — that Vendor ID (Princeton / generic
        HID) is shared with Xin-Mo and RetroShooter-style signals, so only the board's own PID is
        claimed (16C0&PID_0006, typical Reaper board). The draft additionally matched Gun4IR
        (2341/8036), OpenFIRE (2E8A/000A) and AimTrak (D209/160*) VIDs: those are DEVICES Hook of the
        Reaper drives, not the identity of the program, and they were removed. Program identification
        runs over process / port / tools folder.
#>

function Test-HookOfTheReaperHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [hashtable] $Snapshot)
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-OutputSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-HookOfTheReaperAdapterInfo
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

function Get-HookOfTheReaperAdapterInfo {
    @{
        ToolDir         = 'HookOfTheReaper'
        DetectProcesses = @('Hook of the Reaper', 'HookOfTheReaper', 'HOTR')   # without .exe, case-insensitive
        DetectPorts     = @(8000)                                              # HoTR's own TCP server (remote control), not MAME output
        # Only the Reaper board's own signature — bare VID_16C0 also covers Xin-Mo / RetroShooter
        # signals. Guns HoTR merely drives (Gun4IR, OpenFIRE, AimTrak) are NOT part of its identity.
        BoardMatchIds   = @('USB\VID_16C0&PID_0006*')
        MameOutput      = 'windows'                                            # mame.ini: output = windows (Win32 messages)
        SettingsTargets = @(
            @{
                File    = 'settings.ini'
                Section = ''                              # root section
                # SAFETY (enforced, never user-editable — see header): 200 ms max solenoid open time +
                # protection switch. Without these, continuous fire holds the coil and it burns out.
                Safety  = @{ SolenoidMaxOpenTime = '200'; SolenoidProtection = '1' }
                Values  = @{ TcpServerPort = '8000'; EnableTcpServer = '1' }
            }
        )
        Links           = @{ 'Hook of the Reaper' = 'https://hotr.6bolt.express/' }
        Notes           = 'Port 8000; conflicts with local web servers on 8000.'
    }
}

# Deliberately does NOT download: the kit only names the official source. The user fetches the ZIP and
# passes it as -PackagePath; with -Approved the kit unpacks it into tools\HookOfTheReaper. Without a
# package nothing happens beyond the hint — and HoTR is never registered as a service or started.
function Install-HookOfTheReaperSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-HookOfTheReaperAdapterInfo
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

function Configure-HookOfTheReaperProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    # Routes through the core so the Safety hashtable (200 ms solenoid cap) is always enforced on the
    # existing settings.ini — this function must never write settings.ini by hand.
    Set-OutputMiddlewareConfiguration -Names @('HookOfTheReaper') -RetroBatRoot $RetroBatRoot -Confirm:$false
}

# Interference shield, kit style: HoTR binds TCP 8000 for its remote-control server, a port local web
# servers love. The shield only REPORTS the owning process — never kills it, never rebinds, no service.
function Set-HookOfTheReaperInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-HookOfTheReaperAdapterInfo
    foreach ($p in $info.DetectPorts) {
        $owner = @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name } | Select-Object -Unique)
        if ($owner.Count) { Write-KitLog (Get-KitText 'Output.Shield.PortOwner' -f $p, ($owner -join ', ')) -Level Info }
    }
}
