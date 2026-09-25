# Virtual-Pinball Einrichtungsanleitung

Umfassendes technisches Handbuch zum Umziehen und Wiederherstellen von Virtual-Pinball-Cabinets mit **Fried's Retrogaming Kit**.

---

## 📌 Architektur-Überblick

Das Aufsetzen eines digitalen Flipperautomaten (Virtual Pinball Cabinet) war in der Vergangenheit oft fehleranfällig. Komponenten wie Visual Pinball X, VPinMAME, B2S Backglass Server, FlexDMD, Freezy's DMD Extensions und Future Pinball/BAM verankern Pfade tief in SQLite-Datenbanken, Konfigurationsdateien und der Windows-Registry.

Fried's Retrogaming Kit vereinfacht diesen Ablauf durch eine automatisierte, zerstörungsfreie Relokations- und Wiederherstellungs-Engine, basierend auf der bewährten **Baller-Installer**-Verzeichnisstruktur:

```
<PinballRoot>\
├── 2-Programs\            # Runtimes, Hilfsprogramme
├── DOFLinx\               # DirectOutput-Bridge für Future Pinball
├── Future Pinball\        # Future Pinball und BAM (Better Arcade Mode)
└── vPinball\
    ├── B2SBackglassServer\  # DirectB2S Backglass Server
    ├── PinUPSystem\         # PinUP Popper Frontend, Player und PUPDatabase.db
    ├── VisualPinball\       # Visual Pinball X (VPX) Tables, Scripts, VPinballX.ini
    └── VPinMAME\            # VPinMAME ROM-Emulation, DmdDevice.ini, nvram, cfg
```

---

## 🔄 Zwei Betriebsmodi

Der Pinball-Installer bietet zwei klar definierte Modi:

| Modus | Anwendungsfall | Pfad- und Registry-Verhalten |
| :--- | :--- | :--- |
| **Move auf diesem PC** | Umzug eines vorhandenen Builds auf eine neue schnelle SSD oder ein neues Verzeichnis (z. B. von `E:\Old Build` nach `D:\Pinball`). | Liest bestehende Konfigurationen und Windows-Registry-Werte (`HKCU\Software`) aus und passt alle Pfade an Ort und Stelle an. Benutzerdefinierte Einstellungen bleiben erhalten. |
| **Rebuild auf neuem Windows** | Neuinstallation von Windows 10/11 oder Aufbau eines komplett neuen Cabinet-PCs. | Importiert Einstellungen aus einem früheren Kit-Backup-ZIP oder einem alten `NTUSER.DAT`-Registry-Hive und schreibt Pfade beim Import um. Ohne Backup werden sichere Standardwerte gesetzt. |

---

## 🚀 Schritt-für-Schritt-Ablauf

Jeder Schritt folgt dem Prinzip **Test → Invoke → Verify**. Ein Schritt wird erst dann als erledigt markiert, wenn die Live-Prüfung auf dem System erfolgreich war. Alle Schritte unterstützen `-WhatIf` für zerstörungsfreie Trockenläufe (Dry-Runs).

### Schritt 1: Build erkennen (`01-Detect.ps1`)
- **Aktion**: Überprüft das angegebene Quellverzeichnis.
- **Verifikation**:
  - Öffnet `vPinball\PinUPSystem\PUPDatabase.db` direkt über die Windows-eigene `winsqlite3.dll` ohne externe Abhängigkeiten.
  - Ermittelt den ursprünglichen Stammpfad (`OldRoot`) aus `GlobalSettings.GlobalMediaDir`.
  - Erkennt begleitende Ordner (z. B. `DOFLinx` und BAM).
  - Ermittelt Verzeichnisgröße und Dateianzahl.

