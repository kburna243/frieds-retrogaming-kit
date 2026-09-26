# Lightgun adapters

This folder holds one file per USB lightgun system. The kit's step 15 (`lightgun\steps\15-Adapter.ps1`)
scans this folder, loads every adapter and calls its `Test-<Name>Hardware` - detection reads the PnP
device list and changes nothing on the machine.

## Shipped adapters

| File | Hardware | PnP signature |
|------|----------|---------------|
| `Gun4IR.ps1` | Gun4IR on Arduino Leonardo / Pro Micro | `USB\VID_2341&PID_8036` (runtime), `USB\VID_1B4F&PID_9206` (bootloader) |
| `OpenFIRE.ps1` | OpenFIRE firmware (RP2040 / ESP32-S3 guns) | `VID_2E8A&PID_000A`, `VID_303A&PID_1001` |
| `AimTrak.ps1` | Ultimarc AimTrak modules, gun 1-8 | `VID_D209&PID_1601` .. `VID_D209&PID_1608` |
| `RetroShooter.ps1` | Retro Shooter RS3 Reaper hub | `VID_16C0&PID_05E1/0x187C`, `VID_0079&PID_187C` (never a bare `VID_0079` - that is also the DolphinBar) |

## Contributing one

1. Copy `_Template.ps1` to `<YourGun>.ps1` (the file name becomes the adapter name).
2. Fill the five contract functions - the template lists them and their parameters.
3. Test detection on your cabinet: `powershell -File lightgun\steps\15-Adapter.ps1 -RetroBatRoot C:\RetroBat -WhatIf`
4. Open a pull request. The VID/PID signature is the heart of an adapter: state where it came from.

## Kit rules every adapter follows

- Detection is read-only and works standalone (no kit module required for `Test-*`).
- Writing functions honour `-WhatIf` (they use `SupportsShouldProcess` through the kit helpers);
  INI files are edited value by value with a backup, never by killing or rewriting whole files.
- **No auto-download from arbitrary hosts.** Software sources are listed as official `Links`; the user
  fetches a portable ZIP and the kit unpacks it via `-PackagePath` after `-Approved`, logging the SHA256.
  Allow-list changes (`core\download-allowlist.psd1`) are a maintainer decision, not an adapter's.
- Interference with Steam Input is shielded through Steam's `controller_blacklist` (the entries from
  `Get-<Name>AdapterInfo.SteamEntries`) - no process is ever killed, no HKLM registry value is touched.
- mame.ini values use MAME's own `name  value` format and stay byte-for-byte intact otherwise;
  `retrobat.ini` writes go into the `[Guns]` section; DemulShooter can record the detected gun in
  `[Player1] Device` (single-player slot today; multi-gun wiring is per-adapter TODO).
