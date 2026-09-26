# Wiimote Lightgun & RetroBat Einrichtungsanleitung

Umfassendes technisches Handbuch für den Aufbau eines latenzarmen Multi-Emulator Wiimote-Lightgun-Setups mit **Fried's Retrogaming Kit**.

---

## 📌 Architektur-Überblick

Nintendo Wiimotes als PC-Lightguns bieten ein authentisches Arcade-Erlebnis zu einem Bruchteil der Kosten dedizierter Lightgun-Hardware. In der Praxis scheitern manuelle Setups jedoch oft an typischen Problemen: kollidierende Mauszeiger, unkontrolliertes Zittern des Cursors in Frontend-Menüs, Steam-Desktop-Konfigurationen, die virtuelle Controller kapern, und widersprüchliche Tastenbelegungen zwischen verschiedenen Emulatoren.

Fried's Retrogaming Kit macht RetroBat zu einer schlüsselfertigen Wiimote-Lightgun-Station durch die Orchestrierung von vier Kernkomponenten:
1. **Mayflash DolphinBar (Hardware-Modus 4)**: Sorgt für latenzarmes Infrarot-Tracking und Controller-Synchronisation.
2. **Nefarius ViGEmBus**: Emuliert virtuelle Xbox 360 Gamepads.
3. **Gunmote (`gunmotelabs`)**: Übersetzt Wiimote-IR-Koordinaten und Tastenimpulse in virtuelle Xbox 360 Controller-Achsen und -Buttons.
4. **RetroCabinetKit Profil-Automation**: Wechselt Eingabeprofile automatisch beim Spielstart je nach System, sodass Menü-Navigation stabil bleibt und das Zielen im Spiel pixelgenau funktioniert.

```
       [ Mayflash DolphinBar (Modus 4) ]
                     │ (USB / IR)
                     ▼
             [ Nintendo Wiimote ]
                     │
                     ▼
         [ Gunmote (gunmotelabs) ]
                     │
        ┌────────────┴────────────┐
        ▼                         ▼
 [ ViGEmBus (Virtuelles X360) ] [ Windows-Mauszeiger ]
        │                         │
        └────────────┬────────────┘
                     ▼
      [ RetroBat & Ziel-Emulatoren ]
 (MAME64, DuckStation, Demul, TeknoParrot)
```

---

## 🚀 Schritt-für-Schritt-Ablauf

Alle Schritte folgen dem Schema **Test → Invoke → Verify**. Jeder Schritt unterstützt `-WhatIf` für zerstörungsfreie Trockenläufe.

### Schritt 1: RetroBat erkennen (`01-Detect.ps1`)
- **Aktion**: Überprüft das RetroBat-Verzeichnis (z. B. `C:\RetroBat`).
- **Verifikation**:
  - Prüft das Vorhandensein von `retrobat.exe` und `retrobat.ini`.
  - Verifiziert den Zugriff auf `system\es_settings.cfg` und die Emulator-Ordner.
  - Speichert Version und Konfigurationspfade im Kit-Zustand.

### Schritt 2: Hardware-Prüfung (`02-Hardware.ps1`)
- **Aktion**: Prüft angeschlossene USB-Lightgun-Hardware rein lesend.
- **Prüfpunkte**:
  - **DolphinBar Modus 4**: Sucht in den Windows-PnP-Geräten nach der Hardware-ID `USB\VID_057E&PID_0306` (DolphinBar im Wiimote-Controller-Modus).
  - Erkennt falsche Modi (Modus 1/2 Tastatur/Maus oder Gamepad-Modus) und gibt klare Handlungshinweise.
  - Prüft den Windows-Bluetooth-Dienst (`bthserv`).
  - Überprüft die Bildwiederholraten der Monitore (60 Hz empfohlen; unter 50 Hz erfolgt eine Warnung).

### Schritt 3: ViGEmBus Virtueller Controller-Treiber (`03-ViGEmBus.ps1`)
- **Aktion**: Prüft oder installiert den Nefarius Virtual Gamepad Emulation Bus (`ViGEmBus`).
- **Details**:
  - Kontrolliert, ob der Treiberdienst installiert und aktiv ist.
  - Wenn fehlend: Lädt den offiziell signierten Installer von `nefarius/ViGEmBus` in den geschützten ProgramData-Ordner herunter.
  - Verifiziert digitale Signatur (Authenticode) und SHA-256-Hash vor der stillen Installation (`/qn`).
  - *Erfordert Administratorrechte.*

