<#
.SYNOPSIS
    Adds a synthetic TeknoParrot setup to a test RetroBat (New-LightgunTestRetroBat.ps1 first): UserProfiles from a
    foreign build root, a touch screen game, a pad game, a switched-off profile, a missing game, a nested "roms"
    folder; RetroBat's teknoparrot.yml (excerpt with generic names); rom folders with a name duplicate, a content
    duplicate and an unregistered folder; gamelist.xml with an orphan; es_settings leftovers of a build creator.
    Generic values only.
#>
param([Parameter(Mandatory)] [string] $Root)
$utf8 = New-Object Text.UTF8Encoding $false
$nl = "`r`n"
$tp = Join-Path $Root 'emulators\teknoparrot'
$up = Join-Path $tp 'UserProfiles'
$roms = Join-Path $Root 'roms\teknoparrot'
foreach ($d in $up, (Join-Path $tp 'Metadata'), (Join-Path $Root 'system\resources\inputmapping'), "$roms\images",
    "$roms\GunA.parrot", "$roms\GunA.teknoparrot", "$roms\GunB.parrot\bin", "$roms\Copy of B\bin", "$roms\Stray.parrot",
    "$roms\TouchGame.parrot", (Join-Path $Root 'roms\namco\roms')) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
foreach ($f in "$roms\GunA.parrot\game.exe", "$roms\GunA.teknoparrot\game.exe", "$roms\TouchGame.parrot\t.exe", "$roms\Stray.parrot\s.exe",
    (Join-Path $Root 'roms\namco\roms\nested.bin'), "$roms\images\GunA-image.png") { [IO.File]::WriteAllBytes($f, [byte[]](1, 2, 3)) }
foreach ($d in "$roms\GunB.parrot", "$roms\Copy of B") { [IO.File]::WriteAllBytes("$d\bin\b.elf", [byte[]](1..40)); [IO.File]::WriteAllBytes("$d\readme.txt", [byte[]](7, 7)) }

function New-Button([string] $Name, [string] $Mapping, [switch] $Raw) {
    $rawXml = if ($Raw) { "$nl      <RawInputButton>$nl        <DevicePath>\\?\HID#VID_0000&amp;PID_0000#1</DevicePath>$nl        <DeviceType>Mouse</DeviceType>$nl        <MouseButton>LeftButton</MouseButton>$nl        <KeyboardKey>None</KeyboardKey>$nl      </RawInputButton>" } else { '' }
    "    <JoystickButtons>$nl      <ButtonName>$Name</ButtonName>$rawXml$nl      <InputMapping>$Mapping</InputMapping>$nl      <AnalogType>None</AnalogType>$nl      <BindNameRi>Some Gun</BindNameRi>$nl      <BindName>Some Gun</BindName>$nl      <HideWithXInput>false</HideWithXInput>$nl    </JoystickButtons>"
}
$gunButtons = @(
    New-Button 'Test' 'Test'
    New-Button 'Coin 1' 'Coin1'
    New-Button 'Player 1 Trigger' 'P1Button1' -Raw
    New-Button 'Player 1 Reload' 'P1Button2' -Raw
    New-Button 'Player 1 Grenade' 'P1Button3'
    New-Button 'Player 2 Trigger' 'P2Button1'
    New-Button 'Player 1 Gun X' 'Analog0'
    New-Button 'Player 1 Gun Y' 'Analog2'
    New-Button 'Player 1 Gun Y Up' 'P1RelativeUp'
) -join $nl

