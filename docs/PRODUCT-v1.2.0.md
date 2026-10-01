# Fried's Retrogaming Kit — v1.2.0 Produktbeschreibung

> **Version:** 1.2.0 · **API-Version:** 1.4 · **PowerShell:** 5.1 · **Plattform:** Windows
> **Stand:** Oktober 2026
> **Lizenz:** MIT · **Repository:** [github.com/kburna243/frieds-retrogaming-kit](https://github.com/kburna243/frieds-retrogaming-kit)

---

## Was ist das Kit?

Fried's Retrogaming Kit ist ein quelloffenes Automations-Toolkit für Windows, das den Bau und
Betrieb eines Arcade-Cabinets vereinfacht. Es besteht aus 10 Paketen (core, pinball, lightgun,
arcade, pads, output, displays, enhancements, library, emulators, frontends), die über eine
einheitliche PowerShell-5.1-Basis zusammenarbeiten. Jedes Paket bringt eigene Adapter-Plugins
und Step-Skripte mit; der gemeinsame Kern stellt Backup, Logging, I18n, SQLite, Step-Engine,
INI-Parser und den MCP-Server bereit.

**Kernprinzipien:**
- **Lokal und offline.** Keine Cloud, keine Telemetrie, keine versteckten Downloads.
- **Lesen, planen, ausführen.** Jede Änderung läuft über `Test → Invoke → Verify`. Change-Operationen
  sind immer erst ein Dry-Run; der Anwender sieht, was passiert, bevor es passiert.
- **Backup vor jeder Änderung.** Dateien werden nie ohne vorherige Sicherung modifiziert.
- **Sicherheit geht vor.** Solenoid-Schutz (200 ms Max-Offenzeit), Double-Consumer-Erkennung,
  Interference-Shield — keine verbrannten Spulen, keine doppelten Rumble-Events.
- **Erweiterbar.** Neue Emulatoren, Frontends oder Lightguns? Kopiere `_Template.ps1`, fülle
  5 Funktionen aus — das Kit erkennt den Adapter automatisch.

---

## Architektur (Stand v1.2.0)

```
retro-cabinet-kit/
├── core/                        Gemeinsamer Kern (25 Module + 4 Presets)
│   ├── modules/                 Log, State, Step, Backup, I18n, Doctor, Recovery,
│   │   Presets, IniParser,      SetupContext, AdapterContract, Diagnostics,
│   │   AutoDetect, Rollback,    Transaction, …
│   └── presets/                 4 Built-in-Presets (JSON)
├── api/                         API-Fassade + MCP-Server
│   ├── RetroCabinetKit.Api.psm1 42 Operationen im Catalog, Dispatcher, Facade
│   ├── Start-KitMcpServer.ps1   JSON-RPC-MCP-Server über stdio
│   └── modules/                 Result.ps1, Isolation.ps1
├── emulators/                   15 Emulator-Adapter + Steps
├── frontends/                   5 Frontend-Adapter + Steps
├── output/                      6 Output-Adapter + HookOfTheWiimote
├── lightgun/                    6 Lightgun-Adapter + Steps
├── arcade/                      12 Arcade-Encoder-Adapter
├── pads/                        Gamepad-Adapter
├── displays/                    Display-Adapter
├── enhancements/                Shader/Enhancement-Adapter
├── library/                     ROM-Library-Adapter
├── pinball/                     Virtual Pinball Suite (9 Steps)
├── tests/                       5 Test-Suiten
└── tools/                       Set-KitVersion, Build, Release, Assemble
```

---

## Feature-Katalog v1.2.0

### 1. Setup-Levels — Drei Modi für jede Zielgruppe

**Datei:** `core/modules/SetupContext.ps1` · **API-Ops:** `setup.set_mode`, `presets.list`, `presets.apply`

| Level | Name | Motto | Zielgruppe | Verhalten |
|---|---|---|---|---|
| 1 | **Easy** | „Ein Klick, läuft." | Spieler | ≤3 Fragen, Best-Practice-Presets, keine technischen Details, Backups im Hintergrund |
| 2 | **Custom** | „Ich will mitbestimmen, aber bitte führ mich." | Standard-Nutzer | Auswahl + Optionen, 3-4 Profile pro Kategorie, Klartext-Zusammenfassung vor Ausführung |
| 3 | **NerdExtreme** | „Ich will jede Schraube drehen." | Schrauber | Exakte INI-Schlüssel, Dateipfade, JSON-Diffs, keine Hand-holding — aber Dry-Run bleibt Pflicht |

Die Level ändern nur, **wie viel gefragt und gezeigt** wird. Die Sicherheitsregeln (Dry-Run,
Backup, Approved-Gate) gelten in allen drei gleich.

**Context-Header** (Agent → Kit):
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

**Mode-aware Logging:** Easy unterdrückt Info-Logs (nur Warnungen). Custom zeigt alles.
NerdExtreme zeigt alles plus interne Pfade. Mode-aware Approval: Easy und NerdExtreme
genehmigen automatisch; Custom fragt den Agenten explizit.

---

### 2. Preset-Management — Konfigurationen speichern und teilen

**Datei:** `core/modules/Presets.ps1` · **API-Ops:** `presets.list`, `presets.apply`

**4 Built-in-Presets:**

| Preset | Modul | Mode | Werte |
|---|---|---|---|
| `easy_arcade` | emulators | Easy | CRT-Lottes-Shader, Fullscreen, VSync, Stereo-Audio |
| `custom_racing` | controllers | Custom | Deadzone=5, FFB-Gain=80, Rotation=900°, Pedal-Mode=separate |
| `nerd_lightgun` | lightgun | NerdExtreme | Deadzone-X/Y=2, Saturation=95, Rumble=100%, Recoil=150ms |
| `balanced_cabinet` | enhancements | Custom | CRT-Lottes, 2x-Upscaling, Adaptive-VSync, Run-Ahead=1, FXAA |

**Benutzer-Presets** in `%USERPROFILE%\RetroCabinet\Presets\` — nie vom Kit-Update
überschrieben. CRUD-Operationen: `Get-KitPreset`, `Set-KitPreset`, `Remove-KitPreset` (nur
User-Presets), `Invoke-KitPreset` (laden + Mode setzen + Werte anwenden).

---

### 3. Strukturierter INI-Parser — Round-Trip ohne Datenverlust

**Datei:** `core/modules/IniParser.ps1`

| Funktion | Beschreibung |
|---|---|
| `ConvertFrom-Ini` | Liest INI → `@{ Section = @{ Key = Value } }` (Hashtable), Section-aware, Kommentare erhalten |
| `ConvertTo-Ini` | Schreibt Hashtable → INI, Backup vor dem Schreiben, UTF-8 |
| `Merge-IniData` | Deep-Merge: Override-Werte gewinnen über Base-Werte, per Section und Key |
| `Get-IniOverridePath` | Leitet `.override.ini`-Pfad aus INI-Pfad ab |
| `Test-IniIsOverridden` | `$true`, wenn ein Key unter einer Section vom User-Override verwaltet wird |
| `Get-IniEffectiveConfig` | Lädt Base-INI + Override → liefert die effektive Konfiguration (Union) |

**Shadow Override Pattern** — das Herzstück des INI-Handlings:

```
Für jede config.ini darf der User config.override.ini anlegen.

Pipeline:  Read INI → Apply Kit-Rules (in memory) → Merge Overrides (user wins) → Write

Get-*IniPlan SKIPPT Keys, die der User managed — kein Drift-Fehler, kein Loop.
Kit-Updates überschreiben User-Customizations NIE.
```

Betrifft: `emulators/modules/Adapters.ps1` und `frontends/modules/Adapters.ps1` — beide
`Get-*IniPlan` und `Set-*IniValue` wurden von zeilenbasiertem Parsing auf den strukturierten
Parser mit Shadow-Override-Unterstützung umgestellt.

---

### 4. Adapter-Contract — Formale Validierung aller Plugins

**Datei:** `core/modules/AdapterContract.ps1`

- `Test-AdapterContract` prüft: 5-Funktionen-Vertrag, Parse-Fehler, Capabilities-Hashtable
- `Test-AdapterContractBatch` validiert alle Adapter in einem Verzeichnis
- Unterstützt 9 Adapter-Kinds: Emulator, Frontend, Library, Enhancement, Display, Output,
  Lightgun, Arcade, Pad
- Ersetzt die frühere AST-basierte `Has*`-Boolean-Ableitung durch deklarative Prüfung

---

### 5. System Health — Fast-Path-Diagnose (unter 2 Sekunden)

**Datei:** `core/modules/Diagnostics.ps1` · **API-Op:** `status.health`

**Drei Vital-Säulen:**

| Säule | Was | Methode |
|---|---|---|
| **Hardware** | DolphinBar, Arcade-Encoder, 5 Lightgun-Familien (Sinden, Gun4IR, AimTrak, OpenFIRE, RetroShooter), Xbox-Controller, HID-Count | `Get-CimInstance Win32_PnPEntity` → VID-Matching |
| **Storage** | RetroBat, PinballY, KitRoot + optionale UNC-NAS-Pfade | `Test-Path` mit **Pre-Flight-Ping** für UNC-Shares (vermeidet 28-s-Hänger) |
| **Interference** | Epic, JoyToKey, AnyDesk, TeamViewer, GOG, Battle.net, Ubisoft, Razer … | `Get-Process` · Steam/Discord **kontextsensitiv**: nur bei aktivem `SteamInput`/`DiscordOverlay` |

**System-Vitals:** Uptime (h), RAM frei (MB), C:-Platte frei (GB), CPU-Last (%)

**Rückgabe:** `{ Status: 'OK'|'Degraded', Hardware: {…}, Storage: {…}, Interference: {ActiveBlockers: […], ContextBlockers: […]}, Vitals: {…}, ExecutionTime: '…ms' }`

**Parameter:** `ExtraStoragePaths` (UNC-Mounts), `ExtraBadProcesses`, `RetroBatRoot` (aus Cabinet-Profil).

---

### 6. Auto-Detection — Natürliche Sprache → Kit-Konfiguration

**Datei:** `core/modules/AutoDetect.ps1` · `core/modules/AutoDetect.ps1` · **API-Op:** `auto.detect`

**Keyword-Scoring-Engine** (kein LLM-Aufruf, läuft lokal in unter 100 ms):

- **9 Modul-Kataloge** (DE + EN Keywords): emulators, lightgun, controllers, displays,
  outputs, enhancements, library, frontends, pinball
- **3 Mode-Kataloge**: Easy, Custom, NerdExtreme
- **4 Preset-Hints**: easy_arcade, custom_racing, nerd_lightgun, balanced_cabinet

**Beispiel:**
> *„Ich will einen Automaten mit Lightgun, Rennspielen und CRT-Look. Alles bitte einfach."*

→ `PrimaryModule: lightgun`, `SetupMode: Easy`, `Preset: easy_arcade`, Confidence-Scores
pro Modul.

`Invoke-KitAutoDetect` wendet das Ergebnis direkt an: setzt Mode und lädt den empfohlenen Preset.

---

### 7. Rollback-Stack — Multi-Step-Rollback mit LIFO-Snapshots

**Datei:** `core/modules/Rollback.ps1` · **API-Ops:** `backups.snapshot`, `backups.rollback`

**Operationen:**

| Funktion | Beschreibung |
|---|---|
| `Push-KitRollbackPoint` | Snapshot von N Dateien → auf LIFO-Stack (persistiert in `%USERPROFILE%\RetroCabinet\rollback-stack.json`) |
| `Pop-KitRollbackPoint` | Obersten Punkt poppen → Snapshot-Dateien zurückschreiben → Snapshot-Ordner löschen |
| `Pop-KitRollbackPointByName` | Bis zum benannten Punkt zurückrollen (inkl. aller Zwischenpunkte in umgekehrter Reihenfolge) |
| `Clear-KitRollbackStack` | Stack leeren (nach erfolgreicher Multi-Step-Installation) |
| `Get-KitRollbackStack` | Stack-Tiefe und obersten Punkt anzeigen |

**Persistenz:** Stack überlebt PowerShell-Sessions. Nach einem Reboot kann der letzte
Snapshot wiederhergestellt werden.

---

### 8. Saga Transaction Pattern — Alles oder nichts

**Datei:** `core/modules/Transaction.ps1`

**Muster:**
```powershell
Invoke-KitTransaction -TransactionName "Setup Lightgun" -Action {
    Register-RollbackStep -Description "Restore INI" -RollbackAction { Restore-File ... }
    Set-EmulatorsIniValue -Path $ini -Section "input" -Values @{ lightgun = 1 }

    Register-RollbackStep -Description "Restore Registry" -RollbackAction { Set-ItemProperty ... }
    Set-ItemProperty -Path $reg -Name "GunMode" -Value 1

    # Jeder Schritt registriert sein eigenes Undo.
    # Wirft irgendetwas, wird der Stack LIFO abgebaut.
}
```

**Garantie:** Entweder alle Schritte erfolgreich, oder **keiner** — das Cabinet bleibt konsistent.

**Features:**
- `Register-RollbackStep` registriert pro Schritt eine Gegenaktion (Scriptblock)
- `Test-KitTransactionActive` prüft, ob eine Transaktion läuft
- `Get-KitTransactionDepth` zeigt Stack-Tiefe
- Bei Fehler: Stack wird LIFO abgebaut, jeder Rollback-Schritt einzeln protokolliert
- Kritischer Rollback-Fehler wird als `CRITICAL` geloggt (Cabinet möglicherweise inkonsistent)

---

### 9. Hook of the Wiimote — Wiimote als vollwertige Lightgun

**Dateien:** `output/modules/HookOfTheWiimote.ps1`, `output/modules/WiimoteHook.ps1`
**API-Op:** `outputs.wiimote_hook`

**Problem:** Wiimotes bekommen über Gunmote nur grundlegendes Rumble. Was Sinden und Gun4IR
über Hook of the Reaper an Rückstoß, Treffer-Feedback und Lampen bekommen, fehlt der Wiimote.

**Lösung:** Hook of the Wiimote übersetzt die Output-Protokolle aller Quellen auf das, was
eine Wiimote kann: einen Motor und vier LEDs.

**Architektur:**
```
TeknoParrot/FFBBlaster ─TCP 8002─┐
DemulShooter ──── WM_COPYDATA ──┼─► recoil-stretch.py ─TCP 8000─► Gunmote ArcadeHook ─► Wiimote
MAME (output windows) ─ WM_COPYDATA ┘     (Pulse-Extend · Schuss · Leben · INI-Name)
```

**Detection** (`Get-HookOfTheWiimoteInfo`): DolphinBar, Gunmote (Process + ArcadeOutputs-Ordner),
Recoil-Relay, ViGEmBus, Python, TeknoParrot, DemulShooter, MAME-Output-Mode, Port-Konflikte
(TCP 8000), Double-Consumer (MAMEHooker + Gunmote).

**Setup** (`Install-HookOfTheWiimote`):
1. Recoil-Relay (`recoil-stretch.py`) nach `tools\HookOfTheWiimote\` kopieren
2. Windows-Task für Relay (pythonw, hidden, auto-restart, 3 Wiederholungen)
3. FFBBlaster konfigurieren (`OutputsSystem=1`, `NetOutputsTCPPort=8002`)
4. DemulShooter konfigurieren (Windows Messages Output, kein TCP auf 8000)
5. MAME `output = windows` setzen
6. `hotw.json` initialisieren (Spiel-Auswahl + Effekt-Einstellungen)

**hotw.json** — Persistierte Einstellungen in `%USERPROFILE%\RetroCabinet\hotw.json`:
- `selection`: Welche Spiele bekommen Wiimote-Feedback
- `effects`: HoldMs (150), RumbleOnShot/Reload/Damage, LedMode (Life)
- `gunmoteInis`: Generierte INI-Dateien
- `blockedGames`: Spiele ohne Wiimote-Unterstützung

**Gunmote-INI-Writer** (`Write-HotwGunmoteIni`): Schreibt `ArcadeOutputs\<Name>.ini` mit
korrekten `wii <n> <Ausgang>`-Befehlen (Ausgang 0-4 = LED, 5 = Motor), sortiert, mit
Kommentar-Header. Benötigt Admin (Gunmote liegt in `C:\Program Files\`).

---

### 10. API-Fassade — 42 Operationen, MCP-Server, Isolation

**Datei:** `api/RetroCabinetKit.Api.psm1` (1163 Zeilen, Facade mit dot-sourced Submodulen)

| Kategorie | Operationen |
|---|---|
| **Core** | `operations`, `status`, `status.health`, `components`, `backups.list/check/restore/remove/export`, `support.bundle`, `setup.set_mode`, `presets.list/apply`, `auto.detect`, `backups.snapshot/rollback` |
| **Emulators** | `emulators.detect`, `emulators.install`, `emulators.configure`, `emulators.verify` |
| **Frontends** | `frontends.detect`, `frontends.install`, `frontends.set_theme`, `frontends.configure_genre_routing`, `frontends.import_library`, `frontends.export_catalog` |
| **Controllers** | `controllers.detect` |
| **Displays** | `displays.detect` |
| **Outputs** | `outputs.verify_safety`, `outputs.wiimote_hook` |
| **Pinball** | `pinbally.detect`, `pinbally.retarget` |
| **Profiles** | `profile.export`, `profile.import` |
| **Steps** | `step.pinball.01-09`, `step.lightgun.01-15`, `step.emulators.01`, `step.frontends.01` |

**Submodule-Extraktion:** `Result.ps1` (OperationResult + JSON + Anonymize) und
`Isolation.ps1` (Prozess-Isolation für MCP/JSON-Clients) aus dem 90-KB-Monolithen
extrahiert. Die Facade dot-sourced beide.

**MCP-Server** (`Start-KitMcpServer.ps1`): JSON-RPC über stdio, `read → OK` / `change →
dry-run → plan → apply`. Automatische Tool-Liste aus `Get-KitOperation`-Catalog.

---

### 11. Emulator-Paket — 15 Adapter, Shadow Override

**Adapter (5-Funktionen-Vertrag):** MAME, RetroArch, TeknoParrot, Supermodel, Model2, Cemu,
Dolphin, RPCS3, Xemu, DuckStation, PCSX2, FuturePinball, VisualPinball, PinballArcade,
PinballFX3

**INI-Handling:** `Get-EmulatorsIniPlan` und `Set-EmulatorsIniValue` nutzen den strukturierten
Parser mit Shadow-Override. Jeder Emulator kann eine `config.override.ini` haben — das Kit
respektiert User-Werte und überschreibt sie nie.

**Step:** `01-Emulators.ps1` — Detect → Configure → Shaders → Integrity

---

### 12. Frontend-Paket — 5 Adapter, Genre-Routing, Catalog-Export

**Adapter:** RetroBat, PinballY, Playnite, LaunchBox, PinUP

**Features:**
- **Genre-Routing:** 20-System-Map (`Get-FrontendGenreRouting`) — welcher Emulator startet
  welches System pro Frontend
- **Catalog-Export:** Unified JSON → Frontend-spezifisches Format
- **INI-Handling:** Wie Emulatoren: Shadow Override via `Get/Set-FrontendsIni*`

**Step:** `01-Frontends.ps1` — Detect → Configure → Theme → Genre-Routing → Catalog-Export

---

### 13. Output-Paket — 6 Middleware-Adapter + Hook of the Wiimote

**Adapter:** MAMEHooker, QMamehook, HookOfTheReaper, FFBBlaster, DirectOutputFramework, GunmoteOutput

**Safety-Features:**
- Solenoid-Schutz: 200 ms Max-Offenzeit, `SolenoidProtection = 1` — enforced, nie user-editierbar
- Double-Consumer-Erkennung: Gunmote + MAMEHooker = doppeltes Rumble
- Port-Konflikt-Prüfung: TCP 8000 (HoTR vs. Webserver)
- Wiimote-Rumble-Threshold: max 80% Stärke, max 500 ms Motor-On-Time

---

### 14. API-Monolith-Split

Die 1050-zeilige `api/RetroCabinetKit.Api.psm1` wurde in wartbare Submodule zerlegt:

| Modul | Inhalt |
|---|---|
| `api/modules/Result.ps1` | `New-KitOperationResult`, `ConvertTo-AnonymousValue`, `ConvertTo-KitApiJson` |
| `api/modules/Isolation.ps1` | `Invoke-KitOperationIsolated` (eigener PowerShell-Prozess, kein Console-Host) |

Die Facade dot-sourced beide und behält Catalog + Dispatcher.

---

### Neue API-Operationen (v1.1–v1.2)

| Operation | Kind | Version | Beschreibung |
|---|---|---|---|
| `setup.set_mode` | Change | 1.1 | Easy / Custom / NerdExtreme |
| `presets.list` | Read | 1.1 | Alle Presets (built-in + user), optional gefiltert nach Modul |
| `presets.apply` | Change | 1.1 | Preset laden → Mode + Werte gesetzt |
| `status.health` | Read | 1.2 | Hardware-Matrix, Storage, Interference, Vitals |
| `auto.detect` | Read | 1.2 | NL-Beschreibung → Module/Mode/Preset |
| `backups.snapshot` | Change | 1.2 | Snapshot von N Dateien auf Rollback-Stack |
| `backups.rollback` | Change | 1.2 | Letzten (oder benannten) Rollback-Point wiederherstellen |
| `outputs.wiimote_hook` | Read | 1.2 | Wiimote-Output-Chain-Inspektion |

---

### Neue Core-Module (v1.1–v1.2)

| Modul | Version | Zweck |
|---|---|---|
| `SetupContext.ps1` | 1.1 | Drei Setup-Levels, Context-Header-Parser, mode-aware Logging |
| `Presets.ps1` | 1.1 | Preset-CRUD, 4 Built-ins, User-Presets |
| `IniParser.ps1` | 1.1 | ConvertFrom/ConvertTo/Merge, Shadow-Override-Foundation |
| `AdapterContract.ps1` | 1.1 | Formale Validierung aller Adapter-Plugins |
| `Diagnostics.ps1` | 1.2 | System Health (3 Pillars + Vitals + UNC-Ping) |
| `AutoDetect.ps1` | 1.2 | NL-Keyword-Engine (DE+EN, 9 Module, 3 Modes, 4 Presets) |
| `Rollback.ps1` | 1.2 | Snapshot-LIFO-Stack, persistiert |
| `Transaction.ps1` | 1.2 | Saga-Pattern: Invoke-KitTransaction + Register-RollbackStep |
| `WiimoteHook.ps1` | 1.2 | Wiimote-Output-Chain-Inspektion (Output-Paket) |
| `HookOfTheWiimote.ps1` | 1.2 | Vollständiger Hook: Detection, Setup, hotw.json, Gunmote-INIs (Output-Paket) |

---

### Bugfixes (v1.0 → v1.2)

| Bug | Fix |
|---|---|
| INI-Parser ignorierte `[Section]`-Header | Section-Tracker + `[regex]::Escape($key)` |
| Doppelte `Get-LibrarySystemSnapshot` (Rekursion) | `Get-LibraryBaseSnapshot` extrahiert |
| `Export-ModuleMember` ließ neue Funktionen blind | Explizite Namen in Core + Output |
| `Get-SystemHealth`: RetroBat-Pfad hart `C:\RetroBat` | `$RetroBatRoot`-Parameter + Fallback |
| `Get-SystemHealth`: Steam pauschal als Störer | Kontextsensitiv (nur bei `SteamInput`) |
| `Get-SystemHealth`: UNC-Pfade hingen 28 s | Pre-Flight-Ping mit 1-s-Timeout |
| `AdapterContract.Tests.ps1` ohne UTF-8-BOM | BOM geschrieben |
| `ApiVersion = 1.3` bei 8 neuen Operationen | → 1.4 |
| Alle Em-Dashes (`—`) → `--` (PS-5.1-Parser) | ASCII-Ersatz in allen neuen Dateien |

---

### Test-Suiten

| Test | Prüft |
|---|---|
| `tests/api/V090Api.Tests.ps1` | Emulators-Catalog, Modul, Detect, Verify, Adapter-Contract |
| `tests/api/V100Api.Tests.ps1` | Frontends-Catalog, Modul, Detect, Adapter-Contract, Extensibility |
| `tests/core/AdapterContract.Tests.ps1` | Multi-Section-INI, Contract-Compliance (20 Adapter), Idempotenz, Backup |
| `tests/core/KitDatabase.Tests.ps1` | SQLite Safe-Update, WhatIf, Purpose-Validierung |
| `tests/core/KitText.Tests.ps1` | I18n-Text-Cache, Fallback |

---

### Statistiken

- **42 API-Operationen** im Catalog (8 neu in v1.1–v1.2, 10 ursprünglich, 24 aus Steps/Packages)
- **25 Core-Module** (16 Original + 9 neu)
- **10 Pakete** (core, pinball, lightgun, arcade, pads, output, displays, enhancements, library, emulators, frontends)
- **35+ Adapter** (15 Emulatoren, 5 Frontends, 6 Output, 6 Lightgun, 12 Arcade, …)
- **~300 PowerShell-Dateien** im Repository
- **48 Kern-Dateien syntaktisch geprüft: 0 Fehler**
- **Versionen:** Kit 1.2.0, API 1.4