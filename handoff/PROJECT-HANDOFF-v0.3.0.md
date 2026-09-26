# Übergabe: Fried's Retrogaming Kit – Stand v0.3.0

> Für Menschen und Agenten, die am Kit weiterarbeiten. Beschreibt, was von v0.1.0 bis v0.3.0 entstanden ist,
> wie es zusammenhängt, welche Regeln gelten und was offen ist. Stand: 2026-09-26, `main` nach PR #20.
> Details stehen in den verlinkten Dateien; diese Übergabe ist die Landkarte.

## 1. Stand in einem Absatz

v0.3.0 ist veröffentlicht (Tag `v0.3.0` auf `05b2bc5`, Release mit Zip, `SHA256SUMS.txt` und
Build-Provenance). Das Kit richtet Virtual-Pinball- und Wiimote-Lightgun-Kabinette auf Windows ein, ist
wartbar (Doctor, Backups, Support-Paket), zieht Kabinette um (A → B) und hat eine Desktop-App (WPF-Dashboard).
Alle Clients, also Dashboard, Kommandozeile, Tests und externe Agenten, gehen über eine versionierte Kit-API. Für
Agenten gibt es einen MCP-Server über stdio. Alles läuft lokal auf Windows PowerShell 5.1 ohne Abhängigkeiten,
ohne Telemetrie und ohne Netzwerkport. Die CI ist grün (482 Pester-Tests auf PowerShell 5.1), und die Website
ist über GitHub Actions deployt.

## 2. Zeitleiste

