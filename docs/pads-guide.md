# Gamepad Guide — Pads as the Third Input Class

The `pads\` package gives USB/Bluetooth gamepads their own device class beside
Wiimote/USB lightguns (`lightgun\`) and arcade sticks/wheels (`arcade\`):
**8BitDo, Xbox, PlayStation and Switch Pro controllers**.

---

## 📌 Why pads is not arcade

Fightsticks and gamepads live in different worlds, and the kit keeps them apart on purpose:

| | `arcade\` | `pads\` |
|---|---|---|
| detection | exactly one cabinet device per scan | **all** pads side by side (up to 4 players) |
| class value | `ArcadeStick` / `Wheel` | `Gamepad` |
| Steam policy | vendor VIDs go on the controller blacklist | pads stay **visible** to Steam (navigation input) |
| writes | mame.ini, `[Controllers]`, Model 2/Supermodel | `retrobat.ini [Controllers]` only |

Class order is **lightgun → arcade → pads**: a device that a lightgun or arcade adapter
claims by signature or name hint is never re-claimed as a gamepad. This matters because the
XInput id `045E:028E` is shared by real Xbox pads, GP2040-CE sticks and 8BitDo controllers in
X-mode, and `045E:0719` is both the Xbox wireless receiver and the arcade wheel's. Every
exclusion is logged (`Pad.Excluded`), so you can see who claimed what.

## 🎮 The four adapters (v1)

| Adapter | Signature families | Quirks reported |
|---|---|---|
| `EightBitDoPad` | `2DC8:` official 8BitDo PIDs | mode-switch combo (X/D/S), BT impersonation |
| `XboxPad` | `045E:` wired/BT/receiver PIDs | BLE `0B13` double-input (needs Xbox Accessories firmware, manual) |
| `PlayStationPad` | `054C:` DS3…DS5 PIDs | DS3 needs DsHidMini/BthPS3 (driver, manual — links only) |
| `SwitchProPad` | `057E:2009` | pairing handshake via middleware (manual) |

Bluetooth: classic-BTHENUM instances (`VID&0002054C_PID&09CC` form) are matched alongside USB.
**BLE `BTHLE\…` instances carry no VID/PID — invisible to v1 by design** (see the adapter README).

## ⛔ What the kit deliberately does not do

The community design docs for pads ask for four things the kit's rules refuse, and they stay
manual with official links printed instead:

- installing drivers/middleware (DsHidMini, BthPS3, DS4Windows, BetterJoy, HidHide) — HKLM/kernel territory
- downloading vendor software (8BitDo Ultimate, Xbox Accessories) — no allowlisted HTTPS sources
- firmware updates and physical mode-switch combos
- putting pads on the Steam blacklist — that would kill exactly the input Steam should keep

## 💻 Command line

```powershell
# what does the cabinet see? (read-only; pass -Devices in scripts/agents)
& pads\steps\01-Gamepads.ps1

# preview the [Controllers] write
& pads\steps\01-Gamepads.ps1 -WhatIf

# apply
& pads\steps\01-Gamepads.ps1
```

```powershell
Import-Module pads\RetroCabinetKit.Pads.psd1
Get-PadDetectedGamepad -Devices (Get-PnpDevice -PresentOnly)
Set-PadGamepadConfiguration -Name 'XboxPad' -RetroBatRoot 'D:\RetroBat'
```

## 🧪 Tests & bench

`tests\pads\Pads.Tests.ps1` — class exclusions (GP2040 stays Arcade, AimTrak stays Lightgun,
bare `045E:028E` Xbox pad lands on XboxPad), BT-classic matching, BLE blindness documented,
`[Controllers]` idempotence, absent retrobat.ini stays unwritten, and a **Steam leak guard**:
no pad code path may ever touch a real `config.vdf`.
At the cabinet, [bench-check.md](bench-check.md) section 6 verifies the class split with real pads.
