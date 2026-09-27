# output\adapters\ — haptic middleware (rumble, lamps, solenoids)

Middleware like **MAMEHooker**, **qMamehook** and **Hook of the Reaper** receives emulator output
events and drives solenoids, lamps, shakers and force feedback. The two pinball-cabinet additions
work the same way: **DirectOutputFramework** (DOF R3++ — the Win32 output engine of most vpin cabs)
and **DmdExtensions** (freezy's dmdext — the dot-matrix mirror for real DMD panels). They serve
lightguns *and* wheels — which is why they are a package of their own instead of being scattered
across the device classes.

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
| `MameOutput` | the mame.ini `output` key the tool needs: `windows` (Win32 messages), `network` (TCP) or `''` — the tool does not use the key at all (dmdext) |
| `SettingsTargets` | per settings file: `File`/`Path`, `Section`, `Safety` (enforced), `Values` (defaults) — written only while the file exists |
| `Links` | official sources; Install never downloads |

## The five adapters

| Adapter | Evidence used | mame.ini `output` |
|---|---|---|
| `MameHooker` | processes, LED-Wiz board `USB\VID_0DFA&PID_0001*`, `tools\MAMEHooker` | `windows` |
| `HookOfTheReaper` | processes, TCP 8000, Reaper board `USB\VID_16C0&PID_0006*`, `tools\HookOfTheReaper` | `windows` + enforced solenoid safety |
| `QMamehook` | processes, TCP 9735, `tools\QMamehook` | `network` |
| `DirectOutputFramework` | process `DirectOutput` only — no boards, no port, no tools dir (see below) | `windows` |
| `DmdExtensions` | process `dmdext`, `tools\dmdext` | *none* — the DMD path is not fed by the `output` key |

## The `output` key is exclusive

MAME has one `output` setting: `windows` (MAMEHooker, HotR, DirectOutputFramework) **or** `network`
(qMamehook). Several `windows` tools detected together are **not** a conflict — they can coexist and
the interference shields only *report* rival listeners; the exclusive decision is windows-vs-network.
`DmdExtensions` declares an empty `MameOutput`, stays out of the modes list and never participates in
a mode conflict. Detection reports conflicts as structured objects:

```powershell
$d = Get-OutputDetectedMiddleware -RetroBatRoot 'D:\RetroBat'
$d.DetectedOutputs   # @('DirectOutputFramework','MameHooker','QMamehook') — multi is fine
$d.Conflicts         # OutputModeConflict / PortConflict with human-readable Detail
```

`Set-OutputMiddlewareConfiguration` refuses to write `output` while a mode conflict exists — the
report stays honest and a person decides which tool gives way. The lightgun Gun4IR adapter uses
`output windows` too, so a qMamehook install is a conscious cabinet decision.

## Boards belong to the consumers

A board is evidence of the adapter that talks HID to it *directly* — not of a framework sitting
above it. `USB\VID_0DFA&PID_0001*` therefore stays **MameHooker's** signature.
**DirectOutputFramework** claims no boards: its process is the honest evidence (an installed but
idle DOF must not flip the mame `output` key through a dead folder), and **DmdExtensions** claims
none either — the delivered draft's board list was a false-positive minefield that is refused on
principle: `303A:1001` is Espressif's generic VID and belongs to the **OpenFIRE lightgun** in the
lightgun package (collision — never DMD evidence), while CH340 `1A86:7523`, FTDI `0403:6014` and
STM32-CDC `0483:5740` are bare cable-chip IDs matching every USB-serial adapter in the house.
Board signatures must name the device, not the wire.

## Safety first

Hook of the Reaper drives solenoids. Without the current limiter coils burn within seconds of
continuous fire, so `SolenoidProtection=1` and `SolenoidMaxOpenTime=200` are **enforced** `Safety`
values — Configure always writes them into an existing settings.ini, and Verify fails while they
are missing or higher than 200 ms. Neither new adapter carries `Safety` values in v1: DOF's and
dmdext's limits live in files the kit does not write (see NOT-YET list and DmdDevice.ini ownership).

## Open fact questions

* `FAFA:00F0-00FF` (LED-Wiz unit clones): the unit-numbered clone range and a Pinscape controller's
  LedWiz **emulation (Unit #8)** share this vendor namespace — VID/PID alone cannot tell them
  apart. **Decided: this is a cabinet-owner question** (it depends on what physically hangs in your
  setup), not a kit question — the range stays **unclaimed**; real hardware that reports under FAFA
  is configured via the consumer adapters' own folders/processes, and a follow-up may add a
  per-cabinet opt-in if scans prove a safe signature.
* `D209:1401` (Ultimarc PacLED64): a tight, genuine board signature — but no consumer adapter in
  the kit has demonstrated driving one yet. Candidate for a MameHooker follow-up, deliberately
  unclaimed in this round (bare `D209` stays out regardless: AimTrak lightguns report under it).
* Pinscape as an **input** device (flipper buttons, plunger, nudge, axis masking): later pinball
  input territory with its own colleague package — consciously *not* handled from `output\adapters\`.
* `DmdDevice.ini` (**decided**): the kit keeps and sets it — inside the **pinball package** (step
  08-Screens, `pinball\modules\Screens.ps1` owns `[VPinMAME.DMD]`/`[FP.DMD]` with golden tests), so
  one writer feeds all the tools (Baller/PinUP, PinballY, …). The output adapter never writes it —
  two writers, one file, was the exact failure this decision prevents. The draft's machine-scope
  `DMDDEVICE_CONFIG` env var stays out: unverified and a system-wide intervention.

## What the kit deliberately does not do

- install nothing as a Windows service, start nothing, kill nothing (tray apps are the user's)
- create firewall rules (everything here talks over loopback)
- synthesize MAMEHooker `.xml`/profile scripts (`P1_CtmRecoil=scom 3 1000 1`) — per-cabinet wiring,
  planned as a later feature
- download from vendor sites (plain HTTP hosts and repo naming ambiguity) — links + `-PackagePath`
  local ZIP + `-Approved` only
- **NOT YET — DOF's own world:** the `C:\DirectOutput\Config\*.xml` layout (`GlobalConfig*.xml`,
  `Cabinet.xml` — outside every root contract, and the kit has no XML writer), the COM registration
  (`RegisterDirectOutputComObject.exe` writes HKLM — hand work by a person, the kit never touches
  the registry) and `directoutputconfig30.ini` generation (the Online Configuration Tool produces
  it from a person's cabinet wiring — never invent the file)
- **NOT YET — DMD side:** writing `DmdDevice.ini` (pinball package's file, see above) and
  HidHide-based device strips / axis masking (pinball input territory)
