# Fehlerbehebungs-Handbuch (Troubleshooting)

Umfassende Diagnose, Fehlercodes und praxiserprobte Lösungen für **Fried's Retrogaming Kit**.

---

## ⚡ Allgemeine Systemprobleme

### 1. Ausführung von PowerShell-Skripten blockiert (`PSSecurityException`)
- **Symptom**: `Die Datei kann nicht geladen werden, da die Ausführung von Skripten auf diesem System deaktiviert ist.`
- **Ursache**: Windows-Clientversionen deaktivieren standardmäßig die Ausführung ungesigneter Skripte.
- **Lösung**:
  - Nutze die beiliegenden `.cmd`-Starter (`Start-Kit.cmd`, `Start-Pinball.cmd`, `Start-Lightgun.cmd`). Diese setzen den Parameter `-ExecutionPolicy Bypass` isoliert für den jeweiligen Prozess.
  - Oder starte die Skripte manuell über PowerShell mit Bypass:
    ```powershell
    powershell -NoProfile -ExecutionPolicy Bypass -File pinball\steps\01-Detect.ps1
    ```

### 2. Administratorrechte & Benutzer-Sperre (SID-Mismatch)
- **Symptom**: Warnung `Kit running elevated as different user` oder blockierte Registry-Schritte.
- **Ursache**: Wenn die PowerShell mit einem separaten Admin-Konto gestartet wird, werden `HKCU`-Schlüssel (Current User) in den falschen Benutzer-Hive geschrieben.
- **Lösung**: Starte die PowerShell direkt unter dem normalen Benutzerkonto, unter dem auch gespielt wird, und bestätige die UAC-Abfrage. Das Kit übergibt die Benutzer-SID automatisch.

---

## 🎱 Virtual-Pinball Probleme

### 1. COM-Registrierung schlägt fehl (`regsvr32` Fehler 0x80004005 / 0x80070005)
- **Symptom**: Schritt `pinball-6-register` meldet `Failed` für `PinMAME.dll`, `B2S.Server.dll` oder `FlexDMD.dll`.
- **Ursachen**:
  - Fehlende Administratorrechte bei der Ausführung.
  - Fehlende Visual C++ Runtimes (z. B. VC++ 2010 x86 für die 32-Bit-PinMAME).
  - Architektur-Konflikt (32-Bit DLL mit 64-Bit regsvr32 registriert oder umgekehrt).
- **Lösung**:
  1. Führe Schritt 3 (`03-Dependencies.ps1`) mit `-AllowDownload` erneut aus, um alle Runtimes zu vervollständigen.
  2. Führe Schritt 6 mit erhöhten Administratorrechten aus.
  3. Prüfe die Ordnerberechtigungen: Rechtsklick auf `D:\Pinball\vPinball` > Eigenschaften > Sicherheit: Dein Benutzerkonto muss Vollzugriff besitzen.

### 2. Backglass bleibt schwarz oder liegt hinter dem Spielfeld
- **Symptom**: Tische starten, aber das DirectB2S-Backglass ist unsichtbar oder wird vom VPX-Spielfenster verdeckt.
- **Ursachen**:
  - Das Playfield-Display ist in Windows nicht als primärer Hauptbildschirm definiert.
  - In `ScreenRes.txt` sind falsche oder negative Koordinaten hinterlegt.
  - Die Windows-Skalierung steht auf 125 % oder 150 % statt 100 %.
- **Lösung**:
  1. In den Windows-Einstellungen > System > Bildschirm: Wähle das Playfield aus und aktiviere **„Diese Anzeige als Hauptbildschirm verwenden“**.
  2. Setze die Skalierung auf **allen** Bildschirmen zwingend auf **100 %**.
  3. Führe Schritt 8 (`08-Screens.ps1 -Mode Replace`) erneut aus, um `ScreenRes.txt` neu zu berechnen.

### 3. VPinMAME ROM nicht gefunden / Kein Sound
- **Symptom**: VPX-Tisch bricht mit Fehlermeldung `ROM not found` ab.
- **Ursache**: Der Registry-Wert `vpmpath` zeigt noch auf das alte Installationsverzeichnis.
- **Lösung**:
  - Führe Schritt 5 (`05-Relocate.ps1 -Mode Move`) erneut aus, um `HKCU\Software\Freeware\Visual PinMame\vpmpath` auf den neuen Pfad `vPinball\VPinMAME` zu aktualisieren.
  - Öffne `D:\Pinball\vPinball\VPinMAME\Setup.exe`, klicke auf **Test**, wähle dein ROM aus und überprüfe den Pfad.

