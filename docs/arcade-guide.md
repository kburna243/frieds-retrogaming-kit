# Arcade Input Guide — Fightsticks, Encoders & Wheels

How **Fried's Retrogaming Kit** treats USB arcade devices as a device class of their own, beside the
Wiimote/USB lightguns. Package: `arcade\` (steps in `arcade\steps\`, one plugin per device in
`arcade\adapters\`).

---

## 📌 Design: one cabinet, several input classes

The cabinet may hold a lightgun, two fightsticks and a wheel at the same time. The kit never mixes
the classes and never re-claims hardware:

```
        [ USB devices ]
               │  detection = tight "VID_xxxx&PID_yyyy" signatures
               ▼
   ┌───────────────────────────────┐
   │  lightgun\adapters\  checked FIRST (guns win)      │
   ├───────────────────────────────┤
   │  arcade\adapters\    sticks + wheels               │
   └───────────────────────────────┘
               │ no device matched? report and stop — no guessing
               ▼
   [ mame.ini ] [ retrobat.ini [Controllers] ] [ Emulator.ini / Supermodel.ini ] [ Steam blacklist ]
```

Why "guns win" matters: several arcade and gun devices share USB vendor IDs.

| Shared id | Gun side | Arcade side |
|---|---|---|
| `2E8A:000A` | OpenFIRE (GP2040 bootloader) | GP2040/DIY-wheel sketches matched it — excluded from arcade |
| `16C0:05E1` | Retro Shooter | Zero Delay clones use it — arcade matches only `0079:0006` |
| `0079:*` | DolphinBar `1802/1803`, RetroShooter `187C` | Zero Delay `0006`, Mayflash multi `0183/0184` — exact PIDs only |
| `D209:*` | AimTrak `16xx` | Ultimarc I-PAC `0301/0302/0401` — exact PIDs only |
| `045E:028E` | — (XInput is the gun path) | every X360 pad — GP2040-CE is matched by **name** (`*GP2040*`), never by this id |

Name patterns are only ever a fallback for adapters that intentionally ship no VID/PID (GP2040-CE);
they can never outvote a real signature match.

## 🕹️ Supported devices (v1)

| Adapter | Device class | Notes |
|---|---|---|
| `GP2040CE` | ArcadeStick | GP2040-CE firmware sticks; web-configured, XInput |
| `BrookUFB` | ArcadeStick | Brook UFB/PCB (0C12) |
| `IPAC` | ArcadeStick | Ultimarc I-PAC keyboard encoder (D209:03xx/0401) |
| `ZeroDelay` | ArcadeStick | classic 0079:0006 encoder |
| `MadCatzArcade` | ArcadeStick | TE/TE2/etc.; surfaces the **Code 43** quirk (see below) |
| `HoriArcade` | ArcadeStick | Real Arcade Pro family (0F0D, exact PIDs) |
| `MultiConsoleArcade` | ArcadeStick | Razer/Mayflash/Qanba multi-system sticks |
| `PS2ToUSBAdapter` | ArcadeStick | 0810/0079 PS2 bridges (`shared-endpoints` quirk) |
| `Xbox360Wheel` | Wheel | 045E:0719/0291; FFB needs the **Lavendy driver (manual, HKLM)** |
| `LogitechWheel` | Wheel | G25/G27/G29/G920/G923…; `combined-pedals` quirk |
| `ThrustmasterFanatecWheel` | Wheel | T300/TX + Fanatec CSL DD (044F/0EB7) |
| `DIYArcadeWheel` | Wheel | 1209:FFB0 OpenFFB boards (community — verify PID) |

## 🖥️ What "configure" actually writes

Everything goes through the audited lightgun writers — backup, encoding preserved, atomic replace,
running-emulator guard, `-WhatIf` supported:

| Info table | Target file |
|---|---|
| `MameValues` | `emulators\mame\mame.ini` (`joystick`/`keyboard`, `paddle_device`, `pedal_device`) |
| `ControllersValues` | `retrobat.ini` `[Controllers]` (`Autocontrollers`, `WheelForceFeedback`, `WheelRotation`) |
| `Model2Values` | `emulators\m2emulator\Emulator.ini` — only if the file exists |
| `SupermodelValues` | `emulators\supermodel\Config\Supermodel.ini` `[Global]` — only if it exists |
| `SteamEntries` | Steam `controller_blacklist` in `config.vdf` — **never a process kill** |

Absent optional emulators are skipped, both when writing and when verifying. RetroArch's global
`input_joypad_driver` is deliberately **not** touched (last writer would silently win — use
per-core overrides). MAME `ctrlr` XML profiles and the vendor drivers (Lavendy, LGS 5.10) stay
manual work; the adapters name the official sources instead of downloading.

> ⚠️ Bench check pending: the `[Controllers]` keys and values follow the community design doc; the
> kit writes them idempotently and backs everything up, but confirm on a real RetroBat that these
> keys drive your wheels as intended.

### Mad Catz and Code 43

PS3-era Mad Catz sticks (TE, TE2, FightStick) often fail on USB-3.0 xHCI ports with device manager
error **Code 43**. The kit detects this language-independently (`ConfigManagerErrorCode`, never a
localized error string) and logs the known workarounds: USB-2.0 hub in front, or the BIOS xHCI
compatibility option. Detection still classifies the stick — the quirk is reported, not hidden.

## 💻 Command line

```powershell
# detect (read-only) — what does the cabinet see?
& arcade\steps\01-Adapter.ps1                    # RetroBat root comes from arcade/lightgun state

# force a device list (agent/test) and see only a plan:
& arcade\steps\01-Adapter.ps1 -Devices (Get-PnpDevice -PresentOnly) -WhatIf

# configure: mame.ini + [Controllers] + emulator INIs + Steam blacklist
& arcade\steps\01-Adapter.ps1

# vendor tool from a locally downloaded ZIP (the kit never downloads itself):
& arcade\steps\01-Adapter.ps1 -Install -Name LogitechWheel -PackagePath D:\downloads\lgs.zip -Approved
```

Module level:

```powershell
Import-Module arcade\RetroCabinetKit.Arcade.psd1
Get-ArcadeDetectedAdapter                       # live scan
Get-ArcadeDetectedAdapter -Devices @($myStick)  # injected
Set-ArcadeAdapterConfiguration -Name 'IPAC' -RetroBatRoot 'D:\RetroBat'
```

## ➕ Adding a device

Copy `arcade\adapters\_Template.ps1` to `<Name>.ps1`, fill the Info table (tight `MatchIds`!), keep
the five function names. A file that does not parse, or lacks `Test-…Hardware`/`Get-…AdapterInfo`,
is reported as incomplete and skipped — it can never break the scan. The test suite
(`tests\arcade\Adapters.Tests.ps1`) includes the class-collision cases: add a regression case for
every new signature.
