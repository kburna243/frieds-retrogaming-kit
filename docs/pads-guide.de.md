# Gamepad-Guide — Pads als dritte Eingabeklasse

Das Paket `pads\` gibt USB-/Bluetooth-Gamepads eine eigene Geräteklasse neben
Wiimote-/USB-Lightguns (`lightgun\`) und Arcade-Sticks/Lenkrädern (`arcade\`):
**8BitDo-, Xbox-, PlayStation- und Switch-Pro-Controller**.

---

## 📌 Warum pads nicht arcade ist

Fightsticks und Gamepads leben in verschiedenen Welten, und das Kit hält sie bewusst getrennt:

| | `arcade\` | `pads\` |
|---|---|---|
| Erkennung | genau ein Cabinet-Gerät pro Scan | **alle** Pads parallel (bis 4 Player) |
| Klassenwert | `ArcadeStick` / `Wheel` | `Gamepad` |
| Steam-Politik | Hersteller-VIDs auf die Controller-Blacklist | Pads bleiben für Steam **sichtbar** (Navigations-Input) |
| Schreibziele | mame.ini, `[Controllers]`, Model 2/Supermodel | nur `retrobat.ini [Controllers]` |

Reihenfolge der Klassen: **lightgun → arcade → pads**. Ein Gerät, das ein Lightgun- oder
Arcade-Adapter per Signatur oder Namens-Hinweis beansprucht, wird nie zum Gamepad umgewidmet.
Das ist wichtig, weil die XInput-ID `045E:028E` echten Xbox-Pads, GP2040-CE-Sticks und 8BitDo-Pads
im X-Modus gehört und `045E:0719` sowohl Xbox-Empfänger als auch Arcade-Lenkrad ist. Jede
Ausnahme wird geloggt (`Pad.Excluded`) — du siehst, wer was beansprucht hat.

## 🎮 Die vier Adapter (v1)

| Adapter | Signatur-Familien | Gemeldete Quirks |
|---|---|---|
| `EightBitDoPad` | `2DC8:` offizielle 8BitDo-PIDs | Moduswechsel-Kombo (X/D/S), BT-Imitation |
| `XboxPad` | `045E:` verdrahtet/BT/Empfänger | BLE `0B13` Doppel-Input (braucht Xbox-Accessories-Firmware, Handarbeit) |
| `PlayStationPad` | `054C:` DS3…DS5-PIDs | DS3 braucht DsHidMini/BthPS3 (Treiber, Handarbeit — nur Links) |
| `SwitchProPad` | `057E:2009` | Pairing-Handshake über Middleware (Handarbeit) |

Bluetooth: Classic-BTHENUM-Instanzen (Form `VID&0002054C_PID&09CC`) werden neben USB gematcht.
**BLE-`BTHLE\…`-Instanzen tragen keine VID/PID — für v1 bewusst unsichtbar** (siehe Adapter-README).

## ⛔ Was das Kit bewusst nicht tut

Die Pads-Designdocs der Community fordern vier Dinge, die die Kit-Regeln ablehnen; sie bleiben
Handarbeit, und die Adapter nennen stattdessen die offiziellen Quellen:

- Treiber/Middleware installieren (DsHidMini, BthPS3, DS4Windows, BetterJoy, HidHide) — HKLM/Kernel-Territorium
- Herstellersoftware laden (8BitDo Ultimate, Xbox Accessories) — keine Allowlist-HTTPS-Quelle
- Firmware-Updates und physische Moduswechsel-Kombos
- Pads auf die Steam-Blacklist setzen — das würde genau den Input töten, den Steam behalten soll

## 💻 Kommandozeile

```powershell
# Was sieht das Cabinet? (read-only; in Skripten/Agenten -Devices übergeben)
& pads\steps\01-Gamepads.ps1

# [Controllers]-Schreibvorgang als Vorschau
& pads\steps\01-Gamepads.ps1 -WhatIf

# anwenden
& pads\steps\01-Gamepads.ps1
```

```powershell
Import-Module pads\RetroCabinetKit.Pads.psd1
Get-PadDetectedGamepad -Devices (Get-PnpDevice -PresentOnly)
Set-PadGamepadConfiguration -Name 'XboxPad' -RetroBatRoot 'D:\RetroBat'
```

## 🧪 Tests & Bench

`tests\pads\Pads.Tests.ps1` — Klassen-Ausnahmen (GP2040 bleibt Arcade, AimTrak bleibt Lightgun,
 nacktes `045E:028E`-Xbox-Pad landet bei XboxPad), BT-Classic-Matching, dokumentierte
BLE-Blindheit, `[Controllers]`-Idempotenz, fehlende retrobat.ini bleibt ungeschrieben, und ein
**Steam-Leak-Guard**: Kein Pad-Code-Pfad darf je eine echte `config.vdf` anfassen.
Am Cabinet prüft [bench-check.de.md](bench-check.de.md) Kapitel 6 die Klassen-Aufteilung mit echten Pads.
