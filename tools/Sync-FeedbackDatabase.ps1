<#
.SYNOPSIS
    Sync-FeedbackDatabase.ps1 - Synchronisiert Feedback- und Testberichte von GitHub in eine lokale SQLite-Datenbank und erzeugt eine tägliche Auswertung.

.DESCRIPTION
    Liest gemeldete Community- und Testergebnisse aus den GitHub-Repositories
    (frieds-retrogaming-kit und frieds-retrogaming-agent) via `gh`-CLI aus,
    parst die strukturierten Systemdaten und speichert sie in einer lokalen SQLite-DB.
    Erzeugt anschließend einen täglichen Markdown-Report für Entwickler.

.EXAMPLE
    pwsh -File tools/Sync-FeedbackDatabase.ps1
#>

[CmdletBinding()]
param(
    [string]$DatabasePath = "",
    [string]$OutputSummaryPath = "",
    [string[]]$Repos = @("kburna243/frieds-retrogaming-kit", "kburna243/frieds-retrogaming-agent"),
    [switch]$SkipEvaluation
)

$ErrorActionPreference = "Stop"

$scriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $scriptDir) { $scriptDir = (Get-Location).Path }
$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $scriptDir ".."))

if (-not $DatabasePath) {
    $DatabasePath = Join-Path $repoRoot "output\feedback.db"
} else {
    $DatabasePath = [System.IO.Path]::GetFullPath($DatabasePath)
}

if (-not $OutputSummaryPath) {
    $OutputSummaryPath = Join-Path $repoRoot "output\feedback-daily-summary.md"
} else {
    $OutputSummaryPath = [System.IO.Path]::GetFullPath($OutputSummaryPath)
}

