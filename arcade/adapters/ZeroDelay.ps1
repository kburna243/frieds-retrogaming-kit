# Zero Delay USB encoder adapter (DragonRise-class no-name arcade encoder).
# VID_0079 appears on three unrelated kits: PID_1802/1803 is the Mayflash DolphinBar (lightgun
# route) and PID_187C belongs to the RetroShooter, so only the exact PID_0006 pair is matched.
# "Generic USB Joystick" as a name hint would claim half the joystick market and is deliberately
# not used. There is no official vendor source for these no-name boards, so Links carries only a
# community reference; nothing is ever downloaded.

function Test-ZeroDelayHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [object[]] $Devices)
    # Read-only! $Devices (objects with InstanceId) replaces the live PnP list in tests.
    if (-not $PSBoundParameters.ContainsKey('Devices') -or -not $Devices) {
        $Devices = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue)
    }
    $info = Get-ZeroDelayAdapterInfo
    foreach ($d in @($Devices | Where-Object { $_ })) {
        $id = (Get-ArcadeDeviceId $d).ToUpperInvariant()
        foreach ($m in $info.MatchIds) { if ($id -like $m.ToUpperInvariant()) { return $true } }
        # Name hints are only the second signal, never a bare-VID style fallback.
        $name = Get-ArcadeDeviceName $d
        if ($name) { foreach ($h in $info.NameHints) { if ($name -like $h) { return $true } } }
    }
    $false
}

function Get-ZeroDelayAdapterInfo {
    @{
        Class     = 'ArcadeStick'
        ToolDir   = 'ZeroDelay'
        MatchIds  = @('USB\VID_0079&PID_0006*')
        NameHints = @('*DragonRise*')
        Quirks    = @()
        SteamEntries  = @('0x0079/0x0006')
        MameValues      = @{ joystick = '1' }
        ControllersValues = @{ }
        Model2Values    = @{ }
        SupermodelValues = @{ }
        Links     = @{ 'Community description' = 'https://forum.arcadecontrols.com/' }
    }
}

# Plug-and-play HID board without a driver: Install only names the community link. A user-
# supplied ZIP (-PackagePath with -Approved) is unpacked into tools\ZeroDelay as template-per.
function Install-ZeroDelaySoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-ZeroDelayAdapterInfo
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

function Configure-ZeroDelayProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $DetectedDeviceId, [string] $SteamConfigVdf)
    $params = @{ Name = 'ZeroDelay'; RetroBatRoot = $RetroBatRoot; DetectedDeviceId = $DetectedDeviceId }
    if ($PSBoundParameters.ContainsKey('SteamConfigVdf')) { $params.SteamConfigVdf = $SteamConfigVdf }
    Set-ArcadeAdapterConfiguration @params -Confirm:$false
}

function Set-ZeroDelayInterferenceShield {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [switch] $Disable, [string] $SteamConfigVdf = '')
    # The shield is the Steam blacklist — adding entries never hurts; "Disable" only reports.
    if ($Disable) { Write-KitLog (Get-KitText 'Arcade.Adapter.ShieldReportsOnly') -Level Info; return }
    $info = Get-ZeroDelayAdapterInfo
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
