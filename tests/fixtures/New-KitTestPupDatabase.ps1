<#
.SYNOPSIS
    Creates a synthetic PinUP-Popper-like database (schema excerpt only, fake generic paths).
#>
param([Parameter(Mandatory)] [string] $Path)

Import-Module (Join-Path $PSScriptRoot '..\..\core\RetroCabinetKit.Core.psd1')

$db = Open-KitSqlite -Path $Path -Create
try {
    $null = Invoke-KitSqlNonQuery -Connection $db -Sql @'
CREATE TABLE Emulators(EMUID INTEGER PRIMARY KEY, EmuName TEXT, DirGames TEXT, LaunchScript TEXT);
CREATE TABLE GlobalSettings(GlobalMediaDir TEXT);
'@
    $rows = @(
        @{ id = 1; name = 'Visual Pinball X'; dir = 'C:\Games\vPinball\VisualPinball\Tables'; script = 'START "" "C:\Games\vPinball\VisualPinball\VPinballX.exe"' }
        @{ id = 2; name = 'Future Pinball';   dir = 'C:\Games\vPinball\FuturePinball\Tables'; script = 'cd /d "C:\Games\vPinball\FuturePinball"' }
        @{ id = 3; name = 'PinballFX';        dir = 'C:\Program Files (x86)\Steam\steamapps\common'; script = $null }
    )
    foreach ($r in $rows) {
        $null = Invoke-KitSqlNonQuery -Connection $db -Parameters $r `
            -Sql 'INSERT INTO Emulators(EMUID, EmuName, DirGames, LaunchScript) VALUES (@id, @name, @dir, @script)'
    }
    $null = Invoke-KitSqlNonQuery -Connection $db -Sql 'INSERT INTO GlobalSettings(GlobalMediaDir) VALUES (@m)' `
        -Parameters @{ m = 'C:\Games\vPinball\pinupsystem\POPMedia\Default' }
} finally {
    Close-KitSqlite $db
}