### Schritt 4: Gunmote Einrichtung & Privilegierter Task (`04-Gunmote.ps1`)
- **Aktion**: Bindet Gunmote (`gunmotelabs/Gunmote`) als Übersetzungs-Engine ein.
- **Ablauf**:
  - Leitet den Benutzer zum Download und zur Installation des offiziellen Gunmote-Releases nach `C:\Program Files\Gunmote` an.
  - Registriert eine geplante Windows-Aufgabe `RetroCabinetKit Gunmote`, die bei Benutzeranmeldung mit höchsten Rechten (`RunLevel = Highest`) startet.
  - Dadurch kann Gunmote Tasten- und Controller-Ereignisse auch in erhöhte Spielefenster einspeisen, ohne dass UAC-Meldungen das Spiel unterbrechen.

### Schritt 5: Störquellen bereinigen (`05-Interference.ps1`)
- **Aktion**: Schaltet Hintergrunddienste ab, die Lightgun-Eingaben kapern oder stören.
- **Maßnahmen**:
  - **Steam-Desktop-Konfiguration**: Trägt die DolphinBar-Hardware-IDs in die `controller_blacklist` von Steams `config\config.vdf` ein. Dies verhindert, dass Steam Input die DolphinBar als Desktop-Maus vereinnahmt.
  - **Steam Input Xbox-Unterstützung**: Liest `localconfig.vdf` aus und empfiehlt das Abschalten der Xbox-Konfigurationsunterstützung in den Steam-Einstellungen.
  - **VMulti-Treiberkonflikte**: Erkennt vorhandene `GunmoteVMultiGuard`-Tasks und deaktiviert sie nach Bestätigung sicher.

### Schritt 6: Gunmote-Layouts einspielen (`06-GunmoteLayouts.ps1`)
- **Aktion**: Hinterlegt optimierte Profile im `Keymaps`-Ordner von Gunmote und aktualisiert `Keymaps.json`.
- **Eingespielte Profile**:
  - `Default (Menu Pad)`: Virtuelles Xbox 360 D-Pad ohne Mauszeiger für ruhige Menüführung in RetroBat ohne wild umherirrenden Cursor.
  - `Pad 4:3`: Konfiguriert für MAME, PSX, Model 2 und Model 3 mit analoger Trigger-Zuordnung.
  - `TeknoParrot`: Belegung mit Unterstützung des rechten Sticks für moderne Arcade-Titel.
  - `Naomi / Atomiswave`: Angepasste Bindings für Demul und Flycast.
  - `Mouse`: Direkte Mausemulation für RetroArch-Lightgun-Cores und PCSX2.
  - Off-Screen-Reload (Nachladen außerhalb des Bildschirms) ist explizit aktiviert; die Home-Taste der Wiimote ist deaktiviert, um versehentliche Menü-Pausen zu vermeiden.

### Schritt 7: RetroBat-Einstellungen harmonisieren (`07-RetroBatSettings.ps1`)
- **Aktion**: Passt RetroBat-Konfigurationsdateien an, um Treiberkonflikte zu verhindern.
- **Konfigurierte Einstellungen**:
  - `es_settings.cfg`: Setzt `use_guns=0` und `disableautocontrollers=1` für MAME, Naomi, Atomiswave, PSX, Model 2, Model 3 und TeknoParrot. Dies verhindert, dass RetroBats interne Lightgun-Verwaltung dazwischenfunkt.
  - Setzt Standard-Emulatoren: MAME auf `mame64` (mit `ctrlr`-Profil `custom1`), Naomi auf `demul` (`use_demulshooter=0`), PSX auf `duckstation`.
  - `es_input.cfg`: Hinterlegt die Controller-Belegung für das virtuelle Xbox 360 Pad so, dass das Ziehen des Wiimote-Triggers (Button 0 / A) Spiele im Menü direkt startet.

