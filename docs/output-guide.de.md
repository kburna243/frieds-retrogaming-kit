# Output-Haptik-Guide — Rumble, Lampen & Solenoids

Wie das **Fried's Retrogaming Kit** die *haptische* Hälfte des Cabinets behandelt: die Middleware,
die Emulator-Output-Events in Force Feedback, blinkende Lampen und klickende Spulen verwandelt.
Paket: `output\` (Schritt `output\steps\01-Middleware.ps1`, Plugins in `output\adapters\`).

---

## 📌 Warum ein eigenes Paket

Output-Tools sind hardware-agnostische Vermittler zwischen Emulator und Cabinet-Hardware — sie
dienen **Lightguns und Lenkrädern** gleichermaßen:

```
   [ MAME / Emulatoren ]
        │  Output-Events: Win32-Messages ("output windows") oder TCP ("output network")
        ▼
   [ Middleware: MAMEHooker | qMamehook | Hook of the Reaper ]
        │  Serial-/USB-Board-Kommandos (LEDWiz, Pac-Drive, Ultimarc, …)
        ▼
   [ Solenoids · Lampen · Shaker · FFB-Lenkräder ]
```

Das Kit erkennt und konfiguriert diese Ebene; es **installiert nichts als Dienst, startet und
beendet nichts** — Middleware sind Tray-Apps von Menschenhand (Erkennung läuft über Prozess, Port
und tools-Ordner, läuft also auch, wenn die Tools gerade nicht starten).

## 🧰 Unterstützte Middleware (v1)

| Adapter | Transport | mame.ini `output` | Erkennungsbelege |
|---|---|---|---|
| `MameHooker` | Win32-Messages | `windows` | Prozess `MameHooker`, LED-Wiz-Board `0DFA:0001`, tools-Ordner |
| `QMamehook` | TCP (Port 9735*) | `network` | Prozess, lauschender Port, tools-Ordner |
| `HookOfTheReaper` | Win32 + eigener TCP-Server auf **8000** | `windows` | Prozess, Port, tools-Ordner |
| `DirectOutputFramework` | Win32-Messages (DOF R3++) | `windows` | nur Prozess `DirectOutput` — die XML-Welt (`C:\DirectOutput\Config`) bleibt Handarbeit |
| `DmdExtensions` | DMD-Frames (freezy dmdext) | *nicht beteiligt* | Prozess `dmdext`, tools-Ordner; nie an einem Modus-Konflikt beteiligt |

Zwei `windows`-Adapter koexistieren bewusst (DOF und MAMEHooker belauschen denselben Broadcast —
das Kit meldet Rivale-Lausher, es kürt nie einen Sieger). Nur `windows` gegen `network` ist ein
Konflikt. LED-Boards gehören zur Beweiskette der *Consumer*-Adapter: Der LED-Wiz ist MameHookers
Claim, DOF und dmdext beanspruchen bewusst keine Boards (die ZeDMD-ID `303A:1001` ist OpenFIREs
Lightgun, und generische CH340/FTDI-IDs würden an jedem USB-Kabel feuern).

\* 9735 ist Community-Konvention für qMamehook, kein amtlicher Standard — der Port bleibt in
`qmhook.ini` konfigurierbar, die das Kit nur anfasst, wenn sie existiert.

## ⚔️ Der eine exclusive Schlüssel: `output`

MAME hat genau **ein** `output`-Setting. `windows` und `network` gehen nicht gleichzeitig — und die
Gun4IR-Konfiguration nutzt bereits `output windows`. Das Kit erkennt deshalb alle laufenden
Middleware zusammen (Multi ist ok: HotR für die Gun-Spule, während MAMEHooker die Lampen treibt),
meldet aber Uneinigkeit statt drüberzubügeln:

```powershell
$d = Get-OutputDetectedMiddleware -RetroBatRoot 'D:\RetroBat'
$d.DetectedOutputs   # @('HookOfTheReaper','QMamehook')      — mehrere Tools: normal
$d.Conflicts         # Kind='OutputModeConflict' Detail='…windows…network…'
```

Solange ein `OutputModeConflict` besteht, bleibt der Configure-Schritt `NeedsUser`: nichts wird
geschrieben, der Report sagt warum. Ein Werkzeug muss weichen — das ist eine Cabinet-Entscheidung,
keine Skript-Entscheidung. Dasselbe gilt für zwei Tools auf demselben TCP-Port (`PortConflict`).

## 🔥 Solenoid-Schutz wird erzwungen

Hook of the Reaper treibt Spulen. Eine dauerhaft bestromte Solenoid brennt in Sekunden durch,
deshalb sind diese zwei Werte **Safety**-Einträge im Adapter — Configure schreibt sie immer wieder
in eine vorhandene `settings.ini`, und Verify bleibt rot, solange sie fehlen oder schwächer sind:

| Schlüssel | Wert | Bedeutung |
|---|---|---|
| `SolenoidProtection` | `1` | Strombegrenzung aktiv |
| `SolenoidMaxOpenTime` | `200` | jede Spule schließt nach spätestens 200 ms |

Benutzerwerte in derselben Datei (z. B. `DefaultLGPath`) bleiben unberührt; fehlende Dateien werden
nie angelegt — der Sicherheitseingriff gilt genau dort, wo das Tool installiert ist.

## 💻 Kommandozeile

```powershell
# Bestandsaufnahme (Prozesse, Ports, tools-Ordner — nichts wird gestartet oder gestoppt)
& output\steps\01-Middleware.ps1

