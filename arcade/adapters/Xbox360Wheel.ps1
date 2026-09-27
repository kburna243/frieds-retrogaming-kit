<#
.SYNOPSIS
    Xbox 360 racing wheel adapter for Fried's Retrogaming Kit (Wheel class).
.DESCRIPTION
    Detects the Xbox 360 Wireless Racing Wheel behind its USB receiver
    (USB\VID_045E&PID_0719) and the wired wheel signature (USB\VID_045E&PID_0291).
    Detection is read-only; every write goes through the audited writers in
    arcade\modules\Adapters.ps1 (backup, encoding kept, WhatIf, Steam
    controller_blacklist instead of any process kill).

    FORCE FEEDBACK CAVEAT: the community driver for this wheel is the Lavendy FFB
    package. That is a KERNEL FILTER DRIVER - installed via msiexec, writing to
    HKLM. THE KIT DOES NOT INSTALL IT. Driver work stays manual; this adapter only
    names the source (see Links) and flips the emulator-side FFB switches that a
    properly installed driver needs to become useful.

    MODEL 2 / SUPERMODEL NOTE: Model2Values targets emulators\m2emulator\Emulator.ini
    (root section) and SupermodelValues targets emulators\supermodel\Config\
    Supermodel.ini ([Global]). Those INIs usually DO NOT EXIST unless the emulator
    is installed. The writers only ever modify existing files and never create
    them, so on a machine without Model 2 / Supermodel the two tables below are
    inert - safe by design, but this is documented half-knowledge: no FFB switch
    was promised beyond what RetroBat and MAME actually received.
#>

function Test-Xbox360WheelHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [object[]] $Devices)
    # Read-only! $Devices (objects with InstanceId) replaces the live PnP list in tests.
    if (-not $PSBoundParameters.ContainsKey('Devices') -or -not $Devices) {
        $Devices = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue)
    }
    $info = Get-Xbox360WheelAdapterInfo
    foreach ($d in @($Devices | Where-Object { $_ })) {
        $id = (Get-ArcadeDeviceId $d).ToUpperInvariant()
        foreach ($m in $info.MatchIds) { if ($id -like $m.ToUpperInvariant()) { return $true } }
        # Name hints are only the second signal, never a bare-VID style fallback.
        $name = Get-ArcadeDeviceName $d
        if ($name) { foreach ($h in $info.NameHints) { if ($name -like $h) { return $true } } }
    }
    $false
}

function Get-Xbox360WheelAdapterInfo {
    @{
        Class     = 'Wheel'
        ToolDir   = 'Xbox360Wheel'
        MatchIds  = @('USB\VID_045E&PID_0719*', 'USB\VID_045E&PID_0291*')
        NameHints = @('*Xbox 360 Wireless Racing Wheel*')
        Quirks    = @('needs-lavendy-ffb-driver')
        SteamEntries = @('0x045e/0x0719')
        MameValues        = [ordered]@{ joystick = '1'; paddle_device = 'joystick'; pedal_device = 'joystick' }
        ControllersValues = [ordered]@{ Autocontrollers = '1'; WheelForceFeedback = '1'; WheelRotation = '270' }
        # Wired only when emulators\m2emulator\Emulator.ini exists (see header).
        Model2Values = [ordered]@{ UseFeedback = '1'; EnableDirectInput = '1' }
        # Wired only when ...\supermodel\Config\Supermodel.ini exists (see header).
        SupermodelValues = [ordered]@{ ForceFeedback = '1' }
        Links = @{
            'Lavendy FFB driver (manual install)' = 'http://lavendy.net/'
            'Xbox 360 Wireless Racing Wheel'      = 'https://en.wikipedia.org/wiki/Xbox_360_Wireless_Racing_Wheel'
        }
    }
}

# Deliberately does NOT download: the Lavendy driver is a kernel filter driver and manual work.
# With -PackagePath and -Approved the kit unpacks a ZIP the user fetched themselves into
# tools\Xbox360Wheel; without a package it only names the official links.
function Install-Xbox360WheelSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-Xbox360WheelAdapterInfo
    $target = Join-Path $RetroBatRoot "tools\$($info.ToolDir)"
    if (-not $PackagePath) {
        foreach ($k in $info.Links.Keys) { Write-KitLog (Get-KitText 'Arcade.Adapter.SoftwareLink' -f $k, $info.Links[$k]) }
        return $false
    }
    if (-not $Approved.IsPresent) { Write-KitLog (Get-KitText 'Arcade.Adapter.NeedsApproval') -Level Warn; return $false }
    if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) { Write-KitLog (Get-KitText 'Arcade.Adapter.PackageMissing' -f $PackagePath) -Level Warn; return $false }
    if (-not $PSCmdlet.ShouldProcess($target, 'unpack adapter package')) { return $false }
    $null = New-Item -ItemType Directory -Path $target -Force
    Write-KitLog (Get-KitText 'Arcade.Adapter.PackageHash' -f (Split-Path -Leaf $PackagePath), (Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash)
    Expand-Archive -LiteralPath $PackagePath -DestinationPath $target -Force
    Write-KitLog (Get-KitText 'Arcade.Adapter.SoftwareInstalled' -f $info.ToolDir, $target)
    $true
}

function Configure-Xbox360WheelProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $DetectedDeviceId, [string] $SteamConfigVdf)
    $params = @{ Name = 'Xbox360Wheel'; RetroBatRoot = $RetroBatRoot; DetectedDeviceId = $DetectedDeviceId }
    if ($PSBoundParameters.ContainsKey('SteamConfigVdf')) { $params.SteamConfigVdf = $SteamConfigVdf }
    Set-ArcadeAdapterConfiguration @params -Confirm:$false
}

# Interference shield, kit style: Steam Input is blocked from grabbing the wheel via
# controller_blacklist. Adding entries never hurts; -Disable only reports. No process kill, ever.
function Set-Xbox360WheelInterferenceShield {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [switch] $Disable, [string] $SteamConfigVdf = '')
    if ($Disable) { Write-KitLog (Get-KitText 'Arcade.Adapter.ShieldReportsOnly') -Level Info; return }
    $info = Get-Xbox360WheelAdapterInfo
    $se = @($info.SteamEntries)
    if (-not $se.Count) { return }
    if (-not $SteamConfigVdf) {
        $steam = Get-LightgunSteamPath
        if (-not $steam) { Write-KitLog (Get-KitText 'Arcade.Adapter.NoSteam') -Level Warn; return }
        $SteamConfigVdf = Join-Path $steam 'config\config.vdf'
    }
    if (Test-Path -LiteralPath $SteamConfigVdf -PathType Leaf) {
        $null = Set-LightgunSteamBlacklist -ConfigVdf $SteamConfigVdf -ExtraEntries $se -Confirm:$false
    }
}
