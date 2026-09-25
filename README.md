# retro-cabinet-kit

> **Status: work in progress.** Only the shared core (phase P0) exists so far.

Guided Windows installers for retro gaming cabinets: a **virtual pinball** package (bring your own
PinUP Popper build) and a **Wiimote lightgun** package for RetroBat. Every step is checked
(Test → Invoke → Verify), can run as a dry run (`-WhatIf`) and is shown in German or English.

The kit contains **no** ROMs, BIOS files, tables, media, purchased builds or third-party binaries.
Free tools are downloaded from their official sources only; everything else is supplied by you.
All the people and projects this kit builds on are listed in [CREDITS.md](CREDITS.md).

## Requirements

- Windows 10/11 with Windows PowerShell 5.1 (nothing else to install; SQLite comes from the
  `winsqlite3.dll` that ships with Windows)

## Layout

| Path | Content |
|---|---|
| `Start-Kit.cmd` | Starts the kit (`-ExecutionPolicy Bypass` for this process only) |
| `core\` | Shared PowerShell module `RetroCabinetKit.Core` (log, state, steps, i18n, elevation, SQLite, text, registry, processes, backup, shortcuts, downloads) |
| `i18n\` | User-facing texts (`de-DE.psd1`, `en-US.psd1`) |
| `tests\` | Pester 3 tests with synthetic fixtures: `powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1` |

## License

To be decided.
