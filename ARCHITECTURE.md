# Architecture

This document is the map for contributors: how the kit is layered, where things live and which contract every
step follows. User documentation lives in [`docs/`](docs/); the security model in [SECURITY.md](SECURITY.md).

## Layers

```text
                 ┌──────────────────────────────────────────────┐
                 │ Start-Kit.cmd · Start-Pinball.cmd ·          │   launchers: full path to Windows
                 │ Start-Lightgun.cmd                           │   PowerShell 5.1, -ExecutionPolicy Bypass
                 └──────────────────────┬───────────────────────┘
                                        │
                 ┌──────────────────────▼───────────────────────┐
                 │ Dashboard: gui\Start-KitGui.ps1 (WPF)        │   new · migrate · recover, system status
                 └──────────────────────┬───────────────────────┘
                                        │
                 ┌──────────────────────▼───────────────────────┐
                 │ Wizards: pinball\ui\Wizard.ps1,              │   WinForms UI, no logic of its own:
                 │          lightgun\ui\Wizard.ps1              │   runs the step scripts in order
                 └──────────────────────┬───────────────────────┘
                                        │
                 ┌──────────────────────▼───────────────────────┐
                 │ Step scripts: <suite>\steps\NN-Name.ps1      │   one stand-alone script per step,
                 │                                              │   -WhatIf, -StatePath, -Culture
                 └──────────────────────┬───────────────────────┘
                                        │
          ┌─────────────────────────────┼─────────────────────────────┐
          │                             │                             │
┌─────────▼──────────┐       ┌──────────▼──────────┐       ┌──────────▼──────────┐
│ pinball\modules    │       │ lightgun\modules    │       │ core\modules        │
│ Build · Copy ·     │       │ Detect · Hardware · │       │ Log · State · Step ·│
│ Relocate ·         │       │ ViGEm · Gunmote ·   │       │ I18n · Elevation ·  │
│ Register · Screens │       │ Steam · Layouts ·   │       │ Sqlite · Text ·     │
│ Dependencies ·     │       │ EsSettings ·        │       │ Registry ·          │
│ FpBam · Finish     │       │ Automation · Verify │       │ Processes · Backup ·│
│                    │       │ TeknoParrot · Demul │       │ Links · Download ·  │
│                    │       │ Model2Supermodel ·  │       │ Ui                  │
│                    │       │ DuckStationPcsx2    │       │                     │
└─────────┬──────────┘       └──────────┬──────────┘       └──────────▲──────────┘
          │                             │                             │
          └───────── both suites build on the core only ──────────────┘
                                        │
                 ┌──────────────────────▼───────────────────────┐
                 │ User-supplied software (never bundled):      │
                 │ PinUP Popper, VPX, VPinMAME, B2S, FlexDMD,   │
                 │ Future Pinball · RetroBat, MAME, TeknoParrot,│
                 │ Demul, DemulShooter, Model 2, Supermodel,    │
                 │ DuckStation, PCSX2, Gunmote                  │
                 └──────────────────────────────────────────────┘
```

