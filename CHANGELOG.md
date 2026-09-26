# Changelog

All notable changes to Fried's Retrogaming Kit are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).
The version lives in the [`VERSION`](VERSION) file; the release workflow publishes a release for every tag `vX.Y.Z`
that matches it.

## [Unreleased]

### Added
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
- `tools/New-ReleasePackage.ps1` reads the version from `VERSION` (zip name `frieds-retrogaming-kit-vX.Y.Z.zip`),
  packages only files tracked by git, writes zip entries with `/` and creates `SHA256SUMS.txt`.
- `tools/Assemble-LaunchPack.ps1` takes the zip name and version from `VERSION` and copies `SHA256SUMS.txt`.
- README (English and German): feature status table and the lightgun quickstart in three phases including
  steps 10-14; lightgun guides list the real emulator status.

### Fixed
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

[Unreleased]: https://github.com/kburna243/frieds-retrogaming-kit/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/kburna243/frieds-retrogaming-kit/releases/tag/v0.1.0
