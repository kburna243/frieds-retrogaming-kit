# --- PAD ADAPTER TEMPLATE --- copy, rename to <YourPadFamily>.ps1, fill in, never execute this file ---
# Every pads\adapters\<Name>.ps1 implements the five functions below and nothing else.
# "<Name>" must equal the file name. Files starting with _ are never scanned or executed.
#
# Rules the kit enforces (see also pads\adapters\README.md):
#   * DEVICE CLASS FIRST: lightgun > arcade > pads. Get-PadDetectedGamepad removes every device a
#     lightgun or arcade adapter claims before the pad families ever see it, and logs each drop
#     (Pad.Excluded). A pad adapter must not widen that rule - 045E:028E is an Xbox pad AND a
#     GP2040-CE stick, and the stick has to win.
#   * Read-only detection. Match TIGHT 'VID_xxxx&PID_yyyy' signatures - never a bare VID (0079 alone
#     is a DolphinBar, 2E8A/000A is OpenFIRE's bootloader, D209 alone is AimTrak's). The BTHENUM
#     Bluetooth-classic spelling of the same signature is derived by Get-PadSignaturePatterns; do not
#     hand-write it, one normalizer for all families means it cannot drift.
#   * NameHints are the last resort only (GP2040-CE style, when there is no signature). If MatchIds is
#     non-empty, a friendly name can never outvote a signature - the rule pads inherited from arcade.
#   * No downloads. Install only from -PackagePath (a local ZIP) and only with -Approved; without a
#     package just name the official source. Network APIs are forbidden in this package entirely.
#   * Never kill a process, never touch Steam. Pads are the input device Steam needs to navigate, so
#     SteamEntries stays EMPTY (Pad.NoBlacklist explains it to the user).
#   * Writes: ControllersValues -> retrobat.ini [Controllers] through lightgun's audited writer.
#     MameValues / Model2Values / SupermodelValues stay EMPTY by class decision, not by laziness.
#   * Quirks are reported, never repaired. The codes land in the scan result; the human-readable
#     version belongs into this adapter's -InterferenceShield, because only this file knows the
#     details (which mode masquerades as which vendor id).
#   * No Write-Host, no HKLM, no services, no scheduled tasks here - steps and the wizard do that.

function Test-ExamplePadHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [object[]] $Devices)
    # Detection goes through the central scan so the class rule applies to every entry point, and so
    # that no adapter can invent its own signature handling. -Devices stays injected when bound.
    $params = @{ Quiet = $true }
    if ($PSBoundParameters.ContainsKey('Devices')) { $params.Devices = $Devices }
    if ($RetroBatRoot) { $params.RetroBatRoot = $RetroBatRoot }
    @((Get-PadDetectedGamepad @params).DetectedPads | Where-Object { (Get-PadDetectedName $_) -eq 'ExamplePad' }).Count -gt 0
}

function Get-ExamplePadAdapterInfo {
    @{
        Class     = 'Gamepad'                    # every pad adapter: 'Gamepad'
        ToolDir   = ''                           # non-empty only for a portable vendor ZIP in tools\
        MatchIds  = @('USB\VID_1234&PID_5678*')  # tight signatures, USB and BT form share these
        NameHints = @()                          # only when there is no signature at all
        Quirks    = @()                          # e.g. 'mode-switch-combo', 'bt-impersonation'
        SteamEntries     = @()                   # ALWAYS empty for pads: no controller_blacklist entry
        MameValues       = @()                   # pads are RetroBat-side auto-mapping, not per-emulator
        ControllersValues = @{ Autocontrollers = '1' }
        Model2Values     = @()
        SupermodelValues = @()
        Links = @{ 'Vendor (official)' = 'https://example.com/' }
        Notes = 'One paragraph a human reads: modes, pair button, what the kit cannot do here.'
    }
}

function Install-ExamplePadSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    Install-PadAdapterPackage -Name 'ExamplePad' -RetroBatRoot $RetroBatRoot -PackagePath $PackagePath -Approved:$Approved
}

function Configure-ExamplePadProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [object[]] $DetectedPads)
    # The detected list is a gate, not decoration: a profile is never applied to a family that is not
    # plugged in (0 changes, retrobat.ini untouched). Unbound keeps the by-name call working.
    if ($PSBoundParameters.ContainsKey('DetectedPads')) {
        if (-not @($DetectedPads | Where-Object { (Get-PadDetectedName $_) -eq 'ExamplePad' }).Count) { return 0 }
    }
    Set-PadGamepadConfiguration -Name 'ExamplePad' -RetroBatRoot $RetroBatRoot -Confirm:$false
}

# Report-only by design: there is no interference to shield against, because pads are never blacklisted
# and processes are never killed. What this function IS for: the quirks of this family, in prose.
function Set-ExamplePadInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [object[]] $Devices)
    Write-KitLog (Get-KitText 'Pad.Adapter.ShieldReportsOnly') -Level Info
    Write-KitLog (Get-KitText 'Pad.NoBlacklist') -Level Info
    # Example of family-specific quirk prose - see XboxPad for the BLE firmware case.
}
