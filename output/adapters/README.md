# output\adapters\ — haptic middleware (rumble, lamps, solenoids)

Middleware like **MAMEHooker**, **qMamehook** and **Hook of the Reaper** receives emulator output
events and drives solenoids, lamps, shakers and force feedback. They serve lightguns *and* wheels —
which is why they are a package of their own instead of being scattered across the device classes.

Same five-function contract as `arcade\adapters\` (Test / Get-AdapterInfo / Install / Configure /
Shield), but detection is process-, port-, file- and board-based through an injectable snapshot:

```powershell
Test-<Name>Hardware -RetroBatRoot 'D:\RetroBat' -Snapshot @{
    Processes = @('hookofthereaper'); Ports = @(8000); Devices = @()
}
```

## Info table keys

| Key | Meaning |
|---|---|
| `DetectProcesses` / `DetectPorts` / `BoardMatchIds` | evidence the tool is present (all read-only) |
| `MameOutput` | the mame.ini `output` key the tool needs: `windows` (Win32 messages) or `network` (TCP) |
| `SettingsTargets` | per settings file: `File`/`Path`, `Section`, `Safety` (enforced), `Values` (defaults) — written only while the file exists |
| `Links` | official sources; Install never downloads |

## The `output` key is exclusive

MAME has one `output` setting: `windows` (MAMEHooker, HotR) **or** `network` (qMamehook). Detection
therefore reports conflicts as structured objects:

```powershell
$d = Get-OutputDetectedMiddleware -RetroBatRoot 'D:\RetroBat'
$d.DetectedOutputs   # @('MameHooker','HookOfTheReaper','QMamehook') — multi is fine
$d.Conflicts         # OutputModeConflict / PortConflict with human-readable Detail
```

`Set-OutputMiddlewareConfiguration` refuses to write `output` while a mode conflict exists — the
report stays honest and a person decides which tool gives way. The lightgun Gun4IR adapter uses
`output windows` too, so a qMamehook install is a conscious cabinet decision.

## Safety first

Hook of the Reaper drives solenoids. Without the current limiter coils burn within seconds of
continuous fire, so `SolenoidProtection=1` and `SolenoidMaxOpenTime=200` are **enforced** `Safety`
values — Configure always writes them into an existing settings.ini, and Verify fails while they
are missing or higher than 200 ms.

## What the kit deliberately does not do

- install nothing as a Windows service, start nothing, kill nothing (tray apps are the user's)
- create firewall rules (everything here talks over loopback)
- synthesize MAMEHooker `.xml`/profile scripts (`P1_CtmRecoil=scom 3 1000 1`) — per-cabinet wiring,
  planned as a later feature
- download from vendor sites (plain HTTP hosts and repo naming ambiguity) — links + `-PackagePath`
  local ZIP + `-Approved` only