# Maschinenbild vorgeben (Tests/Agenten) und Vorschau zeigen
& output\steps\01-Middleware.ps1 -Snapshot @{ Processes=@('mamehooker'); Ports=@(); Devices=@() } -WhatIf

# mame.ini output= + Settings schreiben — aber nur, wenn die Modi sich einig sind
& output\steps\01-Middleware.ps1

# portables ZIP selbst heruntergeladen (das Kit lädt nichts):
& output\steps\01-Middleware.ps1 -Install -Name MameHooker -PackagePath C:\Games\mamehook5.1.zip -Approved
```

## 🧪 Tests & Grenzen

`tests\output\Middleware.Tests.ps1` deckt ab: Multi-Erkennung, Modus-Konflikt-Ablehnung (mame.ini
danach byte-identisch), erzwungene Solenoid-Werte, Fehlende-Datei-Semantik und die Step-Status —
immer gegen injizierte Snapshots, nie gegen den laufenden Rechner.

Bewusst (noch) nicht automatisiert:

- **MAMEHooker-Profile** (`P1_CtmRecoil=scom 3 1000 1` — die Cabinet-Verdrahtung pro Spiel): Das
  Kit konfiguriert die Middleware, nicht den Lampen-/Spulen-Plan.
- **DOFs XML-Welt** — `GlobalConfig_B2SServer.xml`, `Cabinet.xml` und COM-Registrierung unter
  `C:\DirectOutput` liegen außerhalb des RetroBat-Root-Vertrags, und das Kit besitzt keinen
  XML-Writer; `directoutputconfig30.ini` erzeugt das Online-DOF-Config-Tool, nie lokal erfunden.
- **DmdDevice.ini** gehört zum pinball-Paket (dessen Screens-Schritt besitzt die VP/FP-DMD-Einträge);
  das Output-Paket konfiguriert dmdext selbst, nicht die gemeinsame Table-Config.
- **Firewall** — Loopback braucht keine; es wird nichts geöffnet.
- Hersteller-Downloads (dragonking.arcadecontrols.com ist reines HTTP, die qMamehook-Repos brauchen
  Pflege-Verifizierung) — bewusst außerhalb der Core-Download-Allowlist: bitte `-PackagePath`.
