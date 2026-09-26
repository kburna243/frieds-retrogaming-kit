<div align="center">
  <img src="docs/images/character-controller.svg" alt="Fried's Retrogaming Kit Mascot" width="160" style="margin-bottom: 12px;" />
  <h1>🕹️ Fried's Retrogaming Kit</h1>
  <p><strong>The Definitive Automation & Setup Suite for Windows Retro Gaming & Pinball Cabinets</strong></p>

  [![Windows Platform](https://img.shields.io/badge/Platform-Windows%2010%20%7C%2011-0078D6?style=for-the-badge&logo=windows&logoColor=white)](https://github.com/kburna243/frieds-retrogaming-kit)
  [![PowerShell](https://img.shields.io/badge/Engine-PowerShell%205.1%2B-5391FE?style=for-the-badge&logo=powershell&logoColor=white)](https://github.com/kburna243/frieds-retrogaming-kit)
  [![License: MIT](https://img.shields.io/badge/License-MIT-yellow?style=for-the-badge)](LICENSE)
  [![Documentation](https://img.shields.io/badge/Docs-English%20%7C%20Deutsch-3DDC84?style=for-the-badge&logo=gitbook&logoColor=white)](docs/)
  [![Live Website](https://img.shields.io/badge/Website-kburna243.github.io%2Ffrieds--retrogaming--kit-ff2d95?style=for-the-badge&logo=googlechrome&logoColor=white)](https://kburna243.github.io/frieds-retrogaming-kit/)
  [![CI](https://img.shields.io/github/actions/workflow/status/kburna243/frieds-retrogaming-kit/ci.yml?branch=main&style=for-the-badge&label=CI)](https://github.com/kburna243/frieds-retrogaming-kit/actions/workflows/ci.yml)
  [![Depersonalization](https://img.shields.io/badge/Privacy-0%20Data%20Leaks-success?style=for-the-badge&logo=shield)](tools/Test-Depersonalized.ps1)

  <p>
    <a href="README.md"><strong>English</strong></a> •
    <a href="README.de.md"><strong>Deutsch</strong></a> •
    <a href="docs/pinball-guide.md"><strong>Pinball Guide</strong></a> •
    <a href="docs/lightgun-guide.md"><strong>Lightgun Guide</strong></a> •
    <a href="docs/troubleshooting.md"><strong>Troubleshooting</strong></a> •
    <a href="docs/faq.md"><strong>FAQ</strong></a>
  </p>
</div>

---

> [!NOTE]
> **Status: v0.1.0 — early release.** The shared core (`core\`), the virtual pinball suite (`pinball\`, steps 1–9) and the Wiimote lightgun suite (`lightgun\`, steps 1–14 including TeknoParrot, Demul + DemulShooter, Model 2 / Supermodel and a guided DuckStation / PCSX2 check) are functional. Rumble output is planned. See the [feature status](#-feature-status) below, the [CHANGELOG](CHANGELOG.md) and the [ROADMAP](ROADMAP.md).

---

## 💡 What is Fried's Retrogaming Kit?

Building and maintaining a modern Windows retro arcade or virtual pinball cabinet is notoriously complex. Moving installations between drives breaks paths in obscure SQLite databases; connecting Wiimotes results in conflicting mouse inputs, jittery cursors, and Steam Desktop configs hijacking controls; while COM DLL registrations silently fail.

**Fried's Retrogaming Kit** solves this with an auditable, zero-dependency PowerShell automation engine. It transforms complex manual installation routines into guided, reproducible steps where **every action is checked, verified live, and backed up before execution**.

Created by **Fried ([@kburna243](https://github.com/kburna243))** — built by arcade & pinball enthusiasts, for enthusiasts.

---

## 🏛️ The Three Core Pillars

<p align="center">
  <img src="docs/images/frieds-rgk-3pillars.webp" alt="The Three Core Pillars of Fried's Retrogaming Kit" width="860" style="border-radius: 12px; box-shadow: 0 8px 32px rgba(0,0,0,0.5); margin: 16px 0;" />
</p>

### 1. 🎱 Virtual Pinball Suite (`pinball\`)
- **Seamless Relocation & Rebuild**: Move an entire **Baller Installer** layout (PinUP Popper, Visual Pinball X, VPinMAME, B2S, FlexDMD, Future Pinball) to a new drive (e.g. `E:\Old Build` ➔ `D:\Pinball`) or restore it onto a fresh Windows installation.
- **Deep Database & Config Rewriting**: Patches table entries, emulators, and media directories inside `PUPDatabase.db` using Windows built-in `winsqlite3.dll`, alongside updating `VPinballX.ini`, `PinUpPlayer.ini`, `ScreenRes.txt`, `DmdDevice.ini`, and registry branches.
- **COM Component Orchestration**: Safely registers `PinMAME.dll`, `B2S.Server.dll`, and `FlexDMD.dll` in verified operational sequence with 32-bit and 64-bit validation.
- **Multi-Screen Calibration Engine**: Identifies physical monitor roles (Playfield, Backglass, DMD/Topper) with DPI awareness, previews coordinate diffs before saving, keeps existing valid calibrations, and maintains automatic rollback snapshots.

<p align="center">
  <img src="docs/images/frieds-rgk-pinball.webp" alt="Virtual Pinball Suite Architecture" width="760" style="border-radius: 10px; box-shadow: 0 4px 20px rgba(0,0,0,0.3); margin-top: 12px;" />
</p>

### 2. 🎯 Wiimote Lightgun Suite (`lightgun\`)
- **Turnkey RetroBat Integration**: Transforms RetroBat into an authentic arcade shooting cabinet using Nintendo Wiimotes and the Mayflash DolphinBar.
- **Hardware Mode 4 Enforced**: Guarantees ultra-low latency direct IR tracking and pairing without Windows Bluetooth PIN prompts.
- **Virtual Xbox 360 Gamepads**: Leverages signed **ViGEmBus** drivers to present lightguns as standard XInput controllers, avoiding chaotic Windows raw-mouse conflicts.
- **Intelligent Interference Shield**: Neutralizes Steam Desktop Configuration captures and disables colliding background mouse guards.
- **Automated Profile Switching**: Background watchers automatically switch Gunmote input mappings upon launching games (e.g. MAME, DuckStation, TeknoParrot, Naomi) and return to a stable D-Pad menu profile on exit.

<p align="center">
  <img src="docs/images/frieds-rgk-wiimote.webp" alt="Wiimote Lightgun Suite Architecture" width="760" style="border-radius: 10px; box-shadow: 0 4px 20px rgba(0,0,0,0.3); margin-top: 12px;" />
</p>

### 3. ⚙️ Core Platform & Verification Engine (`core\`)
- **Zero-Dependency Native Architecture**: Runs out of the box on standard Windows 10 and 11 using built-in Windows PowerShell 5.1 and native `winsqlite3.dll`—no external package managers or compilers required.
- **Test → Invoke → Verify Lifecycle**: No step completes based on assumptions. Every action is tested first, invoked, and verified via live measurement.
- **Total Dry-Run Capability**: Full support for `-WhatIf` across all scripts. Preview planned file transfers, registry tweaks, and coordinate diffs safely.
- **Hardened Security & Privacy**: Enforces strict NTFS permissions, verifies Authenticode digital signatures on official Microsoft/Nefarius downloads, and guarantees 0% personal data leakage.

<p align="center">
  <img src="docs/images/frieds-rgk-core.webp" alt="Core Platform Architecture" width="760" style="border-radius: 10px; box-shadow: 0 4px 20px rgba(0,0,0,0.3); margin-top: 12px;" />
</p>

---

## 🚦 Feature Status

What "supported" means: **Automated** = the kit tests, changes and verifies it; **Guided check** = the kit audits and reports, you apply the change; **User-supplied** = you bring the (closed-source) program, the kit configures around it.

| Area | Status | What the kit does |
| :--- | :--- | :--- |
| **Core** (backup, state, logging, downloads, i18n) | ✅ Stable | Shared engine for all steps |
| **Pinball** relocation, COM registration, screens | ✅ Automated | Steps 1–9, wizard `Start-Pinball.cmd` |
| **Lightgun base** (DolphinBar, ViGEmBus, Gunmote, RetroBat) | ✅ Automated | Steps 1–9, wizard `Start-Lightgun.cmd` |
| **MAME** | ✅ Automated | RetroBat settings (`use_guns=0`, XInput pads), step 7 |
| **TeknoParrot** | ✅ Automated | Profile paths, XInput gun bindings, game lists, steps 10–11 |
| **Demul + DemulShooter** (Naomi, Atomiswave) | ⚠️ Automated · Demul user-supplied | Checks, DemulShooter config, RetroBat settings, step 12 |
| **Model 2** | ⚠️ Automated · emulator user-supplied | Checks and RetroBat settings, step 13 |
| **Supermodel** (Model 3) | ✅ Automated | Crosshairs, XInput gun bindings, step 13 |
| **DuckStation / PCSX2** | 🔎 Guided check | Audits settings and explains the mapping, step 14 |
| **Flycast** | ⛔ Not covered | — |
| **Doctor, backups, support bundle** | ✅ Read-only / guarded | `Start-Kit.cmd -Doctor`, `-Backups`, `-SupportBundle` |
| **Rumble / force feedback** | 🚧 Planned | See [ROADMAP](ROADMAP.md) |

---

## 🎛️ Hardware & Requirements Matrix

| Component | Minimum Requirement | Recommended Cabinet Spec |
| :--- | :--- | :--- |
| **Operating System** | Windows 10 64-bit (21H2+) | Windows 11 64-bit |
| **PowerShell** | Windows PowerShell 5.1 (Built-in) | PowerShell 5.1 or PowerShell 7+ |
| **Pinball Displays** | 2 Screens (Playfield + Backglass) | 3 Screens (4K Playfield 120Hz + 1080p Backglass + DMD) |
| **Display Scaling** | 100% DPI Scaling (Required) | 100% DPI Scaling across all screens |
| **Lightgun Sensor** | Mayflash DolphinBar (Firmware v09+) | Mayflash DolphinBar placed top/bottom of screen |
| **Lightgun Controllers** | 1x Original Nintendo Wiimote | 2x Nintendo Wiimotes with MotionPlus & Gun Shells |
| **Free Storage** | Build Size + 10% Headroom Buffer | Fast NVMe SSD (`D:\Pinball` or `C:\RetroBat`) |

---

## ⚡ Quickstart Guide

### 1. Launching the Kit
Clone or download the repository to your gaming PC and open the interactive menu:
```cmd
:: Double-click or run from Command Prompt / PowerShell:
Start-Kit.cmd
```
*Or launch specialized wizards directly:*
- **Virtual Pinball Setup**: `Start-Pinball.cmd`
- **Wiimote Lightgun Setup**: `Start-Lightgun.cmd`

### 2. Performing a Virtual Pinball Move (Example)
```powershell
# Preview changes safely with dry-run (-WhatIf)
powershell -ExecutionPolicy Bypass -File pinball\steps\05-Relocate.ps1 -Source "E:\Old Build" -Target "D:\Pinball" -WhatIf

# Execute complete relocation
powershell -ExecutionPolicy Bypass -File pinball\steps\01-Detect.ps1 -Source "E:\Old Build"
powershell -ExecutionPolicy Bypass -File pinball\steps\02-Target.ps1 -Target "D:\Pinball"
powershell -ExecutionPolicy Bypass -File pinball\steps\04-Copy.ps1
powershell -ExecutionPolicy Bypass -File pinball\steps\05-Relocate.ps1 -Mode Move
powershell -ExecutionPolicy Bypass -File pinball\steps\06-Register.ps1
powershell -ExecutionPolicy Bypass -File pinball\steps\08-Screens.ps1 -Mode Keep
powershell -ExecutionPolicy Bypass -File pinball\steps\09-Finish.ps1
```

### 3. Setting Up Wiimote Lightguns (Example)
The wizard (`Start-Lightgun.cmd`) runs these steps in order. From the command line, every step also accepts `-WhatIf` for a dry run.

```powershell
# PHASE 1 — base lightgun setup (RetroBat + Wiimote)
powershell -ExecutionPolicy Bypass -File lightgun\steps\01-Detect.ps1 -RetroBatRoot "C:\RetroBat"
powershell -ExecutionPolicy Bypass -File lightgun\steps\02-Hardware.ps1
powershell -ExecutionPolicy Bypass -File lightgun\steps\03-ViGEmBus.ps1 -AllowInstall
powershell -ExecutionPolicy Bypass -File lightgun\steps\04-Gunmote.ps1
powershell -ExecutionPolicy Bypass -File lightgun\steps\05-Interference.ps1 -DisableVMultiGuard
powershell -ExecutionPolicy Bypass -File lightgun\steps\06-GunmoteLayouts.ps1 -Mode Keep
powershell -ExecutionPolicy Bypass -File lightgun\steps\07-RetroBatSettings.ps1
powershell -ExecutionPolicy Bypass -File lightgun\steps\08-ProfileAutomation.ps1
powershell -ExecutionPolicy Bypass -File lightgun\steps\09-Verify.ps1 -XInputTimeoutSeconds 15

# PHASE 2 — arcade emulators (optional, only what you use)
powershell -ExecutionPolicy Bypass -File lightgun\steps\10-TeknoParrot.ps1
powershell -ExecutionPolicy Bypass -File lightgun\steps\11-GameLists.ps1
powershell -ExecutionPolicy Bypass -File lightgun\steps\12-Demul.ps1
powershell -ExecutionPolicy Bypass -File lightgun\steps\13-Model2Supermodel.ps1

# PHASE 3 — console emulators (guided check)
powershell -ExecutionPolicy Bypass -File lightgun\steps\14-DuckStationPcsx2.ps1
```

> [!TIP]
> Step 9 is the end of the **base** setup, not of the kit: steps 10–14 add the arcade and console emulators. Emulators you do not use are simply reported as missing.

### 4. Doctor, Backups & Support Bundle
```cmd
:: Read-only health check of system, pinball and lightgun (OK / INFO / WARN / ERROR, exit code 1 on errors)
Start-Kit.cmd -Doctor

:: List all backups the kit made (zip backups and <file>.bak_* copies), newest first
Start-Kit.cmd -Backups

:: Anonymized support bundle for an issue (doctor report, environment, step states, newest logs)
Start-Kit.cmd -SupportBundle
```
Restoring, checking, exporting and deleting single backups: `core\Start-KitTools.ps1` (`-CheckBackup`, `-RestoreBackup` with `-WhatIf`, `-ExportBackup`, `-RemoveBackup`). Restoring a file copy first saves the current file, so every restore can be undone.

---

## 🛡️ Safety, Privacy & Integrity Principles

We adhere to a non-negotiable software safety charter:
1. **Bring Your Own Builds (BYO)**: The kit contains **zero** ROMs, BIOS dumps, commercial tables, or copyrighted artwork. You bring your own legal games; the kit only provides the glue.
2. **Official Verified Sources Only**: Drivers and tools are downloaded exclusively from official vendor endpoints (Microsoft, Nefarius). Every downloaded binary is verified against Authenticode certificates and SHA-256 hashes before execution.
3. **Never Destructive**: The kit **never** deletes your tables, ROMs, or personal files. Backups are generated automatically before configuration changes.
4. **Dry-Run by Default**: Review every file copy, registry entry, and screen coordinate modification using `-WhatIf` before committing changes.
5. **Local Only**: No telemetry, no analytics, no accounts, no cloud, no tracking. The only network code is the verified download module (`core\modules\Download.ps1`); CI fails if network calls appear anywhere else.
6. **Zero Data Leaking**: Strict CI scans (`tools\Test-Depersonalized.ps1`) guarantee no personal hostnames, private IP addresses, or system paths are committed to the repository.

---

## 📖 Complete Documentation Index

| Guide | Description | Language Links |
| :--- | :--- | :--- |
| **Virtual Pinball Manual** | Step-by-step Baller Installer relocation, COM registration, and multi-screen setup. | [English](docs/pinball-guide.md) • [Deutsch](docs/pinball-guide.de.md) |
| **Wiimote Lightgun Manual** | DolphinBar Mode 4 configuration, ViGEmBus, Gunmote layouts, and profile automation. | [English](docs/lightgun-guide.md) • [Deutsch](docs/lightgun-guide.de.md) |
| **Troubleshooting Guide** | Solutions for COM errors, monitor offsets, Steam hijacking, and IR drift. | [English](docs/troubleshooting.md) • [Deutsch](docs/troubleshooting.de.md) |
| **Frequently Asked Questions** | Answers regarding architecture, hardware compatibility, and safety. | [English](docs/faq.md) • [Deutsch](docs/faq.de.md) |
| **Security Policy** | Vulnerability reporting, task privilege model, and hardening disclosures. | [English](SECURITY.md) |
| **Contribution Guidelines** | Coding standards, Pester tests, and PR submission rules. | [English](CONTRIBUTING.md) |
| **Architecture** | Layers, the step contract, Definition of Done, quality gates. | [English](ARCHITECTURE.md) |
| **Changelog & Roadmap** | What changed per version and what comes next. | [Changelog](CHANGELOG.md) • [Roadmap](ROADMAP.md) |

---

## 🤝 Community & Credits

Fried's Retrogaming Kit stands on the shoulders of brilliant communities and open-source pioneers:
- **Communities**: [Light Gun Lunatics](https://lightgun.retrolunatics.com/) and [Pinball Lunatics](https://pinball.retrolunatics.com/) for unmatched guides, hardware testing, and passionate support.
- **Lightgun Pioneers**: **Gunmote** (gunmotelabs), **Touchmote** (simphax), **Lichtknarre** (Geekonarium), **DemulShooter** (argonlefou), and **ViGEmBus** (Nefarius).
- **Frontend & Emulation**: **RetroBat Team**, **TeknoParrot** (Teknogods), **MAMEdev**, **DuckStation** (Stenzek), **PCSX2 Team**, **Flycast**, and **Libretro**.
- **Virtual Pinball Legends**: **PinUP Popper & Player** (nailbuster), **Visual Pinball Team**, **PinMAME Team**, **B2S Backglass Server** (Herweh), **DMD Extensions** (freezy), **FlexDMD** (vbousquet), and **Future Pinball / BAM** (Ravarcade).
- **Inspiration**: The German virtual pinball community handbook *"Projekt Virtual Pinball"* by **Moster** (flippermarkt.de / vpinball.de).

*For a complete, unabridged list of contributors, projects, and verified licenses, please see [CREDITS.md](CREDITS.md).*

---

## 📄 License

This project is licensed under the terms of the **MIT License**.  
See the [LICENSE](LICENSE) file for complete details.  
Copyright (c) 2026 Friedrich Börner.
