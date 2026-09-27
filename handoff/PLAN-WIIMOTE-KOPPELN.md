# Plan: Wiimotes koppeln — TeknoParrot und die Wege, die noch gehen

Status: **Entwurf 2026-09-27, noch nicht umgesetzt.** Grundlage ist der Stand nach Kit v0.4.0
(Schritt 15, Arcade-/Output-/Pads-Paket) und dem neuen Wissen aus der Sinden-Analyse.
Dieses Dokument ist die Arbeitsanweisung für eine Folgesitzung — jeder Schreibschritt läuft
über das Gate: erst Dry Run, Plan ansehen, menschliches Ja, `-Apply`, Verifikation.

## 0. Was wir wissen

- Die Wiimote-Hardware hängt am **DolphinBar** (Bluetooth) und wird über **Gunmote** zu
  XInput-Geräten. Das ist die einzige Route, die in TeknoParrot **ohne** zusätzliche
  Ziel-Hardware funktioniert: TP kennt nur XInput/Maus, kein Wii-IR.
- **TeknoParrot**: Schritte 10–11 des Kits richten Profilpfade, XInput-Gun-Bindungen und
  Spielelisten ein. Copypasta: `use_guns`-Einträge nur da, wo der Titel sie wirklich braucht.
- **Demul + DemulShooter** (Schritt 12): DemulShooter kann Wiimotes über sein **DSWiio-
  Plugin selbst koppeln** (IR-Kamera der Wiimote, eigene Kalibrierung). Das ist der einzige
  Weg, bei dem die Wiimote echtes **Zeigerät** ist statt XInput-Attrappe.
- **Supermodel / Model 2** (Schritt 13): nur XInput-Bindung, Wiimote-Zielen funktioniert hier
  nicht vernünftig — ehrliche Erwartung: Trigger ja, Zielen nein.
- **Output-Paket** (neu in v0.4.0): erkennt MAMEHooker/qMameHook/Hook of the Reaper per
  Prozess, Port und Board. **Wiimote-Rumble** über MAMEHookers EmuOutput + Wii-Plugin ist der
  erste Rumble-Testkandidat, weil der DolphinBar die Bluetooth-Strecke hält.
- **Schritt 15 / Sinden & Co.**: falls mit der Wiimote-Route die Zielgenauigkeit nicht reicht,
  ist der USB-Adapterweg (Sinden-Kamera, Gun4IR …) der eingebaute Plan B — konfigurierbar,
  Hardware-Bank läuft über den Community-Call.

## Phase 1 — Bank aufbauen (nur prüfen, nichts schreiben)

1. DolphinBar in Bluetooth-Modus, Firmware ≥ v09 prüfen — API `step.lightgun.01-*` (read).
2. ViGEmBus present? — Schritt 2. Fehlt er, ist das ein Mensch-mit-Beschluss-Schritt.
3. Gunmote vorhanden und Version notieren — Schritt 3/4.
4. Pairing pro Wiimote: DolphinBar-Sync-Knopf, dann an der Wiimote **1+2**; danach
   Kalibrierung (Sensorleiste/IR-Punkt) — das ist interaktiv, das Kit führt, die Hand macht.
5. Ergebnis-Beweis bevor geschrieben wird: **zwei XInput-Geräte** müssen in der
   Windows-Gaming-Geräte-Liste stehen (`joy.cpl` genügt als Sichtprüfung).

Abbruchkriterium: ohne zwei saubere XInput-Geräte hat Phase 2 keine Basis.

## Phase 2 — TeknoParrot (der Auftrag: „koppeln in TeknoParrot")

6. `fagent` bzw. Assistent: Schritt **10** (TeknoParrot-Profilpfade) erst als Dry Run.
7. Schritt **11** (XInput-Gun-Bindungen, Spielelisten): Dry Run → Plan → ja → `-Apply` →
   Verify. Erwartetes Planbild: nur `[Controllers]`-/Tweakmenu-Zeilen der **Gun-Titel**,
   keine Änderungen an Nicht-Gun-Spielen.
8. Titel-Auswahl „da wo es noch geht": aufgestellte TP-Gun-Titel durchgehen und für **jeden**
   notieren, ob er offline startet (HOTD4 braucht netzwerklose Konstellation, einige Titel
   sind tot). Was nicht offline annehmbar ist, fliegt auf die Liste für den Demul-Weg.

## Phase 3 — Der Weg, auf dem Wiimote wirklich zeigt: DemulShooter

9. Schritt **12**: Demul (selbst mitgebracht) + DemulShooter; im DemulShooter-Konfig die
   Wiimote als Gerät wählen (DSWiio). Kit schreibt Routing und `[Guns]`-Einstellung,
   startet aber nichts und killt nichts.
10. Kalibrierung im DemulShooter-Oberfläche von Hand (IR-Punkte anzeigen), dann
    Ghost-Squad/Rambo-artige Titel testen. Trigger + Zielen aus einer Hand — das ist der
    „es geht noch"-Beweis.

## Phase 4 — Rumble-Beweis mit dem Output-Paket (Neuland, klein halten)

11. MAMEHooker manuell starten, EmuOutput + Wii-Plugin laden, Wiimote als Rumble-Ziel
    wählen; Solenoid-Leitung bleibt zu (200-ms-Guard gilt für Boards, Motor-Rumble ist
    unkritisch, aber trotzdem erst mit einem Titel mit kurzer Rückkopplung testen).
12. Gelingt der Rumble: ROADMAP-Punkt „Rumble/Force-Feedback" um **ein** Ergebnis reicher —
    `lightgun\modules\Rumble.ps1`-Entwurf kann MAMEHooker als erstes Werkzeug festhalten.
    Misslingt er: Call-Eintrag ins Feedback-Formular, Route bleibt offen.

## Gates & Ehrlichkeit (für jede Phase)

- Schreiben nur nach Dry Run + Plan + menschlichem Ja; `Interactive`-Schritte bleiben beim
  Menschen am Automaten.
- Das Kit lädt keine Treiber, keine Firmware, keine Emulatoren herunter — alles
  selbst mitgebracht, das Kit prüft und stellt ein.
- Jeder Testbefund (welcher Titel, welche Route, Zielen ja/nein, Rumble ja/nein) geht in den
  **Community-Feedback-Call** — dafür ist die Most-Wanted-Liste gebaut.

## Offene Punkte, vor der Umsetzung zu klären

| # | Frage | Warum sie zählt |
| :--- | :--- | :--- |
| 1 | Welche TP-Gun-Titel sind auf dem Automaten installiert? | Phase 2 entscheidet pro Titel |
| 2 | Gunmote-Version und Sensorleisten-Aufstellung (Höhe, Abstand)? | Zielen ist Geometrie, nicht Software |
| 3 | Sollen die Wiimotes nur Trigger (XInput) oder echte Zeiger (DSWiio) sein? | bestimmt Reihenfolge Phase 2 ↔ 3 |
| 4 | Ist MAMEHooker auf dem Automaten, und welche Version? | Phase 4 braucht ≥ 0.9x mit EmuOutput |
