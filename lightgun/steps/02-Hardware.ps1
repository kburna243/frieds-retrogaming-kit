<#
.SYNOPSIS
    Lightgun step 2 (check only, changes nothing): DolphinBar in Mode 4 (USB\VID_057E&PID_0306; Mode 1/2 and
    gamepad mode are recognized and explained), Bluetooth service hint, real refresh rate per monitor
    (60 Hz recommended, below 50 Hz = warning). Green when Mode 4 is present and no monitor runs below 50 Hz.
.PARAMETER Devices
    Injected device list (objects with InstanceId) instead of the present PnP devices (tests).
.PARAMETER BluetoothService
    Injected service object (Status, StartType) instead of bthserv (tests).
.PARAMETER Monitors
    Injected monitors (DeviceName, Width, Height, RefreshRate) instead of the real ones (tests).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [object[]] $Devices,
    [object] $BluetoothService,
    [object[]] $Monitors,
    [string] $StatePath,
    [string] $Culture
)
$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1')
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1')
if ($Culture) { Set-KitCulture -Culture $Culture }
if (-not $StatePath) { $StatePath = Get-LightgunDefaultStatePath }

$hw = @{}
if ($PSBoundParameters.ContainsKey('Devices')) { $hw.Devices = $Devices }
if ($PSBoundParameters.ContainsKey('BluetoothService')) { $hw.Service = $BluetoothService }
if ($PSBoundParameters.ContainsKey('Monitors')) { $hw.Monitors = $Monitors }
$ok = Test-LightgunHardware @hw

# Check-only step: Verify is the live measurement, so a green state never outlives an unplugged DolphinBar.
$step = New-KitStep -Name 'lightgun-2-hardware' -Test { $ok } -Invoke { } -Verify { $ok }
Invoke-KitStep -Step $step -StatePath $StatePath -WhatIf:$WhatIfPreference
