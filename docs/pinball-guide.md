# Virtual Pinball Setup Guide

Comprehensive technical manual for relocating and rebuilding virtual pinball cabinets using **Fried's Retrogaming Kit**.

---

## 📌 Architectural Overview

Setting up a digital pinball cabinet has historically been notoriously fragile. Components such as Visual Pinball X, VPinMAME, B2S Backglass Server, FlexDMD, Freezy's DMD Extensions, and Future Pinball/BAM rely heavily on hardcoded drive paths across SQLite databases, text initialization files, and Windows Registry keys.

Fried's Retrogaming Kit eliminates this complexity by providing an automated, non-destructive relocation and restoration engine based on the **Baller Installer** directory structure:

```
<PinballRoot>\
├── 2-Programs\            # Redistributables, runtimes, utilities
├── DOFLinx\               # DirectOutput framework bridge for Future Pinball
├── Future Pinball\        # Future Pinball executable and BAM (Better Arcade Mode)
└── vPinball\
    ├── B2SBackglassServer\  # DirectB2S backglass server
    ├── PinUPSystem\         # PinUP Popper frontend, player, and PUPDatabase.db
    ├── VisualPinball\       # Visual Pinball X (VPX) tables, scripts, VPinballX.ini
    └── VPinMAME\            # VPinMAME ROM emulation, DmdDevice.ini, nvram, cfg
```

---

## 🔄 Two Setup Modes

The pinball installer operates in two distinct operational modes:

| Mode | Use Case | Path Handling & Registry Behavior |
| :--- | :--- | :--- |
| **Move on this PC** | Moving an existing build to a new fast SSD or directory (e.g. from `E:\Old Build` to `D:\Pinball`). | Reads existing machine configuration and Windows Registry keys (`HKCU\Software`), updating all paths in place without losing custom table settings. |
| **Rebuild on fresh Windows** | Reinstalling Windows 10/11 or building a new cabinet hardware rig. | Imports settings from a previous kit backup ZIP or an existing `NTUSER.DAT` registry hive, updating all paths during import. If no backup is provided, sensible defaults are applied. |

---

## 🚀 Step-by-Step Installation Flow

Every step follows the **Test → Invoke → Verify** design pattern. A step only succeeds when live system verification passes. All steps support `-WhatIf` for non-destructive dry runs.

### Step 1: Detect Build (`01-Detect.ps1`)
- **Action**: Inspects the user-provided source directory.
- **Verification**:
  - Connects to `vPinball\PinUPSystem\PUPDatabase.db` using Windows built-in `winsqlite3.dll` without external dependencies.
  - Queries `GlobalSettings.GlobalMediaDir` to deduce the original installation root path (`OldRoot`).
  - Detects companion folders (such as `DOFLinx` and BAM).
  - Measures total directory byte size and file count.

