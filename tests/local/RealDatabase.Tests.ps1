$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1') -Force

# Runs only with tests\Run-Tests.ps1 -Local. Works on a COPY of a real Popper database that is kept in
# tests\fixtures-local\ (gitignored, never committed). A missing fixture is a failure, not a skip.
$fixture = Join-Path $kitRoot 'tests\fixtures-local\PUPDatabase-real.db'
$newRoot = Join-Path ([IO.Path]::GetTempPath()) 'Kit Test' # only a path in the rewritten texts, nothing is written there

function Get-Hash([string] $Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }

# Independent count by plain SQL substring arithmetic (no regex): occurrences of "<old>\vpinball" followed
# by a separator or the end, per text column.
function Get-OracleCount([string] $Db, [string] $OldRoot) {
    $needle = ($OldRoot + '\vpinball').ToLowerInvariant()
    $c = Open-KitSqlite -Path $Db -ReadOnly
    $result = [pscustomobject]@{ Occurrences = 0; Cells = 0; Columns = @() }
    try {
        foreach ($t in Get-KitSqlTable -Connection $c) {
            $qt = '"' + $t + '"'
            foreach ($col in Get-KitSqlColumn -Connection $c -Table $t) {
                $qc = '"' + $col.Name + '"'
                $rows = @(Invoke-KitSqlQuery -Connection $c -Parameters @{ n = $needle; s = "$needle\"; e = "$needle`"" } -Sql (
                    "SELECT (length(lower($qc)) - length(replace(lower($qc), @s, ''))) / length(@s) " +
                    "     + (length(lower($qc)) - length(replace(lower($qc), @e, ''))) / length(@e) " +
                    "     + (CASE WHEN substr(lower($qc), -length(@n)) = @n THEN 1 ELSE 0 END) AS k " +
                    "FROM $qt WHERE typeof($qc) = 'text' AND instr(lower($qc), @n) > 0"))
                $hits = @($rows | Where-Object { $_.k -gt 0 })
                if ($hits) {
                    $result.Occurrences += ($hits | Measure-Object -Property k -Sum).Sum
                    $result.Cells += $hits.Count
                    $result.Columns += "$t.$($col.Name)"
                }
            }
        }
    } finally { Close-KitSqlite $c }
    $result
}

function Get-SteamValue([string] $Db) {
    $c = Open-KitSqlite -Path $Db -ReadOnly
    try {
        foreach ($t in Get-KitSqlTable -Connection $c) {
            foreach ($col in Get-KitSqlColumn -Connection $c -Table $t) {
                Invoke-KitSqlQuery -Connection $c -Sql "SELECT rowid AS rid, `"$($col.Name)`" AS v FROM `"$t`" WHERE instr(`"$($col.Name)`", 'Program Files (x86)\Steam') > 0" |
                    ForEach-Object { "$t.$($col.Name)#$($_.rid)=$($_.v)" }
            }
        }
    } finally { Close-KitSqlite $c }
}

Describe 'Relocation of a real Popper database (local fixture)' {
    Set-KitCulture -Culture 'en-US'

    It 'has the local fixture' {
        $fixture | Should Exist
    }

    $originalHash = Get-Hash $fixture
    $root = Join-Path $TestDrive 'Kit Test'
    $db = Get-PinballDatabasePath -Root $root
    New-Item -ItemType Directory -Path (Split-Path $db) -Force | Out-Null
    Copy-Item -LiteralPath $fixture -Destination $db
    $oldRoot = Get-PinballOldRoot -DatabasePath $db
    $relocator = New-PinballRelocator -OldRoot $oldRoot -NewRoot $newRoot
    $oracle = Get-OracleCount $db $oldRoot
    $steam = @(Get-SteamValue $db)

    It 'knows the schema and derives the old root' {
        (Test-PinballDatabaseSchema -Path $db).IsValid | Should Be $true
        $oldRoot | Should Not BeNullOrEmpty
    }

    It 'counts the same occurrences as an independent SQL count in a dry run and changes nothing' {
        $hash = Get-Hash $db
        $dry = Invoke-PinballDatabaseRelocation -Path $db -Relocator $relocator -DryRun
        Write-Host ("    dry run: {0} occurrences in {1} cells / {2} rows / {3} columns ({4}); SQL count: {5} occurrences in {6} cells / {7} columns; Steam values: {8}" -f `
            $dry.Occurrences, $dry.Cells, $dry.Rows, $dry.Columns.Count, ($dry.Columns -join ', '), $oracle.Occurrences, $oracle.Cells, $oracle.Columns.Count, $steam.Count)
        $dry.Occurrences | Should Be $oracle.Occurrences
        $dry.Cells | Should Be $oracle.Cells
        $dry.Columns.Count | Should Be $oracle.Columns.Count
        $dry.Occurrences | Should BeGreaterThan 0
        Get-Hash $db | Should Be $hash
    }

    It 'rewrites all of them, leaves Steam alone and keeps the database intact' {
        $r = Invoke-PinballDatabaseRelocation -Path $db -Relocator $relocator
        $r.Applied | Should Be $true
        $after = (Invoke-PinballDatabaseRelocation -Path $db -Relocator $relocator -DryRun).Occurrences
        $afterSql = (Get-OracleCount $db $oldRoot).Occurrences
        $newCount = (Get-OracleCount $db $newRoot).Occurrences
        Write-Host ("    real run: {0} occurrences rewritten; afterwards old: {1} (SQL: {2}), new root: {3}" -f $r.Occurrences, $after, $afterSql, $newCount)
        $after | Should Be 0
        $afterSql | Should Be 0
        $newCount | Should Be $oracle.Occurrences
        (@(Get-SteamValue $db) -join "`n") | Should BeExactly ($steam -join "`n")
        $c = Open-KitSqlite -Path $db -ReadOnly
        try { (@(Invoke-KitSqlQuery -Connection $c -Sql 'PRAGMA integrity_check'))[0].integrity_check | Should Be 'ok' } finally { Close-KitSqlite $c }
        (Invoke-PinballDatabaseRelocation -Path $db -Relocator $relocator).Applied | Should Be $false
    }

    It 'leaves the original fixture byte-identical' {
        Get-Hash $fixture | Should Be $originalHash
    }
}
