# Häufig gestellte Fragen (FAQ)

Alles Wissenswerte rund um **Fried's Retrogaming Kit**.

---

## 🌟 Allgemeine Fragen

### Was ist Fried's Retrogaming Kit?
Fried's Retrogaming Kit ist ein quelloffenes Automations-Toolkit für Retro-Gaming- und Arcade-Cabinets unter Windows. Es vereint zwei Hauptbereiche auf einer gemeinsamen PowerShell 5.1-Basis:
1. **Virtual-Pinball Suite**: Zieht vollständige PinUP-Popper-Installationen (Baller Installer Struktur) nahtlos auf neue Festplatten um oder stellt sie auf frischen Windows-Systemen wieder her.
2. **Wiimote-Lightgun Suite**: Verwandelt RetroBat zusammen mit Mayflash DolphinBar, ViGEmBus und Gunmote in eine schlüsselfertige Arcade-Shooter-Station.

### Warum basiert das Kit auf PowerShell 5.1 statt auf einer compilierten App?
Windows PowerShell 5.1 ist auf jedem Windows 10 und Windows 11 standardmäßig vorinstalliert. Durch die direkte Nutzung der Windows-eigenen `winsqlite3.dll` für SQLite-Operationen benötigt das Kit keinerlei externe Runtimes, keine Paketmanager und keine Compiler. Alle Abläufe sind im Klartext einsehbar und auditierbar.

### Enthält das Kit ROMs, BIOS-Dateien, Tische oder Medien?
**Nein. Keinerlei urheberrechtlich geschützte Spieledateien.** Das Kit ist ein reines Konfigurations- und Orchestrierungs-Werkzeug. Du bringst deine eigenen Builds, ROMs, BIOS-Dateien und Flipper-Tische mit. Das Kit lädt lediglich frei lizenzierte Systemtreiber und Runtimes direkt von offiziellen Herstellerseiten (wie Microsoft oder signierten GitHub-Releases) herunter.

### Kann ich das Kit auch ohne aktive Internetverbindung nutzen?
Ja! Wenn dein Build die nötigen Runtimes (z. B. in `2-Programs\All In One Runtimes`) bereits enthält und du Installer wie Gunmote und ViGEmBus vorab heruntergeladen hast, läuft das Kit komplett offline. Es gibt keine Cloud-Abhängigkeiten.

### Kann ich Änderungen vorab gefahrlos testen?
Ja. Jeder einzelne Schritt unterstützt den PowerShell-Parameter `-WhatIf`. Ein Durchlauf mit `-WhatIf` erzeugt detaillierte Berichte über geplante Registry-Änderungen, Kopiervorgänge und Bildschirmkoordinaten, ohne auch nur ein einziges Byte auf der Festplatte zu verändern.

---

## 🎱 Virtual-Pinball Fragen

### Kann ich eine bestehende Baller-Installation umziehen, ohne Windows neu zu installieren?
Ja! Genau dafür existiert der **Modus: Move auf diesem PC**. Das Kit verschiebt deinen gesamten Flipper-Build in ein neues Verzeichnis (z. B. `D:\Pinball`), schreibt alle Pfade in der `PUPDatabase.db` um, aktualisiert Konfigurationsdateien, passt die Windows-Registry an und registriert die COM-DLLs neu. Alle Tische und Highscores bleiben erhalten.

### Wie funktioniert das Rückgängigmachen (Undo) bei der Bildschirmkonfiguration?
In Schritt 8 (`08-Screens.ps1`) sichert das Kit vor dem Schreiben aller Monitorwerte die bisherige Konfiguration in einem zeitgestempelten Backup-Ordner (`backups\`). Sollte ein Layout auf deinen Bildschirmen nicht wie gewünscht aussehen, kannst du den vorherigen Stand sofort wiederherstellen.

### Werden Cabinets mit nur zwei Bildschirmen (Playfield + Backglass) unterstützt?
Ja. Obwohl Drei-Monitor-Setups (Spielfeld, Backglass, DMD/Topper) der Standard sind, unterstützt die Bildschirm-Engine auch Zwei-Monitor-Gehäuse. Virtuelle DMDs können nahtlos im Backglass-Bereich integriert werden.

---

## 🎯 Lightgun & RetroBat Fragen

### Warum nutzt das Kit die Mayflash DolphinBar in Modus 4?
Modus 4 versetzt die DolphinBar in den nativen Wiimote-Controller-Modus (`USB\VID_057E&PID_0306`). Dieser Modus umgeht den Standard-Bluetooth-Stack von Windows (keine PIN-Abfragen nötig) und ermöglicht eine latenzarme, direkte Kommunikation mit Gunmote. Die Modi 1 und 2 (Tastatur-/Mausemulation) leiden unter Mausbeschleunigung und unterstützen keine getrennten Spieler-Guns.

### Warum Gunmote statt Lichtknarre oder Touchmote?
Gunmote (`gunmotelabs`) ist ein moderner, aktiv gepflegter Lightgun-Mapper, der Wiimote-Infrarotsignale und Tastenimpulse über ViGEmBus in virtuelle Xbox 360 Controller-Eingaben übersetzt. Dadurch verstehen Emulatoren die Gun als XInput-Gamepad, was störende Mauskonflikte verhindert.

### Warum benötigt die Profil-Automation geplante Aufgaben mit höchsten Rechten?
Für ein authentisches Gehäuse-Erlebnis muss der Profilwechsel beim Spielstart aus RetroBat automatisch und ohne störende Windows-UAC-Abfragen ablaufen. Da manche Emulatoren exklusive Vollbildrechte beanspruchen, benötigt der Hintergrund-Dienst (`profile.ps1`) erhöhte Ausführungsrechte. Das genaue Sicherheitsmodell und die Deaktivierung sind in [SECURITY.md](../SECURITY.md) offengelegt.

### Werden Sinden, AimTrak oder GUN4IR unterstützt?
Die automatisierte Lightgun-Konfiguration dieses Kits ist aktuell auf **Wiimote + Mayflash DolphinBar** spezialisiert. Ausführliche Anleitungen für Sinden, AimTrak und GUN4IR findest du in unserer Partner-Community [Light Gun Lunatics](https://lightgun.retrolunatics.com/).

---

## 🔒 Datenschutz & Sicherheit

### Sammelt Fried's Retrogaming Kit Telemetriedaten?
**Niemals.** Es gibt keine Tracker, keine Analyse-Pings und keine Verbindung zu externen Servern abgesehen von explizit genehmigten Treiber-Downloads.

### Wie entferne ich das Kit und seine Hintergrundaufgaben vollständig?
Führe folgenden Befehl in einer administrativen PowerShell aus:
```powershell
Get-ScheduledTask -TaskName "RetroCabinetKit Gunmote*" | Unregister-ScheduledTask -Confirm:$false
Remove-Item -Recurse -Force "C:\ProgramData\RetroCabinetKit\lightgun"
```
Danach verbleiben keinerlei Hintergrunddienste auf deinem PC.
