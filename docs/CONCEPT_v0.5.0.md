# Konzept & Roadmap: Fried's Retrogaming Kit v0.5.0+

**Status:** Beschlussreif · 28.09.2026
**Basis:** Kit v0.4.1 (Pakete core, pinball, lightgun, arcade, output, pads, gui, api; 653 Pester-Fälle, CI grün)
+ Agent v0.3.0
**Kontext:** Architektur-Audit & Persona-Workshop, gegen den Repo-Stand geprüft

---

## 1. Kernentscheidungen

### Entscheidung A: Sieben Module als API-Namensräume, nicht als Ordner-Umzug

Die sieben Module ordnen, **was das Kit kann** — im API-/MCP-Katalog, in den Guides und im Agenten. Die
bestehenden Pakete bleiben, wo sie sind; neue Fähigkeiten, die in kein Paket passen, bekommen ein neues Paket.

| Modul (API-Namensraum) | Zweck | Heute umgesetzt in | Neu |
|:--|:--|:--|:--|
| `controllers.*` | Erkennung, Mapping, Kalibrierung, SOCD | `lightgun/`, `arcade/` (inkl. Lenkräder), `pads/` | — |
| `library.*` | ROMs, Medien, Playlists, Metadaten | (nur Pinball-Tabellen in `pinball/`) | Paket `library/` (v0.8.0) |
| `emulators.*` | Emulator-Configs, Patches, Shader | verteilt: lightgun-Schritte 10–14, `pinball/` | Paket `emulators/` (v0.9.0) |
| `frontends.*` | RetroBat, PinballY, PinUP, Playnite, LaunchBox | `pinball/` (PinUP, PinballY), lightgun (RetroBat) | Paket `frontends/` (v1.0.0) |
| `outputs.*` | Game-reaktive Aktorik: DOF, Solenoids, Rumble/FFB, Lampen | `output/` | — |
| `displays.*` | Reine Video-Pipelines: Multi-Monitor, DMD, Backglass, Topper | `output/adapters/DmdExtensions.ps1` | Paket `displays/` (v0.6.0) |
| `enhancements.*` | Ambient/System: Performance, Upscaling, Lighting, Frame-Pacing, Audio | — | Paket `enhancements/` (v0.7.0) |

**Warum kein Ordner-Umzug** (`lightgun/`+`arcade/`+`pads/` → `controllers/`, `output/` → `outputs/`):
Modulnamen (`RetroCabinetKit.Lightgun`, `.Output`, …), Start-CMDs, i18n-Schlüssel (`Lightgun.*`),
Schrittnummern, CI-Test-Shards, Guides und der API-Vertrag mit dem Agenten hängen an den heutigen Namen. Der
Umzug bringt Nutzern nichts und bricht den Agenten. Namensräume geben dieselbe Ordnung ohne Bruch.

Bestehende Operationen behalten ihre Namen (`pinbally.detect`, `pinbally.retarget`, `backup.*`, `profile.*`,
`support.bundle`); neue Operationen bekommen den Namensraum ihres Moduls.

**Modul-Grenzen (Audit-Beschluss):**
- **`outputs`** = game-reaktiv, ROM-/Spiel-getriggert: DOF, Flasher, Solenoids, Rumble, FFB, Lampen.
  **DOF gehört hierher** (verarbeitet ROM-Events) und liegt dort schon (`output/adapters/DirectOutputFramework.ps1`).
- **`displays`** = reine Video-Pipelines (DMD, LCD, CRT, Backglass). Die DMD-Ausgabe
  (`output/adapters/DmdExtensions.ps1`) wandert mit dem Paket `displays/` (v0.6.0) dorthin — das ist der einzige
  Adapter-Umzug.
- **`enhancements`** = ambient / systemweit (Ambilight, statische Cabinet-Beleuchtung, Inaktivitäts-Dimmer).
- **Regel:** DOF-Events werden nie von `enhancements` ausgelöst.

