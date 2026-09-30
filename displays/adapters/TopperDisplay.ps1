<#
.SYNOPSIS
    Topper Display output-middleware adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    Topper Display detects a fourth monitor (or higher) positioned above the backglass
    for displaying topper information in pinball cabinets. It is DETECTED, never installed
    as a service and never started by the kit. Detection reads a snapshot (processes, ports,
    devices, tools folder) so tests can inject everything.

    ─── SAFETY — READ THIS ───
    This adapter does not enforce safety limits; safety is handled by the core module.

    Kit deviations from the downloaded draft (deliberate, permanent):
      * The draft attempted to download topper detection tools - the kit never downloads.
        The adapter only names official sources; a user-supplied ZIP goes through
        Install-TopperDisplaySoftware with -PackagePath and -Approved.
      * Topper detection relies on WMI monitor count (WmiMonitorID) - 4+ monitors indicates
        a topper setup.
      * No specific tools folder or processes are required for basic topper detection.
      * Configuration suggests topper monitor assignment but does not write files
        directly - routes through core configuration system.
#>

function Test-TopperDisplayHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [hashtable] $Snapshot)
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-OutputSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-TopperDisplayAdapterInfo
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
    # Topper display is present if 4 or more monitors are detected
    try {
        $monitors = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop
        return ($monitors.Count -ge 4)
    } catch {
        # Fallback: if WMI fails, we cannot reliably detect topper
        return $false
    }
}

function Get-TopperDisplayAdapterInfo {
    @{
        ToolDir         = ''                               # no specific tools folder required
        DetectProcesses = @()                              # no specific processes to detect
        DetectPorts     = @()                              # no ports to detect
        BoardMatchIds   = @()                              # no device IDs to match
        MameOutput      = ''                               # not applicable to monitor detection
        SettingsTargets = @()                              # monitor configuration handled by Windows/Drivers
        Links           = @{}                              # no specific download links
        Notes           = 'Topper detection via WmiMonitorID; 4+ monitors indicates topper setup above backglass.'
    }
}

# Deliberately does NOT download: the kit only names the official source. The user fetches the ZIP
# and passes it as -PackagePath; with -Approved the kit unpacks it into tools\ (if needed). Without a
# package nothing happens beyond the hint - and topper detection is handled by Windows.
function Install-TopperDisplaySoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-TopperDisplayAdapterInfo
    $target = Join-Path $RetroBatRoot "tools\$($info.ToolDir)"
    if (-not $PackagePath) {
        # No specific links to show for topper detection
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

function Configure-TopperDisplayProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    # Routes through the core so topper configuration suggestions can be processed
    # Actual monitor configuration is handled by Windows graphics drivers
    Set-OutputMiddlewareConfiguration -Names @('TopperDisplay') -RetroBatRoot $RetroBatRoot -Confirm:$false
}

# Interference shield, kit style: monitors don't typically own ports that interfere,
# but Windows display renumbering can cause issues for topper setups.
function Set-TopperDisplayInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-TopperDisplayAdapterInfo
    foreach ($p in @(Get-OutputAdapterValue $info 'DetectPorts')) {
        $owner = @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name } | Select-Object -Unique)
        if ($owner.Count) { Write-KitLog (Get-KitText 'Output.Shield.PortOwner' -f $p, ($owner -join ', ')) -Level Info }
    }
    # Warn about potential Windows display renumbering issues affecting topper
    try {
        $monitors = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID -ErrorAction Stop
        if ($monitors.Count -ge 4) {
            Write-KitLog (Get-KitText 'Output.Shield.Warning' -f 'Topper setup detected ($($monitors.Count) monitors). Windows may renumber displays after reboot, affecting topper assignment.') -Level Info
        }
    } catch {
        # Ignore WMI errors in shield function
    }
}