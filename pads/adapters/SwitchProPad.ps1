<#
.SYNOPSIS
    Nintendo Switch Pro Controller for Fried's Retrogaming Kit (Gamepad class).
.DESCRIPTION
    Detects the Switch Pro Controller (USB\VID_057E&PID_2009) over its USB-C cable and over
    Bluetooth-classic. Detection is read-only; the only write is retrobat.ini [Controllers] through
    lightgun's audited INI writer. No downloads, no process kills, no Steam blacklist.

    HANDSHAKE REALITY: over Bluetooth the Pro Controller stays in a low-power state and drops the link
    after roughly half a minute unless an Init reports / 0x01 handshake keeps it awake. That is what
    middleware (BetterJoy, or Steam's own input stack) does. It is a service-like third-party component
    - the kit names the source, configures nothing about it, and does not install it.
#>

function Test-SwitchProPadHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [object[]] $Devices)
    $params = @{ Quiet = $true }
    if ($PSBoundParameters.ContainsKey('Devices')) { $params.Devices = $Devices }
    if ($RetroBatRoot) { $params.RetroBatRoot = $RetroBatRoot }
    @((Get-PadDetectedGamepad @params).DetectedPads | Where-Object { (Get-PadDetectedName $_) -eq 'SwitchProPad' }).Count -gt 0
}

function Get-SwitchProPadAdapterInfo {
    @{
        Class   = 'Gamepad'
        # BetterJoy and DS4Windows are third-party applications the user chooses to run (and DS4Windows
        # is a PlayStation tool anyway); nothing portable belongs into RetroBat's tools\ for this pad.
        ToolDir = ''
        MatchIds = @(
            'USB\VID_057E&PID_2009*'   # Switch Pro Controller: wired and Bluetooth-classic share the id
        )
        NameHints = @()
        Quirks    = @('middleware-handshake', 'bt-impersonation')
        SteamEntries = @()             # class decision: Steam keeps its pads (Pad.NoBlacklist)
        MameValues = @()
        ControllersValues = @{ Autocontrollers = '1' }
        Model2Values      = @()
        SupermodelValues  = @()
        Links = @{
            # Documentation strings only - the kit never fetches anything (see pads\adapters\README.md).
            'BetterJoy (Switch/PS middleware)' = 'https://github.com/Davidobot/BetterJoy'
            'DS4Windows (PlayStation middleware, related)' = 'https://github.com/Ryochan7/DS4Windows'
        }
        Notes = @'
One signature, deliberately: 057E:2009 is the Pro Controller, and 8BitDo pads in S-mode present exactly
that id, so this adapter can also see a pad that is not a Nintendo original. The kit reports the
signature it found and the mode note - it does not decide which device the user believes they own.
Known blind spot: a Pro Controller paired as Bluetooth LOW ENERGY appears as BTHLE\Dev_<mac> with no
VID/PID in the instance path at all, so no signature rule can reach it (documented in
pads\adapters\README.md; the cable or the Bluetooth-classic pairing is detected).
'@
    }
}

function Install-SwitchProPadSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    Install-PadAdapterPackage -Name 'SwitchProPad' -RetroBatRoot $RetroBatRoot -PackagePath $PackagePath -Approved:$Approved
}

function Configure-SwitchProPadProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [object[]] $DetectedPads)
    if ($PSBoundParameters.ContainsKey('DetectedPads')) {
        if (-not @($DetectedPads | Where-Object { (Get-PadDetectedName $_) -eq 'SwitchProPad' }).Count) { return 0 }
    }
    Set-PadGamepadConfiguration -Name 'SwitchProPad' -RetroBatRoot $RetroBatRoot -Confirm:$false
}

# Report-only, and the handshake note is the reason it exists: a pad that drops its link every 30
# seconds is the thing a user will blame on the kit first.
function Set-SwitchProPadInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [object[]] $Devices)
    Write-KitLog (Get-KitText 'Pad.Adapter.ShieldReportsOnly') -Level Info
    Write-KitLog (Get-KitText 'Pad.NoBlacklist') -Level Info
    $params = @{ Quiet = $true }
    if ($PSBoundParameters.ContainsKey('Devices')) { $params.Devices = $Devices }
    if ($RetroBatRoot) { $params.RetroBatRoot = $RetroBatRoot }
    if (@((Get-PadDetectedGamepad @params).DetectedPads | Where-Object { (Get-PadDetectedName $_) -eq 'SwitchProPad' }).Count) {
        Write-KitLog (Get-KitText 'Pad.Quirk.BtImpersonation' -f 'S (8BitDo)', '057E:2009 (Switch Pro)') -Level Info
    }
}
