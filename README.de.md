<div align="center">
  <img src="https://raw.githubusercontent.com/kburna243/frieds-retrogaming-kit/main/site/public/mascot.svg" alt="Fried's Retrogaming Kit Banner" width="480" style="border-radius: 16px; margin-bottom: 16px; box-shadow: 0 8px 32px rgba(0,0,0,0.6);" onerror="this.style.display='none'" />
  <h1>🕹️ Fried's Retrogaming Kit</h1>
  <p><strong>Die definitive Automations- und Setup-Suite für Windows Retro-Gaming- und Pinball-Cabinets</strong></p>

  [![Windows Plattform](https://img.shields.io/badge/Plattform-Windows%2010%20%7C%2011-0078D6?style=for-the-badge&logo=windows&logoColor=white)](https://github.com/kburna243/frieds-retrogaming-kit)
  [![PowerShell](https://img.shields.io/badge/Engine-PowerShell%205.1%2B-5391FE?style=for-the-badge&logo=powershell&logoColor=white)](https://github.com/kburna243/frieds-retrogaming-kit)
  [![Lizenz: MIT](https://img.shields.io/badge/Lizenz-MIT-yellow?style=for-the-badge)](LICENSE)
  [![Dokumentation](https://img.shields.io/badge/Doku-Deutsch%20%7C%20English-3DDC84?style=for-the-badge&logo=gitbook&logoColor=white)](docs/)
  [![Webseite](https://img.shields.io/badge/Webseite-kburna243.github.io%2Ffrieds--retrogaming--kit-ff2d95?style=for-the-badge&logo=googlechrome&logoColor=white)](https://kburna243.github.io/frieds-retrogaming-kit/)
  [![Datenschutz](https://img.shields.io/badge/Datenschutz-0%20Datenlecks-success?style=for-the-badge&logo=shield)](tools/Test-Depersonalized.ps1)

  <p>
    <a href="README.de.md"><strong>Deutsch</strong></a> •
    <a href="README.md"><strong>English</strong></a> •
    <a href="docs/pinball-guide.de.md"><strong>Pinball-Anleitung</strong></a> •
    <a href="docs/lightgun-guide.de.md"><strong>Lightgun-Anleitung</strong></a> •
    <a href="docs/troubleshooting.de.md"><strong>Fehlerbehebung</strong></a> •
    <a href="docs/faq.de.md"><strong>FAQ</strong></a>
  </p>
</div>

---

> [!NOTE]
> **Status: In Entwicklung (Work in Progress).** Fried's Retrogaming Kit befindet sich in aktiver Entwicklung. Der gemeinsame Kern (`core\`), die Virtual-Pinball-Relokationssuite (`pinball\`) und die Wiimote-Lightgun-Engine (`lightgun\`) sind einsatzbereit; zusätzliche Emulator-Anbindungen (TeknoParrot, Demul + DemulShooter, Force-Feedback/Rumble) werden aktuell fertiggestellt.

---

## 💡 Was ist Fried's Retrogaming Kit?

Der Aufbau und die Wartung eines modernen Windows-Arcade- oder Flippergehäuses (Virtual Pinball Cabinet) waren bisher mühsam und fehleranfällig: Beim Umziehen von Ordnern brechen Pfade in kryptischen SQLite-Datenbanken; beim Anschließen von Wiimotes kollidieren Maustreiber, Cursor springen unkontrolliert, Steam kapert Controller und COM-DLL-Registrierungen schlagen lautlos fehl.

**Fried's Retrogaming Kit** löst diese Probleme mit einer auditierbaren, abhängigkeitsfreien PowerShell-Automationsplattform. Es verwandelt komplexe manuelle Einzelschritte in geführte, reproduzierbare Abläufe, bei denen **jede Aktion vorab geprüft, live verifiziert und vor jeder Änderung gesichert wird**.

Entwickelt von **Fried ([@kburna243](https://github.com/kburna243))** — von Arcade- und Flipper-Enthusiasten für Enthusiasten.

---

## 🏛️ Die drei Kernsäulen

```
                      ┌─────────────────────────────────────────┐
                      │        Fried's Retrogaming Kit          │
                      │       (Gemeinsame Kernplattform)        │
                      └────────────────────┬────────────────────┘
                                           │
         ┌─────────────────────────────────┼─────────────────────────────────┐
         ▼                                 ▼                                 ▼
┌──────────────────┐              ┌──────────────────┐              ┌──────────────────┐
│ Virtual Pinball  │              │ Wiimote Lightgun │              │  Kernplattform   │
│      Suite       │              │      Suite       │              │    & Engine      │
├──────────────────┤              ├──────────────────┤              ├──────────────────┤
│• Baller-Umzug    │              │• DolphinBar (M4) │              │• Zero-Dep SQLite │
│• SQLite-Pfad-Fix │              │• ViGEmBus X360   │              │• Test-Invoke-Ver │
│• COM-Regsvr32    │              │• Gunmote-Layouts │              │• Dry-Run Support │
│• FP / BAM Setup  │              │• RetroBat-Tuning │              │• ACL-Härtung     │
│• Multi-Screen 4K │              │• Auto-Profile    │              │• Auto-Backups    │
└──────────────────┘              └──────────────────┘              └──────────────────┘
```

### 1. 🎱 Virtual Pinball Suite (`pinball\`)
- **Nahtloser Umzug & Wiederherstellung**: Verschiebt ein komplettes **Baller Installer**-Layout (PinUP Popper, Visual Pinball X, VPinMAME, B2S, FlexDMD, Future Pinball) auf ein neues Laufwerk (z. B. `E:\Old Build` ➔ `D:\Pinball`) oder stellt es auf einem frisch installierten Windows sauber wieder her.
- **Tiefes Umschreiben von Datenbanken & Konfigurationen**: Aktualisiert Tische, Emulatoren und Medienpfade in `PUPDatabase.db` direkt über die Windows-eigene `winsqlite3.dll` und passt `VPinballX.ini`, `PinUpPlayer.ini`, `ScreenRes.txt`, `DmdDevice.ini` sowie Registry-Einträge an.
- **COM-Komponenten-Orchestrierung**: Registriert `PinMAME.dll`, `B2S.Server.dll` und `FlexDMD.dll` in geprüfter Reihenfolge mit 32-Bit- und 64-Bit-Validierung.
- **Multi-Screen Kalibrierungs-Engine**: Erkennt Monitore DPI-bewusst (Playfield, Backglass, DMD/Topper), zeigt Differenz-Vorschauen vor dem Speichern, bewahrt bestehende Kalibrierungen und legt automatische Rollback-Backups an.

### 2. 🎯 Wiimote Lightgun Suite (`lightgun\`)
- **Schlüsselfertige RetroBat-Integration**: Verwandelt RetroBat mithilfe von Nintendo Wiimotes und der Mayflash DolphinBar in ein echtes Lightgun-Arcade-Gehäuse.
- **Erzwungener Hardware-Modus 4**: Garantiert latenzarmes Infrarot-Tracking und Kopplung ohne lästige Windows-Bluetooth-PIN-Abfragen.
- **Virtuelle Xbox 360 Controller**: Nutzt signierte **ViGEmBus**-Treiber, um Lightguns als Standard-XInput-Pads bereitzustellen – Schluss mit chaotischen Windows-Mauskonflikten.
- **Intelligenter Schutz vor Störquellen**: Schaltet störende Steam-Desktop-Konfigurationen ab und deaktiviert kollidierende Maustreiber im Hintergrund.
- **Automatischer Profilwechsel**: Hintergrund-Dienste schalten Gunmote-Belegungen beim Spielstart automatisch um (MAME, DuckStation, TeknoParrot, Naomi) und kehren beim Beenden zu einem stabilen Menü-Pad zurück.

### 3. ⚙️ Kernplattform & Verifikations-Engine (`core\`)
- **Vollständig abhängigkeitsfreie Architektur**: Läuft direkt auf jedem Standard-Windows 10 und 11 mit Windows PowerShell 5.1 und `winsqlite3.dll` – keine Paketmanager, keine externen Compiler.
- **Test → Invoke → Verify Zyklus**: Kein Schritt gilt als abgeschlossen ohne echte Messung. Jede Aktion wird getestet, ausgeführt und live verifiziert.
- **Vollständige Trockenlauf-Unterstützung**: Alle Skripte unterstützen `-WhatIf`. Änderungen an Dateien, Registry und Bildschirmkoordinaten lassen sich vorab gefahrlos einsehen.
- **Gehärtete Sicherheit & Datenschutz**: Setzt strenge NTFS-Rechte durch, prüft Authenticode-Signaturen bei offiziellen Microsoft/Nefarius-Downloads und garantiert 0 % Datenabfluss.

---

## 🎛️ Hardware- & Systemanforderungen

| Komponente | Mindestanforderung | Empfohlene Cabinet-Ausstattung |
| :--- | :--- | :--- |
| **Betriebssystem** | Windows 10 64-Bit (21H2+) | Windows 11 64-Bit |
| **PowerShell** | Windows PowerShell 5.1 (Vorinstalliert) | PowerShell 5.1 oder PowerShell 7+ |
| **Pinball-Monitore** | 2 Bildschirme (Playfield + Backglass) | 3 Bildschirme (4K Playfield 120Hz + 1080p Backglass + DMD) |
| **Windows-Skalierung**| 100 % Skalierung (Zwingend erforderlich)| 100 % Skalierung auf allen Bildschirmen |
| **Lightgun-Sensor** | Mayflash DolphinBar (Firmware v09+) | Mayflash DolphinBar oben oder unten am Monitor |
| **Lightgun-Controller**| 1x Original Nintendo Wiimote | 2x Nintendo Wiimotes mit MotionPlus & Gun-Gehäuse |
| **Freier Speicher** | Build-Größe + 10 % Sicherheitspuffer | Schnelle NVMe-SSD (`D:\Pinball` oder `C:\RetroBat`) |

---

## ⚡ Schnellstart-Anleitung

### 1. Starten des Kits
Lade das Repository auf deinen Gaming-PC herunter und starte das Hauptmenü:
```cmd
:: Doppelklick im Explorer oder Aufruf in Eingabeaufforderung / PowerShell:
Start-Kit.cmd
```
*Oder starte die spezialisierten Assistenten direkt:*
- **Virtual Pinball Setup**: `Start-Pinball.cmd`
- **Wiimote Lightgun Setup**: `Start-Lightgun.cmd`

### 2. Virtual Pinball Umzug durchführen (Beispiel)
```powershell
# Änderungen vorab gefahrlos im Trockenlauf prüfen (-WhatIf)
powershell -ExecutionPolicy Bypass -File pinball\steps\05-Relocate.ps1 -Source "E:\Old Build" -Target "D:\Pinball" -WhatIf

# Vollständigen Umzug ausführen
powershell -ExecutionPolicy Bypass -File pinball\steps\01-Detect.ps1 -Source "E:\Old Build"
powershell -ExecutionPolicy Bypass -File pinball\steps\02-Target.ps1 -Target "D:\Pinball"
powershell -ExecutionPolicy Bypass -File pinball\steps\04-Copy.ps1
powershell -ExecutionPolicy Bypass -File pinball\steps\05-Relocate.ps1 -Mode Move
powershell -ExecutionPolicy Bypass -File pinball\steps\06-Register.ps1
powershell -ExecutionPolicy Bypass -File pinball\steps\08-Screens.ps1 -Mode Keep
powershell -ExecutionPolicy Bypass -File pinball\steps\09-Finish.ps1
```

### 3. Wiimote Lightgun konfigurieren (Beispiel)
```powershell
# RetroBat für Wiimote-Lightguns vorbereiten
powershell -ExecutionPolicy Bypass -File lightgun\steps\01-Detect.ps1 -RetroBatRoot "C:\RetroBat"
powershell -ExecutionPolicy Bypass -File lightgun\steps\02-Hardware.ps1
powershell -ExecutionPolicy Bypass -File lightgun\steps\03-ViGEmBus.ps1 -AllowInstall
powershell -ExecutionPolicy Bypass -File lightgun\steps\05-Interference.ps1 -DisableVMultiGuard
powershell -ExecutionPolicy Bypass -File lightgun\steps\06-GunmoteLayouts.ps1 -Mode Keep
powershell -ExecutionPolicy Bypass -File lightgun\steps\07-RetroBatSettings.ps1
powershell -ExecutionPolicy Bypass -File lightgun\steps\08-ProfileAutomation.ps1
powershell -ExecutionPolicy Bypass -File lightgun\steps\09-Verify.ps1 -XInputTimeoutSeconds 15
```

---

## 🛡️ Sicherheit, Datenschutz & Integritäts-Prinzipien

Wir arbeiten nach strengen, unverhandelbaren Grundsätzen:
1. **Bring Your Own Builds (BYO)**: Das Kit enthält **keine** ROMs, BIOS-Dateien, kommerziellen Tische oder geschützten Grafiken. Du bringst deine eigenen legalen Spiele mit; das Kit übernimmt lediglich die Konfiguration.
2. **Nur offizielle, geprüfte Quellen**: Treiber und Hilfsmittel werden ausschließlich von offiziellen Herstellerseiten (Microsoft, Nefarius) bezogen. Jede Datei wird vor der Ausführung auf digitale Authenticode-Signaturen und SHA-256-Prüfsummen getestet.
3. **Zerstörungsfrei**: Das Kit löscht **niemals** deine Tische, ROMs oder Spielstände. Vor Konfigurationsänderungen werden automatische Backups erstellt.
4. **Standardmäßig Trockenlauf fähig**: Prüfe jeden Kopiervorgang, Registry-Eintrag und Monitor-Offset mit `-WhatIf`, bevor etwas geschrieben wird.
5. **Kein Datenabfluss**: Automatisierte CI-Scans (`tools\Test-Depersonalized.ps1`) stellen sicher, dass niemals private Hostnamen, IP-Adressen oder persönliche Benutzerpfade ins Repository gelangen.

---

## 📖 Dokumentations-Übersicht

| Handbuch | Beschreibung | Sprachlinks |
| :--- | :--- | :--- |
| **Virtual Pinball Handbuch** | Schritt-für-Schritt-Anleitung für Baller-Umzug, COM-Registrierung und Monitorkalibrierung. | [Deutsch](docs/pinball-guide.de.md) • [English](docs/pinball-guide.md) |
| **Wiimote Lightgun Handbuch** | DolphinBar Modus 4, ViGEmBus, Gunmote-Layouts und Profil-Automation. | [Deutsch](docs/lightgun-guide.de.md) • [English](docs/lightgun-guide.md) |
| **Fehlerbehebungs-Handbuch** | Schnelle Lösungen für COM-Fehler, Monitor-Verschiebungen, Steam-Konflikte und Drift. | [Deutsch](docs/troubleshooting.de.md) • [English](docs/troubleshooting.md) |
| **Häufig gestellte Fragen (FAQ)** | Antworten zu Architektur, Hardware-Kompatibilität und Sicherheit. | [Deutsch](docs/faq.de.md) • [English](docs/faq.md) |
| **Sicherheits-Richtlinie** | Sicherheitsmodell, Privilegien der Hintergrundaufgaben und Deaktivierung. | [English](SECURITY.md) |
| **Richtlinien für Beiträge** | Codierungsstandards, Pester-Tests und Pull-Request-Ablauf. | [English](CONTRIBUTING.md) |

---

## 🤝 Community & Danksagung

Fried's Retrogaming Kit baut auf der herausragenden Arbeit weltweiter Communities und Open-Source-Pioniere auf:
- **Communities**: [Light Gun Lunatics](https://lightgun.retrolunatics.com/) und [Pinball Lunatics](https://pinball.retrolunatics.com/) für unschätzbare Tutorials, Hardware-Tests und Community-Austausch.
- **Lightgun-Pioniere**: **Gunmote** (gunmotelabs), **Touchmote** (simphax), **Lichtknarre** (Geekonarium), **DemulShooter** (argonlefou) und **ViGEmBus** (Nefarius).
- **Frontend & Emulatoren**: **RetroBat Team**, **TeknoParrot** (Teknogods), **MAMEdev**, **DuckStation** (Stenzek), **PCSX2 Team**, **Flycast** und **Libretro**.
- **Virtual Pinball Pioniere**: **PinUP Popper & Player** (nailbuster), **Visual Pinball Team**, **PinMAME Team**, **B2S Backglass Server** (Herweh), **DMD Extensions** (freezy), **FlexDMD** (vbousquet) und **Future Pinball / BAM** (Ravarcade).
- **Inspiration**: Das deutsche Virtual-Pinball Community-Handbuch *"Projekt Virtual Pinball"* von **Moster** (flippermarkt.de / vpinball.de).

*Eine vollständige, ungekürzte Liste aller Mitwirkenden, Projekte und verifizierten Lizenzen findest du in [CREDITS.md](CREDITS.md).*

---

## 📄 Lizenz

Dieses Projekt steht unter den Bedingungen der **MIT-Lizenz**.  
Siehe [LICENSE](LICENSE) für den vollständigen Lizenztext.  
Copyright (c) 2026 Friedrich Börner.