| Folder | Content |
| :--- | :--- |
| `core\` | `RetroCabinetKit.Core` module. Sub-modules in `modules\*.ps1` are dot-sourced into one module scope; public functions are named `Verb-Kit*`, private helpers never contain `-Kit` and are not exported. `download-allowlist.psd1` lists the only download sources. |
| `pinball\`, `lightgun\` | One module per suite (`RetroCabinetKit.Pinball`, `RetroCabinetKit.Lightgun`) with `modules\`, numbered `steps\` and a `ui\Wizard.ps1`. Suites depend on the core, never on each other. |
| `i18n\` | `en-US.psd1` (fallback) and `de-DE.psd1`, same keys (checked by `tests\core\I18n.Tests.ps1`). |
| `tests\` | Pester 3.4 tests per suite with synthetic fixtures; `tests\local\` runs against real files that only exist on a developer machine (`tests\fixtures-local\`, git-ignored). |
| `api\` | Kit API v1 (`API.md`): `RetroCabinetKit.Api` (`Invoke-KitOperation`, `Get-KitOperation`, `OperationResult`) `Invoke-KitApi.ps1` (one-shot JSON over stdio for other processes) and `Start-KitMcpServer.ps1` (MCP server over stdio). The only entry point for external clients; dry run unless `-Apply`, approvals only with `-Approved`. |
| `gui\` | `RetroCabinetKit.Gui` module and `Start-KitGui.ps1`: the WPF dashboard (views in `Views\*.xaml`, brand theme in `Themes\Brand.xaml`, mascot in `Assets\`). It only maps engine results to the view and calls the engine; texts come from `i18n\` via `Tag="i18n:<key>"`. |
| `core\Start-KitTools.ps1` | Doctor (`Invoke-KitDoctor` over `Get-KitSystemCheck`, `Get-PinballDoctorCheck`, `Get-LightgunDoctorCheck`), recovery (`Get-KitBackup`, `Test-KitBackup`, `Restore-KitFileBackup`, `Export-KitBackup`) and support bundle (`Export-KitSupportBundle`). `Start-Kit.cmd -Doctor / -Backups / -SupportBundle` forwards here. Doctor checks only read. |
| `tools\` | Repository tooling: depersonalization scan, static checks, release package build and check, launch pack. |
| `site\` | Website (Vite/React, GitHub Pages). Not part of the release zip. |

## The step contract

Every change to a machine happens inside a step created with `New-KitStep` and run by `Invoke-KitStep`:

```powershell
New-KitStep -Name 'lightgun-10-tp-bind' `
    -Test   { <# preconditions: $true = ready to run (e.g. RetroBat found, guarded programs closed) #> } `
    -Invoke { <# change the machine; backup first #> } `
    -Verify { <# measure the real state; $true only if the target state is really there #> }
```

`Invoke-KitStep` (`core\modules\Step.ps1`) runs them in this order:

1. **Verify** first: already in the target state → `Skipped` (this makes every step idempotent).
2. **Test**: preconditions not met → `NeedsUser` (something only the user can fix).
3. `-WhatIf` → `Skipped` as a dry run; nothing is written, not even the state file.
4. **Invoke**, then **Verify** again → `Done` only if the measurement confirms it, otherwise `Failed`
   (an exception is `Failed` as well).

A step never reports success from assumptions.

The result (`RetroCabinetKit.StepResult`) is structured, so a front end never parses output:

| Field | Content |
| :--- | :--- |
| `Name`, `Status`, `WhatIf`, `Message`, `Error` | outcome as above |
| `Duration` | run time (`TimeSpan`) |
| `Changed`, `Changes` | what was written: `Kind` (File, Registry, Database, Task, Setting), `Target`, `Detail` |
| `Backups` | backups made during the step (kit zips and `<file>.bak_*` copies) |
| `Warnings`, `Errors`, `Log` | the step's own log lines |

Writers report themselves while a step runs (`Add-KitStepChange`, `Add-KitStepBackup`); the core already does
for text rewrites, registry values and imports, database updates and backups. Outside a step the calls do nothing.

### Definition of Done for a step

| | Requirement |
| :--- | :--- |
| Test | Checks the preconditions; a missing one is `NeedsUser` with a clear message, never a crash. |
| Preview | Shows the plan (files, registry values, coordinates) before anything is written. |
| WhatIf | `-WhatIf` writes nothing, not even state. |
| Backup | Everything that is changed is backed up first (`New-KitBackup`: zip + manifest + SHA-256). |
| Invoke | Writes atomically where the core offers it; refuses to write while programs that hold the files are open. |
| Verify | Measures the result; a second run is `Skipped` (idempotent) and a step only turns green after Verify. |
| Rollback | A restore path exists (`Restore-KitBackup`) and is documented. |
| Logging | All actions in the kit log, no personal data. |
| Texts | Every user-facing text in `i18n\en-US.psd1` and `i18n\de-DE.psd1`. |
| Tests | Pester tests with synthetic fixtures, including the dry run and the second run. |

## Principles

- **Local only.** No telemetry, no analytics, no accounts, no cloud, no tracking, no ROM collection. The only
  network code is `core\modules\Download.ps1`: HTTPS, hosts from `core\download-allowlist.psd1`, Authenticode
  and SHA-256 checks before anything runs. `tools\Test-KitSyntax.ps1` fails CI if a network API appears anywhere
  else in `core\`, `pinball\` or `lightgun\`.
- **User-supplied assets.** The kit ships no ROMs, BIOS files, tables, builds or closed-source tools.
- **Zero dependencies.** Windows PowerShell 5.1 and Windows built-ins (`winsqlite3.dll`, WinForms, Task
  Scheduler) only.
- **Never destructive.** Files are moved to review folders, never deleted; configurations are backed up first.
- **Depersonalized.** No real paths, host names, IPs or e-mail addresses in the repository
  (`tools\Test-Depersonalized.ps1`, enforced in CI and on the release zip).

## Runtime data

| Data | Location |
| :--- | :--- |
| State of finished steps | `install-state.json` (path per suite, `-StatePath` overrides) |
| Logs | `logs\` below the kit folder |
| Backups | zip archives with `manifest.json` (SHA-256 per file) |
| Profile automation | `%ProgramData%\RetroCabinetKit\lightgun\` (admin-only ACL), scheduled tasks `RetroCabinetKit Gunmote Profile *` |

None of this is ever committed or packaged: `.gitignore` excludes it and `tools\Test-ReleasePackage.ps1` fails
a release zip that contains it.

## Quality gates and release

```text
push / pull request                       tag vX.Y.Z (= VERSION)
────────────────────                      ──────────────────────
Test-Depersonalized  (ubuntu, pwsh 7)     same gates as CI
Test-KitSyntax       (Windows PS 5.1)       ↓
Run-Tests (Pester 3.4, Windows PS 5.1)    New-ReleasePackage → zip + SHA256SUMS.txt
New-ReleasePackage + Test-ReleasePackage    ↓
site: npm ci && npm run build             Test-ReleasePackage
                                            ↓
                                          build provenance attestation
                                            ↓
                                          GitHub release (notes from CHANGELOG.md)
```

The version lives only in `VERSION`; the three module manifests must carry the same `ModuleVersion`
(checked by `tools\Test-KitSyntax.ps1` and `tools\New-ReleasePackage.ps1`).
