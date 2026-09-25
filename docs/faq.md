# Frequently Asked Questions (FAQ)

Everything you need to know about **Fried's Retrogaming Kit**.

---

## 🌟 General Questions

### What is Fried's Retrogaming Kit?
Fried's Retrogaming Kit is an open-source, automated configuration toolkit designed for Windows retro gaming cabinets. It provides two major suites built on a unified PowerShell 5.1 core:
1. **Virtual Pinball Suite**: Seamlessly relocates or rebuilds complete PinUP Popper (Baller Installer) setups across drives or on clean Windows installations.
2. **Wiimote Lightgun Suite**: Automates Mayflash DolphinBar, ViGEmBus, Gunmote, and RetroBat into a ready-to-play arcade shooting cabinet.

### Why is it built in PowerShell 5.1 instead of a compiled app?
PowerShell 5.1 is preinstalled on every Windows 10 and Windows 11 installation. By utilizing the Windows built-in `winsqlite3.dll` for SQLite operations, the kit requires zero external runtimes, zero third-party package managers, and no compilation. Everything is transparent, easily inspectable, and auditable directly in plain text.

### Does the kit include ROMs, BIOS files, tables, or game media?
**No. Absolutely none.** The kit is strictly an orchestration and automation tool. You supply your own legal game builds, ROMs, BIOS files, and pinball tables. The kit only downloads freely licensed drivers or runtimes from official upstream sources (such as Microsoft and signed GitHub releases).

### Can I run the kit without an active internet connection?
Yes! If your build already includes necessary runtimes (e.g. inside `2-Programs\All In One Runtimes`) and you have downloaded installers like Gunmote and ViGEmBus locally, the kit runs completely offline. The kit never relies on external cloud services.

### Can I preview changes before anything is written to disk?
Yes. Every single step supports PowerShell's `-WhatIf` parameter. Running a step with `-WhatIf` will display detailed reports, planned registry modifications, file copies, and screen coordinate diffs without changing a single byte on your system.

---

## 🎱 Virtual Pinball Questions

### Can I relocate an existing Baller Installer without reinstalling Windows?
Yes! This is the primary purpose of **Mode: Move on this PC**. The kit moves your entire pinball build to a new directory (e.g. `D:\Pinball`), rewrites all internal paths in `PUPDatabase.db`, updates all INI and CFG files, updates the Windows Registry, and re-registers the COM DLLs. Your tables, high scores, and customizations remain intact.

### How does the screen coordinate undo mechanism work?
In Step 8 (`08-Screens.ps1`), before any screen coordinates are written, the kit saves the original settings to a timestamped backup directory (`backups\`). If a layout does not appear correctly on your monitors, you can revert instantly to your previous configuration without manual file editing.

### Does the kit support cabinets with only 2 screens (Playfield + Backglass)?
Yes. While 3-screen setups (Playfield, Backglass, DMD/Topper) are standard, the screen configuration engine cleanly handles 2-screen setups. Virtual DMDs can be integrated into the backglass display.

---

## 🎯 Lightgun & RetroBat Questions

### Why does the kit use Mayflash DolphinBar in Mode 4?
DolphinBar Mode 4 exposes the hardware in native Wiimote controller mode (`USB\VID_057E&PID_0306`). This mode bypasses the standard Windows Bluetooth stack (avoiding pairing PIN prompts) and provides consistent, low-latency communication directly with Gunmote. Modes 1 and 2 (keyboard/mouse emulation) suffer from acceleration issues and lack dual-gun separation.

### Why Gunmote instead of Lichtknarre or Touchmote?
Gunmote (`gunmotelabs`) is an actively developed, modern lightgun mapper that translates Wiimote IR points and button clicks into virtual Xbox 360 controller inputs via ViGEmBus. This allows seamless compatibility with emulators that prefer XInput controllers while preventing raw mouse conflicts.

### Why does Profile Automation require Scheduled Tasks with highest privileges?
To provide an authentic cabinet experience, profile switching must happen automatically when you launch a game from RetroBat without showing interactive Windows UAC prompts. Because some target games or emulators run with elevated rights or capture exclusive fullscreen focus, the background profile switcher (`profile.ps1`) requires elevated privileges to manage virtual controller assignments. Full details and instructions to inspect or remove these tasks are documented in [SECURITY.md](../SECURITY.md).

### Can I use Sinden, AimTrak, or GUN4IR lightguns with this kit?
The dedicated lightgun automation in this release is tailored specifically for **Wiimote + Mayflash DolphinBar** hardware. However, our sister community [Light Gun Lunatics](https://lightgun.retrolunatics.com/) maintains excellent guides for Sinden, AimTrak, and GUN4IR setups.

---

## 🔒 Privacy & Safety Questions

### Does Fried's Retrogaming Kit collect telemetry or phone home?
**Never.** There are zero analytical trackers, zero telemetry pings, and zero remote logging endpoints.

### How do I completely remove the kit and its automation tasks?
To cleanly remove all scheduled tasks and background hooks installed by the kit:
```powershell
Get-ScheduledTask -TaskName "RetroCabinetKit Gunmote*" | Unregister-ScheduledTask -Confirm:$false
Remove-Item -Recurse -Force "C:\ProgramData\RetroCabinetKit\lightgun"
```
No other background services remain on your system.
