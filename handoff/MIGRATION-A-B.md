# Handoff: cabinet migration A → B (simulated)

> **Kurz auf Deutsch:** Ziel ist ein Migrationsprofil: Einstellungen von Kabinett A exportieren und auf Kabinett B
> einspielen, ohne ROMs, BIOS, Tische oder Medien. Mangels Platz und zweitem PC wird alles **simuliert**: zwei
> synthetische Kabinette (wenige KB) im Temp-Ordner, andere Laufwerksbuchstaben per `subst`, Registry nur unter
> einem Test-Schlüssel, Monitore injiziert. Der Rest dieses Dokuments ist für den umsetzenden Agenten (Englisch,
> wie der Code).

This document is self-contained. Read it fully, then read `ARCHITECTURE.md` and `CONTRIBUTING.md` before
writing code. Roadmap item: `ROADMAP.md` → *v0.3 — cabinet migration*.

---

## 1. Goal

Two commands (core, public names follow `Verb-Kit*`):

```powershell
Export-KitCabinetProfile -Destination <zip> [-Suite Pinball, Lightgun]    # on cabinet A, read-only
Import-KitCabinetProfile -Path <zip> [-RootMap @{...}] [-WhatIf]          # on cabinet B, a guided step
```

A **profile** carries the *settings* the kit manages, never the games. Moving the build itself stays the job of
the existing pinball steps 4 (copy) and 5 (relocate, mode `Rebuild`). The profile makes cabinet B *configured*
the way A was: same RetroBat gun settings, same Gunmote layouts, same TeknoParrot bindings, same pinball
registry settings — with every path rewritten to B's folders.

Done means: a profile exported from simulated cabinet A, imported into simulated cabinet B with other drive
letters and other folder names, leaves B in a state where the **doctor** reports the same OK rows as on A for
everything the profile covers, and a second import changes nothing.

## 2. Non-negotiable rules (from the repository)

- Windows PowerShell 5.1, no dependencies, UTF-8 **with BOM** for any `.ps1/.psm1/.psd1` containing non-ASCII.
- Import is a set of steps built with `New-KitStep` (Test → Invoke → Verify, see `ARCHITECTURE.md`):
  Verify first (already there → `Skipped`), `-WhatIf` writes nothing (not even state), backup with
  `New-KitBackup` before every change, a second run is `Skipped`.
- Export only reads. It never includes: ROMs, BIOS, tables, media, databases (`PUPDatabase.db`), executables,
  logs, scheduled tasks, ACLs, SIDs, user or computer names.
