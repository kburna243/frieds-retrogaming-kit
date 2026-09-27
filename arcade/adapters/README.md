# arcade\adapters\ — USB fightsticks, arcade encoders and steering wheels

One `<Name>.ps1` per device. The kit parses these files (never executes them at scan time) and only
runs adapters that provide all five functions:

| Function | Purpose |
|---|---|
| `Test-<Name>Hardware -RetroBatRoot [-Devices]` | Read-only VID/PID detection. `-Devices` injects a device list (tests). |
| `Get-<Name>AdapterInfo` | Data table — everything the kit writes is driven from here, no logic. |
| `Install-<Name>Software -RetroBatRoot [-PackagePath] [-Approved]` | Never downloads; without a local ZIP it only prints the official link. |
| `Configure-<Name>Profile -RetroBatRoot [-DetectedDeviceId] [-SteamConfigVdf]` | Delegates to `Set-ArcadeAdapterConfiguration`; returns the number of changes. |
| `Set-<Name>InterferenceShield -RetroBatRoot [-Disable] [-SteamConfigVdf]` | Steam `controller_blacklist` only — the kit never kills processes. |

`_`-prefixed files (the template) are skipped by the catalog.

## Info table keys

| Key | Written to |
|---|---|
| `Class` | detection report only (`ArcadeStick` / `Wheel`) |
| `MatchIds` | tight `USB\VID_xxxx&PID_yyyy*` signatures — **no bare VIDs** (see collision notes) |
| `NameHints` | FriendlyName patterns — fallback signal only for adapters with **no** `MatchIds` (GP2040-CE); never an extra trigger while VID/PID signatures exist |
| `Quirks` | documented device pitfalls surfaced in the detection result (`usb-descriptor-failed` triggers the language-independent Code-43 check) |
| `MameValues` | `emulators\mame\mame.ini` (space format, backup, encoding kept) |
| `ControllersValues` | `retrobat.ini` `[Controllers]` |
| `Model2Values` | `emulators\m2emulator\Emulator.ini` (root section) — only if the file exists |
| `SupermodelValues` | `emulators\supermodel\Config\Supermodel.ini` `[Global]` — only if it exists |
| `SteamEntries` | Steam `controller_blacklist` (`Set-LightgunSteamBlacklist -ExtraEntries`) |
| `Links` | official sources; shown by Install instead of downloading |

## Class coexistence

Lightgun wins: devices claimed by `lightgun\adapters\` are never re-detected here. That is why
signature curation matters — several arcade and gun devices share USB IDs:

- `2E8A:000A` — OpenFIRE lightgun (GP2040 bootloader). **Must not** appear in arcade.
- `16C0:05E1` — Retro Shooter. Zero Delay adapters clone it; only `0079:0006` is matched here.
- `0079` alone — the Mayflash DolphinBar family; only exact PIDs are matched.
- `D209` alone — AimTrak guns live in the same vendor ID as Ultimarc I-PAC boards; exact PIDs only.
- `045E:028E` — every XInput pad. GP2040-CE is matched by name hints (`*GP2040*`), not this ID.

## Not (yet) automated

- Vendor driver installs (Lavendy FFB filter driver, Logitech Gaming Software 5.10) touch HKLM —
  the kit prints the link, the person installs. Unverified RetroBat `[Controllers]` keys
  (`WheelRotation`, `P1Device_*`) are written as documented in the design doc — verify on hardware.
- MAME `ctrlr` XML profiles (e.g. `xarcade.ctrlr` for the I-PAC): the files differ per button plan,
  so the kit only sets `joystick`/`keyboard` basics.
- RetroArch `input_joypad_driver` is global — adapters do **not** write it (one cabinet, many devices,
  last writer would silently win). Use RetroArch per-core overrides instead.
