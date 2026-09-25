$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
$newDb = Join-Path $kitRoot 'tests\fixtures\New-KitTestPupDatabase.ps1'

function Get-Hash([string] $Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }

Describe 'Sqlite basics' {
    $dbPath = Join-Path $TestDrive 'PUPDatabase.db'
    & $newDb -Path $dbPath
    $db = Open-KitSqlite -Path $dbPath

    It 'lists tables and columns' {
        (Get-KitSqlTable -Connection $db) -join ',' | Should Be 'Emulators,GlobalSettings'
        ((Get-KitSqlColumn -Connection $db -Table 'Emulators') | ForEach-Object { $_.Name }) -join ',' | Should Be 'EMUID,EmuName,DirGames,LaunchScript'
    }

    It 'binds text with an apostrophe' {
        $n = Invoke-KitSqlNonQuery -Connection $db -Sql 'INSERT INTO Emulators(EMUID, EmuName, DirGames) VALUES (@id, @name, @dir)' `
            -Parameters @{ id = 10; name = "Demon's Tilt"; dir = "C:\Games\Demon's Tilt" }
        $n | Should Be 1
        $rows = @(Invoke-KitSqlQuery -Connection $db -Sql 'SELECT EMUID, DirGames FROM Emulators WHERE EmuName = @name' -Parameters @{ name = "Demon's Tilt" })
        $rows.Count | Should Be 1
        $rows[0].EMUID | Should Be 10
        $rows[0].DirGames | Should BeExactly "C:\Games\Demon's Tilt"
    }

    It 'binds NULL and keeps the empty string distinct from NULL' {
        $null = Invoke-KitSqlNonQuery -Connection $db -Sql 'INSERT INTO Emulators(EMUID, EmuName, LaunchScript) VALUES (@id, @name, @script)' -Parameters @{ id = 11; name = 'null'; script = $null }
        $null = Invoke-KitSqlNonQuery -Connection $db -Sql 'INSERT INTO Emulators(EMUID, EmuName, LaunchScript) VALUES (@id, @name, @script)' -Parameters @{ id = 12; name = 'empty'; script = '' }
        (@(Invoke-KitSqlQuery -Connection $db -Sql 'SELECT EMUID FROM Emulators WHERE LaunchScript IS NULL AND EMUID >= 11'))[0].EMUID | Should Be 11
        $empty = @(Invoke-KitSqlQuery -Connection $db -Sql 'SELECT LaunchScript FROM Emulators WHERE EMUID = @id' -Parameters @{ id = 12 })
        $empty[0].LaunchScript | Should BeExactly ''
        $null -eq $empty[0].LaunchScript | Should Be $false
    }

    It 'binds integers and round-trips Unicode' {
        $null = Invoke-KitSqlNonQuery -Connection $db -Sql 'UPDATE Emulators SET EmuName = @n WHERE EMUID = @id' -Parameters @{ n = 'Flipper ä ö ü ß €'; id = [long]2 }
        (@(Invoke-KitSqlQuery -Connection $db -Sql 'SELECT EmuName FROM Emulators WHERE EMUID = @id' -Parameters @{ id = 2 }))[0].EmuName | Should BeExactly 'Flipper ä ö ü ß €'
    }

    It 'fails on a missing parameter' {
        { Invoke-KitSqlQuery -Connection $db -Sql 'SELECT * FROM Emulators WHERE EMUID = @id' } | Should Throw
    }

    It 'rolls a transaction back when the script block throws' {
        { Invoke-KitSqlTransaction -Connection $db -ScriptBlock {
                param($c)
                $null = Invoke-KitSqlNonQuery -Connection $c -Sql "UPDATE Emulators SET DirGames = 'X'"
                throw 'forced'
            } } | Should Throw 'forced'
        (@(Invoke-KitSqlQuery -Connection $db -Sql "SELECT COUNT(*) AS n FROM Emulators WHERE DirGames = 'X'"))[0].n | Should Be 0
    }

    It 'refuses writes on a read-only connection' {
        $ro = Open-KitSqlite -Path $dbPath -ReadOnly
        try {
            { Invoke-KitSqlNonQuery -Connection $ro -Sql "UPDATE Emulators SET DirGames = 'Y'" } | Should Throw
            @(Invoke-KitSqlQuery -Connection $ro -Sql 'SELECT * FROM GlobalSettings').Count | Should Be 1
        } finally { Close-KitSqlite $ro }
    }

    Close-KitSqlite $db

    It 'does not create a database without -Create' {
        { Open-KitSqlite -Path (Join-Path $TestDrive 'missing.db') } | Should Throw
        Join-Path $TestDrive 'missing.db' | Should Not Exist
    }

    It 'works in 32-bit PowerShell (StdCall declarations)' {
        $ps32 = Join-Path $env:SystemRoot 'SysWOW64\WindowsPowerShell\v1.0\powershell.exe'
        $module = Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1'
        $code = "Import-Module '$module'; `$c = Open-KitSqlite -Path '$dbPath' -ReadOnly; " +
                "`$r = Invoke-KitSqlQuery -Connection `$c -Sql 'SELECT EmuName FROM Emulators WHERE EMUID = @id' -Parameters @{ id = 1 }; " +
                "Close-KitSqlite `$c; '{0}|{1}' -f [IntPtr]::Size, `$r.EmuName"
        $out = & $ps32 -NoProfile -ExecutionPolicy Bypass -Command $code
        $LASTEXITCODE | Should Be 0
        ($out | Select-Object -Last 1) | Should BeExactly '4|Visual Pinball X'
    }
}

