# Changelog

All notable changes to Fried's Retrogaming Kit are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).
The version lives in the [`VERSION`](VERSION) file; the release workflow publishes a release for every tag `vX.Y.Z`
that matches it.

## [Unreleased]

## [1.3.0] - 2026-10-01

### Added

- **Input matrix (universal button setup):** one input profile maps what the player wants (MAME port types such as
  `START1`, `COIN1`, `P1_BUTTON1`) to what the panel sends (`KEY_LCONTROL`, `JOY1_BUTTON2`, `MOUSE1_BUTTON1`,
  several per button joined with `OR`). Built-in profile `ipac2-default` (the I-PAC 2 factory layout); own
  profiles in `%USERPROFILE%\RetroCabinet\InputProfiles`. First dialect: MAME ctrlr (`saves\mame\ctrlr\kit-<profile>.cfg`).
- API 1.5: `controllers.input_profiles` (Read) and `controllers.input_apply` (Change: dry run without `-Apply`,
  ZIP backup before rewriting its own file).

### Safety

- The matrix never overwrites a ctrlr file it did not write (`custom1.cfg` holds the gun layout) nor RetroBat's
  `retrobat_auto.cfg`. It does not change `es_settings.cfg`; the plan warns when `mame.emulator`,
  `mame.disableautocontrollers` or `mame.mame_ctrlr_profile` would keep MAME from loading the file.

## [1.3.0] - 2026-10-01

## [1.2.0] - 2026-10-01

### Added
- **Fast-Path System Health** (`core/modules/Diagnostics.ps1`):
  - `Get-SystemHealth` -- sub-2-second hardware/storage/interference diagnostic.
  - Three vital pillars: USB hardware matrix (DolphinBar, Arcade Encoder, 5 lightgun families, Xbox controllers), storage reachability (local + UNC NAS mounts via Test-Path), interference detection (Steam, Epic, JoyToKey, AnyDesk, Discord, 10 bad actors).
  - System vitals: uptime, free RAM, free disk C:, CPU load.
  - Returns `{Status: 'OK'|'Degraded', Hardware: {…}, Storage: {…}, Interference: {…}, Vitals: {…}}` -- no text parsing needed.
- **API operation `status.health`** (Read) -- automatically exposed as MCP tool, agent can query hardware state without log parsing.
- **Configurable**: `ExtraStoragePaths` (UNC NAS mounts) and `ExtraBadProcesses` parameters for cabinet-specific checks.
- **Auto-Detection** (`core/modules/AutoDetect.ps1`):
  - `Get-KitAutoDetect` -- natural language to kit configuration: keyword/scoring engine, no LLM call.
  - Returns target modules with confidence scores, suggested setup mode, and preset hint.
  - German + English keyword catalogs for 9 modules + 3 setup modes + 4 presets.
  - `Invoke-KitAutoDetect` -- apply detected mode and preset in one call.
- **Rollback Stack** (`core/modules/Rollback.ps1`):
  - `Push-KitRollbackPoint` / `Pop-KitRollbackPoint` -- snapshot-based LIFO rollback for complex installs.
  - Persisted across sessions via `%USERPROFILE%\RetroCabinet\rollback-stack.json`.
  - `Pop-KitRollbackPointByName` -- roll back to a specific named point (unwinds intermediate points too).
- **Saga Transaction Pattern** (`core/modules/Transaction.ps1`):
  - `Invoke-KitTransaction` -- wrap multi-step operations: either all succeed, or NONE are applied.
  - `Register-RollbackStep` -- each step registers its own undo action (scriptblock) on a LIFO stack.
  - On failure: stack unwinds in reverse order, restoring exact pre-transaction state.
  - Per-step error reporting, rollback-failure detection, cabinet consistency guarantees.
- **3 API operations**:
  - `auto.detect` (Read) -- natural language → kit config (modules, mode, preset).
  - `backups.snapshot` (Change) -- take file snapshot, push rollback point.
  - `backups.rollback` (Change) -- roll back to last (or named) point, restore all snapshotted files.

## [1.1.0] - 2026-10-01

### Added
- **Setup-Levels** (`core/modules/SetupContext.ps1`) -- three modes across all 10 packages:
  - **Easy** (Autopilot): minimal questions, best-practice presets, silent backups.
  - **Custom** (Assistent): choice + sliders, plan summary before execution.
  - **NerdExtreme** (Deep Dive): raw INI keys, file paths, JSON diffs, no hand-holding.
  - Context header contract: agent sends `{mode, target_module, hardware_detected, preset}` as JSON.
