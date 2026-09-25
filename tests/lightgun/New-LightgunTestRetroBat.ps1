<#
.SYNOPSIS
    Builds a synthetic RetroBat folder for the lightgun tests: emulationstation.exe (empty), es_settings.cfg
    with a comment and a partial gun setup, es_input.cfg with an incomplete Xbox block, gamelists (one with a
    hard-wired <emulator>) and an emulatorLauncher.log. Generic values only.
#>
param([Parameter(Mandatory)] [string] $Root)
$es = Join-Path $Root 'emulationstation'
$cfg = Join-Path $es '.emulationstation'
New-Item -ItemType Directory -Path $cfg, (Join-Path $Root 'roms\mame'), (Join-Path $Root 'roms\psx'), (Join-Path $Root 'system') -Force | Out-Null
[IO.File]::WriteAllBytes((Join-Path $es 'emulationstation.exe'), [byte[]]@())
[IO.File]::WriteAllText((Join-Path $Root 'system\version.info'), '9.9.9-test')
$utf8 = New-Object Text.UTF8Encoding $false
$nl = "`r`n"

$settings = @(
    '<?xml version="1.0"?>'
    '<config>'
    '  <!-- kept by the kit: a user comment -->'
    '  <bool name="FavoritesFirst" value="true" />'
    '  <string name="mame.emulator" value="libretro" />'
    '  <string name="mame.use_guns" value="1" />'
    '  <string name="mame[&quot;alien3.zip&quot;].use_guns" value="1" />'
    '  <string name="naomi.use_guns" value="0" />'
    '  <string name="psx.core" value="duckstation" />'
    '  <string name="zzz.last" value="stays last" />'
    '</config>'
) -join $nl
[IO.File]::WriteAllText((Join-Path $cfg 'es_settings.cfg'), $settings + $nl, $utf8)

$inputCfg = @(
    "<?xml version='1.0' encoding='utf-8'?>"
    '<inputList>'
    '	<inputConfig type="keyboard" deviceName="Keyboard" deviceGUID="-1">'
    '		<input name="a" type="key" id="120" value="1" />'
    '	</inputConfig>'
    '	<inputConfig type="joystick" deviceName="Xbox 360 Controller" deviceGUID="030000005e0400008e02000000007200">'
    '		<input name="a" type="button" id="1" value="1" />'
    '		<input name="b" type="button" id="0" value="1" />'
    '	</inputConfig>'
    '</inputList>'
) -join $nl
[IO.File]::WriteAllText((Join-Path $cfg 'es_input.cfg'), $inputCfg + $nl, $utf8)

$gamelist = @(
    '<?xml version="1.0"?>'
    '<gameList>'
    '	<game><path>./alien3.zip</path><name>Alien 3</name></game>'
    '	<game><path>./area51.zip</path><name>Area 51</name><emulator>libretro</emulator><core>mame</core></game>'
    '	<game><path>./same.zip</path><name>Same as the kit</name><emulator>mame64</emulator></game>'
    '</gameList>'
) -join $nl
[IO.File]::WriteAllText((Join-Path $Root 'roms\mame\gamelist.xml'), $gamelist + $nl, $utf8)
[IO.File]::WriteAllText((Join-Path $Root 'roms\psx\gamelist.xml'), ('<?xml version="1.0"?>' + $nl + '<gameList />' + $nl), $utf8)

$log = @(
    '2026-01-01 10:00:00.000 [INFO]      [Startup] "X:\RetroBat\emulationstation\emulatorLauncher.exe"  -gameinfo "x.xml" -p1index 0 -p1name "Xbox 360 Controller" -lightgun  -system mame -emulator libretro -core mame -rom "X:\RetroBat\roms\mame\area51.zip"'
    '2026-01-01 10:00:01.000 [INFO]      [LightGun] Assigned player 1 to -> Wiimote4Guns P1 index: 0'
    '2026-01-01 10:00:02.000 [INFO]      [Running] X:\RetroBat\emulators\retroarch\retroarch.exe -L mame'
    '2026-01-01 11:00:00.000 [INFO]      [Startup] "X:\RetroBat\emulationstation\emulatorLauncher.exe"  -gameinfo "x.xml" -p1index 0 -p1name "Xbox 360 Controller" -system psx -emulator duckstation -core duckstation -rom "X:\RetroBat\roms\psx\game (USA).chd"'
    '2026-01-01 11:00:01.000 [INFO]      [Running] X:\RetroBat\emulators\duckstation\duckstation-qt-x64-ReleaseLTCG.exe -batch -fullscreen'
) -join $nl
[IO.File]::WriteAllText((Join-Path $es 'emulatorLauncher.log'), $log + $nl, $utf8)
