# Changelog

All notable changes to Fried's Retrogaming Kit are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).
The version lives in the [`VERSION`](VERSION) file; the release workflow publishes a release for every tag `vX.Y.Z`
that matches it.

## [Unreleased]

### Added
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

[Unreleased]: https://github.com/kburna243/frieds-retrogaming-kit/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/kburna243/frieds-retrogaming-kit/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/kburna243/frieds-retrogaming-kit/releases/tag/v0.1.0
