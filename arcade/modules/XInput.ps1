# XInput slots: which pad sits on which of the four places, and what MAME makes of it. Measured facts from MAME's
# xinput provider (src/osd/modules/input/input_xinput.cpp):
# - it walks the slots 0..3 and skips the empty ones, so JOY<n> is the n-th CONNECTED slot (slot 0 empty, slot 1
#   used -> JOY1);
# - buttons are numbered in the order A, B, X, Y, LT, RT, LB, RB, LSB, RSB, where LT/RT only count as buttons on arcade
#   sticks and arcade pads: there LB/RB are BUTTON7/8, on a gamepad BUTTON5/6.
# XInput itself cannot tell what is behind a slot: Gunmote's Wiimotes, a ViGEm pad and a real Xbox pad are all
# "Gamepad"; the subtype is what the device reports.

$script:XInputSubTypeName = @{
    0 = 'Unknown'; 1 = 'Gamepad'; 2 = 'Wheel'; 3 = 'ArcadeStick'; 4 = 'FlightStick'; 5 = 'DancePad'
    6 = 'Guitar'; 7 = 'GuitarAlternate'; 8 = 'DrumKit'; 11 = 'GuitarBass'; 19 = 'ArcadePad'
}

# Raw capabilities of the four slots (xinput1_4.dll, Windows 8 and later): Slot, Connected, SubType, Flags, the
# mask of the buttons the device has and whether it has the two triggers.
function Get-ArcadeXInputCapability {
    [CmdletBinding()]
    param()
    if (-not ('RetroCabinetKit.XInputCaps' -as [type])) {
        Add-Type -Namespace RetroCabinetKit -Name XInputCaps -MemberDefinition @'
[StructLayout(LayoutKind.Sequential)] public struct Gamepad { public ushort Buttons; public byte LeftTrigger; public byte RightTrigger; public short ThumbLX, ThumbLY, ThumbRX, ThumbRY; }
[StructLayout(LayoutKind.Sequential)] public struct Capabilities { public byte Type; public byte SubType; public ushort Flags; public Gamepad Gamepad; public ushort LeftMotor; public ushort RightMotor; }
[DllImport("xinput1_4.dll")] public static extern uint XInputGetCapabilities(uint index, uint flags, out Capabilities caps);
'@
    }
    foreach ($slot in 0..3) {
        $caps = New-Object 'RetroCabinetKit.XInputCaps+Capabilities'
        $ok = [RetroCabinetKit.XInputCaps]::XInputGetCapabilities([uint32]$slot, 0, [ref]$caps) -eq 0
        [pscustomobject]@{
            Slot = $slot; Connected = $ok; SubType = $(if ($ok) { [int]$caps.SubType } else { $null }); Flags = $(if ($ok) { [int]$caps.Flags } else { 0 })
            ButtonMask = $(if ($ok) { [int]$caps.Gamepad.Buttons } else { 0 })
            HasLeftTrigger = $ok -and $caps.Gamepad.LeftTrigger -gt 0; HasRightTrigger = $ok -and $caps.Gamepad.RightTrigger -gt 0
        }
    }
}

# The slots as MAME sees them. -Capability: rows of Get-ArcadeXInputCapability (tests pass their own).
# Per slot: Slot, Connected, MameJoy (JOY<n> or $null), Kind (subtype name), TriggersAsButtons, Wireless and
# Buttons: the kit's source names of the pad's buttons and d-pad (JOY<n>_BUTTON<m>, JOY<n>_DPAD_<dir>), ready for an
# input profile.
function Get-ArcadeXInputSlot {
    [CmdletBinding()]
    param([AllowEmptyCollection()] [object[]] $Capability = @(Get-ArcadeXInputCapability))
    $joy = 0
    foreach ($c in @($Capability | Sort-Object Slot)) {
        if (-not $c.Connected) {
            [pscustomobject]@{ Slot = $c.Slot; Connected = $false; MameJoy = $null; Kind = $null; TriggersAsButtons = $false; Wireless = $false; Buttons = $null }
            continue
        }
        $joy++
        $kind = if ($script:XInputSubTypeName.ContainsKey([int]$c.SubType)) { $script:XInputSubTypeName[[int]$c.SubType] } else { "SubType$($c.SubType)" }
        $lt = $kind -in 'ArcadeStick', 'ArcadePad'
        # MAME numbers only the buttons the device reports (has_button / has_trigger); without a mask all count.
        $mask = if ($c.PSObject.Properties['ButtonMask'] -and $c.ButtonMask) { [int]$c.ButtonMask } else { 0xF3C0 }
        $has = [ordered]@{
            A = [bool]($mask -band 0x1000); B = [bool]($mask -band 0x2000); X = [bool]($mask -band 0x4000); Y = [bool]($mask -band 0x8000)
            LT = $lt -and (-not $c.PSObject.Properties['HasLeftTrigger'] -or $c.HasLeftTrigger)
            RT = $lt -and (-not $c.PSObject.Properties['HasRightTrigger'] -or $c.HasRightTrigger)
            LB = [bool]($mask -band 0x0100); RB = [bool]($mask -band 0x0200); LSB = [bool]($mask -band 0x0040); RSB = [bool]($mask -band 0x0080)
        }
        $buttons = [ordered]@{}
        $n = 0
        foreach ($b in $has.Keys) { if ($has[$b]) { $n++; $buttons[$b] = 'JOY{0}_BUTTON{1}' -f $joy, $n } }
        foreach ($d in 'UP', 'DOWN', 'LEFT', 'RIGHT') { $buttons["Dpad$($d.Substring(0,1))$($d.Substring(1).ToLowerInvariant())"] = "JOY${joy}_DPAD_$d" }
        $buttons['Start'] = "JOY${joy}_START"
        $buttons['Back'] = "JOY${joy}_SELECT"
        [pscustomobject]@{
            Slot = $c.Slot; Connected = $true; MameJoy = "JOY$joy"; Kind = $kind; TriggersAsButtons = $lt
            Wireless = [bool]([int]$c.Flags -band 0x0002)   # XINPUT_CAPS_WIRELESS
            Buttons = [pscustomobject]$buttons
        }
    }
}