**Abhängigkeiten (Richtung = „braucht"):**
- `controllers` und `library` brauchen nichts außer `core`.
- `emulators` → `controllers` (Input-Configs).
- `outputs` → `emulators` (MAME `output windows/network`, TeknoParrot-FFB-Plugins).
- `displays` → `emulators` (VPinMAME `showpindmd`, `DmdDevice.ini`).
- `enhancements` → `displays` (Monitor-EDID für Upscaling/MPO) + `emulators` (Shader).
- `frontends` → `emulators` + `library` + `controllers` + `displays` (Genre-Routing).
- Keine Zyklen. Untereinander unabhängig sind nur `controllers` und `library`.

### Entscheidung B: Drei Setup-Level

Jedes Modul bietet drei Modi, gesteuert über `SetupContext.Mode` im Agenten:

| Level | Name | Motto | Zielgruppe |
|:--|:--|:--|:--|
| 1 | **Easy** (Autopilot) | „Ein Klick, läuft." | Spieler |
| 2 | **Custom** (Assistent) | „Ich will mitbestimmen, aber bitte führ mich." | Standard-Nutzer |
| 3 | **Nerd Extreme** (Deep Dive) | „Ich will jede Schraube drehen." | Schrauber |

Die Level ändern nur, **wie viel gefragt und gezeigt** wird. Die Sicherheitsregeln des Kits gelten in allen drei
gleich: Probelauf zuerst, Backup vor jeder Änderung, Änderungen über die API nur mit `-Approved`.

---

## 2. Personas

| Persona | Fokus | Primäres Modul | Sekundär |
|:--|:--|:--|:--|
| **Der Schrauber** (Tinkerer) | Buttons, Deadzones, SOCD, FFB-Tuning | `controllers` | `emulators`, `outputs` |
| **Der Kurator** (Librarian) | ROMs, Box-Arts, Playlists, Metadaten | `library` | `frontends` |
| **Der Spieler** (Player) | „Einfach starten, nichts kaputt machen" | `frontends` | alle (nur lesen) |
| **Der Architekt** (Builder) | Komplettes Cabinet aufsetzen | alle | — |
| **Der Techniker** (Rigger) | Haptik, Solenoids, DMDs, Shaker | `outputs`, `displays` | `controllers` |
| **Der Optimierer** (Tweaker) | Performance, Upscaling, Lighting, Frame-Pacing | `enhancements` | `displays`, `emulators` |

---

## 3. Die sieben Module im Detail

### 3.1 `controllers`
**Heute:** `lightgun/` (Wiimote/Gunmote, Adapter AimTrak, Gun4IR, OpenFIRE, RetroShooter, Sinden), `arcade/`
(BrookUFB, GP2040CE, HoriArcade, IPAC, MadCatz, ZeroDelay, MultiConsole, PS2-auf-USB, Lenkräder Logitech,
Thrustmaster/Fanatec, Xbox 360, DIY), `pads/` (Xbox, PlayStation, Switch Pro, 8BitDo).
**Neue MCP-Tools:** `controllers.detect`, `controllers.read_mapping`, `controllers.propose_mapping`,
`controllers.apply_mapping`, `controllers.rollback_mapping`, `controllers.calibrate`, `controllers.set_genre_profile`.
**Lehre aus v0.4.1:** Systeme, deren Emulator oder DemulShooter RawInput liest, brauchen ein Maus-Layout, kein
Pad-Layout — gehört als Regel in `controllers.propose_mapping`.

### 3.2 `library`
**Neue Adapter:** RetroBat, PinballY, Playnite, LaunchBox, Generic.
**Neue MCP-Tools:** `library.scan`, `library.add_roms`, `library.remove_roms`, `library.update_media`,
`library.create_playlist`, `library.validate_integrity`, `library.export_catalog`.

### 3.3 `emulators`
**Neue Adapter:** MAME, RetroArch, TeknoParrot, Supermodel, Model 2, Cemu, Dolphin, RPCS3, Xemu, DuckStation, PCSX2.
Die heutigen Emulator-Schritte aus `lightgun/` (10–14) bleiben dort; `emulators` bündelt sie im Katalog.
**Neue MCP-Tools:** `emulators.detect_installed`, `emulators.install`, `emulators.configure`,
`emulators.apply_shader_preset`, `emulators.patch`, `emulators.verify_integrity`.

### 3.4 `frontends`
**Neue Adapter:** RetroBat, PinballY, Playnite, LaunchBox, PinUP.
**Neue MCP-Tools:** `frontends.detect`, `frontends.install`, `frontends.set_theme`,
`frontends.configure_genre_routing`, `frontends.import_library`, `frontends.export_catalog`.

### 3.5 `outputs` (game-reaktive Aktorik)
**Heute in `output/adapters/`:** DirectOutputFramework (DOF), HookOfTheReaper, MameHooker, QMamehook.
**Neu:**
- **FFBBlaster** (TeknoParrot, aktuelles FFB-Plugin; das ältere FFBArcadePlugin/`FFBPlugin.ini` nur noch erkennen).
- **Gunmote-Output-Hook**: Gunmote liest selbst Windows-Outputs (MAMEHooker-Syntax, `ArcadeOutputs\<System>\<rom>.ini`,
  z. B. `P1_CtmRecoil=wii 1 5 %s%`) — Rumble ohne MAMEHooker. Rumble-Weiterleitung von ViGEm nur über
  Schwellwert (`xinput_rumbleThreshold_*`, Standard 200).
- LEDBlinky, PinscapeOutput.
**Neue MCP-Tools:** `outputs.detect`, `outputs.install`, `outputs.configure`, `outputs.test_pulse`,
`outputs.set_genre_profile`, `outputs.verify_safety`.
**Sicherheitsnetze:**
- Solenoid-Schutz: 200 ms hart (HotR-Guard besteht schon), Nerd-Mode max. 300 ms mit Warnung.
- Port-Konflikt-Prüfung (TCP 8000).
- LEDBlinky nie in derselben Message-Queue wie MAMEHooker.
- **Nur ein Output-Empfänger pro Wirkung:** Gunmote-Hook und MAMEHooker hören auf dieselben Outputs —
  `outputs.verify_safety` meldet doppelt belegtes Rumble.

### 3.6 `displays` (reine Video-Pipelines)
**Adapter:** RealDMD (PIN2DMD/ZeDMD/PinDMD), VirtualDMD (dmdext, heute `output/adapters/DmdExtensions.ps1`),
Backglass (B2S), MultiMonitor, TopperDisplay, EmulatorDisplay.
**Neue MCP-Tools:** `displays.detect`, `displays.install`, `displays.configure_dmd`, `displays.configure_monitors`,
`displays.set_resolution`, `displays.assign_emulator`, `displays.test_pattern`, `displays.set_colorization`,
`displays.verify_integrity`.
**Identifikation (Audit-Beschluss):**
- Monitore **ausschließlich** über EDID-Schlüssel (`WmiMonitorID` → Hersteller + Produktcode + Seriennummer).
- Windows-Display-Nummern (`\\.\DISPLAYn`) werden **nie** gespeichert.
- Die Rolle (Playfield/Backglass/DMD/Topper) hängt am EDID-Schlüssel.

### 3.7 `enhancements` (ambient & systemweit)
**Adapter:** PerformanceCheck, Upscaling, Lighting (nur Ambient/Inaktivitäts-Dimmer), Shaders, FramePacing, Audio.
**Neue MCP-Tools:** `enhancements.performance_check`, `enhancements.get_recommendations`,
`enhancements.apply_upscaling`, `enhancements.configure_lighting`, `enhancements.apply_shader_preset`,
`enhancements.configure_frame_pacing`, `enhancements.configure_audio`, `enhancements.test_performance`.
**Sicherheitsnetze:** Performance-Check nur lesend; Upscaling erst Vorschau, dann Anwenden; Lighting-Profile mit
Timeout (Stromschutz); Warnung bei Audio-Latenz unter 10 ms.

---

## 4. Die drei Setup-Level

- **Easy:** höchstens 2–3 Fragen, feste Best-Practice-Presets, keine technischen Details, Backups im Hintergrund.
- **Custom:** Auswahl + Schieberegler, 3–4 Profile pro Kategorie, Zusammenfassung in Klartext vor der Ausführung.
- **Nerd Extreme:** Agent als technischer Co-Pilot — exakte Dateipfade, INI-Schlüssel, JSON-Diffs, freie Eingaben,
  Low-Level-Tools (`propose_mapping`, `patch_raw`).

Context-Header, den der Agent bei jedem Aufruf mitgibt:

```json
{
  "tool": "setup.run",
  "parameters": {
    "mode": "easy",
    "target_module": "controllers",
    "hardware_detected": "LogitechG29",
    "preset": "arcade_racer"
  }
}
```

---

## 5. Roadmap

| Phase | Version | Fokus | Aufwand | Impact |
|:--|:--|:--|:--|:--|
| **Namensräume + Outputs** | v0.5.0 | Katalog-Namensräume für alle Operationen; `controllers.detect`; `outputs` um FFBBlaster, Gunmote-Hook und `outputs.verify_safety` erweitern | Mittel | Sehr hoch |
| **Displays** | v0.6.0 | Paket `displays/` (EDID-Multi-Monitor, DMD inkl. Umzug DmdExtensions, Topper, Auflösung) | Hoch | Hoch |
| **Enhancements** | v0.7.0 | Paket `enhancements/` (Performance, Upscaling, Frame-Pacing mit EDID/MPO-Check, Ambient Lighting, Shader) | Hoch | Sehr hoch |
| **Library** | v0.8.0 | Paket `library/` (ROM-/Medien-Verwaltung) | Mittel | Hoch |
| **Emulators** | v0.9.0 | Paket `emulators/` (Config-Verwaltung) | Hoch | Mittel |
| **Frontends** | v1.0.0 | Paket `frontends/` (Frontend-Orchestrierung) | Hoch | Mittel |
| **Setup-Level** | v1.1.0 | Drei Modi in allen Modulen | Hoch | Sehr hoch |
| **Auto-Detection** | v1.2.0 | Modus-Erkennung aus natürlicher Sprache | Mittel | Hoch |

---

## 6. Offene Fragen & Entscheidungen

- [x] **Modus-Wechsel zur Laufzeit:** erlaubt (Easy für die Basis, Nerd für die Feinjustierung). Beschluss 28.09.2026
- [x] **Solenoid-Grenze:** 200 ms hart, Nerd-Mode bis 300 ms mit Warnung. Beschluss 28.09.2026
- [x] **Benchmark:** kein schwerer Benchmark; WMI/DXGI-Scan + 5-Sekunden-Render-Test in RetroArch. Beschluss 28.09.2026
- [x] **Module = Namensräume, kein Ordner-Umzug** (Abschnitt 1). Beschluss 28.09.2026
- [ ] **Preset-Verwaltung:** eigene Presets speichern und teilen? (Empfehlung: ja, ab v1.1.0)
- [ ] **Library-Import zwischen Frontends:** unterschiedliche Datenbankformate? (Empfehlung: JSON als neutrales Zwischenformat)
- [ ] **Emulator-Patches:** wer pflegt die Liste? (Empfehlung: Community über das Feedback-System, kuratiert)
- [ ] **DMD-Colorization-Pakete:** `displays` für die Zuordnung, `library` für Download/Update (Empfehlung)
- [ ] **Rumble-Weg für TeknoParrot:** ViGEm-Weiterleitung (Schwellwert) oder Gunmote-Output-Hook — erst nach dem
  Praxistest am Cabinet festlegen

---

## 7. Nächster konkreter Schritt (v0.5.0-Start)

1. API-Katalog: Feld `Module` je Operation (`controllers`, `outputs`, …); bestehende Namen bleiben gültig.
2. `controllers.detect`: fasst die Erkennung aus `lightgun/`, `arcade/` und `pads/` zu einem Ergebnis zusammen (nur lesend).
3. `outputs`: Adapter FFBBlaster und Gunmote-Output-Hook in `output/adapters/`; `outputs.verify_safety`
   (Solenoid-Grenze, Port 8000, doppelte Output-Empfänger).
4. Pester-Tests für die neuen Operationen; die CI-Test-Shards bleiben unverändert.
5. Contract-Snapshot im Agent-Repo aktualisieren (neue Operationen, Feld `Module`).
6. CI muss grün bleiben (Kit und Agent).

---

*Erstellt: 28.09.2026 · Autor: Friedrich Börner + KI-Assistent · Status: Beschlussreif*
*Audit-Integration: DOF bei outputs, EDID-Standard, Lighting-Grenze, Frame-Pacing, Modus-Wechsel.*
*Repo-Abgleich: echte Pakete und Adapter, Module als Namensräume, FFBBlaster und Gunmote-Output-Hook.*
