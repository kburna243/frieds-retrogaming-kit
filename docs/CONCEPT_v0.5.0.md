# Konzept & Roadmap: Fried's Retrogaming Kit v0.5.0+

**Status:** In Umsetzung · 30.09.2026 (Wiimote-Integration validiert)
**Basis:** Kit v0.4.1 (Pakete core, pinball, lightgun, arcade, output, pads, gui, api; 653 Pester-Fälle, CI grün)
+ Agent v0.3.0
**Kontext:** Architektur-Audit & Persona-Workshop, gegen den Repo-Stand geprüft; Wiimote/FFBBlaster/Gunmote-Integration
am Cabinet getestet und dokumentiert (Abschnitt 8)

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

## 8. Validierte Wiimote/FFBBlaster/Gunmote-Integration (Praxis-Test 29.–30.09.2026)

Die im Konzept als „Neu" gelisteten Output-Adapter **FFBBlaster** und **Gunmote-Output-Hook** wurden am
Produktiv-Cabinet mit 2 Nintendo Wiimotes, Mayflash DolphinBar (Mode 4) und dem Spiel **Rambo** (TeknoParrot)
getestet. Der Test validiert die Architektur und liefert konkrete Konfigurationsmuster für die Implementierung.

### 8.1 Hardware-Baseline

| Komponente | Status | Anmerkung |
|:--|:--|:--|
| Mayflash DolphinBar (Firmware v09+, Mode 4) | ✅ Validiert | Primäre Verbindung, kein Windows-Bluetooth-PIN-Prompt |
| Bluetooth-Dongle mit IR-Leiste | ✅ Validiert | Alternative Verbindung getestet, funktioniert ebenfalls |
| 2× Nintendo Wiimote (MotionPlus) + Gun Shells | ✅ Validiert | Spieler 1 + 2 parallel |
| ViGEmBus (signiert, Nefarius) | ✅ Validiert | Virtuelle Xbox-360-Pads für XInput-Kompatibilität |

### 8.2 Architektur: FFBBlaster → TCP → Gunmote (Rumble ohne MAMEHooker)

```
[TeknoParrot / BudgieLoader]
        │ FFBBlaster.dll: OutputsSystem=1, NetOutputsTCPPort=8002
        ▼
[recoil-stretch.py]        ← optional: verlängert Rückstoß-Pulse (16 ms → 150 ms)
        │ TCP 8000 (Gunmote-kompatibler Port)
        ▼
[Gunmote ArcadeHook]       ← TCP-Client in Gunmote.dll, verbindet auf localhost
        │ liest/schreibt ArcadeOutputs\<System>\<rom>.ini
        ▼
[Wiimote Rumble-Motor]     ← wii <spieler> <ausgang> <wert>
```

**Schlüsselerkenntnisse:**

1. **FFBBlaster braucht `OutputsSystem=1`** (TCP-Mode). Der Default `0` sendet nur Windows-Nachrichten
   (`output windows`), die Gunmote nicht empfängt. Port 8000 ist der Standard von Hook of the Reaper und wird
   von Gunmotes ArcadeHook als Client-Port erwartet.