# 1. Sicherstellen, dass Ausgabeverzeichnis existiert
$outputDir = Split-Path -Parent $DatabasePath
if (-not (Test-Path -Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

# 2. SQLite CLI prüfen
$sqliteCmd = Get-Command "sqlite3" -ErrorAction SilentlyContinue
if (-not $sqliteCmd) {
    Write-Error "sqlite3.exe wurde nicht im PATH gefunden. Bitte installieren oder WinGet-Paket aktivieren."
    return
}

# 3. Datenbank-Schema initialisieren
$initSql = @"
CREATE TABLE IF NOT EXISTS feedback_reports (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    repo TEXT NOT NULL,
    issue_number INTEGER NOT NULL,
    state TEXT,
    created_at TEXT,
    synced_at TEXT,
    author TEXT,
    title TEXT,
    kind TEXT,
    outcome TEXT,
    cabinet TEXT,
    os TEXT,
    hardware TEXT,
    version TEXT,
    body_markdown TEXT,
    url TEXT,
    UNIQUE(repo, issue_number)
);

CREATE TABLE IF NOT EXISTS sync_history (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    synced_at TEXT,
    new_reports_count INTEGER,
    total_reports_count INTEGER
);
"@

$initSql | sqlite3 "$DatabasePath"

Write-Host "SQLite-Datenbank initialisiert: $DatabasePath" -ForegroundColor Cyan

# 4. GitHub Issues abrufen
$syncedAt = (Get-Date).ToString("o")
$newCount = 0

foreach ($repo in $Repos) {
    Write-Host "Prüfe Repository: $repo ..." -ForegroundColor Yellow
    
    $issuesJson = gh issue list --repo $repo --state all --json number,title,body,labels,createdAt,state,author,url -L 100 2>$null
    if (-not $issuesJson -or $issuesJson -eq "[]") {
        Write-Host "  Keine Issues in $repo gefunden oder gh CLI nicht eingeloggt." -ForegroundColor DarkGray
        continue
    }

    $issues = $issuesJson | ConvertFrom-Json
    foreach ($issue in $issues) {
        $labels = @($issue.labels | ForEach-Object { $_.name })
        $isFeedback = ($labels -contains "feedback") -or 
                      ($labels -contains "community-report") -or 
                      ($issue.title -match "^\[(Feedback|Cabinet Report|Report|Bug|Idee)\]")

        if (-not $isFeedback) {
            continue
        }

        # Daten parsen
        $kind = "other"
        if ($labels -contains "type:bug" -or $issue.title -match "Bug") { $kind = "bug" }
        elseif ($labels -contains "type:idea" -or $issue.title -match "Idee") { $kind = "idea" }
        elseif ($labels -contains "type:compat" -or $labels -contains "works" -or $labels -contains "partial") { $kind = "compat" }

        $outcome = "unknown"
        if ($labels -contains "outcome:works" -or $issue.body -match "Es läuft bei mir") { $outcome = "works" }
        elseif ($labels -contains "outcome:partial" -or $issue.body -match "Läuft teilweise") { $outcome = "partial" }
        elseif ($labels -contains "outcome:broken" -or $kind -eq "bug") { $outcome = "broken" }

        $cabinet = "Unbekannt"
        if ($issue.body -match "\| \*\*Cabinet-Typ\*\* \| ([^|\r\n]+) \|") { $cabinet = $matches[1].Trim() }
        elseif ($issue.body -match "\| Kabinett \| ([^|\r\n]+) \|") { $cabinet = $matches[1].Trim() }

        $os = "Unbekannt"
        if ($issue.body -match "\| \*\*Betriebssystem\*\* \| ([^|\r\n]+) \|") { $os = $matches[1].Trim() }
        elseif ($issue.body -match "\| Betriebssystem \| ([^|\r\n]+) \|") { $os = $matches[1].Trim() }

        $hw = ""
        if ($issue.body -match "\| \*\*Hardware / Controller\*\* \| ([^|\r\n]+) \|") { $hw = $matches[1].Trim() }
        elseif ($issue.body -match "\| Lightgun-Hardware \| ([^|\r\n]+) \|") { $hw = $matches[1].Trim() }

        $ver = ""
        if ($issue.body -match "\| \*\*Kit-Version\*\* \| ([^|\r\n]+) \|") { $ver = $matches[1].Trim() }
        elseif ($issue.body -match "\| Kit \| ([^|\r\n]+) \|") { $ver = $matches[1].Trim() }

        # In SQLite speichern
        $authorName = if ($issue.author) { $issue.author.login } else { "Anonym" }
        
        # SQL-Escaping (einfache Anführungszeichen verdoppeln)
        $escTitle = $issue.title -replace "'", "''"
        $escBody = $issue.body -replace "'", "''"
        $escUrl = $issue.url -replace "'", "''"
        $escCabinet = $cabinet -replace "'", "''"
        $escOs = $os -replace "'", "''"
        $escHw = $hw -replace "'", "''"

        $upsertSql = @"
INSERT INTO feedback_reports (repo, issue_number, state, created_at, synced_at, author, title, kind, outcome, cabinet, os, hardware, version, body_markdown, url)
VALUES ('$repo', $($issue.number), '$($issue.state)', '$($issue.createdAt)', '$syncedAt', '$authorName', '$escTitle', '$kind', '$outcome', '$escCabinet', '$escOs', '$escHw', '$ver', '$escBody', '$escUrl')
ON CONFLICT(repo, issue_number) DO UPDATE SET
    state = excluded.state,
    synced_at = excluded.synced_at,
    title = excluded.title,
    body_markdown = excluded.body_markdown;
"@
        $upsertSql | sqlite3 "$DatabasePath"
        $newCount++
    }
}

# Gesamtzahl erfassen
$totalCount = ("SELECT COUNT(*) FROM feedback_reports;" | sqlite3 "$DatabasePath").Trim()
"INSERT INTO sync_history (synced_at, new_reports_count, total_reports_count) VALUES ('$syncedAt', $newCount, $totalCount);" | sqlite3 "$DatabasePath"

Write-Host "Sync abgeschlossen: $newCount Berichte synchronisiert. Gesamtbestand in DB: $totalCount" -ForegroundColor Green

# 5. Tägliche Auswertung generieren
if (-not $SkipEvaluation) {
    Write-Host "Erstelle tägliche Feedback-Auswertung..." -ForegroundColor Cyan

    $statsByType = "SELECT kind, count(*) FROM feedback_reports GROUP BY kind;" | sqlite3 "$DatabasePath"
    $statsByOutcome = "SELECT outcome, count(*) FROM feedback_reports GROUP BY outcome;" | sqlite3 "$DatabasePath"
    $recentReports = "SELECT issue_number, repo, title, outcome, cabinet, created_at FROM feedback_reports ORDER BY created_at DESC LIMIT 10;" | sqlite3 "$DatabasePath"

    $digestLines = @(
        "# Tägliche Feedback-Auswertung (Retro Cabinet Kit & Agent)",
        "",
        "> Generiert am: **$((Get-Date).ToString('dd.MM.yyyy HH:mm'))** aus SQLite-Datenbank (`output/feedback.db`)",
        "",
        "## Kennzahlen im Überblick",
        "- **Gesamtzahl erfasste Berichte:** $totalCount",
        "- **Letzter Sync:** $syncedAt",
        "",
        '### Aufteilung nach Art der Meldung',
        '```',
        $statsByType,
        '```',
        '',
        '### Aufteilung nach Testergebnis (Outcome)',
        '```',
        $statsByOutcome,
        '```',
        "",
        "## Die 10 neuesten eingegangenen Berichte",
        "| # | Repo | Titel | Ergebnis | Cabinet | Datum |",
        "|---|---|---|---|---|---|"
    )

    if ($recentReports) {
        foreach ($r in $recentReports -split "`n") {
            if ($r.Trim()) {
                $cols = $r -split "\|"
                $digestLines += "| #$($cols[0]) | $($cols[1] -replace 'kburna243/','') | $($cols[2]) | **$($cols[3])** | $($cols[4]) | $($cols[5].Substring(0, 10)) |"
            }
        }
    } else {
        $digestLines += "| - | - | Noch keine Community-Reports vorhanden | - | - | - |"
    }

    $digestLines += @(
        "",
        "---",
        "### Empfohlene nächste Schritte für Entwickler",
        "- [ ] Testmatrix prüfen: Welche gemeldeten Hardware-Kombinationen sind stabil?",
        "- [ ] Gibt es neue Berichte zur **Sinden Lightgun** oder **VPX 3-Monitor**?",
        '- [ ] Fehlerberichte (Outcome: `broken`) priorisieren und in Issues beantworten.'
    )

    $digestContent = $digestLines -join "`r`n"
    [System.IO.File]::WriteAllText($OutputSummaryPath, $digestContent, [System.Text.UTF8Encoding]::new($false))
    Write-Host "Auswertungsbericht gespeichert: $OutputSummaryPath" -ForegroundColor Green
}
