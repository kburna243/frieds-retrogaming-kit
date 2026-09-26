<#
.SYNOPSIS
    Builds a synthetic PinballY installation for the tests.
.DESCRIPTION
    The layout and the file contents are the ones a real PinballY writes: Settings.txt with UTF-8 BOM and CRLF,
    Databases\<system>\<system>.xml as a HyperList export, Media\<system>\, no PinballY.ini, no launcher .cmd.
    Every path a test asserts is built from the fixture folder itself or from a drive letter the caller hands
    in, so no detail of the test machine decides an outcome: the "present" case is the fixture's own exe, the
    "broken on this machine" case is a nonsense folder on the fixture's drive, and the "from another machine"
    case is a letter that is not mounted. The exe is a stand-in without version information.
.PARAMETER Root
    Folder to create.
.PARAMETER ForeignDrive
    A drive letter that is not mounted on this machine (see Get-PinballYUnmountedDrive in the tests).
.OUTPUTS
    The root folder path.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Root,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z]$')] [string] $ForeignDrive
)
$ErrorActionPreference = 'Stop'

function Write-Utf8Bom([string] $Path, [string] $Text) {
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding $true))
}

$null = New-Item -ItemType Directory -Path $Root -Force
foreach ($sub in @('Media\Sub', 'Databases\vp', 'Farsight', 'PINemHi')) {
    $null = New-Item -ItemType Directory -Path (Join-Path $Root $sub) -Force
}
# A stand-in for the program: present, but with no version data of its own.
Write-Utf8Bom -Path (Join-Path $Root 'PinballY.exe') -Text 'not a real executable, only a name in the right place'

$drive = $Root.Substring(0, 1)
$present = Join-Path $Root 'PinballY.exe'
$broken = '{0}:\not-mounted-for-pinbally\Game.exe' -f $drive
$foreignExe = "${ForeignDrive}:\Games\Pinball Arcade\TPAFreeCamMod.exe"
$foreignRun = "${ForeignDrive}:\Scripts\Run_Arcooda.exe"

# The settings: two paths from another machine, one broken here, one that exists, the tokens PinballY
# expands itself, media and database folders relative to their own anchors, an empty value - and the file's
# own path examples in the comments, which a text replace over the whole file would have rewritten.
$lines = @(
    '# PinballY settings (synthetic test fixture)'
    '#    "c:\my path\my program"'
    '# X:\PinballY\Scripts\my launch.cmd'
    '#'
    'MediaPath = Media'
    'TableDatabasePath = Databases'
    'System1.Enabled = true'
    'System1.Class = VPinball'
    'System1.MediaDir = Sub'
    'System1.DatabaseDir = vp'
    'System1.TablePath = Tables'
    'System2.Enabled = 1'
    'System2.Exe = [STEAM]'
    'System2.Process = Pinball FX3.exe'
    'System2.TablePath = steamapps\common\Pinball FX3\data\steam'
    'System3.TablePath = [PinballY]\Farsight'
    "System4.Exe = $present"
    "System4.RunAfter = $broken"
    "System5.Exe = $foreignExe"
    "System5.RunBeforePre = $foreignRun"
    'System6.Enabled = 0'
    'System6.Class = Future Pinball'
    'System7.MediaDir = NotInMediaFolder'
    'System8.Exe ='
)
# CRLF, because that is what the program writes.
Write-Utf8Bom -Path (Join-Path $Root 'Settings.txt') -Text (($lines -join "`r`n") + "`r`n")

# A HyperList export: metadata only, no path in it. That is what makes a move cheap here.
$db = @(
    '<?xml version="1.0" encoding="utf-8"?>'
    '<menu>'
    '  <header><listname>Test System</listname><platform>Pinball</platform></header>'
    '  <game name="Alien_Isolation" index="" image="">'
    '    <description>Alien Isolation</description><manufacturer>Test</manufacturer><year>1990</year><rating>0</rating>'
    '  </game>'
    '  <game name="Black_Knight" index="" image="">'
    '    <description>Black Knight</description><manufacturer>Test</manufacturer><year>1991</year><rating>0</rating>'
    '  </game>'
    '  <game name="Cyclone" index="" image="">'
    '    <description>Cyclone</description><manufacturer>Test</manufacturer><year>1992</year><rating>0</rating>'
    '  </game>'
    '</menu>'
)
Write-Utf8Bom -Path (Join-Path $Root 'Databases\vp\vp.xml') -Text ($db -join "`r`n")
# One file the program could not read either: the report has to say so instead of counting zero games.
Write-Utf8Bom -Path (Join-Path $Root 'Databases\vp\broken.xml') -Text '<menu><game name="Unclosed"'

# A third-party overlay inside the install folder, with two paths of its own.
$ini = @(
    '; PINemHi configuration'
    'VP=D:\Per\VisualPinball\VPinMame\nvram\'
    'FP=D:\Games\Future Pinball\fpRAM\'
)
[IO.File]::WriteAllText((Join-Path $Root 'PINemHi\pinemhi.ini'), ($ini -join "`r`n"), (New-Object Text.UTF8Encoding $false))

$Root
