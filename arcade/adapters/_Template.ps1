# ─── ARCADE ADAPTER TEMPLATE ─── copy, rename to <YourDevice>.ps1, fill in, never execute this file ───
# Every arcade\adapters\<Name>.ps1 implements the five functions below and nothing else.
# "<Name>" must equal the file name. Files starting with _ are never scanned or executed.
#
# Rules the kit enforces (see also arcade\adapters\README.md):
#   * Read-only detection. Match TIGHT "USB\VID_xxxx&PID_yyyy*" signatures — never a bare VID
#     (0079 alone is the DolphinBar, 2E8A/000A is OpenFIRE's bootloader, D209 alone is AimTrak's).
#   * No downloads. Install only from -PackagePath (a local ZIP) and only with -Approved; without a
#     package just name the official link. Hosts outside the core allow-list must never be fetched.
#   * Never kill a process. Steam interference is the controller_blacklist
#     (Set-LightgunSteamBlacklist -ExtraEntries ...), nothing else.
#   * Write configs only through the audited writers (Set-ArcadeAdapterConfiguration reads the tables
#     below and dispatches to lightgun's backup/encoding/WhatIf writers):
#       MameValues        → mame.ini            (space-separated writer)
#       ControllersValues → retrobat.ini [Controllers]
#       Model2Values      → emulators\m2emulator\Emulator.ini (root section)
#       SupermodelValues  → emulators\supermodel\Config\Supermodel.ini [Global]
#       SteamEntries      → Steam controller_blacklist VIDs like '0x046d/0xc294'
#   * No Write-Host, no HKLM, no services, no scheduled tasks here — steps and the wizard do that.

function Test-ExampleArcadeHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [object[]] $Devices)
    # Read-only! $Devices (objects with InstanceId) replaces the live PnP list in tests.
    if (-not $PSBoundParameters.ContainsKey('Devices') -or -not $Devices) {
        $Devices = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue)
    }
    $info = Get-ExampleArcadeAdapterInfo
    foreach ($d in @($Devices | Where-Object { $_ })) {
        $id = (Get-ArcadeDeviceId $d).ToUpperInvariant()
        foreach ($m in $info.MatchIds) { if ($id -like $m.ToUpperInvariant()) { return $true } }
    }
    $false
}

function Get-ExampleArcadeAdapterInfo {
    @{
        Class     = 'ArcadeStick'              # 'ArcadeStick' | 'Wheel'
        ToolDir   = 'ExampleArcade'            # tools\<ToolDir>
        MatchIds  = @('USB\VID_1234&PID_5678*')
        NameHints = @('*Example Arcade*')      # FriendlyName patterns (only as second signal)
        Quirks    = @()                        # documented device pitfalls, e.g. 'usb-descriptor-failed'
        SteamEntries  = @('0x1234/0x5678')     # lower-case VIDs for controller_blacklist
        MameValues      = @{ joystick = '1' }
        ControllersValues = @{ }
        Model2Values    = @{ }
        SupermodelValues = @{ }
        Links     = @{ 'Vendor tools' = 'https://example.com/tools' }
    }
}

function Install-ExampleArcadeSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-ExampleArcadeAdapterInfo
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

function Configure-ExampleArcadeProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $DetectedDeviceId, [string] $SteamConfigVdf)
    $params = @{ Name = 'ExampleArcade'; RetroBatRoot = $RetroBatRoot; DetectedDeviceId = $DetectedDeviceId }
    if ($PSBoundParameters.ContainsKey('SteamConfigVdf')) { $params.SteamConfigVdf = $SteamConfigVdf }
    Set-ArcadeAdapterConfiguration @params -Confirm:$false
}

function Set-ExampleArcadeInterferenceShield {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [switch] $Disable, [string] $SteamConfigVdf = '')
    # The shield is the Steam blacklist — adding entries never hurts; "Disable" only reports.
    if ($Disable) { Write-KitLog (Get-KitText 'Arcade.Adapter.ShieldReportsOnly') -Level Info; return }
    $info = Get-ExampleArcadeAdapterInfo
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
