# Contributing to Fried's Retrogaming Kit

Thank you for your interest in improving **Fried's Retrogaming Kit**! Whether you are reporting a bug, improving documentation, adding an emulator configuration, or translating guides, we welcome your help.

---

## Code of Conduct & Guiding Philosophy

- **User-Supplied Assets**: Never submit ROMs, BIOS files, copyrighted artwork, tables, or commercial software. The kit is strictly an open orchestration engine.
- **Official Upstream Sources Only**: Any third-party tools referenced must link to their official, authentic repositories or distribution channels.
- **Safety & Non-Destructive Operation**: All changes must preserve user configurations, provide backup paths, support dry-run (`-WhatIf`), and verify steps before reporting success.

---

## Development Standards

### 1. PowerShell 5.1 Compatibility
- All core engine scripts (`core\`, `pinball\`, `lightgun\`) must be compatible with **Windows PowerShell 5.1** (the default version included with Windows 10 and 11).
- We use Windows built-in `winsqlite3.dll` for SQLite operations to maintain a 100% zero-dependency architecture.

### 2. The Test-Invoke-Verify Pattern
Every wizard and installer step must adhere to the three-phase cycle:
```powershell
New-KitStep -Name 'my-feature' `
    -Test   { <# Validate preconditions: return true if ready to execute #> } `
    -Invoke { <# Execute modification: handle backups and state #> } `
    -Verify { <# Perform live measurement: return true only if verified working #> }
```
A step must **never** report completion based on assumptions—it must actively measure the desired state.
`Invoke-KitStep` runs **Verify first** (already done → `Skipped`), then **Test** (preconditions missing → `NeedsUser`),
then **Invoke** and **Verify** again (`Done` or `Failed`). See [ARCHITECTURE.md](ARCHITECTURE.md) for the full contract.

#### Definition of Done for a new or changed step
- [ ] **Test**: checks preconditions; a missing one yields `NeedsUser` with a clear message
- [ ] **Preview**: shows the plan (files, registry values, coordinates) before writing
- [ ] **WhatIf**: `-WhatIf` writes nothing, not even the state file
- [ ] **Backup**: everything changed is backed up first (`New-KitBackup`)
- [ ] **Invoke**: refuses to write while programs holding the files are open
- [ ] **Verify**: measures the result; a second run is `Skipped` (idempotent)
- [ ] **Rollback**: a restore path exists and is documented
- [ ] **Logging**: actions are logged without personal data
- [ ] **Localization**: texts in `i18n\en-US.psd1` **and** `i18n\de-DE.psd1`
- [ ] **Pester tests** with synthetic fixtures, including the dry run and the second run

### 3. Depersonalization Requirement (Mandatory)
Before opening a pull request, you **must** run the depersonalization scanner:
```powershell
powershell -ExecutionPolicy Bypass -File tools\Test-Depersonalized.ps1
```
The test must report **0 findings**. Never commit real local paths, private IP addresses, personal user profile directories, internal machine names, or API tokens. Example paths in documentation must strictly use synthetic examples permitted in `tools/depersonalized-allowlist.psd1` (such as `D:\Pinball`, `C:\RetroBat`, or `E:\Old Build`).

### 4. Bilingual Documentation & Localization
- All user-facing documentation in `docs/` and root README files must be maintained in both **English** (`*.md`) and **German** (`*.de.md`).
- German text must use proper umlauts (`ä`, `ö`, `ü`, `ß`).
- Note: Avoid editing `i18n\*.psd1` directly if active feature branches are touching them; mention any translation corrections in your pull request description instead.

### 5. Running Checks and Tests Locally
These are the same checks CI runs on every push and pull request (`.github/workflows/ci.yml`):
```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-Depersonalized.ps1   # 0 findings
powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-KitSyntax.ps1        # parse, UTF-8 BOM, versions, local-only guard
powershell -NoProfile -ExecutionPolicy Bypass -File tests\Run-Tests.ps1             # Pester 3.4, Windows PowerShell 5.1
```
PowerShell files containing non-ASCII characters (umlauts, dashes, emoji) must be saved as **UTF-8 with BOM**;
Windows PowerShell 5.1 reads files without BOM as ANSI. Network APIs are only allowed in `core\modules\Download.ps1`.

### 6. Versioning & Releases
- The version lives only in [`VERSION`](VERSION). The `ModuleVersion` of the three module manifests
  (`core`, `pinball`, `lightgun`) must match it — CI checks this.
- Add every user-visible change to the *Unreleased* section of [CHANGELOG.md](CHANGELOG.md).
- To release: move the *Unreleased* entries to a new version section, update `VERSION` and the manifests, merge,
  then push a tag `vX.Y.Z`. The release workflow runs all checks, builds the zip with `SHA256SUMS.txt`, attests
  its build provenance and publishes the GitHub release.
- Local build: `tools\New-ReleasePackage.ps1 -DestinationDir dist`, then `tools\Test-ReleasePackage.ps1 -ZipPath <zip>`.

---

## Pull Request Process

1. Fork the repository and create a descriptive branch:
   ```bash
   git checkout -b feature/my-enhancement
   ```
2. Make your changes adhering to the guidelines above.
3. Verify that `tools\Test-Depersonalized.ps1`, `tools\Test-KitSyntax.ps1` and `tests\Run-Tests.ps1` pass.
4. Commit your changes with clear, concise commit messages.
5. Push to your fork and submit a Pull Request against the `main` branch.
