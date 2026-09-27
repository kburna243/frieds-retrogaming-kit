<#
.SYNOPSIS
    Xbox controllers for Fried's Retrogaming Kit (Gamepad class).
.DESCRIPTION
    Detects the Xbox pad family behind Microsoft's vendor id 045E: wired Xbox 360 pads, the Xbox One /
    Series controllers in their USB and Bluetooth-classic spellings, and the BLE advertising form of the
    Series pads. Detection is read-only; the only write is retrobat.ini [Controllers] through lightgun's
    audited INI writer. No downloads, no process kills, no Steam blacklist.

    WHY THIS FILE STILL DECLARES IDS THAT PADS RARELY SEE: 045E:0719 is the Xbox 360 wireless receiver,
    and arcade\adapters\Xbox360Wheel.ps1 claims exactly that id for the Wireless Racing Wheel. The class
    rule (lightgun > arcade > pads) resolves it: the receiver is excluded from the pad scan on every
    machine, and this file keeps the id so the *reason* is visible instead of a missing line. Same for
    045E:028E, which GP2040-CE boards also report - there arcade decides by friendly name.
#>

function Test-XboxPadHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [object[]] $Devices)
    $params = @{ Quiet = $true }
    if ($PSBoundParameters.ContainsKey('Devices')) { $params.Devices = $Devices }
    if ($RetroBatRoot) { $params.RetroBatRoot = $RetroBatRoot }
    @((Get-PadDetectedGamepad @params).DetectedPads | Where-Object { (Get-PadDetectedName $_) -eq 'XboxPad' }).Count -gt 0
}

function Get-XboxPadAdapterInfo {
    @{
        Class   = 'Gamepad'
        # The Xbox Accessories app ships as an MSIX/Store package, not as a portable folder in tools\.
        # Firmware updates are exactly the kind of thing a human confirms in that app, so ToolDir = ''.
        ToolDir = ''
        MatchIds = @(
            'USB\VID_045E&PID_028E*'   # Xbox 360 wired controller (also GP2040-CE boards!)
            'USB\VID_045E&PID_0719*'   # Xbox 360 wireless receiver (arcade's Racing Wheel claims it)
            'USB\VID_045E&PID_02D1*'   # Xbox One wireless controller for Windows (USB)
            'USB\VID_045E&PID_02E0*'   # Xbox One / One S / One X controller, standard descriptor
            'USB\VID_045E&PID_0B12*'   # Xbox Series X|S controller over USB / 2.4 GHz adapter
            'USB\VID_045E&PID_0B13*'   # Xbox Series X|S controller over Bluetooth LE
            # Bluetooth-classic spelling of the 02E0 pairing. Get-PadSignaturePatterns derives this form
            # from every signature, so the line is documentation of a real case, not a second code path.
            'BTHENUM\{00001124-0000-1000-8000-00805F9B34FB}_VID&0002045E_PID&02E0*'
        )
        NameHints = @()
        Quirks    = @('ble-0b13-firmware')
        SteamEntries = @()             # class decision: Steam keeps its pads (Pad.NoBlacklist)
        MameValues = @()
        ControllersValues = @{ Autocontrollers = '1' }
        Model2Values      = @()
        SupermodelValues  = @()
        Links = @{
            # Documentation strings only - the kit never fetches anything (see pads\adapters\README.md).
            # The firmware tool is the "Xbox Accessories" app; it arrives through the Microsoft store,
            # which is exactly why this package has no installer route for it.
            'Xbox (official)'   = 'https://www.xbox.com/'
            'Xbox Support'      = 'https://support.xbox.com/'
        }
        Notes = @'
Windows has a native XInput driver for these pads, which is why the kit configures nothing per device:
Autocontrollers = 1 lets RetroBat/EmulationStation map whatever XInput or DirectInput device appears.
045E:0B13 is the Bluetooth-LE presentation of a Series controller. In that mode an outdated controller
firmware duplicates input (BLE HID plus the GATT overlay), and the fix is the Xbox Accessories app -
manual work, reported by Set-XboxPadInterferenceShield, never performed here.
'@
    }
}

function Install-XboxPadSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    Install-PadAdapterPackage -Name 'XboxPad' -RetroBatRoot $RetroBatRoot -PackagePath $PackagePath -Approved:$Approved
}

function Configure-XboxPadProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [object[]] $DetectedPads)
    if ($PSBoundParameters.ContainsKey('DetectedPads')) {
        if (-not @($DetectedPads | Where-Object { (Get-PadDetectedName $_) -eq 'XboxPad' }).Count) { return 0 }
    }
    Set-PadGamepadConfiguration -Name 'XboxPad' -RetroBatRoot $RetroBatRoot -Confirm:$false
}

# Report-only, as everywhere in this package: no process is touched, no pad is blacklisted. The one
# thing worth saying out loud is the BLE firmware case, decided on the instance id (PID_0B13) and not
# on a localized friendly name - the same language-independent rule arcade uses for its Code-43 report.
function Set-XboxPadInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [object[]] $Devices)
    Write-KitLog (Get-KitText 'Pad.Adapter.ShieldReportsOnly') -Level Info
    Write-KitLog (Get-KitText 'Pad.NoBlacklist') -Level Info
    $params = @{ Quiet = $true }
    if ($PSBoundParameters.ContainsKey('Devices')) { $params.Devices = $Devices }
    if ($RetroBatRoot) { $params.RetroBatRoot = $RetroBatRoot }
    $mine = @((Get-PadDetectedGamepad @params).DetectedPads | Where-Object { (Get-PadDetectedName $_) -eq 'XboxPad' })
    foreach ($pad in $mine) {
        if ($pad.DeviceId.ToUpperInvariant() -like '*PID_0B13*') { Write-KitLog (Get-KitText 'Pad.Quirk.BleFirmware') -Level Warn }
    }
}