### Schritt 2: Zielverzeichnis wählen (`02-Target.ps1`)
- **Aktion**: Validiert das gewünschte Zielverzeichnis (z. B. `D:\Pinball`).
- **Sicherheitsprüfungen**:
  - Stellt sicher, dass das Ziel auf einem lokalen NTFS/ReFS-Laufwerk liegt (Netzwerkfreigaben werden für zuverlässigen Betrieb abgewiesen).
  - Prüft, ob der freie Speicherplatz die Build-Größe plus 10 % Sicherheitspuffer übersteigt.
  - Verhindert versehentliche Installationen direkt in Laufwerkswurzeln (wie `C:\`) oder Systemordner.

### Schritt 3: Voraussetzungen & Runtimes (`03-Dependencies.ps1`)
- **Aktion**: Prüft alle für VPX und PinMAME erforderlichen Systemkomponenten.
- **Verwaltete Komponenten**:
  - Visual C++ Runtimes: 2005, 2008, 2010, 2012, 2013 und 2015–2022 (jeweils x86 und x64).
  - Microsoft .NET Framework: 3.5 (Aktivierung via DISM) und 4.8.
  - DirectX 9.0c Endbenutzer-Runtime (`d3dx9_43.dll`).
- **Integrität**: Nutzt bevorzugt lokale Installer aus `2-Programs\All In One Runtimes` oder `Installer\directx9`. Bei erforderlichen Microsoft-Downloads werden vorab digitale Signaturen (Authenticode) geprüft.

### Schritt 4: Fortsetzbarer Kopiervorgang (`04-Copy.ps1`)
- **Aktion**: Überträgt die Build-Dateien mittels robocopy von der Quelle zum Ziel.
- **Besonderheiten**:
  - Unterbrechbar und fortsetzbar, ohne bereits kopierte Dateien erneut zu übertragen.
  - Schließt flüchtige Cache-Dateien und temporäre Logs automatisch aus.
  - Prüft nach Abschluss Dateianzahl und Byte-Größen.

### Schritt 5: Relokation & Pfade umschreiben (`05-Relocate.ps1`)
- **Aktion**: Führt ein tiefes Umschreiben aller absoluten Pfade von `OldRoot` zu `NewRoot` durch.
- **Bereiche**:
  1. **SQLite-Datenbank (`PUPDatabase.db`)**: Aktualisiert Tabelleneinträge, Emulator-Startbefehle, Medienordner und PuP-Pack-Pfade.
  2. **Konfigurationsdateien**: Passt Pfade in `VPinballX.ini`, `PinUpPlayer.ini`, `ScreenRes.txt`, `DmdDevice.ini` und `DOFLinx.ini` an.
  3. **Windows-Registry**: Ändert Werte unter `HKCU\Software\Freeware\Visual PinMame`, `HKCU\Software\Visual Pinball` und `HKCU\Software\Future Pinball`.
  4. **Verknüpfungen**: Schreibt `.lnk`-Verknüpfungen im Startmenü und auf dem Desktop um.
  - **Idempotenz**: Wiederholtes Ausführen führt zu keinen unerwünschten Änderungen.

### Schritt 6: COM-Komponenten registrieren (`06-Register.ps1`)
- **Aktion**: Registriert die erforderlichen ActiveX/COM-Server mit Windows `regsvr32` in bewährter Reihenfolge:
  1. `VPinMAME\PinMAME.dll` / `PinMAME64.dll` (`VPinMAME.Controller`)
  2. `B2SBackglassServer\B2S.Server.dll` (`B2S.Server`)
  3. `VPinMAME\FlexDMD.dll` (`FlexDMD.FlexDMD`)
  4. `PinUPSystem\PUPDMDControl.dll`
  5. `PinUPSystem\PuP DllSurrogate`
  6. `PinUPSystem\PinUpPlayer.dll`
- **Sicherheitsprüfung**: Überprüft NTFS-Berechtigungen (ACLs) des `vPinball`-Ordners und warnt vor unsicheren Schreibrechten unprivilegierter Benutzer.
- **Verifikation**: Prüft, ob die Windows-Registry-CLSIDs auf die neuen DLL-Pfade im Zielverzeichnis verweisen.

### Schritt 7: Future Pinball & BAM Ersteinrichtung (`07-FpBamSetup.ps1`)
- **Aktion**: Richtet Future Pinball und Better Arcade Mode (BAM) ein.
- **Aufgaben**:
  - Setzt den Kompatibilitätsmodus „Vollbildoptimierungen deaktivieren“ für `FPLoader.exe` und `Future Pinball.exe`.
  - Führt `BAM settings - Cabinet - Reset and Install.bat` nicht-interaktiv aus.
  - Leitet den einmaligen administrativen Start von `FPLoader.exe` zur Initialisierung an.

### Schritt 8: Multi-Screen-Konfiguration (`08-Screens.ps1`)
- **Aktion**: Erkennt angeschlossene Bildschirme DPI-bewusst und ordnet Cabinet-Rollen zu.
- **Unterstützte Rollen**:
  - **Playfield** (Spielfeld: Hauptanzeige / Display 1)
  - **Backglass** (Hintergrundanzeige: Display 2)
  - **DMD / FullDMD / Topper** (Punktmatrixanzeige: Display 3+)
- **Layout-Regeln**:
  - Windows-Skalierung muss auf 100 % stehen.
  - Keine negativen Bildschirmkoordinaten (weitere Monitore müssen rechts von oder unter der Hauptanzeige liegen).
- **Modi**:
  - `Keep` (Standard): Behält bestehende gültige Koordinaten bei und passt nur Werte an, die außerhalb des Desktops liegen.
  - `Replace`: Wendet neu ermittelte Bildschirmwerte auf alle Konfigurationsdateien an.
- **Diff & Undo**: Zeigt vor dem Schreiben eine genaue Differenzanzeige für `PinUpPlayer.ini`, `ScreenRes.txt`, `DmdDevice.ini` und Registry-Werte. Sicherheits-Backups erlauben das Rückgängigmachen.

### Schritt 9: Abschluss, Backup & Autostart (`09-Finish.ps1`)
- **Aktion**: Erstellt ein vollständiges Wiederherstellungs-Backup (`pinball-finish_<zeitstempel>.zip`) mit JSON-Manifest.
- **Optionaler Autostart**: Ermöglicht die Aktivierung des PinUP Popper Autostarts via `RunWindowsStartup.bat`.
- **Abschlusshinweis**: Empfiehlt einen Neustart von Windows, damit COM-Caches und Anzeigehandles sauber initialisiert werden.

---

## 🛠️ CLI-Kurzanleitung

So führst du den Umzug via PowerShell skriptgestützt durch:

```powershell
# Zum Kit-Ordner wechseln
cd "D:\Games\RetroCabinetKit"

# Build von E:\Old Build nach D:\Pinball umziehen
powershell -ExecutionPolicy Bypass -File pinball\steps\01-Detect.ps1 -Source "E:\Old Build"
powershell -ExecutionPolicy Bypass -File pinball\steps\02-Target.ps1 -Target "D:\Pinball"
powershell -ExecutionPolicy Bypass -File pinball\steps\03-Dependencies.ps1 -AllowDownload -AllowDism
powershell -ExecutionPolicy Bypass -File pinball\steps\04-Copy.ps1
powershell -ExecutionPolicy Bypass -File pinball\steps\05-Relocate.ps1 -Mode Move
powershell -ExecutionPolicy Bypass -File pinball\steps\06-Register.ps1
powershell -ExecutionPolicy Bypass -File pinball\steps\07-FpBamSetup.ps1
powershell -ExecutionPolicy Bypass -File pinball\steps\08-Screens.ps1 -Mode Keep
powershell -ExecutionPolicy Bypass -File pinball\steps\09-Finish.ps1
```
