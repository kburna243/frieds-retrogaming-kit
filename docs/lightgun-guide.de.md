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

---

## 🎮 Emulator-Integrationsstatus

Die Lightgun-Basisinfrastruktur (DolphinBar Modus 4, ViGEmBus, Gunmote und RetroBat-Anbindung) ist vollständig einsatzbereit. Dedizierte Emulator-Einrichtungsmodule befinden sich in aktiver Entwicklung:

| Emulator / Plattform | Status | Eingabe-Pipeline |
| :--- | :--- | :--- |
| **MAME (Arcade Classics)** | :white_check_mark: Bereit | MAME64 + XInput Virtual Pad (`use_guns=0`) |
| **DuckStation (PSX)** | :white_check_mark: Bereit | GunCon-Emulation via Virtuellem Controller / Maus |
| **TeknoParrot (Moderne Arcade)** | :construction: In Entwicklung | Right-Stick-Profil + TeknoParrotUI |
| **Demul & DemulShooter** | :construction: In Entwicklung | DemulShooter Hook + Naomi-Profil |
| **Sega Model 2 & Model 3** | :construction: In Entwicklung | Pad 4:3-Profil + Supermodel / M2Emulator |
| **PCSX2 (PS2)** | :construction: In Entwicklung | GunCon 2 Maus-Injektion |
| **Rumble & Force-Feedback** | :construction: In Entwicklung | OutputHooker / MAMEHooker Anbindung |

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
```
