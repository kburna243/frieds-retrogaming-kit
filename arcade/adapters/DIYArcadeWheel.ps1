<#
.SYNOPSIS
    DIY arcade wheel adapter (OpenFFB-style boards) for Fried's Retrogaming Kit.
.DESCRIPTION
    Single tight signature: USB\VID_1209&PID_FFB0*. VID 1209 is the public pid.codes
    range that open-source firmware projects (OpenFFBoard and derived builds) take
    their product IDs from; the name hint *OpenFFB* is the second signal only.
    Detection is read-only; every write goes through the audited writers in
    arcade\modules\Adapters.ps1.

    WHAT WAS DELIBERATELY LEFT OUT - AND WHY: the original draft script also matched
    2E8A&000A, the Raspberry Pi Pico BOOTSEL bootloader. That signature belongs to
    the OpenFIRE LIGHTGUN adapter in this kit, and the arcade module's class
    coexistence rule is "lightgun wins" - a Pico in bootloader mode must never be
    claimed as a wheel by this adapter. On top of that the draft carried a B/F
    transcription typo in that PID area, so nothing from it was trusted.

    WHAT WAS KEPT, WITH A BIGGER PRINT: 1209&FFB0 is taken over as the only match ID,
    but the PID itself is UNVERIFIED - firmware projects pick their own product IDs
    from the 1209 range and the value drifts between builds. The quirk 'verify-pid'
    says so out loud: the community must confirm the real PID of its firmware build
    (check the device's hardware IDs in Device Manager before believing this adapter).

    OpenFFBoard (see Links) is the reference home of generic open-source force-
    feedback wheel firmware and the place to ask about actual product IDs.

    MODEL 2 / SUPERMODEL NOTE: both tables are intentionally EMPTY - nothing
    verified is known for those INIs on DIY boards. (For completeness: even when a
    table is filled elsewhere, the writers only modify EXISTING Emulator.ini /
    Supermodel.ini files and never create them; those INIs usually do not exist at
    all, so half-known values would only be half-applied. Documented on purpose.)
    Driver work stays manual too: this adapter downloads nothing.
#>

function Test-DIYArcadeWheelHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [object[]] $Devices)
    # Read-only! $Devices (objects with InstanceId) replaces the live PnP list in tests.
    if (-not $PSBoundParameters.ContainsKey('Devices') -or -not $Devices) {
        $Devices = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue)
    }
    $info = Get-DIYArcadeWheelAdapterInfo
    foreach ($d in @($Devices | Where-Object { $_ })) {
        $id = (Get-ArcadeDeviceId $d).ToUpperInvariant()
        foreach ($m in $info.MatchIds) { if ($id -like $m.ToUpperInvariant()) { return $true } }
        # Name hints are only the second signal, never a bare-VID style fallback.
        $name = Get-ArcadeDeviceName $d
        if ($name) { foreach ($h in $info.NameHints) { if ($name -like $h) { return $true } } }
    }
    $false
}

function Get-DIYArcadeWheelAdapterInfo {
    @{
        Class     = 'Wheel'
        ToolDir   = 'DIYArcadeWheel'
        # Exactly one signature. 2E8A&000A (Pico bootloader) is OpenFIRE's, NOT ours - see header.
        MatchIds  = @('USB\VID_1209&PID_FFB0*')
        NameHints = @('*OpenFFB*')
        Quirks    = @('verify-pid')
        SteamEntries = @('0x1209/0xffb0')
        MameValues        = [ordered]@{ joystick = '1'; paddle_device = 'joystick'; pedal_device = 'joystick' }
        ControllersValues = [ordered]@{ Autocontrollers = '1'; WheelForceFeedback = '1'; WheelRotation = '900' }
        # Intentionally empty - see header: nothing verified for these INIs.
        Model2Values     = @{ }
        SupermodelValues = @{ }
        Links = @{
            'OpenFFB' = 'https://github.com/Ultrawipf/OpenFFBoard'
        }
    }
}

# Deliberately does NOT download: DIY firmware flashing is manual work (see Links).
# With -PackagePath and -Approved the kit unpacks a ZIP the user fetched themselves into
# tools\DIYArcadeWheel; without a package it only names the official link.
function Install-DIYArcadeWheelSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-DIYArcadeWheelAdapterInfo
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

function Configure-DIYArcadeWheelProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $DetectedDeviceId, [string] $SteamConfigVdf)
    $params = @{ Name = 'DIYArcadeWheel'; RetroBatRoot = $RetroBatRoot; DetectedDeviceId = $DetectedDeviceId }
    if ($PSBoundParameters.ContainsKey('SteamConfigVdf')) { $params.SteamConfigVdf = $SteamConfigVdf }
    Set-ArcadeAdapterConfiguration @params -Confirm:$false
}

# Interference shield, kit style: Steam Input is blocked from grabbing the wheel via
# controller_blacklist. Adding entries never hurts; -Disable only reports. No process kill, ever.
function Set-DIYArcadeWheelInterferenceShield {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [switch] $Disable, [string] $SteamConfigVdf = '')
    if ($Disable) { Write-KitLog (Get-KitText 'Arcade.Adapter.ShieldReportsOnly') -Level Info; return }
    $info = Get-DIYArcadeWheelAdapterInfo
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
