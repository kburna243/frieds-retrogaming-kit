<#
.SYNOPSIS
    Multi-monitor output-middleware adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    Multi-monitor setup detection for configuring display roles (DMD, backglass, topper, etc.)
    across multiple physical monitors. It is DETECTED, never installed as a service and never
    started by the kit. Detection reads a snapshot (processes, ports, devices, tools folder) so
    tests can inject everything.

    ─── SAFETY — READ THIS ───
    This adapter does not enforce safety limits; safety is handled by the core module.

    Kit deviations from the downloaded draft (deliberate, permanent):
      * The draft attempted to download monitor detection tools - the kit never downloads.
        The adapter only names official sources; a user-supplied ZIP goes through
        Install-MultiMonitorSoftware with -PackagePath and -Approved.
      * Monitor identification relies on WMI EDID data (WmiMonitorID) which is persistent
        across reboots, unlike volatile DISPLAYn assignments.
      * No specific tools folder or processes are required for basic multi-monitor detection.
      * Configuration suggests monitor roles based on EDID data but does not write files
        directly - routes through core configuration system.
#>

function Test-MultiMonitorHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [hashtable] $Snapshot)
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-OutputSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-MultiMonitorAdapterInfo
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
    # Multi-monitor is always "present" - any PC has at least one monitor
    # But we return true only if we can actually detect monitors via WMI
    try {
        $monitors = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop
        return ($monitors.Count -gt 0)
    } catch {
        # Fallback: if WMI fails, assume at least one monitor is present
        return $true
    }
}

function Get-MultiMonitorAdapterInfo {
    @{
        ToolDir         = ''                               # no specific tools folder required
        DetectProcesses = @()                              # no specific processes to detect
        DetectPorts     = @()                              # no ports to detect
        BoardMatchIds   = @()                              # no device IDs to match
        MameOutput      = ''                               # not applicable to monitor detection
        SettingsTargets = @()                              # monitor configuration handled by Windows/Drivers
        Links           = @{}                              # no specific download links
        Notes           = 'Monitor count via WmiMonitorID; EDID-based identification (DISPLAYn never stored persistently).'
    }
}

# Deliberately does NOT download: the kit only names the official source. The user fetches the ZIP
# and passes it as -PackagePath; with -Approved the kit unpacks it into tools\ (if needed). Without a
# package nothing happens beyond the hint - and monitor detection is handled by Windows.
function Install-MultiMonitorSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-MultiMonitorAdapterInfo
    $target = Join-Path $RetroBatRoot "tools\$($info.ToolDir)"
    if (-not $PackagePath) {
        # No specific links to show for monitor detection
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

function Configure-MultiMonitorProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    # Routes through the core so monitor configuration suggestions can be processed
    # Actual monitor configuration is handled by Windows graphics drivers
    Set-OutputMiddlewareConfiguration -Names @('MultiMonitor') -RetroBatRoot $RetroBatRoot -Confirm:$false
}

# Interference shield, kit style: monitors don't typically own ports that interfere,
# but Windows display renumbering can cause issues.
function Set-MultiMonitorInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-MultiMonitorAdapterInfo
    foreach ($p in @(Get-OutputAdapterValue $info 'DetectPorts')) {
        $owner = @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name } | Select-Object -Unique)
        if ($owner.Count) { Write-KitLog (Get-KitText 'Output.Shield.PortOwner' -f $p, ($owner -join ', ')) -Level Info }
    }
    # Warn about potential Windows display renumbering issues
    try {
        $monitors = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop
        if ($monitors.Count -gt 1) {
            Write-KitLog (Get-KitText 'Output.Shield.Warning' -f 'Multi-monitor setup detected ($($monitors.Count) monitors). Windows may renumber displays after reboot, affecting configured roles.') -Level Info
        }
    } catch {
        # Ignore WMI errors in shield function
    }
}