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
.PARAMETER Retarget
    Adds the second half of the copied-installation story: settings values that point at the other machine AND
    the counterparts they should become, next to the installation. One counterpart is deliberately left out, so
    a test can show that a target which does not exist here is never written. Off by default: the read tests
    measure the installation exactly as it is.
.OUTPUTS
    The root folder path.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $Root,
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z]$')] [string] $ForeignDrive,
    [switch] $Retarget
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

if ($Retarget) {
    # The other machine's content, as it sits on THIS one: the same names under a folder next to the
    # installation. A map pair turns the dead values above into these paths. One target is deliberately
    # missing, so the case "no counterpart here" is measured and not assumed.
    $target = Join-Path (Split-Path -Parent $Root) 'PinballYRetargetTarget'
    foreach ($sub in @('Games\Pinball Arcade', 'Scripts', 'vpinmame\nvram', 'futurepinball\fpRAM')) {
        $null = New-Item -ItemType Directory -Path (Join-Path $target $sub) -Force
    }
    Write-Utf8Bom -Path (Join-Path $target 'Games\Pinball Arcade\TPAFreeCamMod.exe') -Text 'the counterpart of the program on the other machine'
    Write-Utf8Bom -Path (Join-Path $target 'Scripts\Run_Arcooda.exe') -Text 'the counterpart of the script on the other machine'

    # A value that is ALIVE on this machine and sits under a prefix the map also covers: a correct path must
    # never be touched, even when a pair would match it. That is the guard against a rewrite that "cleans up".
    $lines += "System4.MediaDir = $(Join-Path $Root 'Media\Sub')"
    Write-Utf8Bom -Path (Join-Path $Root 'Settings.txt') -Text (($lines -join "`r`n") + "`r`n")
    # The same dead path a second time in the companion: two lines, one value, both must land in the plan.
    $ini += 'NVRAMExtra=D:\Per\VisualPinball\VPinMame\nvram\'
    [IO.File]::WriteAllText((Join-Path $Root 'PINemHi\pinemhi.ini'), ($ini -join "`r`n"), (New-Object Text.UTF8Encoding $false))

    # Never rewritten, whatever the map says: the factory file PinballY copies back on a reset, and one of
    # the rolling copies the program keeps itself. Both hold the same dead path as the settings.
    Write-Utf8Bom -Path (Join-Path $Root 'DefaultSettings.txt') -Text "System5.Exe = $foreignExe`r`n"
    Write-Utf8Bom -Path (Join-Path $Root 'Settings backup 2020-07-08.txt') -Text "System5.Exe = $foreignExe`r`n"
}

$Root
