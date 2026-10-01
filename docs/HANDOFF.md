# HANDOFF — Retro Kit Development Stand

> **Letzter Stand:** v0.8.0 (2026-10-01)
> **Nächster Meilenstein:** v0.9.0 `emulators.*`
> **Session:** dsh (DeepSeek Harness) — 4 Releases in einer Session

## Aktueller Stand

| Version | Paket | Dateien | Adapter | API-Operationen |
|---|---|---|---|---|
| v0.5.0 | controllers + outputs | — | FFBBlaster, GunmoteOutput | controllers.detect, outputs.verify_safety, Module-Feld |
| v0.6.0 | displays/ | 14 | VirtualDMD, MultiMonitor, Backglass, TopperDisplay, DmdExtensions | displays.detect |
| v0.7.0 | enhancements/ | 16 | ShaderPresets, Latency, Upscaling, FramePacing, PinballVisuals, PinballBAM, AmbientLighting, AudioEnhance | enhancements.detect |
| v0.8.0 | library/ | 14 | RetroBat, PinballY, Playnite, LaunchBox, Generic | 7 ops: scan, add_roms, remove_roms, update_media, create_playlist, validate_integrity, export_catalog |

**241 PowerShell-Dateien, 0 Syntax-Fehler.**

## Nächster Schritt: v0.9.0 `emulators.*`

Laut `docs/CONCEPT_v0.5.0.md` §3.3:

- **Adapter:** MAME, RetroArch, TeknoParrot, Supermodel, Model 2, Cemu, Dolphin, RPCS3, Xemu, DuckStation, PCSX2
- **API-Tools:** `emulators.detect_installed`, `emulators.install`, `emulators.configure`, `emulators.apply_shader_preset`, `emulators.patch`, `emulators.verify_integrity`
- **Abhängigkeiten:** enhancements → emulators (Shader), displays → emulators (Auflösung)

Die heutigen Emulator-Schritte aus `lightgun/` (10–14) bleiben dort; `emulators` bündelt sie im Katalog.

## Wichtige Referenzen

| Datei | Pfad |
|---|---|
| CONCEPT (Roadmap) | `docs/CONCEPT_v0.5.0.md` |
| Wiimote-Konzept | `docs/CONCEPT_hook-of-the-wiimote.md` |
| Enhancement Wissensbasis | `docs/Retro Gaming Enhancement Wissensbasis.md` (369 Zeilen) |
| ROADMAP | `ROADMAP.md` |
| CHANGELOG | `CHANGELOG.md` |

## Architektur-Konventionen

- Jedes Paket: `{name}/RetroCabinetKit.{Name}.psd1` + `.psm1` + `modules/Common.ps1` + `modules/Adapters.ps1` + `adapters/` + `steps/`
- Adapter-Contract: 5 Funktionen (Test-*, Get-*-Info, Install-*, Configure-*, Set-*-InterferenceShield)
- API-Operationen: in `api/RetroCabinetKit.Api.psm1` → Import, Get-KitOperation, Invoke-KitOperation Switch-Case
- Tests: `tests/{name}/{Name}.Tests.ps1` + `tests/api/V{0xx}Api.Tests.ps1`
- Version-Bump: `tools\Set-KitVersion.ps1` (16 Stellen)
- BOM: Pre-Commit-Hook fügt UTF-8 BOM hinzu (edit-Tool strippt)

## Subagent-Pattern (bewährt)

1. Package-Scaffolding + Common.ps1 → 1 Subagent
2. Adapter (4-5 pro Batch) → 1-2 Subagents
3. API-Operationen + Tests → selbst machen (Subagents stocken bei API-Edits)
4. Syntax-Check → `Set-KitVersion.ps1` → Commit → Tag → Push

## Repos

- Kit: `I:\claude-system\data\projects\retro-cabinet-kit` (main, `ffd3dec`)
- Agent: `I:\claude-system\data\projects\frieds-retrogaming-agent` (main)
- CI: https://github.com/kburna243/frieds-retrogaming-kit/actions