function New-Profile([string] $File, [string] $GamePath, [string] $Gun = 'true', [string] $Buttons = $gunButtons, [string] $GamePath2, [switch] $Bom) {
    $gp = if ($GamePath) { "  <GamePath>$([Security.SecurityElement]::Escape($GamePath))</GamePath>" } else { '  <GamePath />' }
    $gp2 = if ($GamePath2) { "$nl  <GamePath2>$([Security.SecurityElement]::Escape($GamePath2))</GamePath2>" } else { "$nl  <GamePath2 />" }
    $xml = @(
        '<?xml version="1.0" encoding="utf-8"?>'
        '<GameProfile xmlns:xsd="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">'
        "  <ProfileName>$([IO.Path]::GetFileNameWithoutExtension($File))</ProfileName>"
        "$gp$gp2"
        '  <ConfigValues>'
        '    <FieldInformation>'
        '      <CategoryName>General</CategoryName>'
        '      <FieldName>Input API</FieldName>'
        '      <FieldValue>RawInput</FieldValue>'
        '    </FieldInformation>'
        '  </ConfigValues>'
        '  <JoystickButtons>'
        $Buttons
        '  </JoystickButtons>'
        "  <GunGame>$Gun</GunGame>"
        '</GameProfile>'
    ) -join $nl
    $enc = if ($Bom) { New-Object Text.UTF8Encoding $true } else { $utf8 }
    [IO.File]::WriteAllText((Join-Path $up $File), $xml + $nl, $enc)
}
$foreign = 'Z:\Some Build\RetroBat'
New-Profile 'GunA.xml' "$foreign\roms\teknoparrot\GunA.parrot\game.exe" -GamePath2 'Q:\Old & Co\roms\namco\roms\nested.bin'
New-Profile 'GunB.xml' "$Root\roms\teknoparrot\GunB.parrot\bin\b.elf" -Bom
New-Profile 'TouchGame.xml' "$Root\roms\teknoparrot\TouchGame.parrot\t.exe"
New-Profile 'PadGame.xml' "$foreign\roms\teknoparrot\PadGame.parrot\p.exe" -Gun 'false'
New-Profile 'Missing.xml' 'Y:\Other\roms\teknoparrot\Gone.parrot\x.exe'
New-Profile 'Escape.xml' "$foreign\roms\..\..\secret.txt"
New-Profile '#Off.xml' "$foreign\roms\teknoparrot\GunA.parrot\game.exe"

$yml = @(
    '# This file is provided with RetroBat (synthetic excerpt)'
    'guna:'
    '  Test: l3 # Test'
    '  Coin1: select # Coin'
    '  P1Button1: righttrigger # Player 1 Gun Trigger'
    '  P1Button2: lefttrigger # Player 1 Reload'
    '  P1Button3: leftshoulder # Player 1 Grenade'
    '  P2Button1: righttrigger # Player 2 Gun Trigger'
    '  Analog0: rightstickleft # Player 1 Gun X'
    '  Analog2: rightstickup # Player 1 Gun Y'
    ''
    '  # Unmapped inputs:'
    '  P1RelativeUp:   # Player 1 Gun Y Up'
    ''
    'gunb:'
    "`tP1Button1: righttrigger # tab indented"
    '  P1Button2: kb_5 # keyboard key: left alone'
    ''
    'touchgame:'
    '  P1ButtonStart: start # TOUCH SCREEN INPUT'
    '  P1Button1: south # Button A'
) -join $nl
[IO.File]::WriteAllText((Join-Path $Root 'system\resources\inputmapping\teknoparrot.yml'), $yml + $nl, $utf8)
[IO.File]::WriteAllText((Join-Path $tp 'Metadata\GunA.json'), '{ "game_name": "Gun Alpha" }', $utf8)
[IO.File]::WriteAllText((Join-Path $tp 'Metadata\Stray.json'), '{ "game_name": "Stray Game" }', $utf8)

$gamelist = @(
    '<?xml version="1.0"?>'
    '<gameList>'
    '	<game id="1">'
    '		<path>./GunA.parrot</path>'
    '		<name>Gun Alpha</name>'
    '		<image>./images/GunA-image.png</image>'
    '	</game>'
    '	<game>'
    '		<path>./Stray.parrot</path>'
    '		<name>Stray</name>'
    '	</game>'
    '	<game>'
    '		<path>./Old.parrot</path>'
    '		<name>Old name</name>'
    '	</game>'
    '</gameList>'
) -join "`n"
[IO.File]::WriteAllText("$roms\gamelist.xml", $gamelist + "`n", $utf8)

$es = Join-Path $Root 'emulationstation\.emulationstation\es_settings.cfg'
$text = [IO.File]::ReadAllText($es)
$extra = @(
    '  <string name="teknoparrot.shaderset" value="sindenborder" />'
    '  <string name="teknoparrot.tp_nocrosshair" value="1" />'
    '  <string name="teknoparrot.use_guns" value="1" />'
    '  <string name="teknoparrot[&quot;GunA.parrot&quot;].bezel" value="none" />'
    '  <string name="teknoparrot[&quot;GunA.parrot&quot;].tp_inputdriver" value="rawinput" />'
) -join $nl
[IO.File]::WriteAllText($es, $text.Replace('  <string name="zzz.last"', $extra + $nl + '  <string name="zzz.last"'), $utf8)
