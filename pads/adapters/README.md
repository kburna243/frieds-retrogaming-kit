# pads\adapters\ - USB/Bluetooth gamepads (8BitDo, Xbox, PlayStation, Switch Pro)

One `<Name>.ps1` per **pad family**, not per model: a family is the set of controllers that share a
vendor id, a mode story and a driver situation. The kit parses these files (never executes them at scan
time) and only runs adapters that provide all five functions:

| Function | Purpose |
|---|---|
| `Test-<Name>Hardware -RetroBatRoot [-Devices]` | Read-only. Delegates to `Get-PadDetectedGamepad` so the class rule applies here too. |
| `Get-<Name>AdapterInfo` | Data table - everything the kit writes is driven from here, no logic. |
| `Install-<Name>Software -RetroBatRoot [-PackagePath] [-Approved]` | Never downloads; delegates to `Install-PadAdapterPackage` (one audited route). |
| `Configure-<Name>Profile -RetroBatRoot [-DetectedPads]` | Delegates to `Set-PadGamepadConfiguration`; returns the number of changes. |
| `Set-<Name>InterferenceShield -RetroBatRoot [-Devices]` | **Report-only**: `Pad.Adapter.ShieldReportsOnly`, `Pad.NoBlacklist`, plus this family's quirks. |

`_`-prefixed files (the template) are skipped by the catalog.

## Info table keys

| Key | Written to / used for |
|---|---|
| `Class` | always `Gamepad`; goes into the detection report |
| `ToolDir` | `tools\<ToolDir>` for a user-supplied portable ZIP. `''` = this family has nothing to unpack |
| `MatchIds` | tight `VID_xxxx&PID_yyyy` signatures (full `USB\...&MI_00*` form or core form) - **no bare VIDs** |
| `NameHints` | FriendlyName patterns, consulted **only** when `MatchIds` is empty. All four families have signatures, so all four leave this empty |
| `Quirks` | documented pitfalls. Codes go into the detection result (`Quirks`), prose goes into the shield. Never repaired |
| `ControllersValues` | `retrobat.ini` `[Controllers]` - the **only** write target of this package |
| `SteamEntries` | **always `@()`** - see "Not blacklisted" below |
| `MameValues`, `Model2Values`, `SupermodelValues` | **always `@()`** - those files belong to the arcade class |
| `Links` | official sources as *strings*; `Install` prints them instead of downloading. Never fetched, so re-check them when a family changes |
| `Notes` | the paragraph a human/agent reads: modes, pair button, what the kit cannot do |

## Device class: lightgun > arcade > pads

`Get-PadDetectedGamepad` builds its exclusion set from the **live catalogs** of the other two packages
(`Get-LightgunAdapterCatalog` + `Get-LightgunDeviceMatch`, `Get-ArcadeAdapterCatalog` +
`Get-ArcadeDeviceMatch`) instead of hard-coding a rival list - if arcade adds a signature tomorrow, the
pad scan honours it without a commit here. Every dropped device is logged once (`Pad.Excluded`) with the
class that owns it.

The ids that make this rule necessary:

- `045E:028E` - Xbox 360 wired **and** every GP2040-CE board **and** 8BitDo in X-mode. arcade claims it
  by name hint (`*GP2040*`), so a stick stays a stick; a bare `028E` is a pad.
- `045E:0719` - the Xbox 360 wireless receiver is arcade's `Xbox360Wheel` signature. `XboxPad` still
  lists the id (it *is* a pad receiver) and is still excluded: class rule beats signature.
- `0738:4716/4718` - Mad Catz: arcade's stick ids, so a Mad Catz SFV FightPad Pro is excluded here too.
  A dedicated pad adapter would have to negotiate that split with arcade first.
- `0079:0011` - Zero Delay / PS2-USB encoders (arcade). Never add `0079` to a pad adapter.
- `D209:*` - Ultimarc: AimTrak guns (lightgun) and I-PAC boards (arcade).
- `2E8A:000A` - GP2040 bootloader, lightgun's OpenFIRE route.

## Signature forms and the two real blind spots

Windows spells the same VID/PID differently per transport, so `Get-PadSignaturePatterns` derives, for
every signature, the raw form, the substring form and the **Bluetooth-classic** form
`VID&0002xxxx_PID&yyyy` (LE prefix `0002`, 4-digit VID, `_PID&`, 4 hex digits). A paired DualShock 4
(`BTHENUM\{00001124-...}_VID&0002054C_PID&09CC\...`) is found that way; adapters may list the BT form
explicitly as documentation, which is harmless.

- **BLE has no VID/PID in the instance path.** A Bluetooth Low Energy device enumerates as
  `BTHLE\Dev_<mac-address>...`, and `BTHLE` device ids for gamepads usually expose no `FRIENDLYNAME` either.
  An Xbox Series controller that only enumerated as `BTHLE\Dev_...` is therefore **not** detectable by this
  package. The wired/2.4 GHz path (`USB\VID_045E&PID_0B12`) and the Bluetooth-classic path are.
- **One pad, several instances.** A composite device enumerates as a `USB\...` parent plus `HID\...&MI_00`
  children, so one physical controller can produce more than one `DetectedPads` entry. `DeviceId` is the
  instance id, not a player number; the player count of a live scan can be too high because of this.

## Why pads are never put on the Steam blacklist

The lightgun and arcade packages add vendor VIDs to Steam's `controller_blacklist`, because Steam Input
would otherwise remap a gun or a fightstick into something it is not. For pads that reasoning inverts:
the gamepad **is** the device Steam expects, and it is the device a user needs to navigate Steam in a
cabinet with no keyboard. Blacklisting a pad can leave Steam uncontrollable - the opposite of the
lightgun case. So `SteamEntries` stays empty, the step has no `-SteamConfigVdf` parameter, and this
package contains no call of Steam's writers at all. `Pad.NoBlacklist` is the line the user hears.

This is a deliberate deviation from the delivered design doc, which suggested device masking through
HidHide for pads as well. HidHide is a kernel filter driver (HKLM, device-class devnode) - driver work is
manual in this kit, and a pad family that needs it should be documented in `Notes`, not half-installed.

## Not (yet) automated

- **Kernel drivers / middleware**: DsHidMini and BthPS3 (DualShock 3, Bluetooth), BetterJoy / DS4Windows
  (Switch Pro handshake, gyros), the Xbox Accessories app (Series firmware). All HKLM or Store territory.
  Adapters name the source and report the quirk; a person installs.
- **Mode switching** on 8BitDo pads is a button combo on the device - nothing on Windows can press it.
- **Per-player mapping** (`P1Device_*` style keys, emulator-side profiles) is not written: pads stay on
  RetroBat's `[Controllers] Autocontrollers`, which is the cabinet-wide switch.
- **Steam per-controller configuration** is intentionally out of scope for this package.
