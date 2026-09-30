# Konzept: Hook of the Wiimote

**Status:** Entwurf · 01.10.2026
**Grundlage:** Praxisbetrieb am Cabinet 30.09.–01.10.2026. Rambo und Walking Dead sind am Gerät bestätigt: Schuss, Treffer und Lebens-LEDs funktionieren. DemulShooter-Weg und 16 weitere TeknoParrot-Spiele sind vorbereitet, aber noch nicht getestet.
**Einordnung:** Ausbau des Pakets `output/` (API-Namensraum `outputs.*`, siehe [CONCEPT_v0.5.0](CONCEPT_v0.5.0.md) Abschn. 8). Aus demselben Repo zusätzlich als eigenständiges Release.

---

## 1. Was es ist

Hook of the Reaper (HotR) setzt Spiel-Outputs in Rückstoß, Rumble und Lampen für Lightguns um. Laut HotR-Wiki unterstützt es nur **serielle Lightguns** (RS3 Reaper, MX24, Gun4IR, Fusion, Blamcon, OpenFIRE, Alien, XGunner, AimTrak, Sinden, beliebige serielle Guns). Wiimotes, XInput und Controller-Rumble kommen dort nicht vor.

**Hook of the Wiimote** schließt diese Lücke für Wiimotes hinter [Gunmote](https://gunmotelabs.com/):

```
TeknoParrot/FFBBlaster ─TCP 8002─┐
DemulShooter ─────── Fenster-Nachr. ┼─► Relay (recoil-stretch.py) ─TCP 8000─► Gunmote ArcadeHook ─► Wiimote
MAME (output windows) ─ Fenster-Nachr. ┘        Pulse · Schuss · Leben · INI-Name          <Name>.ini: wii <n> <Ausgang>
```

Gunmote bringt die Umsetzung auf die Wiimote schon mit, den **ArcadeHook**: ein TCP-Client auf `localhost:8000`, eine INI pro Spiel, Befehl `wii <Wiimote> <Ausgang> %s%` mit Ausgang 1–4 = LED und 5 = Motor. Hook of the Wiimote liefert das, was ihm fehlt:

| Lücke in Gunmote | Lösung im Relay |
|---|---|
| Liest nur TCP. FFBBlaster-Standard und DemulShooter senden Windows-Nachrichten | Client für das MAME-Output-Protokoll über Windows-Nachrichten (`MAMEOutputRegister`, `GetIDString`, `WM_COPYDATA`) |
| DemulShooters TCP-Server hat einen festen Port und kollidiert auf 8000 | DemulShooter über Windows-Nachrichten lesen |
| Rückstoß-Pulse von ~16 ms bewegen den Wiimote-Motor nicht | Aus-Signal bis `HOLD_MS` (150 ms) zurückhalten |
| Manche Spiele melden den Schuss nicht (Walking Dead: Rückstoß nur beim Spannen) | `P<n>_Shot`-Puls, sobald der Munitionszähler sinkt |
| Keine Lebensanzeige | `P<n>_Health` bzw. `P<n>_Life` → `P<n>_Led1..4`, skaliert auf den Höchstwert seit Spielstart |
| Eine INI pro Spiel, die Namen muss man selbst herausfinden | `mame_start` umbenennen → **eine gemeinsame INI pro Quelle** (`TeknoParrot FFB.ini`, `DemulShooter.ini`); MAME behält seine mitgelieferten INIs pro Spiel |

HotR ist dadurch nicht überflüssig. Wer serielle Guns hat, nimmt HotR. Wiimote-Nutzer nehmen Hook of the Wiimote. Ein Parallelbetrieb ist möglich, sofern HotR nicht den Port 8000 belegt.

## 2. Zwei Auslieferungen, eine Codebasis

| | Im Kit | Standalone |
|---|---|---|
| Zielgruppe | Neuaufbau mit dem Kit | bestehende RetroBat-, TeknoParrot- oder MAME-Installationen |
| Einstieg | Output-Schritt im Kit-Installer und in der GUI | eigener kleiner Installer (`HookOfTheWiimote-Setup`) |
| Pfade | aus dem Kit-State | **Erkennung** (Registry, typische Orte, Auswahl durch den Nutzer) |
| Gemeinsam | Relay, Setup-Logik, GUI-Seite, Tests, i18n | dito |

Regeln, damit beides aus einem Paket geht:
- Keine festen Pfade. Alles läuft über einen Erkennungsschritt, der Nutzer bestätigt oder korrigiert.
- Das Paket braucht vom Kit nur `Write-KitLog`, `Get-KitText` und die Backup- und Genehmigungs-Mechanik. Das Standalone-Release liefert diese drei als kleine Kopie mit.
- Jede Änderung an fremden Dateien läuft über Backup, Probelauf und `-Approved`, wie bei den übrigen Kit-Adaptern.

## 3. Funktionsumfang

### 3.1 Prüfen (liest nur)
| Prüfpunkt | Wie |
|---|---|
| Gunmote installiert, Version, ArcadeHook aktiv | Prozess, `Gunmote.dll`, TCP-Verbindung auf 8000 |
| ViGEmBus, Python ≥ 3.10 | Dienst bzw. `py -3 --version` |
| Wiimote-Verbindung | Bluetooth (Dienst `bthserv` nicht deaktiviert, gekoppelte `RVL-CNT-01*`) oder DolphinBar (`VID_0079&PID_18*`) |
| Kalibrierung | `CalibrationData.json`: Einträge pro BT-Adresse, Zielmonitor im Desktop vorhanden |
| TeknoParrot | Profile mit `FFB Blaster` → `Enable=1` (Filter über die **Kategorie**, nicht das erste `Enable`); `FFBBlaster.ini` vorhanden? `OutputsSystem`/Port |
| DemulShooter | `config.ini`: `OutputEnabled`, `WM_OutputsEnabled` |
| MAME | `mame.ini` `output` (`windows` erforderlich) |
| Konflikte | anderer Dienst auf 8000 (HotR, DemulShooter-TCP), MAMEHooker aktiv (doppeltes Rumble) |

### 3.2 Einrichten (ändert, mit Backup und Freigabe)
- **Relay installieren:** `recoil-stretch.py` nach `tools\HookOfTheWiimote\`, Aufgabe „bei Anmeldung“ (`pythonw`, versteckt, 3 Neustarts).
- **TeknoParrot:** Spiele mit Häkchen → FFBBlaster-INI `OutputsSystem=1`, `NetOutputsTCPPort=8002`. FFBBlaster legt die INI erst beim ersten Spielstart an. Deshalb gibt es einen **Nachzieh-Haken** (heute `ffbblaster-netoutputs.ps1` bei Spielstart und -ende über RetroBat).
- **DemulShooter:** `OutputEnabled=True`, `WM_OutputsEnabled=True`, `Net_OutputsEnabled=False`.
- **MAME:** `output windows` (bei MAMEHooker/HotR-Parallelbetrieb auf den Konflikt hinweisen).
- **Gunmote-INIs:** gemeinsame INIs schreiben. `C:\Program Files\Gunmote` ist nur mit Admin-Rechten beschreibbar, und Gunmote muss dafür beendet sein. Das geht über einen erhöhten Einmal-Task (heute das Muster `patch-once.ps1` + Aufgabe „Gunmote Profil Menue“).

### 3.3 Auswahl („wo ja, wo nein“)
Baumansicht mit Häkchen: **Quelle → System → Spiel**, zum Beispiel TeknoParrot → Rambo ☑, Walking Dead ☑, Terminator ☐.
- Abgewählt heißt: Das Relay reicht für dieses Spiel nichts an Gunmote weiter. `mame_start` des Spiels steht dann auf einer Sperrliste.
- Pro Spiel lässt sich getrennt wählen: Rumble ☑ / LEDs ☑.

### 3.4 Effekt-Einstellungen
| Einstellung | Standard | Wirkung |
|---|---|---|
| Pulsdauer Rückstoß | 150 ms | `HOLD_MS` |
| Rumble bei Schuss / Nachladen / Treffer | ☑ / ☑ / ☑ | welche Outputs auf `wii n 5` gehen |
| LED-Modus | Leben | Leben (Balken) · Start-Lampen (`LmpStart`) · aus |
| Gunmote-Schwelle für XInput-Rumble | 50 | `xinput_rumbleThreshold_*` (nur für den XInput-Weg) |

### 3.5 Tasten
Keine eigene Tastenlogik: Die GUI zeigt und bearbeitet die **Gunmote-Layouts** (`Keymaps\*.json`, z. B. `z_tp.json`, `mouse43.json`) für die gewählten Systeme. Sie schreibt Änderungen über denselben Admin-Weg wie oben.

### 3.6 Diagnose
- Schalter „Mitschnitt“ (`recoil-stretch.trace`) plus Anzeige der letzten Outputs mit Spielname.
- „Test-Rumble“ und „Test-LEDs“ pro Wiimote über einen simulierten Output an Gunmote, ohne Spiel.

## 4. Datenbasis pro Spiel: Spieldateien von HotR

HotR pflegt für über 222 Spiele **geräteunabhängige** Spieldateien (`defaultLG/`). Sie sagen, welcher Output Rückstoß, Treffer (`Damage`), Leben (`Display_Life`) oder Munition (`Ammo_Value`) bedeutet. Genau das fehlt heute für MAME, wo jedes Spiel seine Outputs anders nennt.

- **Lizenz:** HotR steht unter **GPL-3.0** (`Fusion-Lightguns/Hook-Of-The-Reaper`), das Kit unter MIT. Deshalb werden die Dateien **nicht mitgeliefert**. Das Relay liest sie aus einer vorhandenen HotR-Installation oder aus einem Paket, das der Nutzer selbst mitbringt. Das passt zur Kit-Regel „lädt nie selbst herunter“.
- **Nutzung:** Aus `[Signals]` wird die Rolle jedes Outputs abgeleitet. Das Relay erzeugt daraus dieselben normierten Signale (`P<n>_Shot`, `P<n>_Damage`, `P<n>_Led*`) wie heute für FFBBlaster und DemulShooter.
- Ohne HotR-Dateien gilt der heutige Stand: feste Namenslisten (`STRETCH`, `AMMO`, `HEALTH`) plus die mitgelieferten Gunmote-INIs.

## 5. Umsetzung in Schritten

| Schritt | Inhalt | Nachweis |
|---|---|---|
| 1 | Relay `output/tools/recoil-stretch.py` = Praxisstand (TCP + Fenster-Nachrichten, Schuss, Leben, gemeinsame INIs) | Selbsttest, End-to-End mit simuliertem MAME-Output-Server |
| 2 | Adapter `GunmoteOutput.ps1` berichtigen (siehe 6) + Prüfen-Funktionen (3.1) mit injizierbarem Snapshot | Pester |
| 3 | Einrichten (3.2) als Kit-Schritt mit Probelauf/Backup/`-Approved`, Admin-Weg für Program Files | Pester + Cabinet |
| 4 | Einstellungsdatei `hotw.json` (Auswahl 3.3, Effekte 3.4), vom Relay gelesen | Pester + Selbsttest |
| 5 | GUI-Seite im Kit | Cabinet |
| 6 | Standalone-Installer aus demselben Paket | frische VM / zweiter Rechner |
| 7 | Leser für HotR-Spieldateien (4) | Selbsttest mit echten `defaultLG`-Dateien |

## 6. Berichtigungen zum Stand in CONCEPT_v0.5.0 Abschn. 8 und im Adapter-Entwurf

- **Schuss-Rumble über FFBBlasters eigenen Effekt (GunEffect → ViGEm → Wiimote) kam nie an.** Das gilt auch mit korrekten Wiimote-GUIDs, und das Log zeigt nie eine Effekt-Zeile. Der Schuss läuft über den Output-Weg plus Pulsverlängerung.
- **INI-Name = Wert von `mame_start`**, nicht `ArcadeOutputs\<System>\<rom>.ini`. Das ist per Test belegt, ein simulierter Server erzeugte `ZZTest.ini`. Unbekannte Outputs hängt Gunmote leer an.
- **Ausgang `0` ist eine LED, kein Motor.** Die mitgelieferten Gunmote-INIs legen `*_Damaged=wii n 0 1` auf `0`, dann rumpelt kein Treffer.
- **Gunmote liest keine Windows-Nachrichten**, nur TCP. `GunmoteOutput.ps1` behauptet noch beides.
- **Die Device-GUID ist für den Output-Weg unerheblich.** Kritisch ist sie nur für FFBBlasters eigenes Rumble, und das nutzen wir nicht.
- **Bluetooth statt DolphinBar** läuft seit 30.09. am Cabinet: eigene Kalibrierung pro Wiimote. Stolpersteine waren ein deaktivierter `bthserv`, die Kalibrierung per Home 3 s und der Zielmonitor, der im Desktop sein muss.

## 7. Offene Fragen

- MAME: Rückstoß-Namen pro Spiel verlängern, entweder über HotR-Dateien (4) oder eine eigene Liste.
- Chihiro/Hikaru: DemulShooter-Start ist nicht verdrahtet, die ROMs fehlen am Cabinet.
- Mehrere Wiimotes > 2: Gunmote kann 4, getestet sind 2.
- Standalone ohne Admin-Rechte: Gunmote liegt in Program Files. Alternative wäre eine portable Gunmote-Installation.
