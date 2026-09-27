<#
.SYNOPSIS
    Lightgun step 15: USB lightgun adapters (Gun4IR, OpenFIRE, AimTrak, Retro Shooter) as a route beside
    the Wiimote/DolphinBar path. Detect reads the PnP list only; configure writes mame.ini, retrobat.ini
    [Guns], the detected gun into DemulShooter [Player1] and the gun VIDs into Steam's controller_blacklist
    - always with backup and -WhatIf support. With -Install the kit unpacks a user-supplied adapter
    package (-PackagePath) into tools\<ToolDir>, but only with -Approved; without a package it only names
    the official source. This step never touches the Wiimote steps 2-8.
.PARAMETER RetroBatRoot
    RetroBat folder (default: RetroBatRoot from install-state.json, written by step 1).
.PARAMETER Devices
    Injected device list (objects with InstanceId) instead of the present PnP devices (tests).
.PARAMETER Install
    Unpack -PackagePath into tools\ (needs -Approved).
.PARAMETER PackagePath
    Local ZIP with the vendor tool suite (portable; the kit never downloads it itself).
.PARAMETER SteamConfigVdf
    config.vdf to extend with the gun VIDs (tests); default: the Steam install found in the registry,
    '' = skip the Steam part on purpose.
.PARAMETER Approved
    Explicit permission for -Install to write into the RetroBat folder.
.PARAMETER StatePath
    install-state.json of the lightgun package.
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
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1')
if ($Culture) { Set-KitCulture -Culture $Culture }
if (-not $StatePath) { $StatePath = Get-LightgunDefaultStatePath }
if (-not $RetroBatRoot) { $RetroBatRoot = [string](Get-KitStateValue -Path $StatePath -Key 'RetroBatRoot') }

$detectParams = @{ RetroBatRoot = $RetroBatRoot }
if ($PSBoundParameters.ContainsKey('Devices')) { $detectParams.Devices = $Devices }
$found = Get-LightgunDetectedAdapter @detectParams

$detectStep = New-KitStep -Name 'lightgun-15-adapter-detect' `
    -Test { $true } `
    -Invoke {
        Set-KitStateValue -Path $StatePath -Key 'LightgunAdapter' -Value $(if ($found.DetectedAdapter) { $found.DetectedAdapter } else { 'None' })
        Set-KitStateValue -Path $StatePath -Key 'LightgunAdapterDevice' -Value $found.DetectedDeviceId
        if ($found.Success) { Write-KitLog (Get-KitText 'Lightgun.Adapter.NextStep' -f $found.NextStep) }
    } `
    -Verify {
        $saved = [string](Get-KitStateValue -Path $StatePath -Key 'LightgunAdapter')
        $saved -eq $(if ($found.DetectedAdapter) { $found.DetectedAdapter } else { 'None' })
    }
Invoke-KitStep -Step $detectStep -StatePath $StatePath -WhatIf:$WhatIfPreference

$name = $found.DetectedAdapter
$devId = $found.DetectedDeviceId
# $PSBoundParameters inside the Invoke/Verify scriptblocks would see the scriptblock call (always empty);
# capture the caller's binding once here, outside.
$steamBound = $PSBoundParameters.ContainsKey('SteamConfigVdf')

$configureStep = New-KitStep -Name 'lightgun-15-adapter-configure' `
    -Test { [bool]$name -and $RetroBatRoot } `
    -Invoke {
        if ($Install) {
            $null = Install-LightgunAdapter -Name $name -RetroBatRoot $RetroBatRoot -PackagePath $PackagePath -Approved:$Approved
        }
        $cfgParams = @{ Name = $name; RetroBatRoot = $RetroBatRoot; DetectedDeviceId = $devId; Confirm = $false }
        if ($steamBound) { $cfgParams.SteamConfigVdf = $SteamConfigVdf }
        $null = Set-LightgunAdapterConfiguration @cfgParams
    } `
    -Verify {
        if (-not $name) { return $false }
        $chkParams = @{ Name = $name; RetroBatRoot = $RetroBatRoot; DetectedDeviceId = $devId }
        if ($steamBound) { $chkParams.SteamConfigVdf = $SteamConfigVdf }
        Test-LightgunAdapterConfiguration @chkParams
    }
Invoke-KitStep -Step $configureStep -StatePath $StatePath -WhatIf:$WhatIfPreference
