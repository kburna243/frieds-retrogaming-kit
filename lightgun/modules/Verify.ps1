# Verify (step 9): measure instead of guessing.
#   XInput     XInputGetState (xinput1_4.dll) per pad: which virtual Xbox pads exist, "press the trigger now"
#              with a timeout. Without any pad the status is simply NoPad.
#   Profiles   the profile automation's log (SENT lines) proves that a game start switched the layout.
#   Launcher   RetroBat's emulatorLauncher.log: what the last start really did (system, emulator, core, and
#              whether RetroBat's own gun automation assigned guns).

if (-not ('RetroCabinetKit.XInputNative' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System.Runtime.InteropServices;
namespace RetroCabinetKit
{
    public static class XInputNative
    {
        [StructLayout(LayoutKind.Sequential)]
        public struct GAMEPAD { public ushort Buttons; public byte LeftTrigger; public byte RightTrigger; public short LX, LY, RX, RY; }
        [StructLayout(LayoutKind.Sequential)]
        public struct STATE { public uint Packet; public GAMEPAD Pad; }
        [DllImport("xinput1_4.dll")]
        public static extern int XInputGetState(int index, out STATE state);
    }
}
'@
}

$script:LightgunXInputButtons = [ordered]@{
    0x1000 = 'A'; 0x2000 = 'B'; 0x4000 = 'X'; 0x8000 = 'Y'; 0x0010 = 'Start'; 0x0020 = 'Back'
    0x0100 = 'LB'; 0x0200 = 'RB'; 0x0040 = 'LS'; 0x0080 = 'RS'; 0x0001 = 'Up'; 0x0002 = 'Down'; 0x0004 = 'Left'; 0x0008 = 'Right'
}

# One pad: Pad, Connected, Buttons (names), Packet. 0 = ERROR_SUCCESS, anything else (1167) = no pad.
function Get-LightgunXInputState {
    [CmdletBinding()]
    param([ValidateRange(0, 3)] [int] $Pad)
    $s = New-Object RetroCabinetKit.XInputNative+STATE
    $rc = [RetroCabinetKit.XInputNative]::XInputGetState($Pad, [ref]$s)
    $names = @(if ($rc -eq 0) { foreach ($k in $script:LightgunXInputButtons.Keys) { if ($s.Pad.Buttons -band $k) { $script:LightgunXInputButtons[$k] } } })
    [pscustomobject]@{ Pad = $Pad; Connected = $rc -eq 0; Buttons = $names; Packet = $s.Packet }
}

# The connected pads (0-3). -Reader { param($pad) ... } replaces the real query (tests).
function Get-LightgunXInputPad {
    [CmdletBinding()]
    param([scriptblock] $Reader = { param($p) Get-LightgunXInputState -Pad $p })
    foreach ($i in 0..3) { $s = & $Reader $i; if ($s.Connected) { [pscustomobject]@{ Pad = $i; Connected = $true; Buttons = @($s.Buttons) } } }
}

# Waits until a button of -Pad goes down (from released). Status: Pressed (with the buttons), Timeout, NoPad.
function Wait-LightgunXInputPress {
    [CmdletBinding()]
    param(
        [ValidateRange(0, 3)] [int] $Pad,
        [ValidateRange(0.1, 120)] [double] $TimeoutSeconds = 15,
        [scriptblock] $Reader = { param($p) Get-LightgunXInputState -Pad $p }
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $first = & $Reader $Pad
    if (-not $first.Connected) { return [pscustomobject]@{ Pad = $Pad; Status = 'NoPad'; Buttons = @() } }
    $released = -not @($first.Buttons).Count
    do {
        $s = & $Reader $Pad
        if (-not $s.Connected) { return [pscustomobject]@{ Pad = $Pad; Status = 'NoPad'; Buttons = @() } }
        if (@($s.Buttons).Count) { if ($released) { return [pscustomobject]@{ Pad = $Pad; Status = 'Pressed'; Buttons = @($s.Buttons) } } }
        else { $released = $true }
        Start-Sleep -Milliseconds 10
    } while ((Get-Date) -lt $deadline)
    [pscustomobject]@{ Pad = $Pad; Status = 'Timeout'; Buttons = @() }
}

# Events of the profile automation's log: Time, Kind (START, SENT, END, ERROR), Layout, Detail.
function Get-LightgunProfileEvent {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $LogPath)
    if (-not (Test-Path -LiteralPath $LogPath -PathType Leaf)) { return }
    foreach ($l in [IO.File]::ReadAllLines($LogPath)) {
        if ($l -notmatch '^(\d{4}-\d\d-\d\d \d\d:\d\d:\d\d) (START|SENT|END|ERROR)\b\s*(.*)$') { continue }
        $time = [datetime]::ParseExact($Matches[1], 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture)
        $kind = $Matches[2]
        $rest = $Matches[3]
        $layout = if ($rest -match "layout='([^']*)'") { $Matches[1] } else { '' }
        [pscustomobject]@{ Time = $time; Kind = $kind; Layout = $layout; Detail = $rest }
    }
}

# $true when, after -Since, a layout other than the menu layout was sent: a game start switched the profile.
function Test-LightgunProfileSwitch {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $LogPath, [Parameter(Mandatory)] [string] $MenuTitle, [datetime] $Since = [datetime]::MinValue)
    [bool](@(Get-LightgunProfileEvent -LogPath $LogPath | Where-Object { $_.Kind -eq 'SENT' -and $_.Layout -ne $MenuTitle -and $_.Time -ge $Since }).Count)
}

