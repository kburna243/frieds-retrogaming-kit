<#
.SYNOPSIS
    Thrustmaster / Fanatec wheel adapter for Fried's Retrogaming Kit (Wheel class).
.DESCRIPTION
    One adapter for the two DirectInput wheel families that share the retro arcade
    use case: Thrustmaster bases (USB\VID_044F&PID_B66E / PID_B669) and Fanatec
    hardware (USB\VID_0EB7&PID_0001 / PID_0020), plus name hints as a second signal.
    Detection is read-only; every write goes through the audited writers in
    arcade\modules\Adapters.ps1.

    DRIVER POLICY - MANUAL: both vendors ship their own control panels; the kit
    downloads nothing (Links point at the vendor pages). Windows normally binds the
    wheels as DirectInput devices without any vendor software at all, which is what
    MAME and RetroBat consume. WheelRotation 900 is the common default; individual
    bases can still be limited in their own control panel - manual tuning, no quirk.

    MODEL 2 NOTE: Model2Values targets emulators\m2emulator\Emulator.ini (root
    section), which usually DOES NOT EXIST unless the emulator is installed. The
    writer only ever modifies existing files and never creates it, so the table is
    inert on a machine without Model 2 - safe by design, but documented
    half-knowledge. SupermodelValues is deliberately EMPTY here: no Supermodel FFB
    value was verified for these bases, and the kit writes no half-known values.
#>

function Test-ThrustmasterFanatecWheelHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [object[]] $Devices)
    # Read-only! $Devices (objects with InstanceId) replaces the live PnP list in tests.
    if (-not $PSBoundParameters.ContainsKey('Devices') -or -not $Devices) {
        $Devices = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue)
    }
    $info = Get-ThrustmasterFanatecWheelAdapterInfo
    foreach ($d in @($Devices | Where-Object { $_ })) {
        $id = (Get-ArcadeDeviceId $d).ToUpperInvariant()
        foreach ($m in $info.MatchIds) { if ($id -like $m.ToUpperInvariant()) { return $true } }
        # Name hints are only the second signal, never a bare-VID style fallback.
        $name = Get-ArcadeDeviceName $d
        if ($name) { foreach ($h in $info.NameHints) { if ($name -like $h) { return $true } } }
    }
    $false
}

function Get-ThrustmasterFanatecWheelAdapterInfo {
    @{
        Class     = 'Wheel'
        ToolDir   = 'ThrustmasterWheel'
        MatchIds  = @('USB\VID_044F&PID_B66E*', 'USB\VID_044F&PID_B669*', 'USB\VID_0EB7&PID_0001*', 'USB\VID_0EB7&PID_0020*')
        NameHints = @('*Thrustmaster*', '*Fanatec*')
        Quirks    = @()
        SteamEntries = @('0x044f/0xb66e', '0x044f/0xb669', '0x0eb7/0x0001')
        MameValues        = [ordered]@{ joystick = '1'; paddle_device = 'joystick'; pedal_device = 'joystick' }
        ControllersValues = [ordered]@{ Autocontrollers = '1'; WheelForceFeedback = '1'; WheelRotation = '900' }
        # Wired only when emulators\m2emulator\Emulator.ini exists (see header).
        Model2Values = [ordered]@{ UseFeedback = '1'; EnableDirectInput = '1' }
        # Intentionally empty - see header (nothing verified for Supermodel).
        SupermodelValues = @{ }
        Links = @{
            'Thrustmaster' = 'https://www.thrustmaster.com/'
            'Fanatec'       = 'https://www.fanatec.com/'
        }
    }
}

# Deliberately does NOT download: vendor control panels are manual work (see Links).
# With -PackagePath and -Approved the kit unpacks a ZIP the user fetched themselves into
# tools\ThrustmasterWheel; without a package it only names the official links.
function Install-ThrustmasterFanatecWheelSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-ThrustmasterFanatecWheelAdapterInfo
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

function Configure-ThrustmasterFanatecWheelProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $DetectedDeviceId, [string] $SteamConfigVdf)
    $params = @{ Name = 'ThrustmasterFanatecWheel'; RetroBatRoot = $RetroBatRoot; DetectedDeviceId = $DetectedDeviceId }
    if ($PSBoundParameters.ContainsKey('SteamConfigVdf')) { $params.SteamConfigVdf = $SteamConfigVdf }
    Set-ArcadeAdapterConfiguration @params -Confirm:$false
}

# Interference shield, kit style: Steam Input is blocked from grabbing the wheel via
# controller_blacklist. Adding entries never hurts; -Disable only reports. No process kill, ever.
function Set-ThrustmasterFanatecWheelInterferenceShield {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [switch] $Disable, [string] $SteamConfigVdf = '')
    if ($Disable) { Write-KitLog (Get-KitText 'Arcade.Adapter.ShieldReportsOnly') -Level Info; return }
    $info = Get-ThrustmasterFanatecWheelAdapterInfo
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
