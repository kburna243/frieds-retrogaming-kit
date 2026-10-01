# HANDOFF — Retro Kit Development Stand

> **Letzter Stand:** v1.0.0 (2026-10-01)
> **Nächster Meilenstein:** v1.1.0 `setup-levels` (Easy/Custom/Nerd Extreme)
> **Session:** dsh (DeepSeek Harness) — 6 Releases in einer Session

## Aktueller Stand

| Version | Paket | Dateien | Adapter | API-Operationen |
|---|---|---|---|---|
| v0.5.0 | controllers + outputs | — | FFBBlaster, GunmoteOutput | controllers.detect, outputs.verify_safety, Module-Feld |
| v0.6.0 | displays/ | 14 | VirtualDMD, MultiMonitor, Backglass, TopperDisplay, DmdExtensions | displays.detect |
| v0.7.0 | enhancements/ | 16 | ShaderPresets, Latency, Upscaling, FramePacing, PinballVisuals, PinballBAM, AmbientLighting, AudioEnhance | enhancements.detect |
| v0.8.0 | library/ | 14 | RetroBat, PinballY, Playnite, LaunchBox, Generic | 7 ops: scan, add_roms, remove_roms, update_media, create_playlist, validate_integrity, export_catalog |
| v0.9.0 | emulators/ | 21 | MAME, RetroArch, TeknoParrot, Supermodel, Model2, Cemu, Dolphin, RPCS3, Xemu, DuckStation, PCSX2, FuturePinball, VisualPinball, PinballArcade, PinballFX3 | 6 ops: detect_installed, install, configure, apply_shader_preset, patch, verify_integrity |
| v1.0.0 | frontends/ | 10 | RetroBat, PinballY, Playnite, LaunchBox, PinUP | 6 ops: detect, install, set_theme, configure_genre_routing, import_library, export_catalog |

**~275 PowerShell-Dateien, 0 Syntax-Fehler in neuen Paketen.**

## Nächster Schritt: v1.1.0 Setup-Levels

Laut `docs/CONCEPT_v0.5.0.md` §4:
- **Easy** (Autopilot): „Ein Klick, läuft." — 2–3 Fragen, Best-Practice-Presets
- **Custom** (Assistent): „Ich will mitbestimmen" — Auswahl + Schieberegler
- **Nerd Extreme** (Deep Dive): „Jede Schraube drehen" — INI-Schlüssel, JSON-Diffs, `propose_mapping`, `patch_raw`
- Context-Header: `{ "mode": "easy", "target_module": "controllers", ... }`

## Architektur-Konventionen

- Jedes Paket: `{name}/RetroCabinetKit.{Name}.psd1` + `.psm1` + `modules/Common.ps1` + `modules/Adapters.ps1` + `adapters/` + `steps/`
- Adapter-Contract: 5 Funktionen (Test-*, Get-*-Info, Install-*, Configure-*, Set-*-InterferenceShield)
- **Erweiterbarkeit:** Drop-in-Adapter — neue `.ps1` in `adapters/` → automatisch von `Get-*AdapterCatalog` entdeckt
- API-Operationen: in `api/RetroCabinetKit.Api.psm1` → Import, Get-KitOperation, Invoke-KitOperation Switch-Case
- Tests: `tests/{name}/{Name}.Tests.ps1` + `tests/api/V{0xx}Api.Tests.ps1`
- Version-Bump: `tools\Set-KitVersion.ps1` (20 Stellen)
- BOM: Pre-Commit-Hook fügt UTF-8 BOM hinzu (edit-Tool strippt)
- ⚠️ Keine Em-Dashes (`—`) in PowerShell-Dateien — werden als schließendes `"` interpretiert

## Subagent-Pattern (bewährt)

1. Package-Scaffolding + Common.ps1 → 1 Subagent
2. Adapter (4-5 pro Batch) → 1-2 Subagents
3. API-Operationen + Tests → selbst machen (Subagents stocken bei API-Edits)
4. Syntax-Check → `Set-KitVersion.ps1` → Commit → Tag → Push

## Repos

- Kit: `kburna243/frieds-retrogaming-kit` (main)
- Agent: `kburna243/frieds-retrogaming-agent` (main)
- CI: https://github.com/kburna243/frieds-retrogaming-kit/actions