- **Preset Management** (`core/modules/Presets.ps1`):
  - 4 built-in presets: `easy_arcade`, `custom_racing`, `nerd_lightgun`, `balanced_cabinet`.
  - User presets in `%USERPROFILE%\RetroCabinet\Presets\`, never deleted by kit updates.
  - `Get-KitPresetCatalog`, `Get-KitPreset`, `Set-KitPreset`, `Remove-KitPreset`, `Invoke-KitPreset`.
- **3 API operations** in the catalog:
  - `setup.set_mode` (Change) -- Easy/Custom/NerdExtreme.
  - `presets.list` (Read) -- all available presets.
  - `presets.apply` (Change) -- apply a named preset, sets mode and values.
- **Structured INI Parser** (`core/modules/IniParser.ps1`):
  - `ConvertFrom-Ini` / `ConvertTo-Ini`: section-aware round-trip with nested hashtables.
  - `Merge-IniData`: deep merge with override priority.
  - `Get-IniEffectiveConfig`: base + override union in one call.
- **Shadow Override** pattern -- for every `config.ini`, user can create `config.override.ini`:
  - `Get-EmulatorsIniPlan` / `Get-FrontendsIniPlan` now skip keys managed by user override.
  - `Set-EmulatorsIniValue` / `Set-FrontendsIniValue` merge overrides on top of kit values.
  - Kit updates never overwrite user customizations -- overrides always win.
  - New plan output includes `Overridden` flag for transparency.
- **Formal Adapter Contract** (`core/modules/AdapterContract.ps1`):
  - `Test-AdapterContract`: verifies required functions + Capabilities hashtable per adapter kind.
  - `Test-AdapterContractBatch`: validate all adapters in a directory.

### Changed
- **API monolith split**: `api/modules/Result.ps1` (OperationResult + JSON + Anonymize) and `api/modules/Isolation.ps1` (process isolation) extracted from `api/RetroCabinetKit.Api.psm1`.
- **Emulator/Frontend INI handlers** rewritten from line-based to structured `ConvertFrom-Ini`/`Merge-IniData`/`ConvertTo-Ini` pipeline with shadow override support.
- **README**: `New in v1.0.0` section replaces stale v0.4.0, all 10 packages listed.
- **MCP server description**: now covers all packages (pinball, lightgun, arcade, pads, displays, enhancements, library, emulators, frontends).

### Fixed
- **INI parser now section-aware**: `[Section]` headers tracked, `[regex]::Escape($key)` for safe key matching (was matching first key occurrence regardless of section).
- **Duplicate `Get-LibrarySystemSnapshot`** renamed to `Get-LibraryBaseSnapshot`, no more recursive calls.
- **All `--` (em dashes) replaced with `--` (ASCII) across all module files (PowerShell 5.1 incompatible).

### Tests
- `tests/core/AdapterContract.Tests.ps1`: multi-section INI, adapter contract compliance (20 adapters), idempotency (Verify-before-Invoke), backup creation.

## [1.0.0] - 2026-10-01

### Added
- **Package `frontends/`** — detect, install, theme, genre-route, and catalog-export 5 game frontends via extensible adapter plugins.
  - **5 Frontend adapters:** RetroBat (EmulationStation), PinballY (PinballLauncher), Playnite (UniversalLauncher), LaunchBox (UniversalLauncher), PinUP (PinballLauncher/Popper).
  - Adapter contract: `Test-<Name>Frontend`, `Get-<Name>FrontendInfo`, `Install-<Name>Frontend`, `Configure-<Name>Frontend`, `Set-<Name>InterferenceShield`.
  - **Drop-in extensibility:** new frontend = copy `_Template.ps1`, fill 5 functions, auto-discovered by `Get-FrontendsAdapterCatalog`.
- **6 API operations** `frontends.*` in the operation catalog:
  - `frontends.detect` (Read) — detect all installed frontends.
  - `frontends.install` (Change) — install frontend via user-provided package.
  - `frontends.set_theme` (Change) — set frontend theme.
  - `frontends.configure_genre_routing` (Change) — which emulator launches which system per frontend.
  - `frontends.import_library` (Read) — import frontend library into unified JSON catalog.
  - `frontends.export_catalog` (Read) — export unified catalog to frontend-specific format.
- **Step** `frontends/steps/01-Frontends.ps1` — detect → configure → theme → genre routing → catalog workflow.
- **Tests** `tests/api/V100Api.Tests.ps1` — catalog, module, detect, and adapter contract assertions.
- **Genre routing map** — 20 systems mapped to best-fit emulators per frontend.

## [0.9.0] - 2026-10-01

### Added
- **Package `emulators/`** — detect, install, configure, patch, and verify 15 emulators via adapter plugins.
  - **11 Arcade/Console adapters:** MAME, RetroArch, TeknoParrot, Supermodel, Model2, Cemu, Dolphin, RPCS3, Xemu, DuckStation, PCSX2.
  - **4 Pinball adapters:** FuturePinball (BAM), VisualPinball (VPX), PinballArcade (Arcooda), PinballFX3.
  - Adapter contract: `Test-<Name>Emulator`, `Get-<Name>EmulatorInfo`, `Install-<Name>Emulator`, `Configure-<Name>Emulator`, `Set-<Name>InterferenceShield`.
- **6 API operations** `emulators.*` in the operation catalog:
  - `emulators.detect_installed` (Read) — detect all installed emulators.
  - `emulators.install` (Change) — install emulator via user-provided package.
  - `emulators.configure` (Change) — apply best-practice settings per emulator (supports `Frontend` parameter for RetroBat/PinballY/PinUP routing).
  - `emulators.apply_shader_preset` (Change) — apply CRT shader presets (none, crt-lottes, crt-royale, hsm-mega-bezel, lcd-grid, scanlines).
  - `emulators.patch` (Change) — community-curated emulator patches (read-only preview).
  - `emulators.verify_integrity` (Read) — verify emulator installation integrity (exe, configs, checksums).
- **Step** `emulators/steps/01-Emulators.ps1` — detect → configure → shaders → integrity workflow.
- **Tests** `tests/api/V090Api.Tests.ps1` — catalog, module, detect, verify, and adapter contract assertions.

## [0.8.0] - 2026-10-01

## [0.7.0] - 2026-10-01

## [0.6.0] - 2026-10-01

## [0.5.0] - 2026-10-01

## [0.4.2] - 2026-09-30

### Added
- `docs/CONCEPT_v0.5.0.md`: Abschnitt 8 „Validierte Wiimote/FFBBlaster/Gunmote-Integration" (Praxistest
  29.–30.09.2026 am Cabinet mit 2 Wiimotes, Mayflash DolphinBar und Rambo/TeknoParrot). Dokumentiert die
  validierte FFBBlaster→TCP→Gunmote-Architektur, zwei getestete Rumble-Wege (Output-Hook für Treffer,
  GunEffect/ViGEm für Schüsse), den Recoil-Stretcher (16 ms→150 ms), Konfigurationsmuster für
  FFBBlaster.ini, Gunmote ArcadeOutputs-INI und patch-once.ps1, 7 dokumentierte Fallen mit Symptom+Lösung
  sowie die daraus abgeleiteten Adapter-Spezifikationen für v0.5.0. Klärt die offene Frage
  „Rumble-Weg für TeknoParrot": beide Wege ergänzen sich, `outputs.verify_safety` verhindert Doppel-Rumble.

### Changed
- CI: the Pester suite runs in two parallel shards (~75 s each instead of ~150 s in one job) and no longer waits
  for the static checks; a static step fails when a test folder belongs to no shard. The website is built once in
  the CI and deployed to GitHub Pages only from main and only after every job is green (`pages.yml` removed; it
  used to deploy before any test had run).
- `tools\Set-KitVersion.ps1`: sets the version in all 16 places (VERSION, manifests, website, READMEs,
  CHANGELOG) and prints the commit and tag commands; `Test-KitSyntax` also checks the website version and the
  README status line. The pads manifest test reads VERSION instead of a hard-coded number.
- Missing UTF-8 BOMs are repaired instead of only reported: `tools\Repair-KitBom.ps1` (valid UTF-8 only), run by
  `tests\Run-Tests.ps1` before a local run and by the new pre-commit hook (`.githooks`, enable with
  `git config core.hooksPath .githooks`); `.editorconfig` sets `utf-8-bom` for PowerShell files. CI stays strict.

## [0.4.1] - 2026-09-27

### Fixed
- Lightgun: no pointer in Model 2, Model 3, Naomi, Atomiswave and Dreamcast started from RetroBat
  (found on the cabinet 27.09.). Their emulators and DemulShooter read RawInput, but the kit sent a pad
  layout (pointer on the Xbox stick), which gives them no mouse data at all. New Gunmote layout
  `Mouse 4:3` (`rck_mouse43.json`, pointer `lightgunmouse-4:3`, Plus/Minus on Xbox Start/Back because Demul
  and Model 2 ignore a keyboard start) for Model 2/3, Naomi/Atomiswave, Singe and Daphne, also bound in
  `Keymaps.json` to `supermodel.exe`, `emulator_multicpu.exe`, `demul.exe` and `hypseus.exe`, so a window
  change keeps the mouse. Dreamcast now uses the `Mouse` profile; MAME and PSX stay on `Pad 4:3`. Gunmote's
  stock `mouse43.json` (Plus on the keyboard) no longer counts as correct in mode Keep. Existing installs:
  run step 6 again before step 8, it records the new layout title.
- Lightgun step 13: Model 2 `EMULATOR.INI [Renderer] DrawCross=1`; the emulator drew no crosshair.

### Added
- `handoff\PLAN-WIIMOTE-KOPPELN.md`: pairing the Wiimotes where that route still works — TeknoParrot
  XInput bindings (steps 10–11, remembering the native two-RawInput-gun limit), DemulShooter
  already running on the Gunmote pads in HID mode as the real-pointer path (DSWiio kept as the
  fallback note), the output package with MAMEHooker `xip 1/2` rumble as the documented first
  test, every write gated dry run first. Revised the same day against the recorded cabinet
  state: the chain is built and live, so this is a transfer plan, not a build plan — Namco 357
  runs, Point Blank X runs via a desktop workaround, Cooper's 9 is the one open trace.

## [0.4.0] - 2026-09-27

### Added
- Lightgun adapter **Sinden** (step 15, fifth shipped adapter): camera-based guns (P1 `16C0/0F01`,
  P2 `16C0/0F02`, recoil models `16C0/0F38`/`0F39`, UVC camera `16C0/0F37`) — matched as exact VID&PID
  pairs only, because bare `VID_16C0` also covers the Retro Shooter hub and the Reaper board. The gun
  tracks a white border, so the adapter enables RetroBat's native border handling through
  `retrobat.ini [Guns]` (`Gun1Device=Sinden`, `SindenBorder=1`, `SindenBorderSize=2`,
  `SindenBorderColor=white`), MAME gets `lightgun_device rawinput` + dual/offscreen values, DemulShooter
  records the gun instance (never the camera endpoint) and Steam's blacklist gets the four gun PIDs.
  Recoil models fire their solenoid over their virtual COM port (byte `0x53`) — the kit's output package
  drives that through Hook of the Reaper with its enforced 200 ms solenoid guard; active hub power and
  separate USB controllers for two guns are documented in the adapter header. Signatures come from the
  2026-09 Sinden integration analysis and await a hardware-bench check. No auto-download (the vendor
  suite stays an official-source hint / local ZIP via `-PackagePath -Approved`), no process kills —
  the kit's rules hold. Docs (adapters README, lightgun guides de/en, FAQ de/en), i18n desc keys and
  `tests\lightgun\Adapters.Tests.ps1` (catalog, collision, camera-vs-gun, end-to-end switch) updated.
- Lightgun step 15 — **USB lightgun adapters** as a route beside the Wiimote/DolphinBar path.
  `lightgun\adapters\` is a drop-in folder: every `<Name>.ps1` provides `Test-<Name>Hardware` (read-only,
  standalone), `Get-<Name>AdapterInfo` (VID/PID signatures, ini values, official links) and
  `Install-/Configure-/Set-<Name>InterferenceShield` functions. Shipped: **Gun4IR** (`VID_2341&PID_8036`,
  bootloader `1B4F/9206`), **OpenFIRE** (`2E8A/000A`, `303A/1001`), **AimTrak** (`D209/1601–1608`) and
  **Retro Shooter** (`16C0/05E1`, `16C0/187C`, `0079/187C` — deliberately never a bare `VID_0079`, that is
  the DolphinBar's too). `lightgun\modules\Adapters.ps1` discovers the hardware from the PnP list, applies
  `mame.ini` (its own space-separated writer with backup), `retrobat.ini [Guns]`, the detected gun into
  `DemulShooter.ini [Player1] Device` and the gun VIDs into Steam's `controller_blacklist` — no process is
  killed, nothing downloads from hosts outside the core allow-list; vendor tools arrive as a local ZIP
  through `-PackagePath` with `-Approved`. `_Template.ps1` and `lightgun\adapters\README.md` document the
  community contract. New wizard page 15; `Set-/Test-LightgunSteamBlacklist` gained optional
  `-ExtraEntries` (defaults unchanged). Tests: `tests\lightgun\Adapters.Tests.ps1`.
- **Arcade package** (`arcade\`) — USB fightsticks, arcade encoders and steering wheels as a device class
  beside the lightguns, on the proven five-function adapter contract. `arcade\adapters\` ships 12 plugins:
  sticks **GP2040-CE, Brook UFB, I-PAC, Zero Delay, Mad Catz (with language-independent Code-43 quirk
  reporting), Hori, multi-console (Razer/Mayflash/Qanba), PS2 bridges** and wheels **Xbox 360 Racing Wheel,
  Logitech, Thrustmaster/Fanatec, DIY OpenFFB**. Detection is signature-tight and class-safe: lightgun
  devices are never re-claimed (`2E8A/000A` stays OpenFIRE, `16C0/05E1` stays Retro Shooter, `D209` is split
  by exact PID against AimTrak, no bare VIDs), name hints only ever stand alone where VID/PID is genuinely
  ambiguous. Configure drives `mame.ini`, `retrobat.ini [Controllers]`, Model 2 `Emulator.ini` and
  Supermodel `[Global]` (absent files are skipped both on write and on verify) plus the Steam
  `controller_blacklist` through lightgun's audited writers. Step `arcade\steps\01-Adapter.ps1`
  (`arcade-1-adapter-detect`/`-configure`, `-Devices` injection, `-SteamConfigVdf ''` skip, `-Install
  -PackagePath -Approved` for local ZIPs only). Tests: `tests\arcade\Adapters.Tests.ps1` (14).
- **Output package** (`output\`) — haptic middleware (rumble, lamps, solenoids) as middleware of its own for
  guns *and* wheels: adapters **MameHooker** (`output windows`), **QMamehook** (`output network`, community
  port 9735), **HookOfTheReaper** (port 8000, board `16C0/0006`). Detection is snapshot-based
  (processes/ports/boards/tools folders, fully injectable) and MULTI by design; mame.ini's single `output`
  key is exclusive, so a `windows`-vs-`network` disagreement surfaces as a structured `OutputModeConflict`
  and Configure refuses to rewrite anything while it stands. HookOfTheReaper's solenoid protection
  (`SolenoidProtection=1`, `SolenoidMaxOpenTime=200`) is an enforced `Safety` value on every existing
  settings file. No services, no firewall, no process kills, no downloads. Step
  `output\steps\01-Middleware.ps1`. Tests: `tests\output\Middleware.Tests.ps1` (14). `Run-Tests.ps1`
  defaults now include both new folders.
- Guides `docs\arcade-guide.md`/`.de.md` and `docs\output-guide.md`/`.de.md`; README doc index and FAQ
  (arcade support, parallel haptics, drivers-stay-manual); i18n namespaces `Arcade.*` and `Output.*`
  (de/en parity). `[Controllers]` values follow the community design doc and still await a hardware-bench
  check — the kit writes them idempotently with backups.
- Pinball: `pinball\modules\PinballY.ps1` describes a **PinballY** installation, the second front end for the same
  tables. Read only: version from `PinballY.exe`, every `SystemN.*` with its enabled state, the settings file as it
  is (UTF-8 with BOM, comment lines counted separately), the table databases with their game counts, other programs
  that live inside the folder (`PINemHi\pinemhi.ini`) and which path values do not resolve on this machine — with
  the difference between *broken here* and *from another machine* (`ReferenceForeign`), because a copied install is
  the normal case and not an error. `[PinballY]`, `[STEAM]`, `[TABLEPATH]` and `[TABLEFILE]` are reported as what
  they are: tokens PinballY expands itself, never a location to fix.
- API 1.2: operation `pinbally.detect` (Read, one mandatory `Path`) and a `PinballY` row in `components`, which
  shows the folder recorded as `PinballYRoot` in the pinball state and says so plainly while nothing is recorded.
  `Get-KitOperation` names both.
- Tests: `tests\pinball\New-PinballYTestInstall.ps1` builds a synthetic installation the way PinballY writes one
  (including the path examples inside the comments and one database it cannot parse), 29 engine tests and 9 API
  tests, among them that a read writes nothing and answers twice with the same words.
- Pinball: `pinball\modules\PinballYRetarget.ps1` gives a copied installation the paths of this machine. It takes
  pairs `Old=New` (a whole drive `C:=D:` included), plans them line by line over `Settings.txt` and the INI files
  inside the install, and writes only what (a) does not resolve here, (b) is a path and not a comment, a token or a
  relative value, and (c) has a target that exists on this machine. The byte order mark, the CRLF endings and the
  padding around `=` survive untouched; `DefaultSettings.txt`, the rolling `Settings backup <date>.txt` copies and
  the HyperList databases are never candidates. A line whose content moved since the plan refuses the file instead
  of writing a line nobody approved, and the write is backed up with `New-KitBackup` beforehand.
- API 1.3: operation `pinbally.retarget` (Change, `Path` + `Map`, optional `BackupDir`). Dry run without `-Apply`,
  `NeedsUser` with `-Apply` alone, one approval text per file, the write only with `-Apply -Approved`; the second
  run answers `Skipped`. Refused means refused: no backup and no state entry. While PinballY or its overlay is
  running the write is refused, because the program rewrites its own settings when it closes.
- Tests: 29 engine tests and 10 API tests for the retarget, among them that a dry run changes neither a single byte
  of the installation nor the state file, that exactly the planned lines and no other line differ afterwards, that
  the same value on two lines of one INI is written on both, that two runs in the same second get two backups
  instead of overwriting one, and that `Restore-KitBackup` is the way back.

## [0.3.1] - 2026-09-26

For clients of the Kit API such as the agent harness: API 1.1 with the kit version in every result.

### Added
- API: every result carries `KitVersion` (the kit's `VERSION`), so a client over JSON or MCP can name the kit it
  talks to (#22). `Get-KitVersion`; the MCP server reports the same value as `serverInfo.version`.

### Changed
- `ApiVersion` is `1.1`: v0.3.0 added `backup.remove`, and `KitVersion` is new; no client breaks on major `1`
  (#21). `API.md` has a version table.
- API: `Apply` and `Approved` (any spelling) are refused as parameter names and never offered in the catalog, so a
  step parameter cannot be mistaken for the API switches or the MCP flags `apply` / `approved` (#23).
- `handoff/PROJECT-HANDOFF-v0.3.0.md`: handoff of the whole development up to v0.3.0.
- Website: TypeScript 7.0.2 (replaces Dependabot #16, whose build failed): `tsconfig.json` without `baseUrl`
  (removed in TypeScript 7, `paths` now relative) and `src/vite-env.d.ts` with the Vite client types, which
  TypeScript 7 needs for the CSS side-effect imports. Also type-checks with TypeScript 5.9.

## [0.3.0] - 2026-09-26

### Added
- **Cabinet migration A → B** (`core\modules\CabinetProfile.ps1`): `Export-KitCabinetProfile` writes one zip per
  suite (pinball, lightgun) with paths as placeholders, tokenized registry settings, PinUP emulator and playlist
  settings as `sqlite-settings.json`, RetroBat, TeknoParrot and Gunmote settings, and screens only as a
  suggestion; never ROMs, BIOS files or tables. `Import-KitCabinetProfile` checks before it changes, backs up
  before every write, writes nothing with `-WhatIf` and changes nothing on a second run; the manifest is treated
  as untrusted (path traversal, absolute paths and SIDs refused, `.reg` content remapped and allowlisted).
  `-AutoInstall` installs a missing ViGEmBus only after showing its plan (SHA-256, signature) and asking.
  `Start-Kit.cmd -ExportProfile -Suite ... [-ProfileDestination ...]`, `-ImportProfile <zip> [-WhatIf]
  [-AutoInstall]`.
- **Migrate mode** in the dashboard: export on cabinet A, choose the zip, dry run and import on cabinet B;
  approvals are shown to the person before an installer runs.
- **Kit API v1** (`API.md`, `api\`): one facade for GUI, CLI, tests and external clients such as an agent
  harness. `Invoke-KitOperation` returns an `OperationResult` (status, changes, backups, warnings, errors,
  approvals, duration, data); change operations are dry runs unless `-Apply`; plans that need a person's approval
  are declined and returned unless `-Approved`; only plain parameters are accepted (no script blocks, no security
  or test bindings); interactive steps stay in the wizards. The catalog (`Get-KitOperation`) is built from the step
  scripts. `api\Invoke-KitApi.ps1` serves other processes with exactly one JSON document on standard output (no
  network port), `-Anonymize` for anything sent to a cloud model. Migration operations appear automatically once
  `Export-/Import-KitCabinetProfile` exist. Contract tests in `tests\api\`.
- API operation `backup.remove` (dry run unless `-Apply`) and `Invoke-KitOperationIsolated`, which runs an
  operation hostless so no engine output reaches the caller's standard output.
- **MCP server over stdio** (`api\Start-KitMcpServer.ps1`): the Kit API as MCP tools for the agent harness and
  any other MCP client, without a network port (JSON-RPC 2.0, one message per line). Tools come from the API
  catalog; change tools are dry runs unless `apply=true`, approvals need `approved=true`, interactive steps are
  not offered. Results are anonymized unless `-NoAnonymize`; `-ReadOnly` offers only the read tools. Tests in
  `tests\api\Mcp.Tests.ps1` drive the server as a child process.
- API rules for the migration operations: `profile.export` without its own dry run is not run without `-Apply`;
  import rows that need a person or failed make the result not succeed; `AutoInstall` is refused unless the
  import can ask for approval (`-Approve`), so no installer runs past the person.
- `handoff/AGENT-HARNESS.md`: the boundary between the kit and a separate agent harness repository.
- **Desktop dashboard** (`Start-Kit.cmd` without switches, `gui\`): a WPF app on Windows PowerShell 5.1 (nothing
  to install) in the brand design (Night / Cream, Pixel Green, Retro Red, Crown Gold, mascot). Three modes:
  new cabinet (starts the pinball / lightgun wizards), migrate (placeholder until v0.3) and recover (backup
  list with check, dry-run restore, export, delete). The system status comes from the doctor, runs in the
  background and shows one row per area. A thin layer: every action is a Kit API operation (`status`,
  `backups.list`, `backup.check`, `backup.restore`, `backup.export`, `backup.remove`), so the dashboard and an
  agent see and do exactly the same.
  `Start-Kit.cmd -Demo` still runs the core demo; `-Doctor`, `-Backups`, `-SupportBundle` stay command-line tools.
- Each suite knows where its backups live (`Get-PinballBackupRoot`, `Get-LightgunBackupRoot`); the command
  line, the wizards' maintenance pages and the dashboard use them.
- `tools\Test-KitSyntax.ps1` checks every `*.xaml` for well-formed XML.
- Structured step results: `Invoke-KitStep` returns `Duration`, `Changed`, `Changes`, `Backups`, `Warnings`,
  `Errors` and `Log` next to the status. Text rewrites, registry writes and imports, database updates, zip
  backups and the lightgun / screen file backups report themselves (`Add-KitStepChange`, `Add-KitStepBackup`).
  Both wizards log one summary line per step (changes, backups, duration) plus the backup paths.

### Changed
- A running Steam client no longer blocks the lightgun steps: Steam is only checked before the kit writes Steam's
  own files (step 5, `config.vdf`) and before restoring a Steam or zip backup (`Get-LightgunProcessName
  -IncludeSteam`, `Assert-/Test-LightgunProcessesClosed -IncludeSteam`).
- Lightgun step 11: its help block was ignored by PowerShell (a line started with `.parrot`); `Get-Help` and the
  API catalog show its description again.
- GitHub Actions: checkout 7, setup-node 7, upload-artifact 7, attest-build-provenance 4, configure-pages 6,
  deploy-pages 5, upload-pages-artifact 5 (all on Node 24; the inputs the workflows use are unchanged).
  Pages builds on Node 22 like CI.
- Website: react / react-dom 19.3.0, vite 8.3.0 with @vitejs/plugin-react 6.1.1, tailwindcss and
  @tailwindcss/vite 4.3.3, @types/node 22.20.4. Replaces Dependabot PRs #4-#13, which updated pairs one side at
  a time (react without react-dom, @tailwindcss/vite without tailwindcss) or could not build alone (vite 8 and
  plugin-react 6 need each other).
- Dependabot groups packages that must move together and skips @types/node majors beyond the Node runtime.

## [0.2.0] - 2026-09-26

### Added
- **Maintenance page** in both wizards (last page): health check, backup list with check / restore / export /
  delete, and the support bundle, without the command line. A restore follows the dry-run switch and asks first.
- **Doctor** (`Start-Kit.cmd -Doctor`): read-only health check with OK / INFO / WARN / ERROR per area. System
  (Windows build, PowerShell, 64-bit, elevation, file system, download marks), step states of both suites,
  pinball (build, prerequisites, COM registration, build folder rights) and lightgun (RetroBat, DolphinBar mode,
  refresh rates, ViGEmBus, Gunmote and its autostart, Steam blacklist, automation folder ACL and hooks).
  A missing part is an error only once that suite's setup was started.
- **Recovery** (`Start-Kit.cmd -Backups`, `core\Start-KitTools.ps1`): lists zip backups and `<file>.bak_*` copies,
  checks zips against their SHA-256 manifest, restores file copies (the current file is saved first as
  `.bak_recovery_*`), restores zip backups into named roots, exports with `SHA256SUMS.txt`, deletes on request.
- **Support bundle** (`Start-Kit.cmd -SupportBundle`): anonymized zip with doctor report, environment, step
  states and the newest logs; profile paths, user and computer names, SIDs, private IPs, e-mail addresses and
  other accounts' profile folders are replaced.
- `VERSION` file as the single source of the kit version; the module manifests are checked against it.
- GitHub Actions CI (`.github/workflows/ci.yml`, replaces `checks.yml`): depersonalization scan, static checks, Pester tests on
  Windows PowerShell 5.1, package build with integrity check, website build.
- Release workflow (`.github/workflows/release.yml`): tag check against `VERSION`, full test run, release zip,
  `SHA256SUMS.txt`, build provenance attestation, GitHub release with notes from this changelog.
- `tools/Test-KitSyntax.ps1`: parse check for every PowerShell file, UTF-8 BOM check for files with non-ASCII
  text (required by Windows PowerShell 5.1), manifest version check and a "local only" guard (network APIs only
  in `core/modules/Download.ps1`).
- `tools/Test-ReleasePackage.ps1`: checks a release zip (checksum, required files, no runtime output or private
  files, safe entry paths, version, depersonalization of the shipped content).
- `.github/workflows/pages.yml`: manual GitHub Pages deployment of the website.
- Issue templates, pull request template with the step Definition of Done, Dependabot for Actions and the website.
- `ARCHITECTURE.md` and `ROADMAP.md`.

### Changed
- Lightgun wizard: the pages for steps 10-14 carry their step numbers (they were labelled 9-13).
- i18n tables are validated with `Import-LocalizedData`, like the kit loads them (`Import-PowerShellDataFile`
  refuses files of their size).
- `tools/New-ReleasePackage.ps1` reads the version from `VERSION` (zip name `frieds-retrogaming-kit-vX.Y.Z.zip`),
  packages only files tracked by git, writes zip entries with `/` and creates `SHA256SUMS.txt`.
- `tools/Assemble-LaunchPack.ps1` takes the zip name and version from `VERSION` and copies `SHA256SUMS.txt`.
- README (English and German): feature status table and the lightgun quickstart in three phases including
  steps 10-14; lightgun guides list the real emulator status.

### Fixed
- CI on Windows: the fixtures' synthetic drives E and X are provided with `subst`, and three tests that relied
  on running without elevation now set the folder owner explicitly (first Windows run: 378/385 passed; the
  seven failures were test environment assumptions, not product bugs).
- `tools/Assemble-LaunchPack.ps1` was saved without UTF-8 BOM (umlauts, dashes and emoji were garbled under
  Windows PowerShell 5.1) and lost every markdown backtick in the generated launch pack README.

## [0.1.0] - 2026-09-26

First public release.

### Added
- Shared core (`core\`): logging, state, Test → Invoke → Verify steps, i18n (English, German), elevation, SQLite
  via `winsqlite3.dll`, text and registry rewriting, process guards, zip backups with manifest and SHA-256,
  shortcuts, verified downloads from allowlisted official sources.
- Virtual pinball suite (`pinball\`, steps 1-9): detect, target, prerequisites, copy, relocate (database, text
  files, registry, shortcuts), COM registration, Future Pinball/BAM setup, screens, finish; WinForms wizard.
- Wiimote lightgun suite (`lightgun\`, steps 1-14): detect, DolphinBar hardware, ViGEmBus, Gunmote, interference
  fixes, Gunmote layouts, RetroBat settings, profile automation, measured verification, TeknoParrot profiles,
  game lists, Demul + DemulShooter, Model 2 / Supermodel, guided DuckStation / PCSX2 check; wizard.
- Bilingual documentation, website and depersonalization scanner.

[Unreleased]: https://github.com/kburna243/frieds-retrogaming-kit/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/kburna243/frieds-retrogaming-kit/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/kburna243/frieds-retrogaming-kit/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/kburna243/frieds-retrogaming-kit/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/kburna243/frieds-retrogaming-kit/compare/v0.9.0...v1.0.0
[0.9.0]: https://github.com/kburna243/frieds-retrogaming-kit/compare/v0.8.0...v0.9.0
[0.8.0]: https://github.com/kburna243/frieds-retrogaming-kit/compare/v0.7.0...v0.8.0
[0.7.0]: https://github.com/kburna243/frieds-retrogaming-kit/compare/v0.6.0...v0.7.0
[0.6.0]: https://github.com/kburna243/frieds-retrogaming-kit/compare/v0.5.0...v0.6.0
[0.5.0]: https://github.com/kburna243/frieds-retrogaming-kit/compare/v0.4.2...v0.5.0
[0.4.2]: https://github.com/kburna243/frieds-retrogaming-kit/compare/v0.4.1...v0.4.2
[0.4.1]: https://github.com/kburna243/frieds-retrogaming-kit/compare/v0.4.0...v0.4.1
[0.4.0]: https://github.com/kburna243/frieds-retrogaming-kit/compare/v0.3.1...v0.4.0
[0.3.1]: https://github.com/kburna243/frieds-retrogaming-kit/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/kburna243/frieds-retrogaming-kit/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/kburna243/frieds-retrogaming-kit/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/kburna243/frieds-retrogaming-kit/releases/tag/v0.1.0
