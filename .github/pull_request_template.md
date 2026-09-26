## What and why

<!-- What does this change, and which problem does it solve? Link the issue if there is one. -->

## How it was tested

<!-- Commands run, Windows version, hardware if relevant. -->

## Checklist

- [ ] `tools\Test-Depersonalized.ps1` reports 0 findings
- [ ] `tools\Test-KitSyntax.ps1` reports 0 problems
- [ ] `tests\Run-Tests.ps1` passes (Windows PowerShell 5.1)
- [ ] English and German documentation updated (`*.md` and `*.de.md`) where user-facing behavior changed
- [ ] `CHANGELOG.md` has an entry under *Unreleased*

### For a new or changed step (Definition of Done, see CONTRIBUTING.md)

- [ ] Test, Invoke and Verify blocks; Verify measures the real state
- [ ] Dry run (`-WhatIf`) changes nothing and shows the plan
- [ ] Backup before every change, rollback path documented
- [ ] Idempotent: a second run is skipped
- [ ] Log output and texts in `i18n\en-US.psd1` and `i18n\de-DE.psd1`
- [ ] Pester tests with synthetic fixtures (no real paths, no copyrighted files)
