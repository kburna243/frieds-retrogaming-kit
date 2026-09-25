# Hardware (step 2): DolphinBar mode, Bluetooth service, real refresh rate per monitor. Read-only.
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
    $rates = @(Get-LightgunRefreshReport @c)
    if (-not $Quiet) {
        if ($bar.Mode4) { Write-KitLog (Get-KitText 'Lightgun.Hw.Mode4') }
        else { Write-KitLog (Get-KitText 'Lightgun.Hw.NoMode4') -Level Warn }
        foreach ($m in $bar.WrongMode) { Write-KitLog (Get-KitText "Lightgun.Hw.$m") -Level Warn }
        if ($bt.Running) { Write-KitLog (Get-KitText 'Lightgun.Hw.Bluetooth') -Level Warn }
        foreach ($r in $rates) {
            $level = if ($r.Level -eq 'Warn') { 'Warn' } else { 'Info' }
            Write-KitLog (Get-KitText "Lightgun.Hw.Refresh.$($r.Level)" -f $r.DeviceName, $r.Width, $r.Height, $r.RefreshRate) -Level $level
        }
    }
    $bar.Mode4 -and -not @($rates | Where-Object { $_.Level -eq 'Warn' }).Count
}
