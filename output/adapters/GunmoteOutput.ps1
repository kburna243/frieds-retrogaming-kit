<#
.SYNOPSIS
    Gunmote output-middleware adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    Gunmote receives MAME-style output messages over TCP (ArcadeHook on localhost:8000) and drives rumble
    and LED feedback via Wiimote. It does NOT read Win32 window messages — FFBBlaster, DemulShooter and
    standalone MAME outputs arrive through the recoil-stretch relay (output\tools\recoil-stretch.py),
    which translates Windows messages and FFBBlaster TCP to the single stream Gunmote understands.
    Gunmote is DETECTED, never installed as a service and never started by the kit. Detection reads a
    snapshot (processes, ports, devices, tools folder) so tests can inject everything.

    ─── SAFETY — READ THIS ───
    Rumble protection is NOT enforced by this adapter: the user must configure safe rumble thresholds in Gunmote's settings.json.
    The adapter notes the risk of double-rumble if MAMEHooker is also active.

    Kit deviations from the downloaded draft (deliberate, permanent):
      * The draft downloaded the Win64 ZIP from the vendor site — the kit never downloads. The adapter
        only names the official source; a user-supplied ZIP goes through Install-GunmoteOutputSoftware
        with -PackagePath and -Approved.
      * The draft overwrote settings.ini wholesale (Set-Content -Force) — the kit edits only files that
        ALREADY exist, through the backup/WhatIf path in Set-OutputMiddlewareConfiguration.
      * BoardMatchIds is empty — Gunmote has no hardware board identity; identification runs over process / folder.
#>

function Test-GunmoteOutputHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [hashtable] $Snapshot)
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-OutputSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-GunmoteOutputAdapterInfo
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
    # Additional detection: Gunmote's ArcadeOutputs folder (live system check)
    if (Test-Path 'C:\Program Files\Gunmote\ArcadeOutputs' -PathType Container) { return $true }
    $false
}

function Get-GunmoteOutputAdapterInfo {
    @{
        ToolDir         = 'Gunmote'
        DetectProcesses = @('Gunmote')   # without .exe, case-insensitive
        DetectPorts     = @()            # Gunmote is a TCP client, not a server
        BoardMatchIds   = @()            # no hardware board
        MameOutput      = 'network'      # Gunmote reads only TCP (ArcadeHook on localhost:8000)
        SettingsTargets = @()            # INIs are per mame_start name, managed via patch-once.ps1
        Links           = @{ 'Gunmote (gunmotelabs)' = 'https://gunmotelabs.com/' }
        Notes           = 'Gunmote reads outputs via TCP only (ArcadeHook on localhost:8000). Auto-creates INIs in C:\Program Files\Gunmote\ArcadeOutputs\<mame_start-Name>.ini. Output 0 = LED, Output 5 = Motor. Uses the recoil-stretch relay for FFBBlaster/DemulShooter/MAME translation. Note: MAMEHooker may also consume the same outputs causing double-rumble.'
    }
}

# Deliberately does NOT download: the kit only names the official source. The user fetches the ZIP and
# passes it as -PackagePath; with -Approved the kit unpacks it into tools\Gunmote. Without a
# package nothing happens beyond the hint — and Gunmote is never registered as a service or started.
function Install-GunmoteOutputSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-GunmoteOutputAdapterInfo
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

function Configure-GunmoteOutputProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    # Routes through the core so the Values hashtable is always applied — this function must never write settings.ini by hand.
    Set-OutputMiddlewareConfiguration -Names @('GunmoteOutput') -RetroBatRoot $RetroBatRoot -Confirm:$false
}

# Interference shield: Warns if MAMEHooker is also active (potential double-rumble).
function Set-GunmoteOutputInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    # Check if MAMEHooker process is running
    if (Get-Process -Name 'MAMEHooker' -ErrorAction SilentlyContinue) {
        Write-KitLog 'MAMEHooker is active; may cause double-rumble with Gunmote.' -Level Warn
    }
}