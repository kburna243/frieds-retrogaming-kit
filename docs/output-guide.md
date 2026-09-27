# Output Haptics Guide — Rumble, Lamps & Solenoids

How the **Fried's Retrogaming Kit** handles the *haptic* half of the cabinet: the middleware that
turns emulator output events into force feedback, blinking lamps and clicking solenoids. Package:
`output\` (step `output\steps\01-Middleware.ps1`, plugins in `output\adapters\`).

---

## 📌 Why a package of its own

Output tools are hardware-agnostic servers between emulator and cabinet hardware — they serve
**lightguns and wheels** alike:

```
   [ MAME / emulators ]
        │  output events: Win32 messages ("output windows") or TCP ("output network")
        ▼
   [ middleware: MAMEHooker | qMamehook | Hook of the Reaper ]
        │  serial / USB board commands (LEDWiz, Pac-Drive, Ultimarc, …)
        ▼
   [ solenoids · lamps · shakers · FFB wheels ]
```

The kit detects and configures this layer; it **never installs it as a service, never starts or
kills it** — middleware are tray apps a person launches (detection is process/port/tools-folder
based, so it works whether or not they happen to run).

## 🧰 Supported middleware (v1)

| Adapter | Transport | mame.ini `output` | Detection evidence |
|---|---|---|---|
| `MameHooker` | Win32 messages | `windows` | process `MameHooker`, LED-Wiz board `0DFA:0001`, tools folder |
| `QMamehook` | TCP (port 9735*) | `network` | process, listening port, tools folder |
| `HookOfTheReaper` | Win32 + own TCP server on **8000** | `windows` | process, port, tools folder |

\* 9735 is community convention for qMamehook's default, not an official standard — the port stays
configurable in `qmhook.ini`, which the kit only touches when it already exists.

## ⚔️ The one exclusive key: `output`

MAME has a single `output` setting. `windows` and `network` cannot both be active — and Gun4IR's
lightgun configuration already uses `output windows`. The kit therefore detects **all** running
middleware (multi-detection is fine: HotR for the gun solenoid while MAMEHooker drives lights) but
reports disagreements instead of overwriting anything:

```powershell
$d = Get-OutputDetectedMiddleware -RetroBatRoot 'D:\RetroBat'
$d.DetectedOutputs   # @('HookOfTheReaper','QMamehook')      — several tools: normal
$d.Conflicts         # Kind='OutputModeConflict' Detail='…windows…network…'
```

While an `OutputModeConflict` exists, the configure step is `NeedsUser`: nothing is rewritten, the
report says why. One tool must give way — that is a cabinet decision, not a script decision.
The same applies to two tools claiming the same TCP port (`PortConflict`).

## 🔥 Solenoid safety is enforced

Hook of the Reaper drives coils. A solenoid held too long burns its coil in seconds, so these two
values are **Safety** entries in the adapter — Configure always (re)writes them into an existing
`settings.ini`, Verify stays red while they are missing or weaker:

| Key | Value | Meaning |
|---|---|---|
| `SolenoidProtection` | `1` | current limiting active |
| `SolenoidMaxOpenTime` | `200` | every solenoid closes after at most 200 ms |

User values in the same file (like `DefaultLGPath`) are never touched; absent files are never
created — the safety enforcement applies exactly where the tool is installed.

## 💻 Command line

```powershell
# read-only survey (processes, ports, tools folders — nothing is started or stopped)
& output\steps\01-Middleware.ps1

# inject a machine picture (tests/agents) and preview
& output\steps\01-Middleware.ps1 -Snapshot @{ Processes=@('mamehooker'); Ports=@(); Devices=@() } -WhatIf

# write mame.ini output= + settings files, but only when the modes agree
& output\steps\01-Middleware.ps1

# portable ZIP deployed manually (the kit downloads nothing):
& output\steps\01-Middleware.ps1 -Install -Name MameHooker -PackagePath D:\downloads\mamehook5.1.zip -Approved
```

## 🧪 Tests & boundaries

`tests\output\Middleware.Tests.ps1` covers: multi detection, mode conflict refusal (mame.ini byte
identical afterwards), enforced solenoid values, absent-file semantics and the step statuses — all
against injected snapshots, never the live machine.

Not (yet) automated, tracked as deliberate gaps:

- **MAMEHooker profiles** (`P1_CtmRecoil=scom 3 1000 1` wiring per cabinet) — the kit configures the
  middleware settings, not the per-game lamp/solenoid plan.
- **Firewall** — loopback needs none; nothing is opened.
- Vendor downloads (dragonking.arcadecontrols.com is plain HTTP, qMamehook repos need maintainer
  verification) — deliberately outside the core download allow-list: use `-PackagePath`.
