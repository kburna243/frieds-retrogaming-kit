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

### Prüfung: DMD-Sektionen, die nicht zum Tisch passen (`pinball.dmd_audit`)
- **Warum**: Eine Tisch-Sektion in der `DmdDevice.ini` von VPinMAME (`[<cGameName>]`) kann das virtuelle DMD auf einen
  schmalen Streifen legen oder abschalten. Richtig ist das nur, wenn der Tisch wirklich ein PuP-Pack lädt: Dann füllt
  das Pack den FullDMD-Bildschirm um den Streifen oder zeichnet den Punktestand selbst. Aus einem anderen Build
  übernommen, bleibt bei Tischen ohne PuP das Menü-Video des Frontends um den Streifen stehen (oder allein, wenn das
  DMD aus ist).
- **Was gelesen wird** (nur gelesen): die Tisch-Sektionen der `DmdDevice.ini`, das Skript jedes Tisches direkt aus der
  `.vpx` (nur lesend geöffnet; es wird nie eine `.vbs` neben einen Tisch geschrieben, VPX würde sie sonst laden) und die
  Ordnernamen unter `PUPVideos`. Ein Pack-Ordner, dessen Name auf Striche endet (`pack-----`), ist abgeschaltet und
  zählt nicht.
- **Ergebnis pro Sektion**: `Ok` (Pack aktiv; DMD aus nur, wenn PuP den Punktestand zeichnet), `NoPup` (Streifen oder
  DMD aus ohne aktives Pack), `Mixed` (ein Name, Tische mit unterschiedlichem Ergebnis), `Orphan` (kein Tisch trägt den
  Namen; wirkungslos), `Unclear` (braucht einen Menschen, z. B. DMD aus, obwohl PuP nie den Punktestand zeichnet).
- **PuP-Schalter im Skript**: Eine `Const` ist die Einstellung des Tisches; eine Variable, die `True` *und* `False`
  bekommt, wird zur Laufzeit erkannt (`bUsePUPDMD = False ... = True`), dann entscheiden PuP-Code und Pack.
- **Reparatur** (`pinball.dmd_repair`): entfernt nur die `virtualdmd`-Zeilen der `NoPup`-Sektionen (eine leer
  gewordene Sektion verliert auch ihre Überschrift). Erst Probelauf, `-Apply -Approved` schreibt nach einer
  ZIP-Sicherung, und die geplanten Zeilen werden direkt vor dem Schreiben noch einmal gegen die Datei geprüft.
  `Mixed`, `Orphan` und `Unclear` werden nie angefasst.

```powershell
Import-Module .\api\RetroCabinetKit.Api.psd1
Invoke-KitOperation -Name pinball.dmd_audit -Parameters @{ Root = 'D:\Pinball' }
Invoke-KitOperation -Name pinball.dmd_repair -Parameters @{ Root = 'D:\Pinball' }                     # Plan
Invoke-KitOperation -Name pinball.dmd_repair -Parameters @{ Root = 'D:\Pinball' } -Apply -Approved    # schreiben
```

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

---

## 🌐 Tische von VPForums per Browser-Session herunterladen (bsk-Methode)

`bsk` ist die Kommandozeile von *browser-skill*, die einen angemeldeten Chromium-Browser fernsteuert; sie gehört nicht
zum Kit. Das Kit lädt selbst keine Tische herunter — Tische, ROMs und Medien bringt jeder selbst mit, und nur von der
offiziellen Seite ihres Autors. Wenn `bsk download` bei großen Dateien (> ~5 MB) einen Timeout meldet, funktioniert
dieser Weg:

### Voraussetzung

- `bsk` Daemon läuft, Session aktiv, Tab auf der `confirm_download`-Seite
  (nach dem "Agree & Download"-Klick auf der VPForums-Showfile-Seite)

### Ablauf

**1. Tab auf confirm_download-Seite navigieren** (`?do=confirm_download&hash=...`)

**2. Direkten Download-Link holen:**

```powershell
bsk evaluate --session <sid> "document.querySelector('a.download_button').href"
# Gibt: https://www.vpforums.org/index.php?do=do_download&hash=...&id=XXXXX
# Bei mehreren Dateien: querySelectorAll('a.download_button')[1].href usw.
```

**3. In-Browser Fetch starten:**

```javascript
window.__dl = { status: 'starting', total: 0, buffer: null };
fetch('<direct_url>')
  .then(r => { window.__dl.total = parseInt(r.headers.get('content-length')||'0',10); return r.arrayBuffer(); })
  .then(buf => { window.__dl.buffer = new Uint8Array(buf); window.__dl.status = 'done'; })
  .catch(e => { window.__dl.status = 'error: '+e.message; });
window.getChunk = function(offset, len) {
  const sub = window.__dl.buffer.subarray(offset, Math.min(offset+len, window.__dl.buffer.length));
  let bin=''; const CHUNK=32768;
  for(let i=0;i<sub.length;i+=CHUNK) bin+=String.fromCharCode.apply(null,sub.subarray(i,Math.min(i+CHUNK,sub.length)));
  return btoa(bin);
};
```

**4. Pollen bis Status "done":**

```powershell
bsk evaluate --session <sid> "JSON.stringify({status:window.__dl.status,total:window.__dl.total,hasBuffer:!!window.__dl.buffer})"
# Wiederholen bis hasBuffer=true
```

**5. Python-Extraktor (2-MB-Chunks):**

```python
import subprocess, json, base64, os

SESSION = "<sid>"; OUT_FILE = "download.zip"; CHUNK_SIZE = 2 * 1024 * 1024

def bsk_eval(expr):
    r = subprocess.run(["bsk","evaluate","--session",SESSION,expr], capture_output=True, text=True, timeout=60)
    return r.stdout.strip()

total = json.loads(bsk_eval("JSON.stringify({total:window.__dl.total})"))["total"]
offset = 0
with open(OUT_FILE, "wb") as f:
    while offset < total:
        chunk = base64.b64decode(bsk_eval(f"window.getChunk({offset},{CHUNK_SIZE})"))
        f.write(chunk); offset += len(chunk)
        print(f"{offset/1024/1024:.1f}/{total/1024/1024:.1f} MB", end="\r")
print(f"\nFertig: {os.path.getsize(OUT_FILE)} Bytes")
```

### Bekannte Stolperfallen

- **Hash kurzlebig:** Nicht navigieren, bis der Download komplett ist. Neuen Hash über die Showfile-Seite holen.
- **`bsk evaluate` blockiert** mit „previous session command still running“, wenn ein Promise noch läuft — erst pollen.
- **VPUniverse** erfordert Login; anonyme Fetches → Login-Redirect. Nur VPForums funktioniert anonym.
- **Dateiname im ZIP ≠ GameFileName** in PUPDatabase — nach dem Entpacken manuell prüfen.
- **Richtwerte:** 63 MB ≈ 45 s, 83 MB ≈ 80 s (lokales WLAN).
