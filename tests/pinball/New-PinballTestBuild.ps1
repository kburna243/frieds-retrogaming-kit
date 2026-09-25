<#
.SYNOPSIS
    Creates a synthetic PinUP Popper build below -Root whose files point to -OldRoot (generic fake paths only):
    database with the measured schema excerpt, text files in several encodings, log files, shortcuts,
    Future Pinball/BAM files, runtime installers (empty placeholders).
#>
param(
    [Parameter(Mandatory)] [string] $Root,
    [Parameter(Mandatory)] [string] $OldRoot
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '..\..\core\RetroCabinetKit.Core.psd1')

$o = $OldRoot.TrimEnd('\')
$v = Join-Path $Root 'vPinball'
function New-File([string] $Path, [string] $Text = '', [Text.Encoding] $Encoding = [Text.Encoding]::Default, [switch] $Bom) {
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $pre = if ($Bom) { $Encoding.GetPreamble() } else { [byte[]]@() }
    [IO.File]::WriteAllBytes($Path, [byte[]]($pre + $Encoding.GetBytes($Text)))
}

# --- database
$dbPath = Join-Path $v 'PinUPSystem\PUPDatabase.db'
New-Item -ItemType Directory -Path (Split-Path $dbPath) -Force | Out-Null
$db = Open-KitSqlite -Path $dbPath -Create
try {
    $null = Invoke-KitSqlNonQuery -Connection $db -Sql @'
CREATE TABLE Emulators(EMUID INTEGER PRIMARY KEY, EmuName VARCHAR (100), DirGames VARCHAR (250), DirMedia VARCHAR (255), DirRoms VARCHAR (250), LaunchScript TEXT, Visible INTEGER);
CREATE TABLE Games(GameID INTEGER PRIMARY KEY, EMUID INTEGER, GameFileName VARCHAR (250), Notes TEXT);
CREATE TABLE GlobalSettings(GlobalMediaDir VARCHAR (250), StartupBatch TEXT);
CREATE TABLE Screens(ScreenID INTEGER, ScreenName VARCHAR (50));
'@
    $emulators = @(
        @{ id = 1; n = 'Visual Pinball X'; g = "$o\vPinball\VisualPinball\Tables"; m = "$o\vPinball\PinUPSystem\POPMedia\Visual Pinball X"; r = $null
           s = "START `"`" `"$o\vPinball\VisualPinball\VPinballX.exe`" -play `"[GAMEFULLNAME]`"`r`ncd /d `"$o\vPinball\VisualPinball`"" }
        @{ id = 2; n = 'PinballFX'; g = 'C:\Program Files (x86)\Steam\steamapps\common'; m = "$o\vPinball\PinUPSystem\POPMedia\PinballFX"; r = $null
           s = 'START "" "C:\Program Files (x86)\Steam\steam.exe" -applaunch 442120' }
        @{ id = 3; n = "Demon's Tilt"; g = "$o\vPinball\Pinball PC\Demon's Tilt"; m = $null; r = "$o\vPinball\Pinball PC\Demon's Tilt\Steam"; s = $null }
        @{ id = 4; n = 'DOF'; g = $null; m = $null; r = $null; s = "START `"`" `"$o\DOFLinx\DOFLinx.exe`"" }
        @{ id = 5; n = 'Look-alikes'; g = "$o\vPinballBackup\Tables"; m = "$o\Other\Media"; r = $null; s = $null }
    )
    foreach ($e in $emulators) {
        $null = Invoke-KitSqlNonQuery -Connection $db -Parameters $e -Sql 'INSERT INTO Emulators(EMUID, EmuName, DirGames, DirMedia, DirRoms, LaunchScript, Visible) VALUES (@id, @n, @g, @m, @r, @s, 1)'
    }
    $null = Invoke-KitSqlNonQuery -Connection $db -Sql 'INSERT INTO Games(GameID, EMUID, GameFileName, Notes) VALUES (1, 1, @f, @n)' `
        -Parameters @{ f = 'Test Table (1990).vpx'; n = "copied from $o\vPinball\VisualPinball\Tables\old" }
    $null = Invoke-KitSqlNonQuery -Connection $db -Sql 'INSERT INTO GlobalSettings(GlobalMediaDir, StartupBatch) VALUES (@m, NULL)' `
        -Parameters @{ m = "$o\vPinball\pinupsystem\POPMedia\Default" }
    $null = Invoke-KitSqlNonQuery -Connection $db -Sql "INSERT INTO Screens(ScreenID, ScreenName) VALUES (0, 'Table')"
} finally { Close-KitSqlite $db }

# --- text files (encodings), logs, siblings
New-File (Join-Path $Root 'DOFLinx\DOFLinx.INI') "PATH_PINUP=$o\vPinball\PinUPSystem\`r`nPATH_FX=C:\Program Files (x86)\Steam\`r`n"
New-File (Join-Path $v 'PinUPSystem\Launch\curlaunch.bat') "rem Läuft`r`ncd /d `"$o\vPinball\PinUPSystem`"`r`n" (New-Object Text.UTF8Encoding $false)
New-File (Join-Path $v 'VisualPinball\Tables\B2STableSettings.xml') "<B2S><Path>$o\vPinball\VisualPinball\Tables\</Path></B2S>" ([Text.Encoding]::Unicode) -Bom
New-File (Join-Path $v 'VisualPinball\Tables\script.vbs') "Const P = `"$o\vPinball\VisualPinball\Tables\`"`r`n"
New-File (Join-Path $v "Pinball PC\Demon's Tilt.bat") "cd /d `"$o\vPinball\Pinball PC\Demon's Tilt`"`r`nstart `"`" `"Demon's Tilt.exe`"`r`n"
New-File (Join-Path $v 'PinUPSystem\log.txt') "started $o\vPinball\PinUPSystem\PinUpMenu.exe`r`n"
New-File (Join-Path $v 'VisualPinball\VPinMAME\PUPLOG.txt') "$o\vPinball\VisualPinball\VPinMAME`r`n"
New-File (Join-Path $v 'PinUPSystem\menu.log') "$o\vPinball\PinUPSystem`r`n"

# --- shortcuts: one into the build (live after relocation), one dead B2S plugin link with its plugin folder
New-File (Join-Path $v 'Deluxe\Arcade.exe')
$null = Set-KitShortcut -Path (Join-Path $v 'Deluxe\Arcade - Shortcut.lnk') -TargetPath "$o\vPinball\Deluxe\Arcade.exe" -WorkingDirectory "$o\vPinball\Deluxe"
New-Item -ItemType Directory -Path (Join-Path $v 'VisualPinball\Tables\plugins\PinUPPlayerB2SDriver') -Force | Out-Null
$null = Set-KitShortcut -Path (Join-Path $v 'VisualPinball\Tables\plugins\PinUPPlayerB2SDriver LINK.lnk') -TargetPath 'C:\PinUPSystem\PinUPPlayerB2SDriver'

# --- Future Pinball / BAM ("set /p" reads stdin: it only returns at once when stdin is nul)
New-File (Join-Path $v 'FuturePinball\Future Pinball.exe')
New-File (Join-Path $v 'FuturePinball\BAM\FPLoader.exe')
New-File (Join-Path $v 'FuturePinball\BAM\BAM Install Guide.pdf')
New-File (Join-Path $v 'FuturePinball\BAM\BAM settings - Cabinet - Reset and Install.bat') "@echo off`r`nset /p answer=Press a key`r`necho done> bam_ran.txt`r`n"

# --- runtime installers (placeholders)
New-File (Join-Path $v '2-Programs\All In One Runtimes\vcredist2008_x86.exe')
New-File (Join-Path $v 'Installer\directx9\DXSETUP.exe')
