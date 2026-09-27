# Bench-Check — Arcade, Pads und Output auf echter Hardware

Dieses Protokoll prüft die Punkte, die die Werkbank (Tests) nicht beweisen kann: ob RetroBat,
MAME und die Haptik-Werkzeuge die Werte wirklich so konsumieren, wie unsere Adapter sie schreiben.
Circa 30–45 Minuten am Cabinet. Jedes Kapitel endet mit **Soll** — weicht der Ist ab, unten
melden; ist alles grün, vermerken wir "bench-verified" im Changelog.

Vorbereitung: Geräte verkabelt an, die es im Betrieb auch sind (Stick, Lenkrad, Pads, Middleware
startbereit). Alle Befehle aus dem Kit-Ordner.

## 1 · `retrobat.ini [Controllers]` — werden die Schlüssel konsumiert?

```powershell
& arcade\steps\01-Adapter.ps1            # schreibt, falls erkannt
(Get-FileHash <RetroBatRoot>\retrobat.ini).Hash
#  RetroBat starten, ein Lenkrad-System laden, RetroBat wieder schließen
(Get-FileHash <RetroBatRoot>\retrobat.ini).Hash   # GLEICH wie vorher?
& arcade\steps\01-Adapter.ps1            # zweiter Lauf: muss "0 Änderungen" verifizieren
```

**Soll:** Hash unverändert nach dem RetroBat-Besuch (RetroBat bügelt uns nicht über), Lenkrad
dreht im Spiel mit korrektem Ausschlag (Logitech ~900°, Xbox-Rad ~270°), Step meldet grün.
Weicht etwas ab → Schlüsselname(n) und beobachteten Wert notieren; das korrigieren wir in
`arcade\adapters\README.md` und den Adaptern.

## 2 · Model 2 / Supermodel-FFB (nur wenn installiert)

`Emulator.ini`/`Supermodel.ini` wurden nur geschrieben, wenn die Dateien existieren — dann im
Spiel (House of the Dead / Harley-Davidson) Force Feedback im Service-Menü an: **Soll:** Lenkrad
vibriert, und nach dem Spiel bleibt `[Global] ForceFeedback=1` stehen.

## 3 · Steam-Blacklist

```powershell
& arcade\steps\01-Adapter.ps1            # Einträge stehen danach in config.vdf
```

Steam neu starten → Einstellungen → Controller. **Soll:** Stick/Lenkrad tauchen **nicht** als
Controller auf (kein "Gerät konfigurieren"-Dialog). Gamepads dagegen **sollen** weiter sichtbar
sein — Pads blacklisten wir bewusst nicht.

## 4 · MAME-Output: `windows` gegen `network`

Mit `output = windows` (MameHooker/DOF/HotR): in einem output-fähigen Spiel **Tab → Output** —
**Soll:** Lampen/LEDs schalten durchs Testmenü. Zusätzlich eine TCP-Middleware (qMamehook) starten:
`& output\steps\01-Middleware.ps1` **Soll:** `OutputModeConflict`, **keine** Änderung an mame.ini —
erst wenn du ein Werkzeug abschaltest, schreibt der Step wieder.

## 5 · HotR-Spulenschutz (live, wichtigster Punkt)

Eine Solenoid-Aktion auslösen (Shot-Rumble in PinMAME, oder HotR-Testbutton). **Soll:** Die Spule
klickt kurz (< 0,2 s) und brummt **nicht** dauerhaft; HotR zeigt `SolenoidProtection=1 /
SolenoidMaxOpenTime=200` in seiner Settings. Solenoid nach 10 Minuten Dauerspiel fühlen: **Soll:**
warm, nicht heiß. Heiß = Schutz greift nicht → sofort HotR aus, Konflikt an mich melden.

## 6 · Pads-Klassen-Aufteilung

Xbox-Pad, 8BitDo (X-Modus), GP2040-Stick und (wenn vorhanden) DS4 gleichzeitig anstecken, dann:

```powershell
& pads\steps\01-Gamepads.ps1
```

**Soll:** Stick bleibt Arcade (Logzeile `Pad.Excluded … Arcade`), nacktes Xbox-Pad → `XboxPad`,
8BitDo → `EightBitDoPad` (im D-Modus: mit Imitations-Quirk unter PlayStation), Xbox-Series-Pad per
BLE → bewusst **nicht** sichtbar (Doku-Punkt, kein Fehler).

## Ergebnis melden

Abweichungen: `& core\Start-KitTools.ps1 -SupportBundle` (anonymisiert) oder die markierten
Logzeilen (`Arcade.*`/`Pad.*`/`Output.*`) direkt. Alles grün: kurze Rückmeldung, dann fällt
"bench-verified" in die Doku.
