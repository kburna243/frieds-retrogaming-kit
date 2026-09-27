# PS2-controller-to-USB bridge adapter ("Twin USB Gamepad" / "PS TO PC" converter family).
# Only the two documented bridge pairs are matched: VID_0810 is also used by no-name webcam
# boards and VID_0079 is shared with the ZeroDelay encoder (0006) and the DolphinBar (1802/1803).
# Both chips present each controller port as a separate joystick on shared USB endpoints, so
# player 2 enumerates as its own device and needs its own slot - recorded as the 'shared-endpoints'
# quirk. No drivers exist for these bridges, so Install is link-only and nothing is downloaded.

function Test-PS2ToUSBAdapterHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [object[]] $Devices)
    # Read-only! $Devices (objects with InstanceId) replaces the live PnP list in tests.
    if (-not $PSBoundParameters.ContainsKey('Devices') -or -not $Devices) {
        $Devices = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue)
    }
    $info = Get-PS2ToUSBAdapterAdapterInfo
    foreach ($d in @($Devices | Where-Object { $_ })) {
        $id = (Get-ArcadeDeviceId $d).ToUpperInvariant()
        foreach ($m in $info.MatchIds) { if ($id -like $m.ToUpperInvariant()) { return $true } }
        # Name hints are only the second signal, never a bare-VID style fallback.
        $name = Get-ArcadeDeviceName $d
        if ($name) { foreach ($h in $info.NameHints) { if ($name -like $h) { return $true } } }
    }
    $false
}

function Get-PS2ToUSBAdapterAdapterInfo {
    @{
        Class     = 'ArcadeStick'
        ToolDir   = 'PS2Adapter'
        MatchIds  = @('USB\VID_0810&PID_0001*', 'USB\VID_0079&PID_0011*')
        NameHints = @('*Twin USB*', '*PS TO PC*')
        Quirks    = @('shared-endpoints')      # one physical bridge, two logical joysticks
        SteamEntries  = @('0x0810/0x0001', '0x0079/0x0011')
        MameValues      = @{ joystick = '1' }
        ControllersValues = @{ P1Device_ps2 = 'ArcadeStick' }
        Model2Values    = @{ }
        SupermodelValues = @{ }
        Links     = @{ 'Adapter family' = 'https://en.wikipedia.org/wiki/USB_adapter' }
    }
}

# Driverless HID bridges: Install names the reference link only; a user-supplied ZIP
# (-PackagePath with -Approved) is unpacked into tools\PS2Adapter exactly as template-per.
function Install-PS2ToUSBAdapterSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-PS2ToUSBAdapterAdapterInfo
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

function Configure-PS2ToUSBAdapterProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $DetectedDeviceId, [string] $SteamConfigVdf)
    $params = @{ Name = 'PS2ToUSBAdapter'; RetroBatRoot = $RetroBatRoot; DetectedDeviceId = $DetectedDeviceId }
    if ($PSBoundParameters.ContainsKey('SteamConfigVdf')) { $params.SteamConfigVdf = $SteamConfigVdf }
    Set-ArcadeAdapterConfiguration @params -Confirm:$false
}

function Set-PS2ToUSBAdapterInterferenceShield {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [switch] $Disable, [string] $SteamConfigVdf = '')
    # The shield is the Steam blacklist — adding entries never hurts; "Disable" only reports.
    if ($Disable) { Write-KitLog (Get-KitText 'Arcade.Adapter.ShieldReportsOnly') -Level Info; return }
    $info = Get-PS2ToUSBAdapterAdapterInfo
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
