# Roadmap

Direction for the next versions. Order matters: quality and release engineering first, then tools that build
on the existing backup and verification engine, new integrations last. Items move to [CHANGELOG.md](CHANGELOG.md)
when they ship.

## v0.2 — release quality (in progress)

- [x] CI on every push and pull request: depersonalization, static checks, Pester on Windows PowerShell 5.1,
      package build and integrity check, website build
- [x] One version source (`VERSION`), release workflow with `SHA256SUMS.txt` and build provenance attestation
- [x] README, quickstart (lightgun steps 10-14) and emulator status in sync with the code
- [x] `ARCHITECTURE.md`, step Definition of Done, issue and pull request templates
- [ ] **Doctor** — one read-only command (`Start-Kit.cmd -Doctor`) that runs the Verify blocks of all suites
      and prints OK / WARN / ERROR per area (system, pinball, lightgun, security) without changing anything
- [ ] **Recovery center** — list, inspect, restore, export and delete the kit's backups (manifest, file count,
      registry keys), built on `Get-KitBackupManifest` and `Restore-KitBackup`
- [ ] **Support bundle** — `Export-KitSupportBundle`: summary, environment, displays, installed components,
      step states and logs in one zip, depersonalized automatically (same rules as `tools\Test-Depersonalized.ps1`)

## v0.3 — cabinet migration

- [ ] `Export-RetroCabinetProfile` / `Import-RetroCabinetProfile`: hardware profile, display layout, RetroBat
      configuration, lightgun profiles, pinball paths, registry settings and emulator settings from cabinet A
      to cabinet B — never ROMs, BIOS files or other copyrighted assets

## Later

- [ ] **Rumble / force feedback** — `lightgun\modules\Rumble.ps1` with one API (`Enable-`, `Disable-`, `Test-`,
      `Get-...RumbleStatus`) and emulator adapters (MAME, TeknoParrot, DemulShooter, DuckStation, PCSX2);
      tool choice (OutputHooker / MAMEHooker) still open
- [ ] **Hardware abstraction** — lightgun providers (Wiimote today; Sinden, Gun4IR, AimTrak later) behind one
      input layer, so emulator steps no longer assume Wiimote + Gunmote
- [ ] Code signing of the release scripts, signed `SHA256SUMS.txt`
- [ ] Further emulator integrations — only after the items above are stable

## Not planned

- Telemetry, analytics, accounts or any cloud service. The kit stays local only.
- Shipping or downloading ROMs, BIOS files, tables, builds or closed-source tools.
