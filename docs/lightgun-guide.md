# Wiimote Lightgun & RetroBat Setup Guide

Comprehensive technical manual for building a low-latency, multi-emulator Wiimote lightgun arcade setup using **Fried's Retrogaming Kit**.

---

## 📌 Architectural Overview

Using Nintendo Wiimotes as PC lightguns provides an affordable, arcade-authentic shooting experience. However, traditional setups suffer from multiple friction points: conflicting mouse inputs, erratic cursor drifting in frontend menus, Steam Desktop configuration hijacking virtual controllers, and inconsistent trigger bindings across different emulators.

Fried's Retrogaming Kit transforms RetroBat into a turnkey Wiimote lightgun arcade station by orchestrating four core components:
1. **Mayflash DolphinBar (Hardware Mode 4)**: Handles low-latency infrared tracking and controller synchronization.
2. **Nefarius ViGEmBus**: Emulates virtual Xbox 360 gamepads.
3. **Gunmote (`gunmotelabs`)**: Maps Wiimote IR coordinates and button triggers to virtual Xbox 360 controller axes and buttons.
4. **RetroCabinetKit Profile Automation**: Seamlessly swaps input profiles on a per-system basis when games launch, keeping frontend navigation smooth and lightgun aiming pixel-precise.

```
       [ Mayflash DolphinBar (Mode 4) ]
                     │ (USB / IR)
                     ▼
             [ Nintendo Wiimote ]
                     │
                     ▼
         [ Gunmote (gunmotelabs) ]
                     │
        ┌────────────┴────────────┐
        ▼                         ▼
 [ ViGEmBus (Virtual X360) ] [ Windows Cursor ]
        │                         │
        └────────────┬────────────┘
                     ▼
      [ RetroBat & Target Emulators ]
 (MAME64, DuckStation, Demul, TeknoParrot)
```

---

## 🚀 Step-by-Step Installation Flow

All steps adhere to the **Test → Invoke → Verify** lifecycle. Each step supports `-WhatIf` for dry-run validation.

### Step 1: Detect RetroBat (`01-Detect.ps1`)
- **Action**: Detects and inspects the RetroBat installation directory (e.g. `C:\RetroBat`).
- **Verification**:
  - Confirms the presence of `retrobat.exe` and `retrobat.ini`.
  - Verifies accessibility of `system\es_settings.cfg` and emulator folders.
  - Records RetroBat version and configuration paths in kit state.

### Step 2: Hardware Verification (`02-Hardware.ps1`)
- **Action**: Verifies connected USB lightgun hardware without making system changes.
- **Checks**:
  - **DolphinBar Mode 4**: Probes Windows PnP devices for hardware ID `USB\VID_057E&PID_0306` (DolphinBar in Wiimote controller mode).
  - Flags improper modes (Mode 1/2 keyboard/mouse or gamepad mode) with clear corrective instructions.
  - Verifies the Windows Bluetooth support service (`bthserv`).
  - Audits monitor refresh rates (60 Hz recommended; displays running below 50 Hz trigger performance warnings).

### Step 3: ViGEmBus Virtual Controller Driver (`03-ViGEmBus.ps1`)
- **Action**: Verifies or installs the Nefarius Virtual Gamepad Emulation Bus (`ViGEmBus`).
- **Details**:
  - Checks if the ViGEmBus driver service is installed and operational.
  - If missing: downloads the official signed installer release from `nefarius/ViGEmBus` into the protected ProgramData directory.
  - Verifies the Authenticode digital signature and SHA-256 hash before executing a silent installation (`/qn`).
  - *Requires Administrator privileges.*

### Step 4: Gunmote Setup & Privileged Task (`04-Gunmote.ps1`)
- **Action**: Integrates Gunmote (`gunmotelabs/Gunmote`) as the input translation engine.
- **Workflow**:
  - Guides the user to download and install the official Gunmote release into `C:\Program Files\Gunmote`.
  - Registers a dedicated Windows Scheduled Task `RetroCabinetKit Gunmote` configured to start at user logon with highest privileges (`RunLevel = Highest`).
  - This allows Gunmote to inject controller and mouse events into elevated or fullscreen games without triggering UAC interruptions.

### Step 5: Interference Mitigation (`05-Interference.ps1`)
- **Action**: Eliminates background services that hijack or disrupt lightgun inputs.
- **Remediations**:
  - **Steam Desktop Configuration**: Adds Mayflash DolphinBar hardware IDs to `controller_blacklist` in Steam's `config\config.vdf`. This prevents Steam Input from capturing the DolphinBar as a desktop mouse.
  - **Steam Input Xbox Support**: Inspects `localconfig.vdf` and instructs the user to disable Xbox controller support in Steam settings.
  - **VMulti Driver Conflicts**: Detects existing `GunmoteVMultiGuard` tasks and safely disables them upon user confirmation.

