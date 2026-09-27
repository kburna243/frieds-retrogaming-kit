# Arcade-Eingabe-Guide — Fightsticks, Encoder & Lenkräder

Wie das **Fried's Retrogaming Kit** USB-Arcade-Geräte als eigene Geräteklasse neben den
Wiimote-/USB-Lightguns behandelt. Paket: `arcade\` (Schritte in `arcade\steps\`, ein Plugin pro
Gerät in `arcade\adapters\`).

---

## 📌 Design: ein Cabinet, mehrere Eingabe-Klassen

Im Cabinet können gleichzeitig Lightgun, zwei Fightsticks und ein Lenkrad hängen. Das Kit vermischt
die Klassen nicht und nimmt keinem Gerät etwas weg:

```
        [ USB-Geräte ]
               │  Erkennung = enge "VID_xxxx&PID_yyyy"-Signaturen
               ▼
   ┌────────────────────────────────────────────┐
   │  lightgun\adapters\  wird ZUERST geprüft (Guns gewinnen) │
   ├────────────────────────────────────────────┤
   │  arcade\adapters\    Sticks + Lenkräder                   │
   └────────────────────────────────────────────┘
               │ kein Treffer? melden statt raten
               ▼
   [ mame.ini ] [ retrobat.ini [Controllers] ] [ Emulator.ini / Supermodel.ini ] [ Steam-Blacklist ]
```

Warum "Guns gewinnen" zählt — mehrere Arcade- und Gun-Geräte teilen sich USB-Vendor-IDs:

| Geteilte ID | Gun-Seite | Arcade-Seite |
|---|---|---|
| `2E8A:000A` | OpenFIRE (GP2040-Bootloader) | GP2040/DIY-Rad-Skripte matcheden das — aus Arcade rausgelassen |
| `16C0:05E1` | Retro Shooter | Zero-Delay-Klone nutzen sie — Arcade matcht nur `0079:0006` |
| `0079:*` | DolphinBar `1802/1803`, RetroShooter `187C` | Zero Delay `0006`, Mayflash-Multi `0183/0184` — nur exakte PIDs |
| `D209:*` | AimTrak `16xx` | Ultimarc I-PAC `0301/0302/0401` — nur exakte PIDs |
| `045E:028E` | — (XInput ist der Gun-Weg) | jedes X360-Pad — GP2040-CE läuft über **Namen** (`*GP2040*`), nie über diese ID |

Namenspatterns sind ausschließlich ein Fallback für Adapter ohne VID/PID-Signatur (GP2040-CE); sie
überstimmen nie ein echtes Signature-Match.

## 🕹️ Unterstützte Geräte (v1)

| Adapter | Klasse | Anmerkung |
|---|---|---|
| `GP2040CE` | ArcadeStick | Sticks mit GP2040-CE-Firmware; Web-Konfig, XInput |
| `BrookUFB` | ArcadeStick | Brook UFB/PCB (0C12) |
| `IPAC` | ArcadeStick | Ultimarc I-PAC-Tastatur-Encoder (D209:03xx/0401) |
| `ZeroDelay` | ArcadeStick | klassischer 0079:0006-Encoder |
| `MadCatzArcade` | ArcadeStick | TE/TE2 & Co.; meldet den **Code-43**-Quirk (unten) |
| `HoriArcade` | ArcadeStick | Real-Arcade-Pro-Familie (0F0D, exakte PIDs) |
| `MultiConsoleArcade` | ArcadeStick | Razer/Mayflash/Qanba Multisystem-Sticks |
| `PS2ToUSBAdapter` | ArcadeStick | 0810/0079-PS2-Brücken (`shared-endpoints`-Quirk) |
| `Xbox360Wheel` | Wheel | 045E:0719/0291; FFB braucht den **Lavendy-Treiber (Handarbeit, HKLM)** |
| `LogitechWheel` | Wheel | G25/G27/G29/G920/G923 …; `combined-pedals`-Quirk |
| `ThrustmasterFanatecWheel` | Wheel | T300/TX + Fanatec CSL DD (044F/0EB7) |
| `DIYArcadeWheel` | Wheel | 1209:FFB0 OpenFFB-Boards (Community — PID verifizieren) |

## 🖥️ Was "configure" konkret schreibt

Alles läuft über die geprüften Lightgun-Schreiber — Backup, Encoding erhalten, atomarer Replace,
laufende-Emulatoren-Guard, `-WhatIf`:

| Info-Tabelle | Zieldatei |
|---|---|
| `MameValues` | `emulators\mame\mame.ini` (`joystick`/`keyboard`, `paddle_device`, `pedal_device`) |
| `ControllersValues` | `retrobat.ini` `[Controllers]` (`Autocontrollers`, `WheelForceFeedback`, `WheelRotation`) |
| `Model2Values` | `emulators\m2emulator\Emulator.ini` — nur wenn vorhanden |
| `SupermodelValues` | `emulators\supermodel\Config\Supermodel.ini` `[Global]` — nur wenn vorhanden |
| `SteamEntries` | Steams `controller_blacklist` in `config.vdf` — **niemals Prozess-Kill** |

Fehlende optionale Emulatoren werden übersprungen — beim Schreiben wie beim Verifizieren.
RetroArchs globales `input_joypad_driver` bleibt bewusst unberührt (sonst gewinnt still der
Letzt-Schreiber — nutze Per-Core-Overrides). MAME-`ctrlr`-Profile und die Hersteller-Treiber
(Lavendy, LGS 5.10) bleiben Handarbeit; die Adapter nennen dafür die offiziellen Quellen statt
herunterzuladen.

> ⚠️ Noch nicht auf Hardware verifiziert: Die `[Controllers]`-Schlüssel folgen dem
> Community-Design-Dokument. Das Kit schreibt sie idempotent und mit Backup — aber prüfe an einem
> echten RetroBat, ob diese Schlüssel deine Lenkraderkennung wie vorgesehen steuern.

### Mad Catz und Code 43

PS3-zeitige Mad-Catz-Sticks (TE, TE2, FightStick) scheitern an USB-3.0-xHCI-Ports oft mit
Fehlercode **Code 43** im Geräte-Manager. Das Kit erkennt das sprachunabhängig
(`ConfigManagerErrorCode`, nie ein lokalisierter Fehlerstring) und meldet die bekannten Workarounds:
USB-2.0-Hub davor, oder die xHCI-Kompatibilitätsoption im BIOS. Erkannt wird der Stick trotzdem —
der Quirk wird gemeldet, nicht versteckt.

## 💻 Kommandozeile

```powershell
# erkennen (read-only) — was sieht das Cabinet?
& arcade\steps\01-Adapter.ps1                    # RetroBat-Pfad aus arcade-/lightgun-State

