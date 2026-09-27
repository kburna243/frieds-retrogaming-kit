# Plan: Wiimotes koppeln — TeknoParrot und die Wege, die noch gehen

Status: **Überarbeitet 2026-09-27 nach dem dokumentierten Automaten-Stand, noch nicht umgesetzt.**
Grundlage: Kit v0.4.0 (Schritt 15, Arcade-/Output-/Pads-Paket), die Sinden-Analyse und der
fest gehaltene Befund aus dem Wissensvault (`02_DOMAINS/retro-gaming/`, Handoffs 24./25.09.,
Sitzungsnotizen 23./24.09.). Dieses Dokument ist die Arbeitsanweisung für die Kabinett-Sitzung —
jeder Schreibschritt läuft über das Gate: erst Dry Run, Plan ansehen, menschliches Ja,
`-Apply`, Verifikation.

## 0. Was wir wissen

- Die Wiimote-Hardware hängt am **DolphinBar** (Bluetooth) und wird über **Gunmote** zu
  XInput-Geräten. Das ist die einzige Route, die in TeknoParrot **ohne** zusätzliche
  Ziel-Hardware funktioniert: TP kennt nur XInput/Maus, kein Wii-IR.
- **TeknoParrot nativ ist limitiert**: RawInput-Mäuse werden nur bis **2 Guns** angenommen.
  Der gangbare Weg führt über die Gunmote-Pads als XInput-Bindung.
- **Kalibrierung ist Geometrie, nicht Software**: Modus-Schalter der Bar steht auf
  **Mode 4** (Wii-Remote-Emulator), Sensorleiste oben/unten richtig adressiert, Kalibrierung
  per **Home + Minus**. Über die Bar liest Gunmote **keine Seriennummer** — alle Wiimotes
  teilen sich ein Profil; das ist hingenommene Realität, kein Bug, den wir jagen.
- **Zielen läuft über Gunmote-Injektion** (Maus-/Lightgun-Pointer im jeweiligen Layout),
  nicht über DSWiio. Der 2IR-Inversions-Bug (x-Achse doppelt gespiegelt) ist seit
  Gunmote ≥ v1.1.0.8 gefixt; das Default-Layout liegt auf „Pad ohne Zeiger", damit bei
  Fensterwechsel nicht auf Maus zurückgefallen wird.
- **Profile pro Vordergrund-EXE**: Keymap je Spiel + RetroBats `game-start`/`game-end`-
  Skripte schalten per Aufgabenplanung um, mit Debounce-Wächter. Kein Hantieren an der
  Wiimote während des Spiels.
- **Fallen, die deaktiviert bleiben müssen**: die Autostart-Aufgabe des vmulti-Treibers
  (Guard-Endlosschleife blockiert sonst die Bar) und der Aus-Knopf der Bar selbst
  (löst dasselbe Muster aus).
- **Demul + DemulShooter** (Schritt 12): DemulShooter 17.9 ist bereits auf die Gunmote-Pads
  im HID-Modus gestellt; Titel, die über die Bar nicht annnehmbar sind, hatten schon einen
  Desktop-AHK-Workaround. DSWiio bleibt die Notiz für direkte IR-Steuerung ohne Umweg.
- **Supermodel / Model 2** (Schritt 13): nur XInput-Bindung — Trigger ja, echtes Zielen
  mit der Wiimote hier nicht; ehrliche Erwartung statt Hoffnung.
- **Rumble ist schon geplant, nicht nur erdacht**: der 25.09.-Befund hält die Kette fest —
  MAMEHooker als Emulator-Binse, Empfänger die virtuellen Gunmote-Pads (`xip 1` / `xip 2`),
  Automatisierung über game-start/game-end. Das Output-Paket (v0.4.0) ist genau das
  Werkzeug, um diesen Plan konfigurierbar und prüfbar zu machen.
- **Schritt 15 / Sinden & Co.**: falls die Wiimote-Zielgenauigkeit nicht reicht, ist der
  USB-Adapterweg (Sinden-Kamera, Gun4IR …) der eingebaute Plan B; die Hardware-Bank läuft
  über den Community-Call.

## 0.5 Was am Automaten bereits steht (Befund, nicht Vermutung)

Kette **aufgebaut und live**: DolphinBar Mode 4 · Gunmote installiert und mit Default-Layout
gegen das Maus-Zurückfallen gehärtet · Profile/Keymaps pro Titel angelegt · Umschaltung über
RetroBat-Hooks · DemulShooter 17.9 auf Gunmote-HID gestellt · Rumble-Plan dokumentiert.

Titel-Befunde aus den Notizen:

| Titel | Befund | Route |
| :--- | :--- | :--- |
| Terminator 2 / **Namco 357** (TeknoParrot) | läuft | Gunmote-Pad-Bindung |
| **Point Blank X** (DemulShooter) | läuft | originally über Desktop-AHK |
| **Cooper's 9** | Profil korrekt, keine Steuerung | offene Spur — Prüfung unter Kit-Schritt 12 |

Der Plan hier ist deshalb **kein Aufbau-, sondern ein Überführungsplan**: das, was manuell
steht, in die prüfbare Kit-Konfiguration überführen und danach mit MAMEHooker den Rumble
beweisen.

## Phase 1 — Bank verifizieren (nur prüfen, nichts schreiben)

1. DolphinBar Mode 4, Firmware ≥ v09, Modus-Schalterlage notieren — API `step.lightgun.01-*`
   (read).
2. ViGEmBus + Gunmote-Version (≥ v1.1.0.8 erwartet) — Schritte 2/3 als read; die
   vmulti-Autostart-Aufgabe muss **aus** bleiben, das Kit prüft nur und ändert sie nicht.
