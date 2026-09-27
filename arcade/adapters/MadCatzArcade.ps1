# Mad Catz arcade stick family (Xbox 360 TE/SE/FightStick Pro, Xbox One TE2, PS3 TE, PS4 TE2).
# VID_0738 also covers Mad Catz wheels and gamepads, so only the six arcade-stick PIDs curated
# from the original script are matched - the 4740/475A/9807 range stays out until verified.
# PS3-era units enumerate as USB 2.0 only and commonly fail behind xHCI/USB 3 ports with Code 43
# (ConfigManagerErrorCode 43); the workaround is a USB 2.0 hub or the BIOS xHCI-compatibility
# option. The core reports this quirk from the device property, never from localized error text.

function Test-MadCatzArcadeHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [object[]] $Devices)
    # Read-only! $Devices (objects with InstanceId) replaces the live PnP list in tests.
    if (-not $PSBoundParameters.ContainsKey('Devices') -or -not $Devices) {
        $Devices = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue)
    }
    $info = Get-MadCatzArcadeAdapterInfo
    foreach ($d in @($Devices | Where-Object { $_ })) {
        $id = (Get-ArcadeDeviceId $d).ToUpperInvariant()
        foreach ($m in $info.MatchIds) { if ($id -like $m.ToUpperInvariant()) { return $true } }
        # Name hints are only the second signal, never a bare-VID style fallback.
        $name = Get-ArcadeDeviceName $d
        if ($name) { foreach ($h in $info.NameHints) { if ($name -like $h) { return $true } } }
    }
    $false
}

function Get-MadCatzArcadeAdapterInfo {
    @{
        Class     = 'ArcadeStick'
        ToolDir   = 'MadCatz'
        MatchIds  = @('USB\VID_0738&PID_4716*', 'USB\VID_0738&PID_4718*', 'USB\VID_0738&PID_4738*',
                      'USB\VID_0738&PID_4758*', 'USB\VID_0738&PID_8838*', 'USB\VID_0738&PID_8384*')
        NameHints = @('*Mad Catz*', '*MadCatz*', '*Fighting Stick*', '*TE*', '*MLG*')
        Quirks    = @('usb-descriptor-failed') # Code 43 on xHCI ports, seen via ConfigManagerErrorCode
        SteamEntries  = @('0x0738/0x4716', '0x0738/0x4718', '0x0738/0x4738', '0x0738/0x4758')
        MameValues      = @{ joystick = '1' }
        ControllersValues = @{ P1Device_arcade = 'ArcadeStick' }
        Model2Values    = @{ }
        SupermodelValues = @{ }
        Links     = @{ 'Mad Catz' = 'https://en.wikipedia.org/wiki/Mad_Catz' }
    }
}

# The sticks are class-compliant; the vendor's legacy tools are abandonware and not fetched.
# Install names the reference link only; a user-supplied ZIP (-PackagePath with -Approved) is
# unpacked into tools\MadCatz exactly as the template prescribes.
function Install-MadCatzArcadeSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-MadCatzArcadeAdapterInfo
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

function Configure-MadCatzArcadeProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $DetectedDeviceId, [string] $SteamConfigVdf)
    $params = @{ Name = 'MadCatzArcade'; RetroBatRoot = $RetroBatRoot; DetectedDeviceId = $DetectedDeviceId }
    if ($PSBoundParameters.ContainsKey('SteamConfigVdf')) { $params.SteamConfigVdf = $SteamConfigVdf }
    Set-ArcadeAdapterConfiguration @params -Confirm:$false
}

function Set-MadCatzArcadeInterferenceShield {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [switch] $Disable, [string] $SteamConfigVdf = '')
    # The shield is the Steam blacklist — adding entries never hurts; "Disable" only reports.
    if ($Disable) { Write-KitLog (Get-KitText 'Arcade.Adapter.ShieldReportsOnly') -Level Info; return }
    $info = Get-MadCatzArcadeAdapterInfo
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