### Step 6: Deploy Gunmote Layouts (`06-GunmoteLayouts.ps1`)
- **Action**: Deploys optimized input profiles to Gunmote's `Keymaps` directory and updates `Keymaps.json`.
- **Profiles Deployed**:
  - `Default (Menu Pad)`: Virtual Xbox 360 D-Pad without mouse cursor, enabling stable D-Pad navigation in RetroBat without wild cursor drifting.
  - `Pad 4:3`: Tailored for MAME, PSX, Model 2, and Model 3 with analog trigger mapping.
  - `TeknoParrot`: Configured with right analog stick support for modern arcade titles.
  - `Naomi / Atomiswave`: Custom bindings for Demul and Flycast.
  - `Mouse`: Direct mouse emulation for RetroArch lightgun cores and PCSX2.
  - Off-screen reload triggers are explicitly enabled; the Wiimote Home button is disabled to avoid accidental pauses.

### Step 7: RetroBat Configuration Harmonization (`07-RetroBatSettings.ps1`)
- **Action**: Updates RetroBat configuration files to eliminate input conflicts.
- **Settings Patched**:
  - `es_settings.cfg`: Sets `use_guns=0` and `disableautocontrollers=1` for MAME, Naomi, Atomiswave, PSX, Model 2, Model 3, and TeknoParrot. This prevents RetroBat from activating its internal raw mouse gun drivers which conflict with Gunmote.
  - Sets default lightgun emulators: MAME to `mame64` (with `ctrlr` profile set to `custom1`), Naomi to `demul` (with `use_demulshooter=0`), and PSX to `duckstation`.
  - `es_input.cfg`: Configures the virtual Xbox 360 controller mapping so that pulling the Wiimote trigger (Button 0 / A) launches selected games directly from RetroBat.

### Step 8: Profile Automation (`08-ProfileAutomation.ps1`)
- **Action**: Installs background watchers and RetroBat game launch hooks.
- **Implementation**:
  - Copies `profile.ps1` into protected `%ProgramData%\RetroCabinetKit\lightgun\`.
  - Registers scheduled tasks `RetroCabinetKit Gunmote Profile <Menu|TP|Pad43|Naomi|Mouse>` with highest rights for the active user account.
  - Deploys batch dispatchers in RetroBat:
    - `scripts\game-start\rck-gunmote-profile.bat`: Reads the launching system name and switches Gunmote to the appropriate layout.
    - `scripts\game-end\rck-gunmote-profile.bat`: Automatically restores the `Menu` pad profile when a game exits.
- *Refer to [SECURITY.md](../SECURITY.md) for full disclosure of this privilege model and instructions to disable it.*

### Step 9: Measured Verification & Calibration (`09-Verify.ps1`)
- **Action**: Verifies all subsystems through live input measurement rather than speculation.
- **Sub-Tests**:
  1. `lightgun-9-xinput`: Probes connected virtual Xbox pads via `XInputGetState`. Prompts the user to pull the trigger on each connected Wiimote within 15 seconds to confirm end-to-end signal delivery.
  2. `lightgun-9-profile`: Validates from `logs\profile.log` that the profile automation responded to game launches.
  3. `lightgun-9-launcher`: Reads RetroBat's `emulatorLauncher.log` to confirm that `use_guns=0` was respected and no conflicting drivers were spawned.


### Phase 2 — Arcade Emulators (optional)

Steps 10–13 only touch emulators you actually have; missing ones are reported, not installed. Every step previews its plan first and writes only while RetroBat and the affected emulator are closed, with a backup before each change.

### Step 10: TeknoParrot Profiles (`10-TeknoParrot.ps1`)
- `lightgun-10-tp-paths`: `GamePath` entries in `UserProfiles\*.xml` that still point into another installation (a bought build keeps its creator's folders) are redirected to the same file below this RetroBat — only if that file exists here; missing games are reported.
- `lightgun-10-tp-bind`: Gun games are bound to XInput (Wiimote 1/2 = XInput index 0/1, B = shot, A = reload, right stick aims). Touch screen games and games passed with `-Exclude` stay unchanged.
- `lightgun-10-tp-settings`: `es_settings.cfg`: `teknoparrot.use_guns=0`, `disableautocontrollers=1` per bound game, leftovers of the build creator removed.

### Step 11: Game Lists (`11-GameLists.ps1`)
- `lightgun-11-tp-duplicates`: Folders in `roms\teknoparrot` that duplicate an active game are **moved** to `<RetroBat>\_duplicates\teknoparrot\` after you confirmed the plan. Nothing is deleted.
- `lightgun-11-tp-gamelist`: `gamelist.xml` gets an entry for every registered game; folders without a profile are hidden until they have one.
- Reported only: missing media, entries without folder, and hard-wired `<emulator>`/`<core>` entries.

### Step 12: Demul & DemulShooter (`12-Demul.ps1`)
- `lightgun-12-demul`: Checks your **user-supplied** Demul 0.7a (`demul.exe`, `nvram`, BIOS `naomi.zip` / `awbios.zip`). Closed source — the kit offers no download.
- `lightgun-12-demulshooter`: Checks DemulShooter and configures its raw input for the Gunmote Xbox pads. Guided download from the official releases (argonlefou/DemulShooter); `-DemulShooterPath` for a custom location.
- `lightgun-12-demul-settings`: `naomi.emulator=demul`, `atomiswave.emulator=demul`, `use_guns=0`, `disableautocontrollers=1`.
- `lightgun-12-demul-gamelist`: Reports hard-wired Flycast/libretro emulators on gun games in the Naomi/Atomiswave game lists; `-RemoveHardwired` removes them.

### Step 13: Model 2 & Supermodel (`13-Model2Supermodel.ps1`)
- `lightgun-13-model2`: Checks your **user-supplied** Model 2 emulator (`EMULATOR.EXE`, `emulator_multicpu.exe`, `Emulator.ini`). Closed source — no download. DemulShooter hooks it via `-target=model2m`.
- `lightgun-13-supermodel`: Checks and configures Supermodel (Model 3): crosshairs on, XInput gun bindings. Official releases from trzy/Supermodel.
- `lightgun-13-model-settings`: `model2.use_guns=0`, `model3.use_guns=0`, `disableautocontrollers=1` for both.

### Phase 3 — Console Emulators (guided check)

### Step 14: DuckStation & PCSX2 (`14-DuckStationPcsx2.ps1`)
- `lightgun-14-duckstation-pcsx2`: **Audits and reports, no automatic binding.** Reads `settings.ini`, `gamesettings\<SERIAL>.ini` and `PCSX2.ini`, explains the *Automatic Mapping* to `XInput-0` and flags Konami games that need the Justifier instead of the GunCon (e.g. Die Hard Trilogy, Crypt Killer). Flycast is not covered.

---

## 🎮 Emulator Status

The core lightgun infrastructure (DolphinBar Mode 4, ViGEmBus, Gunmote, and RetroBat integration) is fully operational. The emulator steps 10–14 build on it:

| Emulator / Platform | Integration Status | Step | Input Pipeline |
| :--- | :--- | :--- | :--- |
| **MAME (Arcade Classics)** | :white_check_mark: Automated | 7 | MAME64 + XInput virtual pad (`use_guns=0`) |
| **TeknoParrot (Modern Arcade)** | :white_check_mark: Automated | 10–11 | XInput gun bindings, right stick aims, game lists |
| **Demul & DemulShooter** | :warning: Automated, Demul user-supplied | 12 | DemulShooter raw input on the Gunmote Xbox pads |
| **Sega Model 2** | :warning: Automated, emulator user-supplied | 13 | DemulShooter (`-target=model2m`) |
| **Supermodel (Model 3)** | :white_check_mark: Automated | 13 | XInput gun bindings, crosshairs |
| **DuckStation (PS1) / PCSX2 (PS2)** | :mag: Guided check | 14 | Automatic Mapping to `XInput-0`, GunCon / Justifier hints |
| **Flycast** | :no_entry: Not covered | — | — |
| **Rumble & Force-Feedback** | :construction: Planned | — | OutputHooker / MAMEHooker, see [ROADMAP](../ROADMAP.md) |

---

## 🛠️ CLI Quickstart Example

```powershell
# Navigate to kit directory
cd "D:\Games\RetroCabinetKit"