| Version / PR | Inhalt |
| :--- | :--- |
| **v0.1.0** | Kern (`core\`), Pinball-Suite (Schritte 1–9), Lightgun-Suite (Schritte 1–14), WinForms-Assistenten, Website, Doku DE/EN, Depersonalisierungs-Scanner |
| **PR #3** (P0 + P1) | CI (Depersonalisierung, statische Prüfung, Pester auf 5.1, Paket, Website), eine Versionsquelle `VERSION`, Release-Workflow mit `SHA256SUMS` und Provenance, README und Anleitungen synchron, `ARCHITECTURE.md`, `CHANGELOG.md`, `ROADMAP.md`, Vorlagen; **Doctor**, **Recovery** (Backups auflisten/prüfen/wiederherstellen/exportieren/löschen), **Support-Paket** |
| **PR #14** → **v0.2.0** | Wartungsseite (Doctor, Backups, Support-Paket) als letzte Seite beider Assistenten; Release 0.2.0; Handoff `MIGRATION-A-B.md` |
| **PR #15** | Strukturierte Schrittergebnisse; **WPF-Dashboard** (neues Kabinett, Umziehen, Retten, Systemstatus) mit Offscreen-Screenshots in der CI; Design-Review; **Kit-API v1** (`API.md`); Dependabot-Updates gebündelt (ersetzt #4–#13) |
| **PR #17** | **Kabinett-Migration** (`core\modules\CabinetProfile.ps1`), umgesetzt vom lokalen Agenten nach `MIGRATION-A-B.md`; über #18 gemergt |
| **PR #18** → **v0.3.0** | Dashboard nur noch über die API; **MCP-Server**; API-Regeln für Migration; Fix: `-AutoInstall` fragt jetzt nach; **Umziehen-Modus** im Dashboard; Steam-Schutz eingegrenzt; Version 0.3.0 |
| **PR #19, #20** | Website und README mit den v0.3.0-Funktionen, Versionsabgleich Website ↔ `VERSION`, Meta-Beschreibung |

Der [CHANGELOG](../CHANGELOG.md) führt jede Änderung einzeln auf.

## 3. Architektur

```text
  Start-Kit.cmd ─► gui\ (WPF-Dashboard)      Assistenten (WinForms)     Agent / Skript
                        │                     pinball\ui, lightgun\ui    │ MCP (stdio) / JSON
                        ▼                             │                  ▼
                   api\RetroCabinetKit.Api  ◄─────────┼──── api\Start-KitMcpServer.ps1
                   (Invoke-KitOperation)              │     api\Invoke-KitApi.ps1
                        │                             │
                        ▼                             ▼
        core\ (Schritt-Vertrag, Backup, State, Log, Registry, SQLite, Download, Doctor, Recovery,
               SupportBundle, CabinetProfile)  ·  pinball\ (Module + steps\01–09)  ·  lightgun\ (Module + steps\01–14)
```

- **Schritt-Vertrag** (`core\modules\Step.ps1`): `New-KitStep` / `Invoke-KitStep`. Zuerst Verify (schon
  erledigt → Skipped), dann Test (Vorbedingung, sonst NeedsUser), dann WhatIf (nur Plan), dann Invoke und am Ende
  Verify (Done/Failed). Das Ergebnis enthält `Duration`, `Changed`, `Changes`, `Backups`, `Warnings`, `Errors`
  und `Log`.
- **Kit-API v1** (`API.md`): `Invoke-KitOperation` liefert ein `OperationResult` (ApiVersion, Operation, Kind,
  Success, Status, Applied, Message, Warnings, Errors, Changes, Backups, Approvals, Duration, StartedAt, Data).
  Den Katalog (`Get-KitOperation`) baut das Kit aus den Schritt-Skripten. Operationen: `status`, `components`,
  `backups.list`, `backup.check|restore|export|remove`, `support.bundle`, `step.<suite>.<nn-name>` sowie
  `profile.export|import`.
- **MCP-Server** (`api\Start-KitMcpServer.ps1`): JSON-RPC 2.0, eine Nachricht pro Zeile. Tools entstehen aus dem
  Katalog, dabei wird `.` zu `_`. Ändernde Tools haben die Argumente `apply` und `approved`. Ergebnisse sind
  anonymisiert, außer mit `-NoAnonymize`; `-ReadOnly` bietet nur lesende Tools an.
- **Dashboard** (`gui\`): XAML-Views, Theme `Themes\Brand.xaml`, Texte über `Tag="i18n:<key>"`. Jede Aktion ist
  eine API-Operation. Der Doctor läuft in einem Hintergrund-Runspace. `Start-KitGui.ps1 -View Migrate|Recover`
  und `-Screenshot` dienen Tests und CI-Screenshots.
- **Migration** (`CabinetProfile.ps1`): eine Zip pro Suite; Pfade werden zu Tokens, Registry tokenisiert,
  SQLite-Einstellungen als JSON, Bildschirme nur als Vorschlag. Der Import prüft vor jeder Änderung, sichert
  vor jedem Schreiben und ist idempotent. Das Manifest gilt als nicht vertrauenswürdig: Traversal, absolute
  Pfade und SIDs werden abgelehnt, `.reg` wird über Root-Remap und Allowlist gefiltert.

Mehr in [ARCHITECTURE.md](../ARCHITECTURE.md).

## 4. Regeln, die nicht verhandelbar sind

1. **Nichts ändert sich ohne `-Apply`** (API/MCP); die Skripte unterstützen `-WhatIf` durchgehend.
2. **Freigaben kommen von einem Menschen.** Installer und geplante Aufgaben zeigen einen Plan (SHA-256,
   Signatur) und fragen. Kein Code beantwortet `-Approve` selbst (siehe Fix in #18). Die API lehnt Freigaben ohne
   `-Approved` ab und gibt den Plantext in `Approvals` zurück.
3. **Nur lokal:** keine Telemetrie, kein Port. Netzwerkcode gibt es nur in `core\modules\Download.ps1`; die CI
   schlägt fehl, wenn er anderswo auftaucht.
4. **Nie destruktiv:** Backup vor jeder Änderung. Das Kit beendet keine Programme, es bittet darum, sie zu
   schließen. Steam muss nur geschlossen sein, wenn Steams eigene Dateien geschrieben werden (Schritt 5,
   Zurückspielen von `.vdf` oder Zip).
5. **BYO:** keine ROMs, BIOS-Dateien, Tische oder Builds im Kit oder im Migrationsprofil.
6. **Depersonalisierung:** `tools\Test-Depersonalized.ps1` muss 0 Funde melden. Keine echten Namen, Pfade mit
   Laufwerksbuchstaben, IPs oder SIDs im Repo; in der Doku Platzhalter wie `<usb-stick>` verwenden.
7. **Interaktive Schritte** (Bildschirm-Kalibrierung `step.pinball.08-screens`, Abzugstest
   `step.lightgun.09-verify`) bleiben in den Assistenten und werden von der API abgelehnt.

## 5. Technische Fallstricke (hart erarbeitet)

- **PowerShell 5.1:** `.ps1`/`.psm1`/`.psd1` mit Nicht-ASCII-Zeichen brauchen **UTF-8 mit BOM**; zwei Tests
  prüfen das (die neue Testdatei in #18 ist genau daran gescheitert). Manche Editor-Werkzeuge entfernen die BOM.
- **Strict Mode 2.0:** `$x = if (...) { @() }` ergibt `$null`, deshalb `@(if ...)` schreiben. `@(List[object])`
  in einem `[pscustomobject]`-Literal wirft einen Fehler; `.ToArray()` verwenden.
- **Modulinstanzen:** Tests importieren Kern und Suiten zusammen mit `-Force`. Sonst meldet eine Suite ihre
  Backups an eine alte Kerninstanz. GUI- und API-Modul laden den Kern nur in ihren eigenen Scope, deshalb
  importieren die Einstiegsskripte ihn ausdrücklich.
- **Pester 3.4:** `$TestDrive` ist ein `DirectoryInfo`, also `"$TestDrive"` oder `[string]$TestDrive` verwenden.
  Mock-Bodies sehen keine Testvariablen. `Mock -ModuleName 'RetroCabinetKit.Core'` ersetzt Funktionen, die der
  Kern aufruft, zum Beispiel `Get-LightgunViGEmState` oder `Install-LightgunViGEm` in den Migrationstests.
- **Saubere Standardausgabe:** JSON- und MCP-Ausgaben laufen über `Invoke-KitOperationIsolated` (Runspace
  ohne Host), damit keine „What if:“-Zeile stdout verschmutzt.
- **Pfade in der Migration:** `Join-Path` wirft einen Fehler, wenn das Laufwerk nicht existiert; Zip-Einträge
  werden über den Provider (`Resolve-Path -Relative`) gebildet, weil es auf CI-Runnern kurze 8.3-Pfade gibt.
- **Linux-Sitzungen** (Cloud-Agent): `pwsh` reicht für die Syntax- und Depersonalisierungsprüfung, den
  MCP-Server und die API-Logik. Die Test-Fixtures erzeugen aber Windows-Pfade, und WPF gibt es nur unter Windows.
  Maßgeblich ist die Windows-CI.
- **CI-Screenshots:** Enthält eine Commit-Nachricht `[snapshot-log]`, schreibt die CI die Dashboard- und
  Umziehen-Screenshots als Base64 ins Log (Marker `SNAPSHOT-BEGIN/END`). Das hilft Reviewern ohne Zugriff auf
  Artefakte.

## 6. Qualität und Release

- **Lokal vor jedem Push:** `tools\Test-KitSyntax.ps1` (Parser, BOM, XAML, Versionen, Netzwerk-Wächter),
  `tools\Test-Depersonalized.ps1` und `tests\Run-Tests.ps1` (Pester 3.4, PowerShell 5.1).
- **CI** (`.github/workflows/ci.yml`): Depersonalisierung, statische Prüfung, Pester (mit `subst` für
  Testlaufwerke), Dashboard-Screenshots, Paketbau mit Integritätsprüfung, Website-Build.
- **Release** (`release.yml`): Tag `vX.Y.Z`, der zu `VERSION` passen muss. Der Workflow testet, baut
  `frieds-retrogaming-kit-vX.Y.Z.zip` mit `SHA256SUMS.txt`, erstellt die Attestierung und veröffentlicht das
  Release mit den Notes aus dem passenden CHANGELOG-Abschnitt.
- **Nächste Version:**
  1. `VERSION` und alle fünf Modul-Manifeste anpassen (core, pinball, lightgun, gui, api), dazu
     `site/src/config.ts` (`KIT_VERSION`); `tests\core\Release.Tests.ps1` prüft alle Stellen.
  2. Im CHANGELOG `## [Unreleased]` in `## [X.Y.Z] - Datum` umbenennen und die Vergleichslinks unten ergänzen.
  3. Nach dem Merge den Tag auf den Merge-Commit setzen und pushen.
- **Website** (`site/`, React + Vite + Tailwind): Deployment über den Workflow „Deploy GitHub Pages“ (manuell,
  auf `main`). Pages steht auf „GitHub Actions“; der Branch `gh-pages` wird nicht mehr gebraucht.

## 7. Offen / nächste Schritte

| Thema | Stand | Hinweis |
| :--- | :--- | :--- |
| Rumble / Force Feedback | geplant | `lightgun\modules\Rumble.ps1`, Werkzeugwahl (OutputHooker / MAMEHooker-Nachfolger) offen |
| Hardware-Abstraktion | geplant | Lightgun-Provider (Wiimote heute; Sinden, Gun4IR, AimTrak) hinter einer Eingabeschicht; das Wissenspaket dazu kommt noch |
| Setup-Modus im Dashboard | offen | Assistentenschritte als WPF-Seiten mit Ergebniskarten, WinForms Seite für Seite ersetzen |
| Operationshistorie | offen | nur anhängen, für Clients nur lesbar; kein zentraler Zustandsspeicher, die Maschine bleibt die Wahrheit |
| Registry-Teil von Zip-Backups | offen | das Recovery-Werkzeug stellt bisher nur Dateien wieder her |
| Marken-Schriften im Dashboard | offen | Playfair Display und Inter (OFL) mitliefern statt Windows-Ersatzschriften |
| Code-Signing | offen | Release-Skripte und signierte `SHA256SUMS.txt` |
| Agent-Harness | eigenes Repo | Schnittstelle: [AGENT-HARNESS.md](AGENT-HARNESS.md); das Kit bleibt Server, das Harness Client |
| PR #16 (TypeScript 7) | offen (Dependabot) | vor dem Merge prüfen, ob `tsc --noEmit` und Vite mit TS 7 bauen |
| Alte Dependabot-Branches | aufräumen | Die PRs #4–#13 sind geschlossen, ihre Branches liegen noch auf origin |
| CI-Runner | Hinweis | `ubuntu-latest` wechselt ab 2026-10-19 auf Ubuntu 26 (nur Website-Build und Pages) |

## 8. Wo steht was

| Datei | Zweck |
| :--- | :--- |
| [README.md](../README.md) / [README.de.md](../README.de.md) | Überblick, Funktionsstatus, Schnellstart (inkl. Umzug, Skripte/Agenten) |
| [API.md](../API.md) | Kit-API v1 und MCP-Server (Vertrag, Operationen, Regeln, Client-Konfiguration) |
| [ARCHITECTURE.md](../ARCHITECTURE.md) | Aufbau, Module, Schritt-Definition-of-Done |
| [CHANGELOG.md](../CHANGELOG.md) / [ROADMAP.md](../ROADMAP.md) | Was geliefert ist / was kommt |
| [handoff/MIGRATION-A-B.md](MIGRATION-A-B.md) | Ursprüngliche Spezifikation der Migration |
| [handoff/AGENT-HARNESS.md](AGENT-HARNESS.md) | Grenze Kit ↔ Agent-Harness, Policy-Mapping, MCP |
| `docs\` | Anleitungen Pinball/Lightgun, Fehlerbehebung, FAQ (DE/EN) |
| `tests\local\` | Tests gegen echte Hardware und Datenbanken (nur lokal, nicht in der CI) |
