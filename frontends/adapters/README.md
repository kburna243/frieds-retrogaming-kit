# Frontend Adapters

Jeder Adapter ist eine `.ps1`-Datei mit fünf Funktionen — **drop-in extensible**:

| Funktion | Zweck |
|---|---|
| `Test-<Name>Frontend` | Erkennt, ob das Frontend installiert ist (EXE, Prozess, Ordner) |
| `Get-<Name>FrontendInfo` | Liefert Metadaten: Pfade, Config-Dateien, Theme-Target, Datenbankformat |
| `Install-<Name>Frontend` | Installation (Link + User-Paket, nie Download) |
| `Configure-<Name>Frontend` | Wendet SettingsTargets aus Get-*Info an |
| `Set-<Name>InterferenceShield` | Port-/Prozess-Konflikt-Prüfung |

## Erweiterbarkeit

Neues Frontend hinzufügen: `_Template.ps1` kopieren, `<Name>` ersetzen, fünf Funktionen befüllen — wird automatisch von `Get-FrontendsAdapterCatalog` entdeckt. Keine Registry, keine Config — pure Dateisystem-Erkennung.

## Adapter-Liste (v1.0.0)

| Adapter | Typ | Datenbank |
|---|---|---|
| `RetroBat` | EmulationStation-Derivat | XML (gamelist.xml) |
| `PinballY` | Pinball-Frontend | XML (Settings.txt + Databases) |
| `Playnite` | Universal-Launcher | SQLite |
| `LaunchBox` | Universal-Launcher | XML |
| `PinUP` | Pinball-Frontend (Popper) | SQLite |