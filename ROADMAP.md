# Roadmap

Direction for the next versions. Order matters: quality and release engineering first, then tools that build
on the existing backup and verification engine, new integrations last. Items move to [CHANGELOG.md](CHANGELOG.md)
when they ship.

## v0.2 — release quality (released)

- [x] CI on every push and pull request: depersonalization, static checks, Pester on Windows PowerShell 5.1,
      package build and integrity check, website build
- [x] One version source (`VERSION`), release workflow with `SHA256SUMS.txt` and build provenance attestation
- [x] README, quickstart (lightgun steps 10-14) and emulator status in sync with the code
- [x] `ARCHITECTURE.md`, step Definition of Done, issue and pull request templates
- [x] **Doctor** — `Start-Kit.cmd -Doctor`: read-only OK / INFO / WARN / ERROR per area (system, pinball,
      lightgun, security)
- [x] **Recovery** — list, check, restore, export and delete the kit's backups (`Start-Kit.cmd -Backups`,
      `core\Start-KitTools.ps1`)
- [x] **Support bundle** — `Start-Kit.cmd -SupportBundle`: anonymized zip with doctor report, environment, step
      states and logs
- [x] Doctor, backups and support bundle as a maintenance page in both wizards
- [ ] Restoring the registry part of a zip backup from the recovery tool (today: files only; the pinball wizard
      restores its own registry backups)

## Desktop app (WPF, Windows PowerShell 5.1)

- [x] Structured step results (`Duration`, `Changes`, `Backups`, `Warnings`, `Errors`) — no UI parses output
- [x] Dashboard with three modes and the system status from the doctor; recover mode (backups)
- [x] Kit API v1 (`API.md`): operation catalog, `OperationResult`, dry run by default, approvals, JSON over stdio
- [x] Dashboard uses the API only
- [ ] Operation history (append-only, read-only for clients)
- [x] MCP server over stdio on top of the API (for the separate agent harness and other agents)
- [ ] Migrate mode on top of the migration engine (export → analyse → compatibility → import → verify)
- [ ] Setup mode: the wizard steps as WPF pages with step result cards, replacing the WinForms wizards page by page
- [ ] Brand fonts (Playfair Display, Inter, OFL) shipped with the app instead of the Windows fallbacks

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
