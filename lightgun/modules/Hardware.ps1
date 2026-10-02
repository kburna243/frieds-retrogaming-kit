# Hardware (step 2): how the Wiimotes connect, DolphinBar mode, Bluetooth service, real refresh rate per monitor.
# Read-only. Two connections are supported, and the later steps pick layouts and profiles by it:
#   DolphinBar  Mayflash DolphinBar in Mode 4: one USB device for all Wiimotes (no Bluetooth address per Wiimote)
#   Bluetooth   each Wiimote paired on its own over a Bluetooth adapter, with a plain IR bar (cabinet since 30.09.2026)
#   DolphinBar Mode 4       = USB\VID_057E&PID_0306 (Gunmote sees the Wiimotes only in this mode)
#   Mode 1/2 (mouse/keys)   = VID_0079&PID_1802
#   Gamepad mode            = VID_0079&PID_1803

$script:LightgunDolphinBarIds = [ordered]@{
    'VID_057E&PID_0306' = 'Mode4'
    'VID_0079&PID_1802' = 'Mode12'
    'VID_0079&PID_1803' = 'Gamepad'
}

# -Devices injects the device list (objects with InstanceId); default: present PnP devices.
function Get-LightgunDolphinBarState {
    [CmdletBinding()]
    param([object[]] $Devices)
    if (-not $PSBoundParameters.ContainsKey('Devices')) { $Devices = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue) }
    $modes = @(foreach ($d in $Devices) {
        foreach ($id in $script:LightgunDolphinBarIds.Keys) {
            if ([string]$d.InstanceId -match [regex]::Escape($id)) { $script:LightgunDolphinBarIds[$id] }
        }
    }) | Sort-Object -Unique
    [pscustomobject]@{
        Mode4     = $modes -contains 'Mode4'
        WrongMode = @($modes | Where-Object { $_ -ne 'Mode4' })
    }
}

# Wiimotes paired over Bluetooth: HID devices of the Bluetooth HID service with Nintendo's vendor id, RVL-CNT-01 (0306)
# or RVL-CNT-01-TR (0330). Over the DolphinBar they are USB devices and do not match.
$script:LightgunBtWiimotePattern = '^HID\\{00001124-[^}]+\}_VID&0002057E_PID&03(06|30)'

function Get-LightgunBluetoothWiimoteCount {
    [CmdletBinding()]
    param([object[]] $Devices)
    if (-not $PSBoundParameters.ContainsKey('Devices')) { $Devices = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue) }
    @($Devices | Where-Object { [string]$_.InstanceId -match $script:LightgunBtWiimotePattern }).Count
}

# 'DolphinBar' (a bar in Mode 4 is there), 'Bluetooth' (at least one Wiimote paired over Bluetooth) or '' (neither,
# e.g. Wiimotes switched off). A bar in Mode 4 wins: Gunmote then takes the Wiimotes through it.
function Get-LightgunConnection {
    [CmdletBinding()]
    param([object[]] $Devices)
    if (-not $PSBoundParameters.ContainsKey('Devices')) { $Devices = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue) }
    if ((Get-LightgunDolphinBarState -Devices $Devices).Mode4) { return 'DolphinBar' }
    if (Get-LightgunBluetoothWiimoteCount -Devices $Devices) { return 'Bluetooth' }
    ''
}

# With nothing connected right now: the connection used last. Windows keeps a paired Bluetooth Wiimote and a
# DolphinBar seen before in the device tree (not present) with the time it last arrived; the newest wins.
# -Devices injects objects with InstanceId and Arrived (tests).
function Get-LightgunLastConnection {
    [CmdletBinding()]
    param([object[]] $Devices)
    if (-not $PSBoundParameters.ContainsKey('Devices')) {
        $Devices = @(Get-PnpDevice -ErrorAction SilentlyContinue | Where-Object {
            [string]$_.InstanceId -match $script:LightgunBtWiimotePattern -or [string]$_.InstanceId -match 'VID_057E&PID_0306' } | ForEach-Object {
            [pscustomobject]@{ InstanceId = $_.InstanceId; Arrived = (Get-PnpDeviceProperty -InstanceId $_.InstanceId -KeyName DEVPKEY_Device_LastArrivalDate -ErrorAction SilentlyContinue).Data } })
    }
    $best = ''
    $bestDate = [datetime]::MinValue
    foreach ($d in $Devices) {
        if (-not $d.Arrived -or $d.Arrived -le $bestDate) { continue }
        if ([string]$d.InstanceId -match $script:LightgunBtWiimotePattern) { $best = 'Bluetooth' }
        elseif ([string]$d.InstanceId -match 'VID_057E&PID_0306') { $best = 'DolphinBar' }
        else { continue }
        $bestDate = $d.Arrived
    }
    $best
}

