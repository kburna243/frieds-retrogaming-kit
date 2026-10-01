$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'arcade\RetroCabinetKit.Arcade.psd1') -Force

# XInput slots as MAME sees them (input_xinput.cpp): JOY<n> counts connected slots only, buttons are numbered in the
# order A B X Y [LT RT] LB RB LSB RSB and only those the device reports. The capabilities are injected, so the tests
# do not depend on the pads plugged into this machine. The masks are the ones measured on a cabinet: Gunmote's
# Wiimotes (gamepad, 0xF3FF) and a Mad Catz SF4 FightStick (arcade stick, 0xF33F: no stick clicks).
function New-Cap([int] $Slot, [int] $SubType = -1, [int] $Mask = 0) {
    if ($SubType -lt 0) { return [pscustomobject]@{ Slot = $Slot; Connected = $false; SubType = $null; Flags = 0; ButtonMask = 0; HasLeftTrigger = $false; HasRightTrigger = $false } }
    [pscustomobject]@{ Slot = $Slot; Connected = $true; SubType = $SubType; Flags = 0; ButtonMask = $Mask; HasLeftTrigger = $true; HasRightTrigger = $true }
}

Describe 'XInput slots' {
    It 'numbers MAME joysticks by connected slots only: an empty slot 0 makes slot 1 JOY1' {
        $s = @(Get-ArcadeXInputSlot -Capability @((New-Cap 0), (New-Cap 1 1 0xF3FF), (New-Cap 2), (New-Cap 3 3 0xF33F)))
        ($s | ForEach-Object { "$($_.Slot):$($_.MameJoy)" }) -join ' ' | Should Be '0: 1:JOY1 2: 3:JOY2'
        $s[0].Connected | Should Be $false
        $s[0].Buttons | Should BeNullOrEmpty
    }

    It 'a gamepad keeps LB/RB as buttons 5/6; the triggers are no buttons' {
        $pad = @(Get-ArcadeXInputSlot -Capability @((New-Cap 0 1 0xF3FF)))[0]
        $pad.Kind | Should Be 'Gamepad'
        $pad.TriggersAsButtons | Should Be $false
        $pad.Buttons.LB | Should Be 'JOY1_BUTTON5'
        $pad.Buttons.RSB | Should Be 'JOY1_BUTTON8'
        $pad.Buttons.PSObject.Properties['LT'] | Should BeNullOrEmpty
        $pad.Buttons.DpadUp | Should Be 'JOY1_DPAD_UP'
        $pad.Buttons.Back | Should Be 'JOY1_SELECT'
    }

    It 'an arcade stick counts LT/RT as buttons 5/6, LB/RB move to 7/8, missing stick clicks get no number' {
        $stick = @(Get-ArcadeXInputSlot -Capability @((New-Cap 0 1 0xF3FF), (New-Cap 1 1 0xF3FF), (New-Cap 2 3 0xF33F)))[2]
        $stick.MameJoy | Should Be 'JOY3'
        $stick.Kind | Should Be 'ArcadeStick'
        $stick.TriggersAsButtons | Should Be $true
        "$($stick.Buttons.A) $($stick.Buttons.LT) $($stick.Buttons.RT) $($stick.Buttons.LB) $($stick.Buttons.RB)" | Should Be 'JOY3_BUTTON1 JOY3_BUTTON5 JOY3_BUTTON6 JOY3_BUTTON7 JOY3_BUTTON8'
        $stick.Buttons.PSObject.Properties['LSB'] | Should BeNullOrEmpty
    }

    It 'a button the device does not report shifts the numbers after it, as in MAME' {
        $pad = @(Get-ArcadeXInputSlot -Capability @((New-Cap 0 1 (0xF3FF -band -bnot 0x0100))))[0]   # no LB
        $pad.Buttons.PSObject.Properties['LB'] | Should BeNullOrEmpty
        $pad.Buttons.RB | Should Be 'JOY1_BUTTON5'
    }
}