3. Pairing-Zustand beider Wiimotes ablesen (verbunden, Ladestand), Kalibrier-Geometrie
   dokumentieren (Höhe/Abstand der Leiste) — die Vault-Notiz nennt Zieltreffer ~60 % als
   Ausgangslage; das ist die Messlatte, die Phase 4/5 verbessern will, nicht ersetzt.
4. Ergebnis-Beweis bevor geschrieben wird: **zwei XInput-Geräte** in der
   Windows-Gaming-Geräte-Liste (`joy.cpl` genügt als Sichtprüfung).

Abbruchkriterium: ohne zwei saubere XInput-Geräte hat Phase 2 keine Basis.

## Phase 2 — TeknoParrot durch die Kit-Gate

5. Schritt **10** (TeknoParrot-Profilpfade) erst als Dry Run.
6. Schritt **11** (Gun-Bindungen, Spielelisten): Dry Run → Plan → ja → `-Apply` → Verify.
   Erwartetes Planbild: nur `[Controllers]`-/Tweakmenu-Zeilen der **Gun-Titel**, keine
   Änderungen an Nicht-Gun-Spielen. Wegen des RawInput-Limits von 2 Mäusen: Bindung auf
   die Gunmote-Pads, nicht auf zusätzliche Mäuse.
7. **RetroBat-Konkurrenz beachten**: RetroBat schreibt seine `mame.ini`-Einstellungen beim
   Start selbst (`use_guns`, Pad-Trennung). Verifikation also **nach** einem EMU-Standalone-
   Start, nicht davor — sonst gewinnt die Automatisierung gegen von Hand gesetzte Werte,
   genau der Befund aus dem Vault.
8. Titel für Titel „da wo es noch geht" abarbeiten: 357 muss als Referenz-Titel **identisch**
   weiterlaufen (Bindung vom Kit bestätigt statt von Hand), Cooper's 9 ist die offene
   Fehlerspur (Profile-Wirkung vs. HID-Gerätenummer), neue Titel kommen auf die Liste.

## Phase 3 — DemulShooter: den Ist-Zustand ins Kit überführen

9. Schritt **12**: DemulShooter 17.9 läuft bereits auf den Gunmote-Pads — das Kit **prüft
   und sichert** die Konfiguration, ohne umzubauen: Dry Run muss „keine Änderung" zeigen.
   Ist er drin, schreibt er `[Guns]`- und Routing-Werte, startet aber nichts, killt nichts.
10. Point Blank X (heute AHK-Workaround) und Cooper's 9 unter der Kit-Konfiguration
    gegeneinander testen; der AHK-Workaround bleibt erhalten, bis ein Titel bewiesen ohne
    ihn läuft. Nur wenn direkte IR-Steuerung ohne Gunmote-Injektion gebraucht wird: DSWiio
    als Experiment-Zweig, nicht als Hauptlinie.

## Phase 4 — Rumble-Beweis mit dem Output-Paket (der 25.09.-Plan, jetzt mit Werkzeug)

11. Output-Paket-Schritt: MAMEHooker als Middleware **detect** (Prozess/Port), EmuOutput
    mit den Gunmote-Empfängern `xip 1` / `xip 2` als Konfiguration (erst Dry Run).
    Solenoid-Leitungen bleiben zu — der 200-ms-Guard gilt für Boards, Motor-Rumble ist
    unkritisch, aber der erste Test gehört einem Titel mit kurzer Rückkopplung.
12. Gelingt der Rumble: ROADMAP-Punkt „Rumble/Force-Feedback" hat sein erstes **Ergebnis** —
    `lightgun\modules\Rumble.ps1`-Entwurf darf MAMEHooker als erstes festes Werkzeug
    benennen. Misslingt er: Befund in den Feedback-Call, Route bleibt offen.

## Phase 5 — Befunde in den Call (der Grund, warum wir das messen)

13. Jeder Testbefund (welcher Titel, welche Route, Zielen ja/nein, Trefferquote, Rumble
    ja/nein) geht in den **Community-Feedback-Call** — dafür ist die Most-Wanted-Liste
    gebaut, und nur so werden die ~60 % Zieltreffer mit Daten statt Mut diskutiert.

## Gates & Ehrlichkeit (für jede Phase)

- Schreiben nur nach Dry Run + Plan + menschlichem Ja; `Interactive`-Schritte bleiben beim
  Menschen am Automaten.
- Das Kit lädt keine Treiber, keine Firmware, keine Emulatoren herunter — alles
  selbst mitgebracht, das Kit prüft und stellt ein.
- Bestehende Handwerks-Setups (AHK-Workarounds, manuelle Keymaps) werden nicht ersetzt,
  bevor die Kit-Route denselben Titel bewiesen hat.

## Offene Punkte, vor der Umsetzung zu klären

| # | Frage | Warum sie zählt |
| :--- | :--- | :--- |
| 1 | Welche TP-Gun-Titel außer 357 sind installiert und offline startbar? | Phase 2 entscheidet pro Titel |
| 2 | Warum zeigt Cooper's 9 keine Steuerung trotz korrekten Profils — HID-Nummer, Port oder Game-Switch-Reihenfolge? | die eine nachgewiesene Lücke im Setup |
| 3 | MAMEHooker-Version auf dem Automaten (≥ 0.9x mit EmuOutput erwartet)? | Phase 4 braucht genau diese Kette |
| 4 | Zieltreffer nach Kit-Bindung gemessen (Vergleich zur ~60-%-Notiz)? | entscheidet, ob der Wiimote-Pfad hält oder Sinden-Call Vorrang bekommt |