# The connection steps 6 and 8 work with: the parameter, else the one recorded in the state, else the one connected
# now, else the one used last, else DolphinBar (the kit's original route). Step 6 records it when it writes.
function Resolve-LightgunConnection {
    [CmdletBinding()]
    param([string] $Connection, [Parameter(Mandatory)] [string] $StatePath, [object[]] $Devices, [object[]] $History)
    $c = if ($Connection) { $Connection } elseif (Test-Path -LiteralPath $StatePath -PathType Leaf) { [string](Get-KitStateValue -Path $StatePath -Key 'WiimoteConnection') } else { '' }
    if (-not $c) {
        $d = @{}; if ($PSBoundParameters.ContainsKey('Devices')) { $d.Devices = $Devices }
        $c = Get-LightgunConnection @d
    }
    if (-not $c) {
        $h = @{}; if ($PSBoundParameters.ContainsKey('History')) { $h.Devices = $History }
        $c = Get-LightgunLastConnection @h
    }
    if ($c -notin 'DolphinBar', 'Bluetooth') {
        Write-KitLog (Get-KitText 'Lightgun.Hw.ConnectionUnknown') -Level Warn
        return 'DolphinBar'
    }
    Write-KitLog (Get-KitText 'Lightgun.Hw.Connection' -f $c)
    $c
}

# -Service injects the service object (Status, StartType); $null = no Bluetooth on this machine.
function Get-LightgunBluetoothState {
    [CmdletBinding()]
    param([object] $Service)
    if (-not $PSBoundParameters.ContainsKey('Service')) { $Service = Get-Service -Name 'bthserv' -ErrorAction SilentlyContinue }
    if (-not $Service) { return [pscustomobject]@{ Present = $false; Running = $false; StartType = '' } }
    [pscustomobject]@{ Present = $true; Running = [string]$Service.Status -eq 'Running'; StartType = [string]$Service.StartType }
}

# Level per monitor: Ok (59-61 Hz), Warn (below 50 Hz, e.g. a TV left at 30 Hz: emulators run at half speed),
# Info (any other rate: works, 60 Hz is recommended). The rate is the real display mode (EnumDisplaySettings).
function Get-LightgunRefreshReport {
    [CmdletBinding()]
    param([object[]] $Monitors)
    if (-not $PSBoundParameters.ContainsKey('Monitors')) { $Monitors = @(Get-KitMonitor) }
    foreach ($m in $Monitors) {
        $hz = [int]$m.RefreshRate
        $level = if ($hz -ge 59 -and $hz -le 61) { 'Ok' } elseif ($hz -gt 0 -and $hz -lt 50) { 'Warn' } else { 'Info' }
        [pscustomobject]@{ DeviceName = $m.DeviceName; Width = $m.Width; Height = $m.Height; RefreshRate = $hz; Level = $level }
    }
}

# Logs the findings; returns $true when the DolphinBar is in Mode 4 and no monitor runs below 50 Hz.
function Test-LightgunHardware {
    [CmdletBinding()]
    param([object[]] $Devices, [object] $Service, [object[]] $Monitors, [switch] $Quiet)
    $a = @{}; if ($PSBoundParameters.ContainsKey('Devices')) { $a.Devices = $Devices }
    $b = @{}; if ($PSBoundParameters.ContainsKey('Service')) { $b.Service = $Service }
    $c = @{}; if ($PSBoundParameters.ContainsKey('Monitors')) { $c.Monitors = $Monitors }
    $bar = Get-LightgunDolphinBarState @a
    $bt = Get-LightgunBluetoothState @b
    $btWiimotes = Get-LightgunBluetoothWiimoteCount @a
    $rates = @(Get-LightgunRefreshReport @c)
    if (-not $Quiet) {
        if ($bar.Mode4) { Write-KitLog (Get-KitText 'Lightgun.Hw.Mode4') }
        elseif ($btWiimotes) { Write-KitLog (Get-KitText 'Lightgun.Hw.BtWiimotes' -f $btWiimotes) }
        else { Write-KitLog (Get-KitText 'Lightgun.Hw.NoMode4') -Level Warn }
        foreach ($m in $bar.WrongMode) { Write-KitLog (Get-KitText "Lightgun.Hw.$m") -Level Warn }
        # Only next to a DolphinBar: old pairings can then take Wiimotes away from it. Bluetooth Wiimotes need it.
        if ($bt.Running -and $bar.Mode4) { Write-KitLog (Get-KitText 'Lightgun.Hw.Bluetooth') -Level Warn }
        foreach ($r in $rates) {
            $level = if ($r.Level -eq 'Warn') { 'Warn' } else { 'Info' }
            Write-KitLog (Get-KitText "Lightgun.Hw.Refresh.$($r.Level)" -f $r.DeviceName, $r.Width, $r.Height, $r.RefreshRate) -Level $level
        }
    }
    ($bar.Mode4 -or $btWiimotes -gt 0) -and -not @($rates | Where-Object { $_.Level -eq 'Warn' }).Count
}
