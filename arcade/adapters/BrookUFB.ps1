# Brook Universal Fighting Board / Fusion adapter.
# VID_0C12 is a generic bridge vendor shared with unrelated PS2/USB receivers, so only the three
# exact board PIDs (0E10 UFB, 0575 and 0EF6 Fusion revisions) are matched - never the bare VID.
# The board is class-compliant HID with no PC software dependency, so Install names the vendor
# page only; nothing is downloaded. Console mode is switched by a button combo on the board
# itself, which is why it carries the 'mode-switch-combo' quirk.

function Test-BrookUFBHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [object[]] $Devices)
    # Read-only! $Devices (objects with InstanceId) replaces the live PnP list in tests.
    if (-not $PSBoundParameters.ContainsKey('Devices') -or -not $Devices) {
        $Devices = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue)
    }
    $info = Get-BrookUFBAdapterInfo
    foreach ($d in @($Devices | Where-Object { $_ })) {
        $id = (Get-ArcadeDeviceId $d).ToUpperInvariant()
        foreach ($m in $info.MatchIds) { if ($id -like $m.ToUpperInvariant()) { return $true } }
        # Name hints are only the second signal, never a bare-VID style fallback.
        $name = Get-ArcadeDeviceName $d
        if ($name) { foreach ($h in $info.NameHints) { if ($name -like $h) { return $true } } }
    }
    $false
}

function Get-BrookUFBAdapterInfo {
    @{
        Class     = 'ArcadeStick'
        ToolDir   = 'Brook'
        MatchIds  = @('USB\VID_0C12&PID_0E10*', 'USB\VID_0C12&PID_0575*', 'USB\VID_0C12&PID_0EF6*')
        NameHints = @('*Brook Universal*', '*Brook Fighting Board*')
        Quirks    = @('mode-switch-combo')     # PS/Xbox/PC mode via button combo, not via software
        SteamEntries  = @('0x0c12/0x0e10', '0x0c12/0x0575', '0x0c12/0x0ef6')
        MameValues      = @{ joystick = '1' }
        ControllersValues = @{ P1Device_arcade = 'ArcadeStick' }
        Model2Values    = @{ }
        SupermodelValues = @{ }
        Links     = @{ 'Brook' = 'https://brook.technology/' }
    }
}

# Direct-input board, no driver needed: Install only names the vendor link. A user-supplied ZIP
# (-PackagePath with -Approved) is unpacked into tools\Brook as the template prescribes.
function Install-BrookUFBSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-BrookUFBAdapterInfo
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

function Configure-BrookUFBProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $DetectedDeviceId, [string] $SteamConfigVdf)
    $params = @{ Name = 'BrookUFB'; RetroBatRoot = $RetroBatRoot; DetectedDeviceId = $DetectedDeviceId }
    if ($PSBoundParameters.ContainsKey('SteamConfigVdf')) { $params.SteamConfigVdf = $SteamConfigVdf }
    Set-ArcadeAdapterConfiguration @params -Confirm:$false
}

function Set-BrookUFBInterferenceShield {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [switch] $Disable, [string] $SteamConfigVdf = '')
    # The shield is the Steam blacklist — adding entries never hurts; "Disable" only reports.
    if ($Disable) { Write-KitLog (Get-KitText 'Arcade.Adapter.ShieldReportsOnly') -Level Info; return }
    $info = Get-BrookUFBAdapterInfo
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
