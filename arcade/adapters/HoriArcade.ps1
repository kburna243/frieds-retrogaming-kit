# HORI Real Arcade Pro / Fighting Stick family adapter.
# A bare VID_0F0D is forbidden: Hori ships ordinary gamepads under the same VID, so only the nine
# documented stick PIDs (RAP EX/SA, VX, V, 4/4 Kai, Fighting Stick Alpha and siblings) are matched
# exactly. The sticks are class-compliant HID with a physical PC/console mode switch on the
# housing - no driver to install and nothing is downloaded; Install names the vendor page only.

function Test-HoriArcadeHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [object[]] $Devices)
    # Read-only! $Devices (objects with InstanceId) replaces the live PnP list in tests.
    if (-not $PSBoundParameters.ContainsKey('Devices') -or -not $Devices) {
        $Devices = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue)
    }
    $info = Get-HoriArcadeAdapterInfo
    foreach ($d in @($Devices | Where-Object { $_ })) {
        $id = (Get-ArcadeDeviceId $d).ToUpperInvariant()
        foreach ($m in $info.MatchIds) { if ($id -like $m.ToUpperInvariant()) { return $true } }
        # Name hints are only the second signal, never a bare-VID style fallback.
        $name = Get-ArcadeDeviceName $d
        if ($name) { foreach ($h in $info.NameHints) { if ($name -like $h) { return $true } } }
    }
    $false
}

function Get-HoriArcadeAdapterInfo {
    @{
        Class     = 'ArcadeStick'
        ToolDir   = 'Hori'
        MatchIds  = @('USB\VID_0F0D&PID_000D*', 'USB\VID_0F0D&PID_0016*', 'USB\VID_0F0D&PID_001B*',
                      'USB\VID_0F0D&PID_005B*', 'USB\VID_0F0D&PID_0066*', 'USB\VID_0F0D&PID_008A*',
                      'USB\VID_0F0D&PID_011C*', 'USB\VID_0F0D&PID_015A*', 'USB\VID_0F0D&PID_00EE*')
        NameHints = @('*Hori*', '*Real Arcade Pro*', '*Fighting Stick Alpha*')
        Quirks    = @()
        SteamEntries  = @('0x0f0d/0x00ee', '0x0f0d/0x001b', '0x0f0d/0x0066')
        MameValues      = @{ joystick = '1' }
        ControllersValues = @{ P1Device_arcade = 'ArcadeStick' }
        Model2Values    = @{ }
        SupermodelValues = @{ }
        Links     = @{ 'Hori' = 'https://www.hori-games.com/' }
    }
}

# Class-compliant stick without any required PC software: Install names the vendor link; a
# user-supplied ZIP (-PackagePath with -Approved) is unpacked into tools\Hori per template.
function Install-HoriArcadeSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-HoriArcadeAdapterInfo
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

function Configure-HoriArcadeProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $DetectedDeviceId, [string] $SteamConfigVdf)
    $params = @{ Name = 'HoriArcade'; RetroBatRoot = $RetroBatRoot; DetectedDeviceId = $DetectedDeviceId }
    if ($PSBoundParameters.ContainsKey('SteamConfigVdf')) { $params.SteamConfigVdf = $SteamConfigVdf }
    Set-ArcadeAdapterConfiguration @params -Confirm:$false
}

function Set-HoriArcadeInterferenceShield {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [switch] $Disable, [string] $SteamConfigVdf = '')
    # The shield is the Steam blacklist — adding entries never hurts; "Disable" only reports.
    if ($Disable) { Write-KitLog (Get-KitText 'Arcade.Adapter.ShieldReportsOnly') -Level Info; return }
    $info = Get-HoriArcadeAdapterInfo
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
