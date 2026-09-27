<#
.SYNOPSIS
    Sinden Lightgun adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    The Sinden gun is camera-based (computer vision, not IR): its muzzle camera streams the screen to
    the PC, where the Sinden software derives the aim point from the four corners of a white border
    around the play area. Detection is read-only and works without the kit module; the other functions
    need the kit context (lightgun\adapters\README.md).

    USB: every Sinden endpoint enumerates under VID_16C0 (Van Ooijen / Princeton — a generic MCU vendor
    id). The PnP signatures are 0x0F01 (player 1), 0x0F02 (player 2), 0x0F38/0x0F39 (the recoil models)
    and 0x0F37 (the UVC camera stream). The same VID also carries the Retro Shooter hub (05E1/187C) and
    the Hook-of-the-Reaper board (0006), so this adapter matches exact VID&PID pairs only — never a bare
    VID_16C0 — and hands DemulShooter the gun instance, not the camera.

    Border: the gun only tracks while a closed white frame surrounds the game. RetroBat covers this
    natively through the [Guns] SindenBorder keys written below. Outside RetroBat the stable options are
    the ReShade shader SindenBorder.fx (swapchain, survives exclusive fullscreen; the kit injects no
    shaders) or a white MAME artwork bezel; a plain desktop overlay breaks on exclusive fullscreen and
    can steal window focus.

    Recoil: the 0x0F38/0x0F39 models drive their solenoid through their own virtual COM port (byte
    0x53 = fire pulse), which the kit's output package wires via Hook of the Reaper — solenoid
    protection stays enforced there (max open time 200 ms). Power: recoil peaks reach ~2 A, above the
    500 mA of a passive USB 2.0 port, and two guns saturate one host controller — run them on an active
    hub / separate controllers. Signatures come from the 2026-09 Sinden integration analysis;
    awaiting a hardware-bench check.
#>

function Test-SindenHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [object[]] $Devices)
    if (-not $PSBoundParameters.ContainsKey('Devices')) { $Devices = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue) }
    foreach ($d in $Devices) {
        $id = ''
        if ($d -is [string]) { $id = $d }
        else {
            if ($d.PSObject.Properties['InstanceId']) { $id = [string]$d.InstanceId }
            if (-not $id -and $d.PSObject.Properties['DeviceID']) { $id = [string]$d.DeviceID }
        }
        # Exact VID&PID pairs only: bare VID_16C0 would hit the Retro Shooter hub and the Reaper board.
        if ($id -like '*VID_16C0&PID_0F01*' -or $id -like '*VID_16C0&PID_0F02*' -or
            $id -like '*VID_16C0&PID_0F38*' -or $id -like '*VID_16C0&PID_0F39*' -or
            $id -like '*VID_16C0&PID_0F37*') { return $true }
        $name = ''
        if ($d.PSObject.Properties['FriendlyName']) { $name = [string]$d.FriendlyName }
        if ($name -like '*Sinden*') { return $true }
    }
    return $false
}

function Get-SindenAdapterInfo {
    @{
        ToolDir    = 'Sinden'
        # Camera PID 0F37 is deliberately absent: MatchIds feed the DemulShooter [Player1] Device,
        # which wants the gun's HID instance (as in the analysis: HID\VID_16C0&PID_0F38...), not the UVC stream.
        MatchIds   = @('VID_16C0&PID_0F01', 'VID_16C0&PID_0F02', 'VID_16C0&PID_0F38', 'VID_16C0&PID_0F39')
        SteamEntries = @('0x16c0/0x0f01', '0x16c0/0x0f02', '0x16c0/0x0f38', '0x16c0/0x0f39')
        # The Sinden software turns the camera stream into an absolute pointer; MAME reads it as rawinput.
        MameValues = [ordered]@{ lightgun = '1'; lightgun_device = 'rawinput'; dual_lightgun = '1'; offscreen_reload = '1' }
        # SindenBorder*/Size/Color follow the RetroBat native border subsystem from the 2026-09 analysis
        # (border = tracking prerequisite, see header); values await the hardware-bench check.
        GunsValues = [ordered]@{ EnableLightguns = '1'; Gun1Device = 'Sinden'; EnableDemulShooter = '1';
                                 SindenBorder = '1'; SindenBorderSize = '2'; SindenBorderColor = 'white' }
        DemulDevice = $true
        Links      = @{ 'Sinden software suite' = 'https://www.sindenlightgun.com'
                        'Hook of the Reaper (recoil haptics)' = 'https://hotr.6bolt.express/' }
    }
}

# The vendor suite arrives as a self-extracting installer from sindenlightgun.com, which is not on the
# core allow-list: the kit names the source and, like every adapter, only unpacks a user-supplied ZIP
# through -PackagePath after -Approved. The kit never runs vendor installers - after unpacking, setup
# stays a manual double-click.
function Install-SindenSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-SindenAdapterInfo
    $targetDir = Join-Path $RetroBatRoot ('tools\' + $info['ToolDir'])
    if (-not $PackagePath) {
        foreach ($k in $info['Links'].Keys) { Write-KitLog (Get-KitText 'Lightgun.Adapter.SoftwareLink' -f $k, $info['Links'][$k]) }
        return $false
    }
    if (-not $Approved) { Write-KitLog (Get-KitText 'Lightgun.Adapter.NeedsApproval') -Level Warn; return $false }
    if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) { throw (Get-KitText 'Lightgun.Adapter.PackageMissing' -f $PackagePath) }
    $hash = (Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash
    Write-KitLog (Get-KitText 'Lightgun.Adapter.PackageHash' -f (Split-Path -Leaf $PackagePath), $hash)
    if (-not $PSCmdlet.ShouldProcess($targetDir, 'unpack adapter package')) { return $false }
    if (-not (Test-Path -LiteralPath $targetDir)) { $null = New-Item -ItemType Directory -Path $targetDir -Force }
    Expand-Archive -LiteralPath $PackagePath -DestinationPath $targetDir -Force
    Write-KitLog (Get-KitText 'Lightgun.Adapter.SoftwareInstalled' -f 'Sinden', $targetDir)
    $true
}

function Configure-SindenProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $DetectedDeviceId = '')
    Set-LightgunAdapterConfiguration -Name 'Sinden' -RetroBatRoot $RetroBatRoot -DetectedDeviceId $DetectedDeviceId -Confirm:$false
}

function Set-SindenInterferenceShield {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-SindenAdapterInfo
    $steam = Get-LightgunSteamPath
    if (-not $steam) { return }
    $vdf = Join-Path $steam 'config\config.vdf'
    if (Test-Path -LiteralPath $vdf -PathType Leaf) {
        $null = Set-LightgunSteamBlacklist -ConfigVdf $vdf -ExtraEntries @($info['SteamEntries']) -Confirm:$false
    }
}