2. **Gunmote hat einen eingebauten TCP-Client** („ArcadeHook") in `Gunmote.dll`. Er verbindet sich auf
   `localhost` und legt spielspezifische INIs unter `C:\Program Files\Gunmote\ArcadeOutputs\` an — die
   INI entsteht automatisch beim ersten Empfang von Output-Signalen.

3. **Zwei Rumble-Wege existieren parallel:**

   | Weg | Auslöser | Transport | Konfiguration | Geeignet für |
   |:--|:--|:--|:--|:--|
   | **Output → INI** | Spiel-Output (z. B. `P1_Damage`) | TCP → Gunmote INI → Wiimote-Motor | `P1_Damage=wii 1 5 %s%` | Treffer, langanhaltende Events (>100 ms) |
   | **GunEffect → ViGEm** | FFBBlaster-interner Schuss-Effekt | FFBBlaster → ViGEm Xbox-Pad → Wiimote | `HowtoRumbleGunEffect=1`, `FeedbackLength=100`, Stärke 50 % | Schüsse (FFBBlaster routed selbst an die Wiimote-GUID) |

4. **Rückstoß-Pulse sind zu kurz für den Wiimote-Motor:** TeknoParrot-Spiele senden Rückstoß-Outputs oft nur
   ~16 ms lang. Der Wiimote-Motor braucht mindestens ~50–80 ms für eine spürbare Vibration. Lösung:
   **`recoil-stretch.py`** — ein Python-TCP-Proxy, der das Aus-Signal um `HOLD_MS` (konfigurierbar, Default
   150 ms) verzögert:
   ```
   FFBBlaster (Port 8002) → recoil-stretch.py (Port 8000) → Gunmote
   ```
   Das Skript lässt alle Nicht-Rückstoß-Outputs unverändert durch. Der Selbsttest ist grün.

5. **Device-GUID-Stabilität ist kritisch:** FFBBlaster adressiert Geräte über ihre Windows-GUID. Eine
   Neuinstallation der Bluetooth-Treiber (z. B. durch Gunmote-Update mit angekreuztem „reinstall drivers")
   setzt die GUIDs zurück → FFBBlaster verliert die Wiimote-Zuordnung. Die GUIDs werden in
   `FFBBlaster.ini` (`DeviceGUID` für P1/P2) und als Backup (`FFBBlaster.ini.bak-wiimote-guids`) vorgehalten.

### 8.3 Konfigurationsmuster

#### 8.3.1 FFBBlaster.ini (Spielverzeichnis, z. B. `Rambo.teknoparrot\elf\`)

```ini
[Outputs]
OutputsSystem=1              ; 0=Windows-Nachrichten, 1=TCP-Netzwerk
NetOutputsTCPPort=8002       ; Ausgangsport (8000 wird vom Recoil-Stretcher belegt)

[Guns]
DeviceGUID = <Wiimote-P1-GUID>
Gun1pStrength = 100          ; 0-100 %, über Gunmote-Rumble-Schwelle (50)
Gun2pStrength = 100
FeedbackLength = 100         ; ms, GunEffect-Dauer
HowtoRumbleGunEffect = 1     ; 1 oder 2 (verschiedene Rumble-Muster)
```

#### 8.3.2 Gunmote ArcadeOutputs\<rom>.ini (automatisch angelegt, dann via patch-once.ps1 befüllt)

```ini
; Angelegt von Gunmote beim ersten TCP-Empfang. patch-once.ps1 trägt die Werte ein.
1pRecoil=wii 1 5 %s%         ; Spieler 1 Rückstoß → Motor (Ausgang 5)
2pRecoil=wii 2 5 %s%         ; Spieler 2 Rückstoß → Motor
P1_Damage=wii 1 5 %s%        ; Spieler 1 Treffer → Motor
P2_Damage=wii 2 5 %s%        ; Spieler 2 Treffer → Motor
; Achtung: wii x 0 1 = LED (Ausgang 0), nicht Motor!
```

#### 8.3.3 patch-once.ps1-Muster (elevated Admin-Task)

Änderungen an Dateien unter `C:\Program Files\Gunmote\` erfordern Admin-Rechte. Das Kit nutzt das
`patch-once.ps1`-Muster: Ein PowerShell-Skript wird einmalig über einen scheduled task mit höchsten
Rechten ausgeführt (`Gunmote Profil Menue`) und danach als `.done` markiert. Gunmote wird nach dem
Patch neu gestartet.

#### 8.3.4 Gunmote settings.json — Rumble-Schwellwert

```json
{
  "xinput_rumbleThreshold_low": 50,
  "xinput_rumbleThreshold_high": 50
}
```

Der Default (200) ist für Wiimotes zu hoch — Werte unter 50 werden nicht zuverlässig erkannt.
**Empfehlung: 50** (am Cabinet bestätigt).

### 8.4 Bekannte Fallen & Sicherheitsnetze

| Falle | Symptom | Lösung |
|:--|:--|:--|
| **FFBBlaster OutputsSystem=0** | Gunmote empfängt nichts, keine INI entsteht | Auf `1` setzen, Port prüfen |
| **Schuss-Impuls zu kurz (16 ms)** | LED blinkt, aber kein Rumble | `recoil-stretch.py` vorschalten (150 ms) |
| **Falscher Ausgang in INI** (0 statt 5) | LED leuchtet statt Motor | `wii x 5 %s%` für Motor, `wii x 0 1` ist LED |
| **Bluetooth-Treiber neu installiert** | FFBBlaster verliert Geräte | GUIDs aus Backup wiederherstellen (`FFBBlaster.ini.bak-wiimote-guids`) |
| **ViGEmBus + echtes Xbox-Pad** | FFB-GUI zeigt falsche Geräteanzahl | Reihenfolge der Geräte-Enumeration prüfen; nur ein Pad-Typ pro Test |
| **Gunmote nach Patch nicht verbunden** | Wiimote-LEDs aus | Warten bis LEDs leuchten, ggf. Sync-Knopf drücken |
| **Gunmote-Menü-Layout nach Neustart verloren** | Pipe-Timeout im Log | Watcher setzt Layout bei Spielstart über RetroBat neu |

### 8.5 Auswirkungen auf v0.5.0-Implementierung

1. **FFBBlaster-Adapter** (`output/adapters/FFBBlaster.ps1`):
   - Erkennt FFBBlaster über Prozess `BudgieLoader` + Port 8000/8002 + spielspezifische `FFBBlaster.ini`
   - `Test-` prüft `OutputsSystem=1` und warnt bei `0`
   - `Configure-` setzt `OutputsSystem=1`, `NetOutputsTCPPort=8002` und trägt Wiimote-GUIDs ein
   - Backup der GUIDs als `.bak-wiimote-guids`

2. **Gunmote-Output-Hook-Adapter** (`output/adapters/GunmoteOutput.ps1`):
   - Erkennt Gunmote ArcadeOutputs-Ordner + laufenden Gunmote-Prozess
   - `Test-` prüft TCP-Verbindung auf Port 8000
   - `Configure-` schreibt spielspezifische INI über `patch-once.ps1`-Muster
   - `Verify-` prüft INI-Einträge gegen erwartete Output-Namen

3. **Recoil-Stretcher** (`output/tools/recoil-stretch.py`):
   - Wird mit dem TeknoParrot-Profil gestartet (`tp.ps1`) und beendet (`menue.ps1`)
   - Konfigurierbare `HOLD_MS` (Default 150 ms)
   - Selbsttest im Adapter integriert

4. **`outputs.verify_safety`**:
   - Port-Konflikt-Prüfung: TCP 8000 (Recoil-Stretcher vs. Hook of the Reaper vs. MAMEHooker-EmuOutput)
   - Doppelte Output-Empfänger: Gunmote-Hook UND MAMEHooker auf dieselben Outputs → Warning
   - Device-GUID-Validierung: GUID in FFBBlaster.ini muss mit aktueller PnP-Enumeration übereinstimmen

### 8.6 Offene Frage geklärt

> **Rumble-Weg für TeknoParrot:** ViGEm-Weiterleitung (Schwellwert) oder Gunmote-Output-Hook?

**Antwort aus dem Praxistest: Beide.** Sie bedienen unterschiedliche Ereignistypen und ergänzen sich:

- **Gunmote-Output-Hook** für langanhaltende Spiel-Events (Treffer, Schild, Health-Change) — der Spiel-Output
  bleibt lange genug an (>100 ms), der Wiimote-Motor spricht direkt an.
- **FFBBlaster GunEffect (ViGEm)** für kurze Impulse (Schüsse) — FFBBlaster erzeugt selbst einen
  konfigurierbaren Rumble-Effekt (100 ms, 50 % Stärke) und schickt ihn über das ViGEm-Pad an die Wiimote.
  Alternativ kann der Recoil-Stretcher den kurzen Spiel-Impuls verlängern und über den Output-Hook an die
  Wiimote leiten.

Die `outputs.verify_safety`-Prüfung stellt sicher, dass nicht beide Wege gleichzeitig auf denselben
Output-Namen hören (Doppel-Rumble).

---

*Erstellt: 28.09.2026 · Autor: Friedrich Börner + KI-Assistent · Status: In Umsetzung*
*Letzte Aktualisierung: 30.09.2026 — Abschnitt 8: Validierte Wiimote/FFBBlaster/Gunmote-Integration*
*Audit-Integration: DOF bei outputs, EDID-Standard, Lighting-Grenze, Frame-Pacing, Modus-Wechsel.*
*Repo-Abgleich: echte Pakete und Adapter, Module als Namensräume, FFBBlaster und Gunmote-Output-Hook.*