# The last game start in emulatorLauncher.log: Time, System, Emulator, Core, Rom, Lightgun (the -lightgun flag),
# GunAutomation (RetroBat assigned guns: "[LightGun] Assigned ..."), Running (command line). $null = no start.
# -System: filters for the most recent start of this specific system (e.g. teknoparrot, naomi, demul).
function Get-LightgunLauncherReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [string] $System
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    $stream = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite') # RetroBat may still have it open
    try { $lines = (New-Object IO.StreamReader ($stream, [Text.Encoding]::UTF8, $true)).ReadToEnd() -split '\r?\n' } finally { $stream.Dispose() }

    # Find all startup indices
    $starts = New-Object Collections.Generic.List[int]
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '\[Startup\].*\s-gameinfo\s') { $starts.Add($i) }
    }
    if ($starts.Count -eq 0) { return $null }

    for ($k = $starts.Count - 1; $k -ge 0; $k--) {
        $startIdx = $starts[$k]
        $endIdx = if ($k -eq $starts.Count - 1) { $lines.Count - 1 } else { $starts[$k + 1] - 1 }
        $head = $lines[$startIdx]
        $block = @($lines[$startIdx..$endIdx])

        $mSystem = [regex]::Match($head, '\s-system\s+(?:"([^"]*)"|(\S+))')
        $sysVal = if ($mSystem.Groups[1].Success) { $mSystem.Groups[1].Value } elseif ($mSystem.Groups[2].Success) { $mSystem.Groups[2].Value } else { '' }

        if ($System -and $sysVal.ToLowerInvariant() -ne $System.ToLowerInvariant()) { continue }

        function Get-Arg([string] $Name) {
            $m = [regex]::Match($head, "\s-$Name\s+(?:`"([^`"]*)`"|(\S+))")
            if (-not $m.Success) { '' } elseif ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
        }
        $running = @($block | Where-Object { $_ -match '\[Running\]\s+(.*)$' } | ForEach-Object { $Matches[1] }) | Select-Object -First 1

        return [pscustomobject]@{
            Time          = if ($head -match '^(\S+ \S+)') { $Matches[1] } else { '' }
            System        = $sysVal
            Emulator      = Get-Arg 'emulator'
            Core          = Get-Arg 'core'
            Rom           = Get-Arg 'rom'
            Lightgun      = $head -match '\s-lightgun(\s|$)'
            GunAutomation = [bool](@($block | Where-Object { $_ -match '\[LightGun( core)?\]\s+Assigned' }).Count)
            Running       = [string]$running
        }
    }
    return $null
}

# Verifies that a launch report used the expected system, emulator, and that use_guns=0 took effect (no gun automation).
function Test-LightgunLauncherLaunch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Report,
        [Parameter(Mandatory)] [string] $ExpectedSystem,
        [Parameter(Mandatory)] [string] $ExpectedEmulator
    )
    $systemMatch = $Report.System -and ($Report.System.ToLowerInvariant() -eq $ExpectedSystem.ToLowerInvariant())
    $emuMatch = $Report.Emulator -and ($Report.Emulator.ToLowerInvariant() -eq $ExpectedEmulator.ToLowerInvariant())
    $noGunAuto = -not $Report.GunAutomation
    [pscustomobject]@{
        Valid         = $systemMatch -and $emuMatch -and $noGunAuto
        SystemMatch   = $systemMatch
        EmulatorMatch = $emuMatch
        NoGunAuto     = $noGunAuto
        Report        = $Report
    }
}
