<#
.SYNOPSIS
    Logitech G-series wheel adapter for Fried's Retrogaming Kit (Wheel class).
.DESCRIPTION
    Detects Logitech Driving Force / G25 / G27 / G29-era wheels by seven tight
    USB\VID_046D&PID_* signatures, with name hints as a second signal only.
    Detection is read-only; every write goes through the audited writers in
    arcade\modules\Adapters.ps1.

    DRIVER POLICY - MANUAL: Logitech Gaming Software (LGS) 5.10 is the LAST version
    exposing a real DirectInput force-feedback API. G Hub re-routes the wheels
    through its own stack and caps that legacy FFB path - which is exactly the path
    the emulators use - so Links names LGS 5.10, NOT G Hub. The kit installs no
    driver at all; it only names the source and configures the emulators.

    COMBINED PEDALS (quirk 'combined-pedals'): out of the box a G29 reports throttle
    and brake on ONE axis (the Z axis) instead of two separate pedals. Splitting them
    requires an LGS profile - manual work on the user's side. The kit reports the
    quirk instead of silently pretending the pedals are split.

    MODEL 2 / SUPERMODEL NOTE: Model2Values targets emulators\m2emulator\Emulator.ini
    (root section) and SupermodelValues targets emulators\supermodel\Config\
    Supermodel.ini ([Global]). Those INIs usually DO NOT EXIST unless the emulator
    is installed. The writers only ever modify existing files and never create
    them, so on a machine without Model 2 / Supermodel the two tables below are
    inert - safe by design, but documented half-knowledge: no FFB switch was
    promised beyond what RetroBat and MAME actually received.
#>

function Test-LogitechWheelHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [object[]] $Devices)
    # Read-only! $Devices (objects with InstanceId) replaces the live PnP list in tests.
    if (-not $PSBoundParameters.ContainsKey('Devices') -or -not $Devices) {
        $Devices = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue)
    }
    $info = Get-LogitechWheelAdapterInfo
    foreach ($d in @($Devices | Where-Object { $_ })) {
        $id = (Get-ArcadeDeviceId $d).ToUpperInvariant()
        foreach ($m in $info.MatchIds) { if ($id -like $m.ToUpperInvariant()) { return $true } }
        # Name hints are only the second signal, never a bare-VID style fallback.
        $name = Get-ArcadeDeviceName $d
        if ($name) { foreach ($h in $info.NameHints) { if ($name -like $h) { return $true } } }
    }
    $false
}

function Get-LogitechWheelAdapterInfo {
    @{
        Class     = 'Wheel'
        ToolDir   = 'LogitechWheel'
        MatchIds  = @(
            'USB\VID_046D&PID_C299*', 'USB\VID_046D&PID_C29B*', 'USB\VID_046D&PID_C24F*',
            'USB\VID_046D&PID_C262*', 'USB\VID_046D&PID_C29A*', 'USB\VID_046D&PID_C294*',
            'USB\VID_046D&PID_C266*'
        )
        NameHints = @('*Logitech*G2*', '*Logitech*G9*', '*Logitech*Driving*')
        Quirks    = @('combined-pedals')
        SteamEntries = @('0x046d/0xc299', '0x046d/0xc29b', '0x046d/0xc24f', '0x046d/0xc262')
        MameValues        = [ordered]@{ joystick = '1'; paddle_device = 'joystick'; pedal_device = 'joystick' }
        ControllersValues = [ordered]@{ Autocontrollers = '1'; WheelForceFeedback = '1'; WheelRotation = '900' }
        # Wired only when emulators\m2emulator\Emulator.ini exists (see header).
        Model2Values = [ordered]@{ UseFeedback = '1'; EnableDirectInput = '1' }
        # Wired only when ...\supermodel\Config\Supermodel.ini exists (see header).
        SupermodelValues = [ordered]@{ ForceFeedback = '1' }
        Links = @{
            'Logitech Gaming Software 5.10 (manual install, NOT G HUB)' = 'https://www.logitech.com/en-gb/software/g-gaming/logitech-gaming-software.html'
        }
    }
}

# Deliberately does NOT download: no driver ships with the kit (LGS 5.10 is manual work,
# see header). With -PackagePath and -Approved the kit unpacks a ZIP the user fetched
# themselves into tools\LogitechWheel; without a package it only names the official link.
function Install-LogitechWheelSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-LogitechWheelAdapterInfo
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

function Configure-LogitechWheelProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $DetectedDeviceId, [string] $SteamConfigVdf)
    $params = @{ Name = 'LogitechWheel'; RetroBatRoot = $RetroBatRoot; DetectedDeviceId = $DetectedDeviceId }
    if ($PSBoundParameters.ContainsKey('SteamConfigVdf')) { $params.SteamConfigVdf = $SteamConfigVdf }
    Set-ArcadeAdapterConfiguration @params -Confirm:$false
}

# Interference shield, kit style: Steam Input is blocked from grabbing the wheel via
# controller_blacklist. Adding entries never hurts; -Disable only reports. No process kill, ever.
function Set-LogitechWheelInterferenceShield {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [switch] $Disable, [string] $SteamConfigVdf = '')
    if ($Disable) { Write-KitLog (Get-KitText 'Arcade.Adapter.ShieldReportsOnly') -Level Info; return }
    $info = Get-LogitechWheelAdapterInfo
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