### Step 2: Choose Target Directory (`02-Target.ps1`)
- **Action**: Validates the designated target path (e.g. `D:\Pinball`).
- **Safety Checks**:
  - Ensures the path is on a local NTFS/ReFS drive (network shares are rejected for performance and stability).
  - Verifies target disk free space exceeds the build size plus a 10% safety buffer.
  - Prevents accidental installation into drive roots (e.g. `C:\`) or Windows system folders.

### Step 3: Prerequisites & Runtimes (`03-Dependencies.ps1`)
- **Action**: Analyzes system dependencies required for VPX and PinMAME.
- **Components Managed**:
  - Visual C++ Redistributables: 2005, 2008, 2010, 2012, 2013, and 2015–2022 (x86 and x64).
  - Microsoft .NET Framework: 3.5 (activated via DISM) and 4.8.
  - DirectX 9.0c runtime (`d3dx9_43.dll`).
- **Integrity**: Prioritizes local installers found within `2-Programs\All In One Runtimes` or `Installer\directx9`. If official fallback downloads from Microsoft are required, the kit verifies Authenticode digital signatures before running.

### Step 4: Resumable File Copy (`04-Copy.ps1`)
- **Action**: Transfers build files from source to target using an optimized robocopy engine.
- **Features**:
  - Resumable: Can be interrupted and restarted without duplicating transferred data.
  - Excludes volatile runtime caches and temporary log directories.
  - Verifies post-copy integrity by matching source and destination file counts.

### Step 5: Relocate & Path Rewriting (`05-Relocate.ps1`)
- **Action**: Performs a deep, multi-tier path relocation from `OldRoot` to `NewRoot`.
- **Targets**:
  1. **SQLite Database (`PUPDatabase.db`)**: Updates table definitions, emulator launch parameters, media directory roots, and PuP-pack paths.
  2. **Configuration Files**: Rewrites paths in `VPinballX.ini`, `PinUpPlayer.ini`, `ScreenRes.txt`, `DmdDevice.ini`, and `DOFLinx.ini`.
  3. **Windows Registry**: Modifies value data under `HKCU\Software\Freeware\Visual PinMame`, `HKCU\Software\Visual Pinball`, and `HKCU\Software\Future Pinball`.
  4. **Shortcuts**: Rewrites Windows `.lnk` shortcuts in Start Menu and Desktop folders.
  - **Idempotency**: Running relocation repeatedly produces zero unintended alterations.

### Step 6: COM Component Registration (`06-Register.ps1`)
- **Action**: Registers essential ActiveX / COM components with Windows `regsvr32` in validated operational order:
  1. `VPinMAME\PinMAME.dll` / `PinMAME64.dll` (`VPinMAME.Controller`)
  2. `B2SBackglassServer\B2S.Server.dll` (`B2S.Server`)
  3. `VPinMAME\FlexDMD.dll` (`FlexDMD.FlexDMD`)
  4. `PinUPSystem\PUPDMDControl.dll`
  5. `PinUPSystem\PuP DllSurrogate`
  6. `PinUPSystem\PinUpPlayer.dll`
- **Security Check**: Audits directory ACL permissions on `vPinball` to warn if unprivileged users have write access to registered COM binaries.
- **Verification**: Confirms Windows registry CLSIDs point directly into the new target directory.

### Step 7: Future Pinball & BAM Setup (`07-FpBamSetup.ps1`)
- **Action**: Configures Future Pinball and Better Arcade Mode (BAM) compatibility settings.
- **Tasks**:
  - Applies Windows compatibility flags (`Disable fullscreen optimizations`) to `FPLoader.exe` and `Future Pinball.exe`.
  - Executes `BAM settings - Cabinet - Reset and Install.bat` non-interactively.
  - Prompts for a one-time elevated launch of `FPLoader.exe` to finalize internal graphics configuration.

### Step 8: Multi-Screen Layout Engine (`08-Screens.ps1`)
- **Action**: Identifies connected physical monitors and aligns cabinet display roles.
- **Supported Roles**:
  - **Playfield** (Display 1 / Primary monitor)
  - **Backglass** (Display 2)
  - **DMD / FullDMD / Topper** (Display 3+)
- **Display Rules**:
  - DPI display scaling must be set to 100%.
  - No negative monitor coordinates (monitors must align to the right of or below the primary display).
- **Modes**:
  - `Keep` (default): Preserves verified existing coordinates, only adjusting values outside current desktop boundaries.
  - `Replace`: Applies freshly measured coordinates to all configuration files simultaneously.
- **Diff & Undo**: Generates an exact visual diff preview across `PinUpPlayer.ini`, `ScreenRes.txt`, `DmdDevice.ini`, and registry keys before saving. Automatic undo backups are retained.

### Step 9: Finish, Backup & Popper Autostart (`09-Finish.ps1`)
- **Action**: Generates a consolidated disaster recovery backup archive (`pinball-finish_<timestamp>.zip`) with a JSON manifest.
- **Optional Autostart**: Allows enabling PinUP Popper autostart via `RunWindowsStartup.bat`.
- **Final Note**: Recommends a system reboot so Windows COM cache and display handles refresh cleanly.

---

## 🛠️ CLI Quickstart Example

To run the pinball relocation unattended via PowerShell:

```powershell
# Navigate to kit directory
cd "D:\Games\RetroCabinetKit"

# Move build from E:\Old Build to D:\Pinball
powershell -ExecutionPolicy Bypass -File pinball\steps\01-Detect.ps1 -Source "E:\Old Build"
powershell -ExecutionPolicy Bypass -File pinball\steps\02-Target.ps1 -Target "D:\Pinball"
powershell -ExecutionPolicy Bypass -File pinball\steps\03-Dependencies.ps1 -AllowDownload -AllowDism
powershell -ExecutionPolicy Bypass -File pinball\steps\04-Copy.ps1
powershell -ExecutionPolicy Bypass -File pinball\steps\05-Relocate.ps1 -Mode Move
powershell -ExecutionPolicy Bypass -File pinball\steps\06-Register.ps1
powershell -ExecutionPolicy Bypass -File pinball\steps\07-FpBamSetup.ps1
powershell -ExecutionPolicy Bypass -File pinball\steps\08-Screens.ps1 -Mode Keep
powershell -ExecutionPolicy Bypass -File pinball\steps\09-Finish.ps1
```
