# Troubleshooting Guide

Comprehensive diagnosis, error codes, and practical remedies for **Fried's Retrogaming Kit**.

---

## ⚡ General & System Issues

### 1. PowerShell Script Execution Blocked (`PSSecurityException`)
- **Symptom**: `File cannot be loaded because running scripts is disabled on this system.`
- **Cause**: Windows client editions disable unverified script execution by default.
- **Remedy**:
  - Run scripts via the provided `.cmd` launchers (`Start-Kit.cmd`, `Start-Pinball.cmd`, `Start-Lightgun.cmd`), which include `-ExecutionPolicy Bypass` scoped strictly to that session.
  - Or run manually:
    ```powershell
    powershell -NoProfile -ExecutionPolicy Bypass -File pinball\steps\01-Detect.ps1
    ```

### 2. Administrator Rights & User Elevation Lock
- **Symptom**: Warning `Kit running elevated as different user` or registry steps blocked.
- **Cause**: Modifying `HKCU` (Current User) while elevated as a different local administrator account will write settings to the wrong user hive.
- **Remedy**: Start PowerShell from the desktop user who will actually play the games, then allow the kit to elevate via UAC while passing your user SID.

---

## 🎱 Pinball Installer Issues

### 1. COM Registration Fails (`regsvr32` Error 0x80004005 / 0x80070005)
- **Symptom**: `pinball-6-register` throws an error or reports `Failed` for `PinMAME.dll`, `B2S.Server.dll`, or `FlexDMD.dll`.
- **Causes**:
  - Lack of administrative privileges during registration.
  - Missing Visual C++ Runtimes (e.g. VC++ 2010 x86 required by 32-bit PinMAME).
  - Architecture mismatch (attempting to register 64-bit DLL with 32-bit regsvr32 or vice-versa).
- **Remedy**:
  1. Re-run Step 3 (`03-Dependencies.ps1`) with `-AllowDownload` to verify all VC++ runtimes are installed.
  2. Ensure you run Step 6 with elevated administrator rights.
  3. Verify file permissions: right-click `D:\Pinball\vPinball`, check Properties > Security to ensure your user has Full Control.

### 2. Black Backglass or Backglass Appears Behind Playfield
- **Symptom**: Tables launch, but the DirectB2S backglass is invisible or hidden beneath the VPX playfield window.
- **Causes**:
  - Playfield monitor is not set as Primary Monitor in Windows Display Settings.
  - `ScreenRes.txt` has incorrect offset coordinates or negative coordinates.
  - Windows display scaling is set to 125% or 150% instead of 100%.
- **Remedy**:
  1. In Windows Settings > System > Display: select the Playfield monitor and check **"Make this my main display"**.
  2. Set Scaling to **100%** on **all** connected displays.
  3. Re-run Step 8 (`08-Screens.ps1 -Mode Replace`) to recalculate `ScreenRes.txt` offsets.

### 3. VPinMAME ROM Not Found / Sound Missing
- **Symptom**: VPX table starts with `ROM not found` error message.
- **Cause**: `vpmpath` in Windows Registry still points to an old drive path.
- **Remedy**:
  - Re-run Step 5 (`05-Relocate.ps1 -Mode Move`) to update `HKCU\Software\Freeware\Visual PinMame\vpmpath` to point to the new `vPinball\VPinMAME` directory.
  - Open `D:\Pinball\vPinball\VPinMAME\Setup.exe`, click **Test**, select your ROM, and verify the path.

### 4. Future Pinball & BAM Crashes on Launch
- **Symptom**: Tables fail to load or Future Pinball crashes with white screen.
- **Cause**: Windows fullscreen optimizations interfering with BAM injection, or `FPLoader.exe` has not been initialized with Administrator rights.
- **Remedy**:
  1. Re-run Step 7 (`07-FpBamSetup.ps1`).
  2. Right-click `D:\Pinball\Future Pinball\FPLoader.exe` and select **Run as Administrator** once.
  3. Confirm the BAM Cabinet reset script ran cleanly.

---

## 🎯 Wiimote Lightgun & RetroBat Issues

### 1. DolphinBar Not Recognized (Wrong Mode / 4 LEDs Flashing)
- **Symptom**: Step 2 fails with `DolphinBar Mode 4 missing`.
- **Causes**:
  - DolphinBar is switched to Mode 1, Mode 2 (keyboard/mouse), or Mode 3 (gamepad).
  - Wiimote is not synced to the DolphinBar.
- **Remedy**:
  1. Press the top hardware button on the Mayflash DolphinBar until **LED 4** is lit.
  2. Press the **SYNC** button on the DolphinBar, then press buttons **1 and 2** simultaneously (or the red SYNC button inside battery compartment) on your Nintendo Wiimote.
  3. When synced, LED 1 or LED 2 on the Wiimote will stay solid blue.

### 2. Steam Desktop Configuration Hijacks the Lightgun
- **Symptom**: Pulling the trigger opens Steam Big Picture, moves the Windows desktop cursor erratically, or brings up on-screen keyboard.
- **Cause**: Steam Input captures virtual Xbox 360 controllers and maps them to desktop mouse/keyboard actions.
- **Remedy**:
  1. Exit Steam completely (check taskbar tray).
  2. Re-run Step 5 (`05-Interference.ps1`).
  3. Open Steam Settings > **Controller**:
     - Turn **OFF** "Enable Steam Input for Xbox controllers".
     - Set "Desktop Layout" to **Disabled**.

### 3. Cursor Jitter, Aim Drift, or Loss of IR Tracking
- **Symptom**: The lightgun crosshair jumps erratically or disappears when aiming near screen edges.
- **Causes**:
  - Sunlight, mirrors, glass cabinets, halogen lights, or candles reflecting into the Wiimote IR camera.
  - DolphinBar sensor bar placement does not match physical position.
  - Standing too close or too far from the screen.
- **Remedy**:
  1. Check DolphinBar position switch (Top vs Bottom of monitor). Set it to match physical placement.
  2. Optimal player distance is typically 1.5 to 2.5 meters (5 to 8 feet) from the screen.
  3. Turn off halogen bulbs or close window blinds behind or near the screen.
  4. Use a phone camera (which sees infrared) to verify both IR LEDs on the DolphinBar are illuminated.

### 4. RetroBat Overrides Gun Settings on Exit
- **Symptom**: After closing RetroBat, gun mappings revert to default or games stop responding to triggers.
- **Cause**: RetroBat's internal gun management was re-enabled, or RetroBat was running while config files were modified.
- **Remedy**:
  1. **Always close RetroBat, Gunmote, and Steam before running kit configuration steps.**
  2. Re-run Step 7 (`07-RetroBatSettings.ps1`) to ensure `use_guns=0` and `disableautocontrollers=1` are enforced in `es_settings.cfg`.

### 5. Profile Automation Does Not Switch Layouts During Game Launch
- **Symptom**: When launching MAME or TeknoParrot from RetroBat, Gunmote remains on the `Menu Pad` profile.
- **Causes**:
  - Scheduled tasks were not registered or are disabled.
  - RetroBat batch hooks are missing or blocked by antivirus.
- **Remedy**:
  1. Verify task status:
     ```powershell
     Get-ScheduledTask -TaskName "RetroCabinetKit Gunmote Profile*"
     ```
  2. Check the automation log for errors:
     ```powershell
     Get-Content "C:\ProgramData\RetroCabinetKit\lightgun\logs\profile.log" -Tail 20
     ```
  3. Re-run Step 8 (`08-ProfileAutomation.ps1`) with Administrator rights.