### Schritt 8: Profil-Automation (`08-ProfileAutomation.ps1`)
- **Aktion**: Richtet Hintergrund-Überwachung und RetroBat-Startskripte ein.
- **Umsetzung**:
  - Kopiert `profile.ps1` in den geschützten Systemordner `%ProgramData%\RetroCabinetKit\lightgun\`.
  - Registriert geplante Aufgaben: `RetroCabinetKit Gunmote Profile <Menu|TP|Pad43|Naomi|Mouse>` mit höchsten Rechten für das angemeldete Benutzerkonto.
  - Hinterlegt Batch-Hooks in RetroBat:
    - `scripts\game-start\rck-gunmote-profile.bat`: Liest das startende System aus und wechselt das Gunmote-Layout automatisch.
    - `scripts\game-end\rck-gunmote-profile.bat`: Setzt beim Verlassen des Spiels automatisch wieder das `Menu`-Pad-Profil aktiv.
- *Details zum Sicherheitsmodell und wie man die Aufgaben deaktiviert, findest du in [SECURITY.md](../SECURITY.md).*

### Schritt 9: Gemessene Verifikation & Kalibrierung (`09-Verify.ps1`)
- **Aktion**: Prüft alle Teilsysteme durch echte Messungen statt Annahmen.
- **Unterprüfungen**:
  1. `lightgun-9-xinput`: Liest virtuelle Xbox-Pads über `XInputGetState` aus. Fordert den Benutzer auf, an jeder verbundenen Wiimote innerhalb von 15 Sekunden den Trigger zu betätigen, um die Signalübertragung live zu bestätigen.
  2. `lightgun-9-profile`: Prüft anhand von `logs\profile.log`, ob die Profil-Automation beim Spielstart angesprochen wurde.
  3. `lightgun-9-launcher`: Liest `emulatorLauncher.log` aus, um sicherzustellen, dass `use_guns=0` gegriffen hat und keine fremden Gun-Treiber gestartet wurden.


### Phase 2 — Arcade-Emulatoren (optional)

Die Schritte 10–13 fassen nur Emulatoren an, die du wirklich hast; fehlende werden gemeldet, nicht installiert. Jeder Schritt zeigt zuerst seinen Plan und schreibt nur, solange RetroBat und der betroffene Emulator geschlossen sind — mit Backup vor jeder Änderung.

### Schritt 10: TeknoParrot-Profile (`10-TeknoParrot.ps1`)
- `lightgun-10-tp-paths`: `GamePath`-Einträge in `UserProfiles\*.xml`, die noch in eine fremde Installation zeigen (ein gekaufter Build behält die Ordner seines Erstellers), werden auf dieselbe Datei unterhalb dieses RetroBat umgestellt — nur wenn sie hier existiert; fehlende Spiele werden gemeldet.
- `lightgun-10-tp-bind`: Gun-Spiele werden auf XInput gelegt (Wiimote 1/2 = XInput-Index 0/1, B = Schuss, A = Nachladen, rechter Stick zielt). Touchscreen-Spiele und per `-Exclude` übergebene Spiele bleiben unverändert.
- `lightgun-10-tp-settings`: `es_settings.cfg`: `teknoparrot.use_guns=0`, `disableautocontrollers=1` je belegtem Spiel, Reste des Build-Erstellers entfernt.

### Schritt 11: Spielelisten (`11-GameLists.ps1`)
- `lightgun-11-tp-duplicates`: Ordner in `roms\teknoparrot`, die ein aktives Spiel doppeln, werden nach deiner Bestätigung des Plans nach `<RetroBat>\_duplicates\teknoparrot\` **verschoben**. Es wird nichts gelöscht.
- `lightgun-11-tp-gamelist`: `gamelist.xml` erhält einen Eintrag für jedes registrierte Spiel; Ordner ohne Profil werden ausgeblendet, bis sie eines haben.
- Nur gemeldet: fehlende Medien, Einträge ohne Ordner und fest verdrahtete `<emulator>`/`<core>`-Einträge.

### Schritt 12: Demul & DemulShooter (`12-Demul.ps1`)
- `lightgun-12-demul`: Prüft dein **selbst mitgebrachtes** Demul 0.7a (`demul.exe`, `nvram`, BIOS `naomi.zip` / `awbios.zip`). Closed Source — das Kit bietet keinen Download an.
- `lightgun-12-demulshooter`: Prüft DemulShooter und richtet dessen Raw-Input für die Gunmote-Xbox-Pads ein. Geführter Download von den offiziellen Releases (argonlefou/DemulShooter); `-DemulShooterPath` für einen eigenen Ort.
- `lightgun-12-demul-settings`: `naomi.emulator=demul`, `atomiswave.emulator=demul`, `use_guns=0`, `disableautocontrollers=1`.
- `lightgun-12-demul-gamelist`: Meldet fest verdrahtete Flycast-/libretro-Emulatoren bei Gun-Spielen in den Naomi-/Atomiswave-Spielelisten; `-RemoveHardwired` entfernt sie.

### Schritt 13: Model 2 & Supermodel (`13-Model2Supermodel.ps1`)
- `lightgun-13-model2`: Prüft deinen **selbst mitgebrachten** Model-2-Emulator (`EMULATOR.EXE`, `emulator_multicpu.exe`, `Emulator.ini`). Closed Source — kein Download. DemulShooter hängt sich über `-target=model2m` ein.
- `lightgun-13-supermodel`: Prüft und konfiguriert Supermodel (Model 3): Fadenkreuz an, XInput-Gun-Belegung. Offizielle Releases von trzy/Supermodel.
- `lightgun-13-model-settings`: `model2.use_guns=0`, `model3.use_guns=0`, `disableautocontrollers=1` für beide.

### Phase 3 — Konsolen-Emulatoren (geführte Prüfung)

### Schritt 14: DuckStation & PCSX2 (`14-DuckStationPcsx2.ps1`)
- `lightgun-14-duckstation-pcsx2`: **Prüft und berichtet, keine automatische Belegung.** Liest `settings.ini`, `gamesettings\<SERIAL>.ini` und `PCSX2.ini`, erklärt das *Automatic Mapping* auf `XInput-0` und markiert Konami-Spiele, die den Justifier statt der GunCon brauchen (z. B. Die Hard Trilogy, Crypt Killer). Flycast ist nicht abgedeckt.

---

## 🎮 Emulator-Integrationsstatus

Die Lightgun-Basisinfrastruktur (DolphinBar Modus 4, ViGEmBus, Gunmote und RetroBat-Anbindung) ist vollständig einsatzbereit. Die Emulator-Schritte 10–14 bauen darauf auf:

| Emulator / Plattform | Status | Schritt | Eingabe-Pipeline |
| :--- | :--- | :--- | :--- |
| **MAME (Arcade Classics)** | :white_check_mark: Automatisiert | 7 | MAME64 + virtuelles XInput-Pad (`use_guns=0`) |
| **TeknoParrot (Moderne Arcade)** | :white_check_mark: Automatisiert | 10–11 | XInput-Gun-Belegung, rechter Stick zielt, Spielelisten |
| **Demul & DemulShooter** | :warning: Automatisiert, Demul selbst mitgebracht | 12 | DemulShooter-Raw-Input auf den Gunmote-Xbox-Pads |
| **Sega Model 2** | :warning: Automatisiert, Emulator selbst mitgebracht | 13 | DemulShooter (`-target=model2m`) |
| **Supermodel (Model 3)** | :white_check_mark: Automatisiert | 13 | XInput-Gun-Belegung, Fadenkreuz |
| **DuckStation (PS1) / PCSX2 (PS2)** | :mag: Geführte Prüfung | 14 | Automatic Mapping auf `XInput-0`, GunCon-/Justifier-Hinweise |
| **Flycast** | :no_entry: Nicht abgedeckt | — | — |
| **Rumble & Force-Feedback** | :construction: Geplant | — | OutputHooker / MAMEHooker, siehe [ROADMAP](../ROADMAP.md) |

---

## 🛠️ CLI-Kurzanleitung

```powershell
# Zum Kit-Ordner wechseln
cd "D:\Games\RetroCabinetKit"