# Geräteliste vorgeben (Agent/Test) und nur den Plan zeigen:
& arcade\steps\01-Adapter.ps1 -Devices (Get-PnpDevice -PresentOnly) -WhatIf

# konfigurieren: mame.ini + [Controllers] + Emulator-INIs + Steam-Blacklist
& arcade\steps\01-Adapter.ps1

# Hersteller-Tool aus lokal geladener ZIP (das Kit lädt nie selbst):
& arcade\steps\01-Adapter.ps1 -Install -Name LogitechWheel -PackagePath D:\downloads\lgs.zip -Approved
```

Auf Modulebene:

```powershell
Import-Module arcade\RetroCabinetKit.Arcade.psd1
Get-ArcadeDetectedAdapter                       # Live-Scan
Get-ArcadeDetectedAdapter -Devices @($meinStick)
Set-ArcadeAdapterConfiguration -Name 'IPAC' -RetroBatRoot 'D:\RetroBat'
```

## ➕ Ein neues Gerät aufnehmen

`arcade\adapters\_Template.ps1` nach `<Name>.ps1` kopieren, Info-Tabelle füllen (enge `MatchIds`!),
die fünf Funktionsnamen beibehalten. Eine Datei, die nicht parst oder `Test-…Hardware`/
`Get-…AdapterInfo` fehlt, wird als unvollständig gemeldet und übersprungen — sie kann den Scan nie
kaputtmachen. Die Testsuite (`tests\arcade\Adapters.Tests.ps1`) enthält die
Klassen-Kollisionsfälle: zu jeder neuen Signatur gehört ein Regressionstest.
