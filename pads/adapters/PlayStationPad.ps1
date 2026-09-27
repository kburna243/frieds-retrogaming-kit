<#
.SYNOPSIS
    Sony PlayStation controllers for Fried's Retrogaming Kit (Gamepad class).
.DESCRIPTION
    Detects the DualShock 3 / DualShock 4 / DualSense family behind Sony's vendor id 054C, in the wired
    USB form and in the Bluetooth-classic form (BTHENUM encodes the same VID/PID differently - that is
    handled centrally by Get-PadSignaturePatterns, not per adapter). Detection is read-only; the only
    write is retrobat.ini [Controllers] through lightgun's audited INI writer.

    DRIVER REALITY (why Install does nothing here): a DualShock 3 on Windows 10/11 needs DsHidMini, and
    Bluetooth on a PC usually needs BthPS3. Both are KERNEL DRIVERS - installed through an MSI / pnputil,
    writing to HKLM and to the driver store. THE KIT DOES NOT INSTALL THEM (same rule as arcade's
    Lavendy FFB driver): this adapter names the official sources and configures only what RetroBat owns.
#>

function Test-PlayStationPadHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [object[]] $Devices)
    $params = @{ Quiet = $true }
    if ($PSBoundParameters.ContainsKey('Devices')) { $params.Devices = $Devices }
    if ($RetroBatRoot) { $params.RetroBatRoot = $RetroBatRoot }
    @((Get-PadDetectedGamepad @params).DetectedPads | Where-Object { (Get-PadDetectedName $_) -eq 'PlayStationPad' }).Count -gt 0
}

function Get-PlayStationPadAdapterInfo {
    @{
        Class   = 'Gamepad'
        # DsHidMini / BthPS3 are MSI driver packages (HKLM): no portable folder, nothing to unpack.
        ToolDir = ''
        MatchIds = @(
            'USB\VID_054C&PID_0268*'   # DualShock 3 / Sixaxis (wired; needs DsHidMini)
            'USB\VID_054C&PID_05C4*'   # DualShock 4 v1
            'USB\VID_054C&PID_09CC*'   # DualShock 4 v2 (wired and Bluetooth)
            'USB\VID_054C&PID_0CE6*'   # DualSense / DualSense Edge (wired and Bluetooth)
            'USB\VID_054C&PID_0DF2*'   # DualSense Edge, separate descriptor
            # The Bluetooth-companion-device form of a DualShock 4 v2. Derived automatically as well -
            # the explicit line exists because this is the pairing 054C is most often seen in.
            'BTHENUM\{00001124-0000-1000-8000-00805F9B34FB}_VID&0002054C_PID&09CC*'
        )
        NameHints = @()
        Quirks    = @('ds3-dshidmini-driver', 'bt-impersonation')
        SteamEntries = @()             # class decision: Steam keeps its pads (Pad.NoBlacklist)
        MameValues = @()
        ControllersValues = @{ Autocontrollers = '1' }
        Model2Values      = @()
        SupermodelValues  = @()
        Links = @{
            # Documentation strings only - the kit never fetches anything (see pads\adapters\README.md).
            'DsHidMini (ViGEm, driver - manual install)'   = 'https://github.com/ViGEm/DsHidMini'
            'DsHidMini documentation (Nefarius)'           = 'https://docs.nefarius.at/projects/DsHidMini/v3/'
            'BthPS3 (Bluetooth driver - manual install)'   = 'https://ns5aft.github.io/BthPS3'
        }
        Notes = @'
DualShock 4 and DualSense are standard HID gamepads once Windows has enumerated them; a DualShock 3 is
not - without DsHidMini it shows up as an unusable vendor-specific device. That is driver work in HKLM
and stays with the user (Links above). Mode note: 8BitDo pads in D-mode and several third-party pads
report 054C too, so this adapter can be the one that "sees first" - that is the intended behaviour of
the impersonation quirk, not a mis-detection.
'@
    }
}

function Install-PlayStationPadSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    Install-PadAdapterPackage -Name 'PlayStationPad' -RetroBatRoot $RetroBatRoot -PackagePath $PackagePath -Approved:$Approved
}

function Configure-PlayStationPadProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [object[]] $DetectedPads)
    if ($PSBoundParameters.ContainsKey('DetectedPads')) {
        if (-not @($DetectedPads | Where-Object { (Get-PadDetectedName $_) -eq 'PlayStationPad' }).Count) { return 0 }
    }
    Set-PadGamepadConfiguration -Name 'PlayStationPad' -RetroBatRoot $RetroBatRoot -Confirm:$false
}

# Report-only: no driver is installed from here, no process is killed, nothing is blacklisted.
function Set-PlayStationPadInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [object[]] $Devices)
    Write-KitLog (Get-KitText 'Pad.Adapter.ShieldReportsOnly') -Level Info
    Write-KitLog (Get-KitText 'Pad.NoBlacklist') -Level Info
    $params = @{ Quiet = $true }
    if ($PSBoundParameters.ContainsKey('Devices')) { $params.Devices = $Devices }
    if ($RetroBatRoot) { $params.RetroBatRoot = $RetroBatRoot }
    if (@((Get-PadDetectedGamepad @params).DetectedPads | Where-Object { (Get-PadDetectedName $_) -eq 'PlayStationPad' }).Count) {
        # A Sony id can also be someone else's pad: 8BitDo in D-mode is the common case in a cabinet.
        Write-KitLog (Get-KitText 'Pad.Quirk.BtImpersonation' -f 'D (8BitDo)', '054C (PlayStation)') -Level Info
    }
}