# RetroBat für Wiimote-Lightgun konfigurieren
powershell -ExecutionPolicy Bypass -File lightgun\steps\01-Detect.ps1 -RetroBatRoot "C:\RetroBat"
powershell -ExecutionPolicy Bypass -File lightgun\steps\02-Hardware.ps1
powershell -ExecutionPolicy Bypass -File lightgun\steps\03-ViGEmBus.ps1 -AllowInstall
powershell -ExecutionPolicy Bypass -File lightgun\steps\04-Gunmote.ps1
powershell -ExecutionPolicy Bypass -File lightgun\steps\05-Interference.ps1 -DisableVMultiGuard
powershell -ExecutionPolicy Bypass -File lightgun\steps\06-GunmoteLayouts.ps1 -Mode Keep
powershell -ExecutionPolicy Bypass -File lightgun\steps\07-RetroBatSettings.ps1
powershell -ExecutionPolicy Bypass -File lightgun\steps\08-ProfileAutomation.ps1
powershell -ExecutionPolicy Bypass -File lightgun\steps\09-Verify.ps1 -XInputTimeoutSeconds 15

# Arcade-Emulatoren (optional)
powershell -ExecutionPolicy Bypass -File lightgun\steps\10-TeknoParrot.ps1
powershell -ExecutionPolicy Bypass -File lightgun\steps\11-GameLists.ps1
powershell -ExecutionPolicy Bypass -File lightgun\steps\12-Demul.ps1
powershell -ExecutionPolicy Bypass -File lightgun\steps\13-Model2Supermodel.ps1

# Konsolen-Emulatoren (geführte Prüfung)
powershell -ExecutionPolicy Bypass -File lightgun\steps\14-DuckStationPcsx2.ps1
```