- The manifest of a profile is **untrusted input** on import (someone else's zip): every target path must lie
  inside roots the user named (`Test-KitPathUnder`), every `.reg` text passes `Assert-KitRegText` against an
  allowlist of roots, exactly like `Restore-KitBackup` does. Reuse it; do not write a second restore engine.
- No network code (the CI guard in `tools\Test-KitSyntax.ps1` enforces it).
- Every user-visible text in `i18n\en-US.psd1` **and** `i18n\de-DE.psd1` (same keys, a test checks it).
- Tests: Pester 3.4 syntax, synthetic fixtures only, `tools\Test-Depersonalized.ps1` must stay at 0 findings
  (no literal user paths, private IPs or e-mail addresses in tests; build such strings at run time).

## 3. What goes into a profile

Paths are stored **tokenized**, so nothing machine-specific survives the export:

| Token | Meaning on A (export) | Resolved on B (import) |
| :--- | :--- | :--- |
| `{PinballRoot}` | pinball `TargetRoot` from `pinball\install-state.json` | `-RootMap`, else B's pinball state |
| `{RetroBatRoot}` | lightgun `RetroBatRoot` | `-RootMap`, else B's lightgun state |
| `{GunmoteDir}` | `Find-LightgunGunmote` | `Find-LightgunGunmote` on B |
| `{SteamDir}` | `Get-LightgunSteamPath` | same on B |
| `<USERPROFILE>` etc. | must not occur — export fails if `ConvertTo-KitAnonymousText` would change any text | — |

| Suite | Item | Source (read it, do not guess) | On import |
| :--- | :--- | :--- | :--- |
| Pinball | Registry: Future Pinball, Visual PinMAME, B2S, Visual Pinball | `Get-PinballRegistryImportRoot`, export with `Export-KitRegistryKey` | Reuse the rebuild path: write the `.reg` exports into a **kit backup zip** (`New-KitBackup -Registry`) and hand it to `Invoke-PinballRelocation -Mode Rebuild -RegistryBackup` — it already rewrites old → new root and imports through the allowlist. |
| Pinball | Screen layout (`ScreenRes.txt`, `VPinballX.ini [Player]`, `PinUpPlayer.ini`, `DmdDevice.ini`) | `pinball\modules\Screens.ps1` | **Proposal only.** Monitors differ between cabinets: map by *role* (Playfield, Backglass, DMD …), never by device name, and let step 8's diff/Keep logic decide. If roles cannot be mapped, report and skip. |
| Lightgun | `es_settings.cfg` keys the kit owns (`use_guns`, `disableautocontrollers`, emulator choices, `teknoparrot["<rom>"]…`) | `lightgun\modules\EsSettings.ps1`, steps 7, 10, 12, 13 | Merge the kit's keys only (same plan/apply functions the steps use); foreign keys stay untouched. |
| Lightgun | Gunmote layouts (the four `RCK …` layouts in `Keymaps\Keymaps.json`) | `lightgun\modules\Layouts.ps1` | Through the step-6 plan in `Keep` mode (own layouts identical → skipped). Program paths inside the layouts are rewritten by token. |
| Lightgun | TeknoParrot `UserProfiles\*.xml` bindings of gun games | `lightgun\modules\TeknoParrot.ps1` | Bindings only; `GamePath` is rewritten by token and only set when the file exists on B (same rule as step 10). |
| Lightgun | Demul / DemulShooter / Supermodel settings the kit wrote | `Demul.ps1`, `Model2Supermodel.ps1` | Same INI plan functions (`Get-LightgunIniPlan`, `Set-LightgunIniValue`). |
| Both | Selected state values (`RetroBatRoot`, `TargetRoot`, `GunmoteDir`, layout titles) | `install-state.json` | Written to B's state only **after** the step verified; roots come from B, never from the profile. |
| — | Scheduled tasks, ViGEmBus, Steam blacklist, automation folder | — | **Never exported.** They are bound to B's user and security context. After import, tell the user to run lightgun steps 3, 4, 5 and 8 (and the doctor lists them as missing anyway). |

## 4. Profile format

```
cabinet-profile_<yyyyMMdd-HHmmss>.zip
├── profile.json            Format, KitVersion (VERSION), Created, Suites, Roots (token → "present"/"absent"),
│                           Items[]: { Suite, Kind = File|Ini|Registry|State, Token path, Sha256, Size }
├── files/<suite>/<token path with / >
└── registry/<nnn>.reg      UTF-16 LE, as Export-KitRegistryKey writes it
```

- `profile.json` never contains an absolute path. A test asserts: no drive-letter path, no UNC path, no SID.
- Size budget: warn above 10 MB (a profile is settings, not a build).
- Import refuses a profile whose `Format` is newer than it knows, and warns when `KitVersion` differs.

## 5. Simulation (limited disk space, one PC)

Everything is synthetic and small (target: **< 5 MB** during a full test run, all below `$TestDrive` or
`$env:TEMP`, removed afterwards). No real build, no real RetroBat, no second computer.

1. **Two cabinets as folders.** Reuse the generators that already exist:
   - `tests\pinball\New-PinballTestBuild.ps1 -Root <A>\Pinball -OldRoot <A-root>` (database via
     `tests\fixtures\New-KitTestPupDatabase.ps1`)
   - `tests\lightgun\New-LightgunTestRetroBat.ps1 -Root <A>\RetroBat`, then
     `New-LightgunTestTeknoParrot.ps1 -Root <A>\RetroBat` and `New-LightgunTestGunmote.ps1 -Gunmote <A>\Gunmote -Steam <A>\Steam`
   - Cabinet B: the same generators into `<B>`, then *un-configure* B (fresh `es_settings.cfg`, Gunmote with only
     the mouse layout) so the import has work to do.
2. **Different drive letters.** Map A and B to two free letters with `subst` (as the CI does for the fixtures'
   E and X): pick letters that do not exist (`Test-Path "${l}:\"`), `subst P: <A>` / `subst Q: <B>`, and
   `subst /d` in a `finally`. PowerShell 5.1 resolves paths only on existing drives, so this matters. Tests must
   also pass with plain folders (no subst) — tokens make drive letters irrelevant.
3. **Registry.** Never real keys. Every function that touches the registry takes `-RegistryRoots` (the pinball
   relocation already does: see `tests\pinball\Relocate.Tests.ps1`, key `HKCU:\Software\retro-cabinet-kit-test-*`).
   Use one test key per cabinet: `...-test-cabA`, `...-test-cabB`; remove both in `AfterAll`/`finally`.
4. **Monitors.** Inject them (`-Monitors`, like the pinball wizard tests): A = 1920×1080 playfield +
   1280×1024 backglass; B = 3840×2160 playfield + 1920×1080 backglass + 1280×390 DMD. Expect a *proposal*, not
   a blind copy.
5. **User and machine.** Export on "A" with a fake `-UserName`, `-ComputerName`, `-UserProfile` (the
   anonymization functions accept them) and assert none of them appears anywhere in the zip.
6. **Optional real run (no extra disk for a VM):** Windows Sandbox (Windows 10/11 Pro) is a throw-away
   Windows that uses almost no disk. A `.wsb` file can map the kit folder read-only and a small writable folder
   for the profile. Useful for one manual end-to-end check of the UI; not required for CI.

## 6. Tests (minimum)

`tests\core\CabinetProfile.Tests.ps1` (core format) and `tests\lightgun\` / `tests\pinball\` suites for the parts:

1. Export from A: zip contains `profile.json`, the expected items, **no absolute path, no user/computer name,
   no SID**, no database, no executable, no log.
2. Export only reads: file hashes and registry values of A are unchanged afterwards.
3. Import into B with `-WhatIf`: nothing on B changes, not even `install-state.json`; the plan lists every item.
4. Import into B: every item is written with B's roots; `New-KitBackup` zips exist for every changed file;
   the doctor rows covered by the profile are OK on B.
5. Second import: every step `Skipped`, no new backup.
6. Hostile profile: a `profile.json` with `..\..\Windows\…`, an absolute path, or a `.reg` for
   `HKLM\SYSTEM\…` is refused **before** the first write (reuse the `Restore-KitBackup` / `Assert-KitRegText`
   pattern and its tests as the model).
7. Missing counterpart on B (no TeknoParrot, no Gunmote): those items are `NeedsUser` with a clear message, the
   rest still imports.
8. Different monitors: screen layout becomes a proposal mapped by role; unmappable roles are reported, not written.

## 7. Suggested order (small PRs, each green in CI)

1. `core\modules\CabinetProfile.ps1`: format, tokenizer (`ConvertTo-KitProfilePath` / `ConvertFrom-KitProfilePath`),
   manifest validation, export skeleton + tests 1, 2, 6.
2. Lightgun export/import items (es_settings keys, layouts, TeknoParrot, INI) + tests 3–5, 7.
3. Pinball items: registry via the existing rebuild path; screens as proposal + test 8.
4. UI: an "Export profile / Import profile" section on the maintenance page (`core\modules\CarePage.ps1`,
   `New-KitCarePage`), import runs through the wizard's dry-run switch and confirmation.
5. Docs: README (EN/DE) quickstart, CHANGELOG, ROADMAP tick, `ARCHITECTURE.md` row.

## 8. Verify locally before every push

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-Depersonalized.ps1   # 0 findings
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-KitSyntax.ps1        # 0 problems
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1             # all green, none skipped
```

CI runs the same on every push (`.github/workflows/ci.yml`, Windows PowerShell 5.1 + Pester 3.4). The CI
runner is elevated and has only drives C and D: do not rely on a non-elevated user or extra drives (set folder
owners explicitly, create drives with `subst`) — see the commit history of `tests\lightgun\Automation.Tests.ps1`.

## 9. Open questions for the owner (ask, do not guess)

- Should the profile include the PinUP Popper **database settings** that are not paths (emulator entries,
  playlists)? Today the database moves with the build; a settings-only export would need a schema decision.
- Should an import on B also *install* missing prerequisites (ViGEmBus, VC++), or only report them?
- Is one profile for both suites right, or one per suite?