Describe 'Update-KitDatabaseSafely' {
    It 'leaves the original byte-identical when the change throws' {
        $p = Join-Path $TestDrive 'fail.db'
        & $newDb -Path $p
        $hash = Get-Hash $p
        { Update-KitDatabaseSafely -Path $p -Purpose 'relocate' -ScriptBlock {
                param($c)
                $null = Invoke-KitSqlNonQuery -Connection $c -Sql "UPDATE Emulators SET DirGames = 'D:\new'"
                throw 'forced failure'
            } } | Should Throw 'forced failure'
        Get-Hash $p | Should Be $hash
        @(Get-ChildItem -LiteralPath $TestDrive -Filter 'fail.db*').Count | Should Be 1
    }

    It 'swaps in the changed copy and keeps the original as backup' {
        $p = Join-Path $TestDrive 'ok.db'
        & $newDb -Path $p
        $hash = Get-Hash $p
        $r = Update-KitDatabaseSafely -Path $p -Purpose 'relocate' -ScriptBlock {
            param($c)
            Invoke-KitSqlNonQuery -Connection $c -Sql 'UPDATE Emulators SET DirGames = REPLACE(DirGames, @old, @new)' -Parameters @{ old = 'C:\Games\'; new = 'D:\Neu Ordner\' }
        }
        $r.Result | Should Be 3
        [IO.Path]::GetFileName($r.Backup) | Should Match '^ok\.db\.bak_relocate_\d{8}-\d{6}$'
        Get-Hash $r.Backup | Should Be $hash
        $c = Open-KitSqlite -Path $p -ReadOnly
        try {
            (@(Invoke-KitSqlQuery -Connection $c -Sql 'SELECT DirGames FROM Emulators WHERE EMUID = 1'))[0].DirGames | Should BeExactly 'D:\Neu Ordner\vPinball\VisualPinball\Tables'
            (@(Invoke-KitSqlQuery -Connection $c -Sql 'PRAGMA integrity_check'))[0].integrity_check | Should Be 'ok'
        } finally { Close-KitSqlite $c }
        @(Get-ChildItem -LiteralPath $TestDrive -Filter 'ok.db.work_*').Count | Should Be 0
    }

    It 'runs a dry run under -WhatIf and changes nothing' {
        $p = Join-Path $TestDrive 'dry.db'
        & $newDb -Path $p
        $hash = Get-Hash $p
        $r = Update-KitDatabaseSafely -Path $p -Purpose 'relocate' -WhatIf -ScriptBlock {
            param($c)
            Invoke-KitSqlNonQuery -Connection $c -Sql "UPDATE Emulators SET DirGames = 'X'"
        }
        $r.WhatIf | Should Be $true
        $r.Result | Should Be 3
        Get-Hash $p | Should Be $hash
        @(Get-ChildItem -LiteralPath $TestDrive -Filter 'dry.db*').Count | Should Be 1
    }

    It 'refuses a purpose with unsafe characters' {
        $p = Join-Path $TestDrive 'purpose.db'
        & $newDb -Path $p
        { Update-KitDatabaseSafely -Path $p -Purpose '..\x' -ScriptBlock { } } | Should Throw
    }
}
