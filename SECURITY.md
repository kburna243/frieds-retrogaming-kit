# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| `main` (development) | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability or privacy issue in **Fried's Retrogaming Kit**, please do **not** open a public issue. We take security and system integrity seriously.

To report a vulnerability responsibly:
- Open a private security advisory on GitHub via **Security > Report a vulnerability**, or
- Contact Friedrich Börner privately via the email address listed in the [LICENSE](LICENSE) file.

Please include:
- A description of the issue and potential security impact.
- Exact reproduction steps, script arguments, or environment conditions.
- Any mitigation or patch suggestions you may have.

You will receive an initial response within 48 hours, followed by regular updates until a fix is released.

---

## Security Model & Integrity Principles

Fried's Retrogaming Kit is designed as an open, inspectable automation toolkit for Windows gaming cabinets. We operate under strict security and privacy principles:

1. **Zero Proprietary Binary Bundling**: The repository contains **no** binary executables, closed-source drivers, ROMs, or game assets. All external tools (e.g. ViGEmBus) are downloaded exclusively from verified, official upstream repositories (such as signed Microsoft or Nefarius releases).
2. **Authenticode & Checksum Verification**: Whenever an official runtime or driver is downloaded, the kit verifies Authenticode digital signatures (Common Name and Organization) and SHA-256 hashes before executing any installer.
3. **Dry-Run by Default**: Every installation and configuration step supports PowerShell `-WhatIf`. Users can preview exactly what files, registry values, or settings will change before anything is written to disk.
4. **Non-Destructive Operations & Automatic Backups**: Existing configurations, databases (`PUPDatabase.db`), INI files, and registry hives are automatically backed up to timestamped ZIP archives before modifications occur. The kit **never** deletes user games, ROMs, or tables.
5. **No Telemetry or Phone-Home**: The kit runs 100% locally. It contains no tracking, telemetry, analytical beacons, or external data collection.

---

## Scheduled Tasks & Privilege Model (Lightgun Profile Automation)

We believe in complete transparency regarding system privileges.

### Why Elevated Tasks are Used
In **Lightgun Step 8 (Profile Automation)**, the kit configures automated profile switching for Gunmote when launching games from RetroBat (e.g., switching between MAME, TeknoParrot, Naomi, and Menu profiles).

To ensure a seamless arcade cabinet experience:
- RetroBat executes non-elevated batch hooks on game launch and exit (`scripts\game-start\rck-gunmote-profile.bat` and `scripts\game-end\rck-gunmote-profile.bat`).
- These batch hooks invoke `schtasks /run /tn "RetroCabinetKit Gunmote Profile <Name>"` to switch the active Gunmote layout via a PowerShell watcher (`profile.ps1`).
- These scheduled tasks are registered with **highest privileges (`RunLevel = Highest`)** for the logged-on user so that Gunmote can adjust virtual input drivers and controller mappings without triggering interactive Windows User Account Control (UAC) prompts that would disrupt fullscreen games.

### Security Consideration & Attack Surface
Because these scheduled tasks run with highest privileges for the logged-on user:
- **Any process running under that user account can trigger these scheduled tasks** by calling `schtasks /run /tn "RetroCabinetKit Gunmote Profile <ProfileName>"`.
- This executes the watcher script `profile.ps1`.

### Mitigations & Hardening in Place
To prevent unprivileged privilege escalation or arbitrary script execution:
1. **Protected Directory ACLs**: The watcher script `profile.ps1` is stored exclusively in `%ProgramData%\RetroCabinetKit\lightgun\`. The kit verifies and enforces NTFS Access Control Lists (ACLs) so that **only Administrators and `NT AUTHORITY\SYSTEM` have write or modify permissions**. Standard users only possess read and execute permissions.
2. **Fixed Task Actions**: The scheduled tasks do not accept arbitrary command-line input from callers; each task is pre-registered with a fixed, immutable layout parameter (e.g. `Menu`, `TP`, `Pad43`, `Naomi`, `Mouse`).
3. **User SID Binding**: Tasks are strictly bound to the security identifier (SID) of the user who initiated setup. The kit refuses to create tasks for different user accounts.
4. **Pre-Release Hardening**: Further hardening is currently being finalized before the official v1.0 release.

---

## How to Inspect, Disable, or Remove Profile Automation

If you do not want elevated scheduled tasks on your system, you can easily inspect, disable, or remove them at any time.

### Inspecting the Tasks
To list all scheduled tasks created by the kit:
```powershell
Get-ScheduledTask -TaskName "RetroCabinetKit Gunmote*" | Format-Table TaskName, State, TaskPath
```

### Disabling the Tasks
To temporarily disable the automated profile tasks without deleting them:
```powershell
Get-ScheduledTask -TaskName "RetroCabinetKit Gunmote*" | Disable-ScheduledTask
```

### Removing the Tasks Completely
To permanently delete all profile automation tasks:
```powershell
Get-ScheduledTask -TaskName "RetroCabinetKit Gunmote*" | Unregister-ScheduledTask -Confirm:$false
```

### Removing Script Hooks
To remove the background automation directory and RetroBat hooks:
1. Delete the folder `C:\ProgramData\RetroCabinetKit\lightgun` (requires Administrator rights).
2. In your RetroBat installation (e.g. `C:\RetroBat`), delete:
   - `system\scripts\game-start\rck-gunmote-profile.bat` (if installed)
   - `system\scripts\game-end\rck-gunmote-profile.bat` (if installed)
