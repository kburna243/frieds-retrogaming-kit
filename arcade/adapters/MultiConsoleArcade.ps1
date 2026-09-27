# Multi-console arcade stick adapter (Razer Atrox/Qanba, Mayflash Magic-N/Magic-X, 1008X boards).
# Mayflash multi-console boards enumerate under their own PIDs 0183/0184; the DolphinBar pair
# (VID_0079&PID_1802/1803) stays on the lightgun route and is untouched here. The original
# script's bare VID_2C22 was narrowed to PID_0010 because the Qanba VID also covers other input
# devices. These sticks are factory HID with per-console switching - no software, no download.

function Test-MultiConsoleArcadeHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [object[]] $Devices)
    # Read-only! $Devices (objects with InstanceId) replaces the live PnP list in tests.
    if (-not $PSBoundParameters.ContainsKey('Devices') -or -not $Devices) {
        $Devices = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue)
    }
    $info = Get-MultiConsoleArcadeAdapterInfo
    foreach ($d in @($Devices | Where-Object { $_ })) {
        $id = (Get-ArcadeDeviceId $d).ToUpperInvariant()
        foreach ($m in $info.MatchIds) { if ($id -like $m.ToUpperInvariant()) { return $true } }
        # Name hints are only the second signal, never a bare-VID style fallback.
        $name = Get-ArcadeDeviceName $d
        if ($name) { foreach ($h in $info.NameHints) { if ($name -like $h) { return $true } } }
    }
    $false
}

function Get-MultiConsoleArcadeAdapterInfo {
    @{
        Class     = 'ArcadeStick'
        ToolDir   = 'MultiConsoleArcade'
        MatchIds  = @('USB\VID_1532&PID_0A00*', 'USB\VID_1532&PID_0A02*', 'USB\VID_0079&PID_0183*',
                      'USB\VID_0079&PID_0184*', 'USB\VID_2C22&PID_0010*')
        NameHints = @('*Razer*', '*Qanba*', '*Mayflash Magic*', '*Multi Console*')
        Quirks    = @()
        SteamEntries  = @('0x1532/0x0a00', '0x0079/0x0183')
        MameValues      = @{ joystick = '1' }
        ControllersValues = @{ P1Device_arcade = 'ArcadeStick' }
        Model2Values    = @{ }
        SupermodelValues = @{ }
        Links     = @{ 'Mayflash' = 'https://www.mayflash.com/' }
    }
}

# Factory-HID sticks need no driver: Install names the vendor link; a user-supplied ZIP
# (-PackagePath with -Approved) is unpacked into tools\MultiConsoleArcade as template-per.
function Install-MultiConsoleArcadeSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-MultiConsoleArcadeAdapterInfo
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

function Configure-MultiConsoleArcadeProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $DetectedDeviceId, [string] $SteamConfigVdf)
    $params = @{ Name = 'MultiConsoleArcade'; RetroBatRoot = $RetroBatRoot; DetectedDeviceId = $DetectedDeviceId }
    if ($PSBoundParameters.ContainsKey('SteamConfigVdf')) { $params.SteamConfigVdf = $SteamConfigVdf }
    Set-ArcadeAdapterConfiguration @params -Confirm:$false
}

function Set-MultiConsoleArcadeInterferenceShield {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [switch] $Disable, [string] $SteamConfigVdf = '')
    # The shield is the Steam blacklist — adding entries never hurts; "Disable" only reports.
    if ($Disable) { Write-KitLog (Get-KitText 'Arcade.Adapter.ShieldReportsOnly') -Level Info; return }
    $info = Get-MultiConsoleArcadeAdapterInfo
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
