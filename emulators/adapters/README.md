# Emulator Adapters

Jeder Adapter ist eine `.ps1`-Datei mit fünf Funktionen:

| Funktion | Zweck |
|---|---|
| `Test-<Name>Emulator` | Erkennt, ob der Emulator installiert ist (EXE, Prozess, Ordner) |
| `Get-<Name>EmulatorInfo` | Liefert Metadaten: Pfade, Config-Dateien, offizielle Links |
| `Install-<Name>Emulator` | Installation (Link + User-Paket, nie Download) |
| `Configure-<Name>Emulator` | Wendet SettingsTargets aus Get-*Info an |
| `Set-<Name>InterferenceShield` | Port-/Prozess-Konflikt-Prüfung |

## Adapter-Liste (v0.9.0)

| Adapter | System(e) | Typ |
|---|---|---|
| `MAME` | Arcade (Multi-System) | Standalone |
| `RetroArch` | Multi-System (Libretro Cores) | Frontend/Emulator |
| `TeknoParrot` | Arcade (PC-basiert) | Standalone |
| `Supermodel` | Sega Model 3 | Standalone |
| `Model2` | Sega Model 2 | Standalone |
| `Cemu` | Nintendo Wii U | Standalone |
| `Dolphin` | Nintendo GameCube/Wii | Standalone |
| `RPCS3` | Sony PlayStation 3 | Standalone |
| `Xemu` | Microsoft Xbox | Standalone |
| `DuckStation` | Sony PlayStation 1 | Standalone |
| `PCSX2` | Sony PlayStation 2 | Standalone |
| `FuturePinball` | Future Pinball + BAM | Pinball |
| `VisualPinball` | Visual Pinball VPX | Pinball |
| `PinballArcade` | Pinball Arcade + Arcooda | Pinball |
| `PinballFX3` | Pinball FX3 (Zen) | Pinball |

## Adapter-Vertrag

Jeder Adapter MUSS die fünf benannten Funktionen exportieren. `_Template.ps1` ist die Vorlage.
Der Catalog (`Get-EmulatorsAdapterCatalog`) parsed jede `.ps1`-Datei auf diese fünf Funktionen.