### 4. Future Pinball & BAM stürzen beim Start ab
- **Symptom**: Tische laden nicht oder Future Pinball stürzt mit weißem Bildschirm ab.
- **Ursache**: Windows-Vollbildoptimierungen kollidieren mit der BAM-Injektion, oder `FPLoader.exe` wurde noch nie als Administrator gestartet.
- **Lösung**:
  1. Führe Schritt 7 (`07-FpBamSetup.ps1`) erneut aus.
  2. Klicke mit der rechten Maustaste auf `D:\Pinball\Future Pinball\FPLoader.exe` und wähle **Als Administrator ausführen** (einmalig erforderlich).
  3. Stelle sicher, dass die BAM-Cabinet-Reset-Batchdatei fehlerfrei durchgelaufen ist.

---

## 🎯 Wiimote Lightgun & RetroBat Probleme

### 1. DolphinBar wird nicht erkannt (Falscher Modus / 4 blinkende LEDs)
- **Symptom**: Schritt 2 meldet `DolphinBar Mode 4 missing`.
- **Ursachen**:
  - Die DolphinBar steht auf Modus 1, 2 (Tastatur/Maus) oder Modus 3 (Gamepad).
  - Die Wiimote ist nicht mit der DolphinBar gekoppelt.
- **Lösung**:
  1. Drücke die Taste auf der Mayflash DolphinBar, bis **LED 4** leuchtet.
  2. Drücke die **SYNC**-Taste an der DolphinBar und danach gleichzeitig die Tasten **1 und 2** (oder die rote SYNC-Taste im Batteriefach) auf der Wiimote.
  3. Sobald gekoppelt, leuchtet LED 1 oder 2 an der Wiimote dauerhaft blau.

### 2. Steam Desktop-Konfiguration kapert die Lightgun
- **Symptom**: Beim Betätigen des Triggers öffnet sich das Steam-Overlay, der Desktop-Cursor springt unkontrolliert oder die Bildschirmtastatur erscheint.
- **Ursache**: Steam Input fängt den virtuellen Xbox 360 Controller ab und übersetzt ihn in Desktop-Mauseingaben.
- **Lösung**:
  1. Beende Steam vollständig (auch im Info-Bereich der Taskleiste).
  2. Führe Schritt 5 (`05-Interference.ps1`) erneut aus.
  3. Öffne in Steam die Einstellungen > **Controller**:
     - Deaktiviere „Steam Input für Xbox-Controller aktivieren“.
     - Setze das „Desktop-Layout“ auf **Deaktiviert**.

### 3. Zitternder Cursor, Drift oder Tracking-Verlust
- **Symptom**: Das Fadenkreuz springt unruhig oder verschwindet am Bildschirmrand.
- **Ursachen**:
  - Sonnenlicht, Glühbirnen, Halogenstrahler, Spiegel oder Kerzen strahlen Infrarotlicht in die Kamera der Wiimote ein.
  - Der Positionsschalter der DolphinBar (Top / Bottom) stimmt nicht mit der realen Platzierung überein.
  - Zu geringer oder zu großer Abstand zum Bildschirm.
- **Lösung**:
  1. Prüfe den Schalter an der DolphinBar: Steht er auf **Top** (oben auf dem Monitor) oder **Bottom** (unten am Fuß)? Passe ihn an.
  2. Idealer Spielerabstand: 1,5 bis 2,5 Meter zum Bildschirm.
  3. Dunkle direkte Lichtquellen im Raum ab.
  4. Überprüfe mit einer Smartphone-Kamera (sieht Infrarotlicht), ob beide IR-LEDs der Sensorleiste leuchten.

### 4. RetroBat überschreibt Gun-Einstellungen beim Beenden
- **Symptom**: Nach dem Schließen von RetroBat sind Gun-Zuweisungen verloren oder reagieren nicht mehr auf Schüsse.
- **Ursache**: RetroBats eigene Lightgun-Verwaltung wurde wieder aktiv, oder RetroBat lief während der Konfigurationsschritte.
- **Lösung**:
  1. **Schließe RetroBat, Gunmote und Steam immer vollständig vor dem Ausführen der Kit-Schritte.**
  2. Führe Schritt 7 (`07-RetroBatSettings.ps1`) erneut aus, damit `use_guns=0` und `disableautocontrollers=1` in `es_settings.cfg` dauerhaft gesetzt sind.

### 5. Profil-Automation wechselt Layouts beim Spielstart nicht
- **Symptom**: Beim Start von MAME oder TeknoParrot aus RetroBat bleibt Gunmote auf dem `Menu Pad`-Profil.
- **Ursachen**:
  - Geplante Aufgaben wurden nicht registriert oder sind deaktiviert.
  - RetroBat-Skripte fehlen oder wurden von Sicherheitssoftware blockiert.
- **Lösung**:
  1. Überprüfe den Status der Aufgaben in PowerShell:
     ```powershell
     Get-ScheduledTask -TaskName "RetroCabinetKit Gunmote Profile*"
     ```
  2. Prüfe das Automations-Logfile:
     ```powershell
     Get-Content "C:\ProgramData\RetroCabinetKit\lightgun\logs\profile.log" -Tail 20
     ```
  3. Führe Schritt 8 (`08-ProfileAutomation.ps1`) als Administrator erneut aus.