# Configure RetroBat for Wiimote Lightgun setup
powershell -ExecutionPolicy Bypass -File lightgun\steps\01-Detect.ps1 -RetroBatRoot "C:\RetroBat"
powershell -ExecutionPolicy Bypass -File lightgun\steps\02-Hardware.ps1
powershell -ExecutionPolicy Bypass -File lightgun\steps\03-ViGEmBus.ps1 -AllowInstall
powershell -ExecutionPolicy Bypass -File lightgun\steps\04-Gunmote.ps1
powershell -ExecutionPolicy Bypass -File lightgun\steps\05-Interference.ps1 -DisableVMultiGuard
powershell -ExecutionPolicy Bypass -File lightgun\steps\06-GunmoteLayouts.ps1 -Mode Keep
powershell -ExecutionPolicy Bypass -File lightgun\steps\07-RetroBatSettings.ps1
powershell -ExecutionPolicy Bypass -File lightgun\steps\08-ProfileAutomation.ps1
powershell -ExecutionPolicy Bypass -File lightgun\steps\09-Verify.ps1 -XInputTimeoutSeconds 15

# Arcade emulators (optional)
powershell -ExecutionPolicy Bypass -File lightgun\steps\10-TeknoParrot.ps1
powershell -ExecutionPolicy Bypass -File lightgun\steps\11-GameLists.ps1
powershell -ExecutionPolicy Bypass -File lightgun\steps\12-Demul.ps1
powershell -ExecutionPolicy Bypass -File lightgun\steps\13-Model2Supermodel.ps1

# Console emulators (guided check)
powershell -ExecutionPolicy Bypass -File lightgun\steps\14-DuckStationPcsx2.ps1
```
