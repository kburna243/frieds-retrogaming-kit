# Bench-Check — Arcade, Pads and Output on Real Hardware

This protocol verifies what the workbench (the test suite) cannot prove: whether RetroBat, MAME
and the haptics tools really consume the values our adapters write. About 30–45 minutes at the
cabinet. Every section ends in **Expect** — if reality differs, report it at the bottom; if all
green, we mark the suites "bench-verified" in the changelog.

Preparation: cable up the devices you actually run (stick, wheel, pads, middleware ready to
start). All commands from the kit folder.

## 1 · `retrobat.ini [Controllers]` — are the keys consumed?

```powershell
& arcade\steps\01-Adapter.ps1            # writes, if a device was detected
(Get-FileHash <RetroBatRoot>\retrobat.ini).Hash
#  start RetroBat, load a wheel system, close RetroBat again
(Get-FileHash <RetroBatRoot>\retrobat.ini).Hash   # SAME as before?
& arcade\steps\01-Adapter.ps1            # second run must verify "0 changes"
```

**Expect:** the hash is unchanged after the RetroBat visit (RetroBat does not iron over us), the
wheel turns with the right range in game (Logitech ~900°, Xbox wheel ~270°), the step reports
green. If anything differs → note the key name(s) and the observed value; we fix them in
`arcade\adapters\README.md` and the adapters.

## 2 · Model 2 / Supermodel force feedback (only if installed)

`Emulator.ini`/`Supermodel.ini` were written only if the files existed — then in game (House of
the Dead / Harley-Davidson) enable force feedback in the service menu. **Expect:** the wheel
vibrates, and after the session `[Global] ForceFeedback=1` still stands.

## 3 · Steam blacklist

```powershell
& arcade\steps\01-Adapter.ps1            # entries then live in config.vdf
```

Restart Steam → Settings → Controller. **Expect:** stick/wheel do **not** appear as controllers
(no "configure device" dialog). Gamepads, by contrast, **should** stay visible — pads deliberately
are never blacklisted.

## 4 · MAME output: `windows` versus `network`

With `output = windows` (MameHooker/DOF/HotR): in an output-capable game **Tab → Output** —
**Expect:** lamps/LEDs cycle through the test menu. Now additionally start a TCP middleware
(qMamehook): `& output\steps\01-Middleware.ps1` **Expect:** `OutputModeConflict`, **no** change
to mame.ini — it only writes again once you stop one tool.

## 5 · HotR solenoid protection (live, the important one)

Trigger a solenoid event (shot rumble in PinMAME, or HotR's test button). **Expect:** the coil
clicks briefly (< 0.2 s) and never drones on; HotR's settings show `SolenoidProtection=1 /
SolenoidMaxOpenTime=200`. Touch a solenoid after 10 minutes of play: **Expect:** warm, not hot.
Hot = protection not effective → power HotR off and report the conflict to me.

## 6 · Pad class split

Plug in an Xbox pad, an 8BitDo (X-mode), a GP2040 stick and (if available) a DS4 at once, then:

```powershell
& pads\steps\01-Gamepads.ps1
```

**Expect:** the stick stays Arcade (log line `Pad.Excluded … Arcade`), the bare Xbox pad →
`XboxPad`, 8BitDo → `EightBitDoPad` (in D-mode it shows under PlayStation with the impersonation
quirk), an Xbox Series pad over BLE → deliberately **not** visible (documented, not a bug).

## Reporting

Deviations: `& core\Start-KitTools.ps1 -SupportBundle` (anonymized) or the marked log lines
(`Arcade.*`/`Pad.*`/`Output.*`) directly. All green: short word back, then "bench-verified" goes
into the docs.
