<#
.SYNOPSIS
    Arcade step 1: USB fightsticks, arcade encoders and steering wheels (GP2040-CE, Brook UFB, I-PAC,
    Zero Delay, Mad Catz, Hori, multi-console sticks, PS2 adapters, Xbox 360 Racing Wheel, Logitech,
    Thrustmaster/Fanatec, DIY wheels) as a device class beside the lightguns. Detect reads the PnP list
    only; configure writes mame.ini, retrobat.ini [Controllers], Model 2 / Supermodel settings and the
    Steam controller_blacklist - always with backup and -WhatIf support. Lightgun devices are never
    re-claimed here. With -Install the kit unpacks a user-supplied package (-PackagePath) into
    tools\<ToolDir>, but only with -Approved; without a package it only names the official source.
.PARAMETER RetroBatRoot
    RetroBat folder (default: arcade state, then the lightgun state — one cabinet, one RetroBat).
.PARAMETER Devices
    Injected device list (objects with InstanceId) instead of the present PnP devices (tests).
.PARAMETER Install
    Unpack -PackagePath into tools\ (needs -Approved).
.PARAMETER PackagePath
    Local ZIP with the vendor tool (portable; the kit never downloads it itself).
.PARAMETER SteamConfigVdf
    config.vdf to extend with the stick/wheel VIDs (tests); default: the Steam install found in the
    registry, '' = skip the Steam part on purpose.
.PARAMETER Approved
    Explicit permission for -Install to write into the RetroBat folder.
.PARAMETER StatePath
    install-state.json of the arcade package.
.PARAMETER Culture
    UI language (de-DE, en-US).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $RetroBatRoot,
    [object[]] $Devices,
    [switch] $Install,
    [string] $PackagePath,
    [string] $SteamConfigVdf,
    [switch] $Approved,
    [string] $StatePath,
    [string] $Culture
)
$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1')
Import-Module (Join-Path $kitRoot 'arcade\RetroCabinetKit.Arcade.psd1')
if ($Culture) { Set-KitCulture -Culture $Culture }
if (-not $StatePath) { $StatePath = Get-ArcadeDefaultStatePath }
if (-not $RetroBatRoot) { $RetroBatRoot = Get-ArcadeRetroBatRoot -StatePath $StatePath }

$detectParams = @{ RetroBatRoot = $RetroBatRoot }
if ($PSBoundParameters.ContainsKey('Devices')) { $detectParams.Devices = $Devices }
$found = Get-ArcadeDetectedAdapter @detectParams

$detectStep = New-KitStep -Name 'arcade-1-adapter-detect' `
    -Test { $true } `
    -Invoke {
        Set-KitStateValue -Path $StatePath -Key 'ArcadeAdapter' -Value $(if ($found.DetectedAdapter) { $found.DetectedAdapter } else { 'None' })
        Set-KitStateValue -Path $StatePath -Key 'ArcadeAdapterClass' -Value $found.DetectedClass
        Set-KitStateValue -Path $StatePath -Key 'ArcadeAdapterDevice' -Value $found.DetectedDeviceId
        if ($found.Success) { Write-KitLog (Get-KitText 'Arcade.Adapter.Detected' -f $found.DetectedAdapter) }
        else { Write-KitLog (Get-KitText 'Arcade.Adapter.None') }
        if ($found.DetectedAdapter) { Write-KitLog (Get-KitText 'Arcade.Adapter.NextStep' -f $found.NextStep) }
    } `
    -Verify {
        $saved = [string](Get-KitStateValue -Path $StatePath -Key 'ArcadeAdapter')
        $saved -eq $(if ($found.DetectedAdapter) { $found.DetectedAdapter } else { 'None' })
    }
Invoke-KitStep -Step $detectStep -StatePath $StatePath -WhatIf:$WhatIfPreference

$name = $found.DetectedAdapter
$devId = $found.DetectedDeviceId
# $PSBoundParameters inside the Invoke/Verify scriptblocks would see the scriptblock call (always empty);
# capture the caller's binding once here, outside.
$steamBound = $PSBoundParameters.ContainsKey('SteamConfigVdf')

$configureStep = New-KitStep -Name 'arcade-1-adapter-configure' `
    -Test { [bool]$name -and $RetroBatRoot } `
    -Invoke {
        if ($Install) {
            $null = Install-ArcadeAdapter -Name $name -RetroBatRoot $RetroBatRoot -PackagePath $PackagePath -Approved:$Approved
        }
        $cfgParams = @{ Name = $name; RetroBatRoot = $RetroBatRoot; DetectedDeviceId = $devId; Confirm = $false }
        if ($steamBound) { $cfgParams.SteamConfigVdf = $SteamConfigVdf }
        $null = Set-ArcadeAdapterConfiguration @cfgParams
    } `
    -Verify {
        if (-not $name) { return $false }
        $chkParams = @{ Name = $name; RetroBatRoot = $RetroBatRoot; DetectedDeviceId = $devId }
        if ($steamBound) { $chkParams.SteamConfigVdf = $SteamConfigVdf }
        Test-ArcadeAdapterConfiguration @chkParams
    }
Invoke-KitStep -Step $configureStep -StatePath $StatePath -WhatIf:$WhatIfPreference
