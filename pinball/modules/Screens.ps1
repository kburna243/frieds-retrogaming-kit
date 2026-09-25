# Screens (step 8): monitors, the official layout rules, one window rectangle per consumer, and the writers.
#
# Rules (nailbuster install_guide): 100 % scaling on every monitor, no negative coordinates, playfield = main
# display, every other monitor right of or below it. Windows keeps the playfield in landscape.
#
# Model: role (Playfield, Backglass, DMD, FullDMD, Topper) -> area (a monitor); consumer (one program window,
# e.g. PuP [INFO1] or the VPinMAME virtual DMD) -> rectangle = a measured rectangle or the area of its role.
# Default mode "Keep": existing valid values stay; only missing values or values outside the virtual desktop
# are proposed. "Replace" proposes everything. Popper rows and PuP sections are matched by NAME only.
#
# Writers: read -> propose -> diff -> write with a backup next to the file (registry: .reg export) and a way
# back (Restore-PinballScreenBackup). A target without changes is never written, so "Keep" on valid files
# leaves them byte-identical. VPX FullScreen is never touched: the Popper launch script controls it (FSMODE).

$script:PinballScreenRoles = @('Playfield', 'Backglass', 'DMD', 'FullDMD', 'Topper')

# Consumer -> role.
$script:PinballScreenConsumers = [ordered]@{
    'Popper.Table' = 'Playfield'; 'Popper.BackGlass' = 'Backglass'; 'Popper.DMD' = 'DMD'; 'Popper.Topper' = 'Topper'; 'Popper.Menu' = 'FullDMD'
    'PuP.INFO3' = 'Playfield'; 'PuP.INFO2' = 'Backglass'; 'PuP.INFO1' = 'DMD'; 'PuP.INFO' = 'Topper'; 'PuP.INFO5' = 'FullDMD'
    'VPinMAME.DMD' = 'DMD'; 'FP.DMD' = 'DMD'
    'B2S.Playfield' = 'Playfield'; 'B2S.Backglass' = 'Backglass'; 'B2S.DMD' = 'DMD'
    'VPX.Playfield' = 'Playfield'; 'FP.Playfield' = 'Playfield'; 'FP.Backbox' = 'Backglass'
    'FX3.Backglass' = 'Backglass'; 'FX3.DMD' = 'DMD'; 'TPA.Backglass' = 'Backglass'; 'TPA.DMD' = 'DMD'
}

# These programs only know "which monitor + size": their rectangle always starts at a monitor origin.
$script:PinballMonitorAnchored = @('B2S.Playfield', 'VPX.Playfield', 'FP.Playfield', 'FP.Backbox')

# Popper Screens.ScreenName -> consumer (Menu = FullDMD in older Popper versions).
$script:PinballPopperScreens = [ordered]@{ Table = 'Popper.Table'; BackGlass = 'Popper.BackGlass'; DMD = 'Popper.DMD'; Topper = 'Popper.Topper'; Menu = 'Popper.Menu' }

$script:PinballXywhKeys = @{
    Pup = @('ScreenXPos', 'ScreenYPos', 'ScreenWidth', 'ScreenHeight')
    Dmd = @('left', 'top', 'width', 'height')
}

# --- rectangles and monitors --------------------------------------------------------------------------------

function New-PinballRect {
    [CmdletBinding()]
    param([int] $X, [int] $Y, [int] $Width, [int] $Height)
    [pscustomobject]@{ X = $X; Y = $Y; Width = $Width; Height = $Height }
}

function Format-PinballRect {
    [CmdletBinding()]
    param([AllowNull()] $Rect)
    if ($null -eq $Rect) { return '-' }
    '{0},{1} {2}x{3}' -f $Rect.X, $Rect.Y, $Rect.Width, $Rect.Height
}

function ConvertTo-PinballInt([AllowNull()] $Value) {
    $n = 0
    if ($null -ne $Value -and [int]::TryParse(([string]$Value).Trim(), [ref]$n)) { return $n }
    $null
}

function New-RectFromValues($X, $Y, $Width, $Height) {
    $v = @($X, $Y, $Width, $Height | ForEach-Object { ConvertTo-PinballInt $_ })
    if (@($v | Where-Object { $null -eq $_ }).Count) { return $null }
    New-PinballRect $v[0] $v[1] $v[2] $v[3]
}

function Get-PinballMonitor {
    [CmdletBinding()]
    param([object[]] $Monitors)
    if ($Monitors) { return $Monitors }
    Get-KitMonitor
}

function Get-PinballDesktop {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object[]] $Monitors)
    $l = [int]::MaxValue; $t = [int]::MaxValue; $r = [int]::MinValue; $b = [int]::MinValue
    foreach ($m in $Monitors) {
        $l = [math]::Min($l, $m.X); $t = [math]::Min($t, $m.Y)
        $r = [math]::Max($r, $m.X + $m.Width); $b = [math]::Max($b, $m.Y + $m.Height)
    }
    New-PinballRect $l $t ($r - $l) ($b - $t)
}

# Plausibility: the whole rectangle lies inside the virtual desktop (an installer once wrote top = 2000).
function Test-PinballRectInDesktop {
    [CmdletBinding()]
    param([AllowNull()] $Rect, [Parameter(Mandatory)] [object[]] $Monitors)
    if ($null -eq $Rect -or $Rect.Width -le 0 -or $Rect.Height -le 0) { return $false }
    $d = Get-PinballDesktop -Monitors $Monitors
    $Rect.X -ge $d.X -and $Rect.Y -ge $d.Y -and ($Rect.X + $Rect.Width) -le ($d.X + $d.Width) -and ($Rect.Y + $Rect.Height) -le ($d.Y + $d.Height)
}

function Find-MonitorAt([object[]] $Monitors, [int] $X, [int] $Y) {
    $Monitors | Where-Object { $X -ge $_.X -and $X -lt $_.X + $_.Width -and $Y -ge $_.Y -and $Y -lt $_.Y + $_.Height } | Select-Object -First 1
}

function Find-MonitorByDevice([object[]] $Monitors, [string] $Device) {
    if (-not $Device) { return $null }
    $Monitors | Where-Object { $_.DeviceName -eq $Device } | Select-Object -First 1
}

function Find-MonitorByNumber([object[]] $Monitors, $Number) {
    $n = ConvertTo-PinballInt $Number
    if ($null -eq $n) { return $null }
    Find-MonitorByDevice $Monitors ('\\.\DISPLAY{0}' -f $n)
}

function Get-DisplayNumber([string] $Device) {
    if ($Device -match 'DISPLAY(\d+)$') { return [int]$Matches[1] }
    $null
}

function Get-RectCenterMonitor([object[]] $Monitors, $Rect) {
    Find-MonitorAt $Monitors ([int]($Rect.X + $Rect.Width / 2)) ([int]($Rect.Y + $Rect.Height / 2))
}

# --- rules, lock, layout ------------------------------------------------------------------------------------

# Session 0 (service) or an unattended run (answer file) has nobody in front of the screens: step 8 is locked.
function Get-PinballScreenLock {
    [CmdletBinding()]
    param([int] $SessionId = [Diagnostics.Process]::GetCurrentProcess().SessionId, [string] $AnswerFile)
    if ($SessionId -eq 0) { return Get-KitText 'Pinball.Screens.LockedSession0' }
    if ($AnswerFile) { return Get-KitText 'Pinball.Screens.LockedAnswerFile' -f $AnswerFile }
    $null
}

function Get-PinballDefaultRole {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object[]] $Monitors)
    $pf = @($Monitors | Where-Object { $_.Primary }) + @($Monitors) | Select-Object -First 1
    $roles = @{ Playfield = $pf.DeviceName }
    $others = @($Monitors | Where-Object { $_.DeviceName -ne $pf.DeviceName } | Sort-Object X, Y)
    if ($others.Count -ge 1) { $roles.Backglass = $others[0].DeviceName }
    if ($others.Count -ge 2) { $roles.DMD = $others[1].DeviceName; $roles.FullDMD = $others[1].DeviceName }
    if ($others.Count -ge 3) { $roles.Topper = $others[2].DeviceName }
    $roles
}

# Returns one object per violation (Code, Device, Message). Empty = the layout follows the official rules.
function Test-PinballMonitorLayout {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object[]] $Monitors, [hashtable] $Roles = @{})
    $violation = { param($code, $device, $message) [pscustomobject]@{ Code = $code; Device = $device; Message = $message } }
    foreach ($m in $Monitors) {
        if ($m.Scale -ne 100) { & $violation 'Scaling' $m.DeviceName (Get-KitText 'Pinball.Screens.Rule.Scaling' -f $m.DeviceName, $m.Scale) }
        if ($m.X -lt 0 -or $m.Y -lt 0) { & $violation 'Negative' $m.DeviceName (Get-KitText 'Pinball.Screens.Rule.Negative' -f $m.DeviceName, $m.X, $m.Y) }
    }
    $pf = if ($Roles['Playfield']) { Find-MonitorByDevice $Monitors $Roles['Playfield'] } else { @($Monitors | Where-Object { $_.Primary })[0] }
    if (-not $pf) { & $violation 'UnknownMonitor' $Roles['Playfield'] (Get-KitText 'Pinball.Screens.Rule.UnknownMonitor' -f $Roles['Playfield']); return }
    if (-not $pf.Primary) { & $violation 'PlayfieldNotPrimary' $pf.DeviceName (Get-KitText 'Pinball.Screens.Rule.NotPrimary' -f $pf.DeviceName) }
    foreach ($m in $Monitors | Where-Object { $_.DeviceName -ne $pf.DeviceName }) {
        $right = $m.X -ge $pf.X + $pf.Width
        $below = $m.Y -ge $pf.Y + $pf.Height
        if (-not ($right -or $below)) { & $violation 'LeftOrAbove' $m.DeviceName (Get-KitText 'Pinball.Screens.Rule.LeftOrAbove' -f $m.DeviceName) }
    }
}

function ConvertTo-PinballHashtable {
    [CmdletBinding()]
    param([AllowNull()] $InputObject)
    $h = @{}
    if ($null -eq $InputObject) { return $h }
    if ($InputObject -is [Collections.IDictionary]) { foreach ($k in $InputObject.Keys) { $h[[string]$k] = $InputObject[$k] }; return $h }
    foreach ($p in $InputObject.PSObject.Properties) { $h[$p.Name] = $p.Value }
    $h
}

# Roles: role -> monitor device name (default: Get-PinballDefaultRole). Windows: consumer -> measured rectangle.
function New-PinballScreenLayout {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object[]] $Monitors, $Roles, $Windows)
    $r = ConvertTo-PinballHashtable $Roles
    if (-not $r.Count) { $r = Get-PinballDefaultRole -Monitors $Monitors }
    $w = @{}
    $measured = ConvertTo-PinballHashtable $Windows
    foreach ($k in $measured.Keys) {
        $v = $measured[$k]
        if ($v) { $w[$k] = New-PinballRect $v.X $v.Y $v.Width $v.Height }
    }
    [pscustomobject]@{ Monitors = @($Monitors); Roles = $r; Windows = $w }
}

function Get-PinballScreenConsumer {
    [CmdletBinding()]
    param()
    @($script:PinballScreenConsumers.Keys)
}

function Get-PinballConsumerRole {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Consumer)
    $script:PinballScreenConsumers[$Consumer]
}

function Get-PinballRoleArea {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Layout, [Parameter(Mandatory)] [string] $Role)
    $m = Find-MonitorByDevice $Layout.Monitors $Layout.Roles[$Role]
    if ($m) { New-PinballRect $m.X $m.Y $m.Width $m.Height }
}

# Proposal for one consumer: its measured rectangle, else the area of its role ($null if the role has no monitor).
function Get-PinballConsumerRect {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Layout, [Parameter(Mandatory)] [string] $Consumer)
    $rect = if ($Layout.Windows.ContainsKey($Consumer)) { $Layout.Windows[$Consumer] }
            else { Get-PinballRoleArea -Layout $Layout -Role $script:PinballScreenConsumers[$Consumer] }
    if ($rect -and $script:PinballMonitorAnchored -contains $Consumer) {
        $m = Get-RectCenterMonitor $Layout.Monitors $rect
        if ($m) { $rect = New-PinballRect $m.X $m.Y $rect.Width $rect.Height }
    }
    $rect
}

# --- INI and text helpers -----------------------------------------------------------------------------------

function Read-PinballTextFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $full = Resolve-PinballFullPath $Path
    $info = Get-KitFileEncoding -Path $full
    $bytes = [IO.File]::ReadAllBytes($full)
    [Text.Encoding]::GetEncoding($info.CodePage).GetString($bytes, $info.BomLength, $bytes.Length - $info.BomLength)
}

function Get-PinballIniValue {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Text, [Parameter(Mandatory)] [string] $Section, [Parameter(Mandatory)] [string] $Key)
    $in = $false
    $pattern = '^\s*' + [regex]::Escape($Key) + '\s*=(.*)$'
    foreach ($line in $Text -split '\r?\n') {
        if ($line -match '^\s*\[(.+?)\]\s*$') { $in = $Matches[1].Trim() -eq $Section; continue }
        if ($in -and $line -match $pattern) { return $Matches[1].Trim() }
    }
    $null
}

# Sets keys in one section, keeping comments, order, spacing and line endings. An existing line keeps its
# own "key = " prefix; new keys are inserted after the last entry of the section as "<key><Separator><value>";
# a missing section is appended. Returns @{ Text; Count } (Count = lines that really changed).
function Set-PinballIniValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text,
        [Parameter(Mandatory)] [string] $Section,
        [Parameter(Mandatory)] [Collections.IDictionary] $Values,
        [string] $Separator = '='
    )
    $nl = if ($Text -match "`r`n" -or -not $Text) { "`r`n" } else { "`n" }
    $lines = New-Object Collections.Generic.List[string]
    foreach ($l in $Text -split '\r?\n') { $lines.Add($l) }
    $endsWithNewline = $Text.EndsWith("`n")
    if ($endsWithNewline -or -not $Text) { $lines.RemoveAt($lines.Count - 1) }

    $pending = [ordered]@{}
    foreach ($k in $Values.Keys) { $pending[[string]$k] = [string]$Values[$k] }
    $count = 0
    $start = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*\[(.+?)\]\s*$' -and $Matches[1].Trim() -eq $Section) { $start = $i; break }
    }
    if ($start -ge 0) {
        $last = $start
        $i = $start + 1
        while ($i -lt $lines.Count -and $lines[$i] -notmatch '^\s*\[.+\]\s*$') {
            $line = $lines[$i]
            if ($line.Trim() -and $line -notmatch '^\s*[;#]') { $last = $i }
            foreach ($k in @($pending.Keys)) {
                if ($line -match ('^(\s*' + [regex]::Escape($k) + '\s*=\s*)(.*?)(\s*)$')) {
                    $prefix = $Matches[1]
                    # "Width =" (empty value, trailing blank lost) gets the blank of the file's style back.
                    if (-not $Matches[2] -and $Separator.EndsWith(' ') -and $prefix -notmatch '\s$') { $prefix += ' ' }
                    $new = $prefix + $pending[$k] + $Matches[3]
                    if ($new -ne $line) { $lines[$i] = $new; $count++ }
                    $pending.Remove($k)
                    break
                }
            }
            $i++
        }
        $at = $last + 1
        foreach ($k in $pending.Keys) { $lines.Insert($at, "$k$Separator$($pending[$k])"); $at++; $count++ }
    } elseif ($pending.Count) {
        if ($lines.Count -and $lines[$lines.Count - 1].Trim()) { $lines.Add('') }
        $lines.Add("[$Section]")
        foreach ($k in $pending.Keys) { $lines.Add("$k$Separator$($pending[$k])"); $count++ }
    }
    $out = $lines -join $nl
    if ($endsWithNewline -or -not $Text) { $out += $nl }
    @{ Text = $out; Count = $count }
}

# --- targets ------------------------------------------------------------------------------------------------

# Every place the kit writes screen values. -Paths overrides single locations (tests use TEMP files and test keys):
# Popper, PinUpPlayer, VpmDmdDevice, FpDmdDevice, ScreenRes, VpxIni, VpxRegistry, FpRegistry.
function Get-PinballScreenTarget {
    [CmdletBinding()]
    param([string] $Root, [hashtable] $Paths = @{})
    $p = @{
        VpxIni      = Join-Path $env:APPDATA 'VPinballX\VPinballX.ini'
        VpxRegistry = 'HKCU:\Software\Visual Pinball\VP10\Player'
        FpRegistry  = 'HKCU:\Software\Future Pinball\GamePlayer'
    }
    if ($Root) {
        $v = Join-PinballPath (ConvertTo-PinballRoot $Root) 'vPinball'
        $p.Popper       = "$v\PinUPSystem\PUPDatabase.db"
        $p.PinUpPlayer  = "$v\PinUPSystem\PinUpPlayer.ini"
        $p.VpmDmdDevice = "$v\VisualPinball\VPinMAME\DmdDevice.ini"
        $p.FpDmdDevice  = "$v\FuturePinball\DmdDevice.ini"
        $p.ScreenRes    = "$v\VisualPinball\Tables\ScreenRes.txt"
    }
    foreach ($k in $Paths.Keys) { $p[$k] = $Paths[$k] }

    $target = { param($name, $kind, $consumers, $canAdd, $extra)
        if (-not $p[$name]) { return }
        $t = [pscustomobject]@{ Name = $name; Kind = $kind; Path = $p[$name]; Consumers = @($consumers); CanAdd = $canAdd; Map = @{}; Separator = '=' }
        if ($extra) { foreach ($k in $extra.Keys) { $t | Add-Member -NotePropertyName $k -NotePropertyValue $extra[$k] -Force } }
        $t
    }
    & $target 'Popper' 'Database' @($script:PinballPopperScreens.Values) $false $null
    & $target 'PinUpPlayer' 'Ini' @('PuP.INFO', 'PuP.INFO1', 'PuP.INFO2', 'PuP.INFO3', 'PuP.INFO5') $true @{
        Map = @{ 'PuP.INFO' = 'INFO'; 'PuP.INFO1' = 'INFO1'; 'PuP.INFO2' = 'INFO2'; 'PuP.INFO3' = 'INFO3'; 'PuP.INFO5' = 'INFO5' }
        IniKeys = $script:PinballXywhKeys.Pup
    }
    & $target 'VpmDmdDevice' 'Ini' @('VPinMAME.DMD') $true @{ Map = @{ 'VPinMAME.DMD' = 'virtualdmd' }; IniKeys = $script:PinballXywhKeys.Dmd; Separator = ' = ' }
    & $target 'FpDmdDevice' 'Ini' @('FP.DMD') $true @{ Map = @{ 'FP.DMD' = 'virtualdmd' }; IniKeys = $script:PinballXywhKeys.Dmd; Separator = ' = ' }
    & $target 'ScreenRes' 'ScreenRes' @('B2S.Playfield', 'B2S.Backglass', 'B2S.DMD') $true $null
    & $target 'VpxIni' 'VpxIni' @('VPX.Playfield') $true @{ Separator = ' = ' }
    & $target 'VpxRegistry' 'VpxRegistry' @('VPX.Playfield') $true $null
    & $target 'FpRegistry' 'FpRegistry' @('FP.Playfield', 'FP.Backbox') $true $null
}

function Test-ScreenTargetExists($Target) {
    if ($Target.Kind -like '*Registry') { return (Test-Path -LiteralPath $Target.Path) }
    Test-Path -LiteralPath $Target.Path -PathType Leaf
}

# B2S display token: "2" = \\.\DISPLAY2, "@1920" = monitor at X = 1920, "=2" = second monitor from the left.
function Resolve-B2SDisplay([object[]] $Monitors, [string] $Token) {
    $t = $Token.Trim()
    if ($t -match '^@(-?\d+)$') { return $Monitors | Where-Object { $_.X -eq [int]$Matches[1] } | Select-Object -First 1 }
    if ($t -match '^=(\d+)$') { return @($Monitors | Sort-Object X, Y)[[int]$Matches[1] - 1] }
    Find-MonitorByNumber $Monitors $t
}

function Get-ScreenResLines([string] $Text) {
    $lines = @($Text -split '\r?\n')
    if ($Text.EndsWith("`n")) { $lines = @($lines | Select-Object -First ($lines.Count - 1)) }
    , $lines
}

# Current rectangles of a target: hashtable consumer -> rectangle ($null = value missing or unusable).
# A consumer key that is absent means the entry itself does not exist (e.g. no Popper row with that name).
function Read-PinballScreenTarget {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Target, [Parameter(Mandatory)] [object[]] $Monitors)
    $r = @{}
    switch ($Target.Kind) {
        'Database' {
            $c = Open-KitSqlite -Path $Target.Path -ReadOnly
            try { $rows = @(Invoke-KitSqlQuery -Connection $c -Sql 'SELECT ScreenName, POSx, POSy, ScreenWidth, ScreenHeight FROM Screens ORDER BY ScreenID') }
            finally { Close-KitSqlite $c }
            foreach ($row in $rows) {
                $consumer = $script:PinballPopperScreens[[string]$row.ScreenName]
                if ($consumer -and -not $r.ContainsKey($consumer)) { $r[$consumer] = New-RectFromValues $row.POSx $row.POSy $row.ScreenWidth $row.ScreenHeight }
            }
        }
        'Ini' {
            $text = Read-PinballTextFile $Target.Path
            foreach ($consumer in $Target.Consumers) {
                $v = @($Target.IniKeys | ForEach-Object { Get-PinballIniValue -Text $text -Section $Target.Map[$consumer] -Key $_ })
                $r[$consumer] = New-RectFromValues $v[0] $v[1] $v[2] $v[3]
            }
        }
        'ScreenRes' {
            $l = Get-ScreenResLines (Read-PinballTextFile $Target.Path)
            foreach ($consumer in $Target.Consumers) { $r[$consumer] = $null }
            if ($l.Count -lt 11) { break }
            $pf = @($Monitors | Where-Object { $_.Primary })[0]
            if ($pf) { $r['B2S.Playfield'] = New-RectFromValues $pf.X $pf.Y $l[0] $l[1] }
            $bg = Resolve-B2SDisplay $Monitors $l[4]
            if ($bg) {
                $r['B2S.Backglass'] = New-RectFromValues ($bg.X + (ConvertTo-PinballInt $l[5])) ($bg.Y + (ConvertTo-PinballInt $l[6])) $l[2] $l[3]
                $r['B2S.DMD'] = New-RectFromValues ($bg.X + (ConvertTo-PinballInt $l[9])) ($bg.Y + (ConvertTo-PinballInt $l[10])) $l[7] $l[8]
            }
        }
        'VpxIni' {
            # ponytail: VPX "Display" is taken as \\.\DISPLAY<n+1>; if a machine numbers adapters differently,
            # "Keep" still leaves valid values alone and the diff shows the proposal before anything is written.
            $text = Read-PinballTextFile $Target.Path
            $display = ConvertTo-PinballInt (Get-PinballIniValue -Text $text -Section 'Player' -Key 'Display')
            $m = if ($null -ne $display) { Find-MonitorByNumber $Monitors ($display + 1) }
            $r['VPX.Playfield'] = if ($m) { New-RectFromValues $m.X $m.Y (Get-PinballIniValue -Text $text -Section 'Player' -Key 'Width') (Get-PinballIniValue -Text $text -Section 'Player' -Key 'Height') }
        }
        'VpxRegistry' {
            $display = ConvertTo-PinballInt (Get-KitRegistryValue -Path $Target.Path -Name 'Display')
            $m = if ($null -ne $display) { Find-MonitorByNumber $Monitors ($display + 1) }
            $r['VPX.Playfield'] = if ($m) { New-RectFromValues $m.X $m.Y (Get-KitRegistryValue -Path $Target.Path -Name 'Width') (Get-KitRegistryValue -Path $Target.Path -Name 'Height') }
        }
        'FpRegistry' {
            $pf = Find-MonitorByDevice $Monitors ([string](Get-KitRegistryValue -Path $Target.Path -Name 'PlayfieldMonitorID'))
            $bb = Find-MonitorByDevice $Monitors ([string](Get-KitRegistryValue -Path $Target.Path -Name 'BackboxMonitorID'))
            $r['FP.Playfield'] = if ($pf) { New-RectFromValues $pf.X $pf.Y (Get-KitRegistryValue -Path $Target.Path -Name 'Width') (Get-KitRegistryValue -Path $Target.Path -Name 'Height') }
            $r['FP.Backbox'] = if ($bb) { New-RectFromValues $bb.X $bb.Y (Get-KitRegistryValue -Path $Target.Path -Name 'SecondMonitorWidth') (Get-KitRegistryValue -Path $Target.Path -Name 'SecondMonitorHeight') }
        }
    }
    $r
}

# --- plan (diff), write, restore ----------------------------------------------------------------------------

function Get-PinballScreenPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Layout,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Targets,
        [ValidateSet('Keep', 'Replace')] [string] $Mode = 'Keep'
    )
    foreach ($t in $Targets) {
        $entry = [pscustomobject]@{ Name = $t.Name; Path = $t.Path; Target = $t; Exists = $false; Final = @{}; Changes = @(); Unresolved = @() }
        if (-not (Test-ScreenTargetExists $t)) { $entry; continue }
        $entry.Exists = $true
        $current = Read-PinballScreenTarget -Target $t -Monitors $Layout.Monitors
        foreach ($c in $t.Consumers) {
            if (-not $current.ContainsKey($c)) { $entry.Unresolved += $c; continue } # e.g. no Popper row: never inserted
            $cur = $current[$c]
            $valid = Test-PinballRectInDesktop -Rect $cur -Monitors $Layout.Monitors
            $measured = $Layout.Windows.ContainsKey($c)
            $proposal = Get-PinballConsumerRect -Layout $Layout -Consumer $c
            $final = if ($valid -and $Mode -eq 'Keep' -and -not $measured) { $cur } elseif ($proposal) { $proposal } else { $cur }
            if (-not (Test-PinballRectInDesktop -Rect $final -Monitors $Layout.Monitors)) { $entry.Unresolved += $c }
            $entry.Final[$c] = $final
            if ((Format-PinballRect $cur) -ne (Format-PinballRect $final)) {
                $reason = if ($null -eq $cur) { 'Missing' } elseif (-not $valid) { 'Outside' } elseif ($measured) { 'Measured' } else { 'Replace' }
                $entry.Changes += [pscustomobject]@{ Target = $t.Name; Consumer = $c; Old = $cur; New = $final; Reason = $reason }
            }
        }
        $entry
    }
}

function Format-PinballScreenPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Plan)
    foreach ($p in $Plan) {
        if (-not $p.Exists) { Get-KitText 'Pinball.Screens.TargetMissing' -f $p.Name, $p.Path; continue }
        if (-not $p.Changes.Count) { Get-KitText 'Pinball.Screens.NoChange' -f $p.Name }
        foreach ($c in $p.Changes) {
            Get-KitText 'Pinball.Screens.Change' -f $p.Name, $c.Consumer, (Format-PinballRect $c.Old), (Format-PinballRect $c.New), (Get-KitText "Pinball.Screens.Reason.$($c.Reason)")
        }
        foreach ($u in $p.Unresolved) { Get-KitText 'Pinball.Screens.Unresolved' -f $p.Name, $u }
    }
}

function Get-PinballScreenChangeCount {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Plan)
    [int](@($Plan | ForEach-Object { $_.Changes.Count }) | Measure-Object -Sum).Sum
}

function Write-IniTarget($Target, $Final, $Changes) {
    Edit-KitTextFile -Path $Target.Path -Confirm:$false -Rewrite {
        param($text)
        $n = 0
        foreach ($c in $Changes) {
            $rect = $Final[$c.Consumer]
            $values = [ordered]@{}
            $keys = $Target.IniKeys
            $values[$keys[0]] = $rect.X; $values[$keys[1]] = $rect.Y; $values[$keys[2]] = $rect.Width; $values[$keys[3]] = $rect.Height
            $set = Set-PinballIniValue -Text $text -Section $Target.Map[$c.Consumer] -Values $values -Separator $Target.Separator
            $text = $set.Text; $n += $set.Count
        }
        @{ Text = $text; Count = $n }
    }
}

function Write-ScreenResTarget($Target, $Final, $Monitors) {
    Edit-KitTextFile -Path $Target.Path -Confirm:$false -Rewrite {
        param($text)
        $nl = if ($text -match "`r`n" -or -not $text) { "`r`n" } else { "`n" }
        $lines = New-Object Collections.Generic.List[string]
        foreach ($l in (Get-ScreenResLines $text)) { $lines.Add($l) }
        while ($lines.Count -lt 12) { $lines.Add('0') }
        $values = @($lines | ForEach-Object { $_.Trim() })
        $pf = $Final['B2S.Playfield']; $bg = $Final['B2S.Backglass']; $dmd = $Final['B2S.DMD']
        if ($pf) { $values[0] = $pf.Width; $values[1] = $pf.Height }
        $mon = if ($bg) { Get-RectCenterMonitor $Monitors $bg }
        if ($mon) {
            $current = Resolve-B2SDisplay $Monitors $values[4]
            if (-not $current -or $current.DeviceName -ne $mon.DeviceName) { $values[4] = '@' + $mon.X }
            $values[2] = $bg.Width; $values[3] = $bg.Height; $values[5] = $bg.X - $mon.X; $values[6] = $bg.Y - $mon.Y
            if ($dmd) { $values[7] = $dmd.Width; $values[8] = $dmd.Height; $values[9] = $dmd.X - $mon.X; $values[10] = $dmd.Y - $mon.Y }
        }
        $n = 0
        for ($i = 0; $i -lt 12; $i++) {
            if ($lines[$i].Trim() -ne [string]$values[$i]) { $lines[$i] = [string]$values[$i]; $n++ }
        }
        $out = $lines -join $nl
        if ($text.EndsWith("`n")) { $out += $nl }
        @{ Text = $out; Count = $n }
    }
}

function Write-VpxIniTarget($Target, $Rect, $Monitors) {
    $m = Get-RectCenterMonitor $Monitors $Rect
    # Only Display, Width, Height. FullScreen is never written.
    $values = [ordered]@{ Display = (Get-DisplayNumber $m.DeviceName) - 1; Width = $Rect.Width; Height = $Rect.Height }
    Edit-KitTextFile -Path $Target.Path -Confirm:$false -Rewrite {
        param($text) Set-PinballIniValue -Text $text -Section 'Player' -Values $values -Separator $Target.Separator
    }
}

function Write-PinballScreenTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Entry,
        [Parameter(Mandatory)] $Layout,
        [Parameter(Mandatory)] [string] $Stamp,
        [string] $BackupDir
    )
    $t = $Entry.Target; $final = $Entry.Final; $changes = $Entry.Changes
    if ($t.Kind -eq 'Database') {
        $names = @{}
        foreach ($k in $script:PinballPopperScreens.Keys) { $names[$script:PinballPopperScreens[$k]] = $k }
        $update = Update-KitDatabaseSafely -Path $t.Path -Purpose 'screens' -Confirm:$false -ScriptBlock {
            param($connection)
            foreach ($c in $changes) {
                $r = $final[$c.Consumer]
                $null = Invoke-KitSqlNonQuery -Connection $connection -Parameters @{ n = $names[$c.Consumer]; x = $r.X; y = $r.Y; w = $r.Width; h = $r.Height } `
                    -Sql 'UPDATE Screens SET POSx = @x, POSy = @y, ScreenWidth = @w, ScreenHeight = @h WHERE ScreenName = @n COLLATE NOCASE'
            }
        }
        return $update.Backup
    }
    if ($t.Kind -like '*Registry') {
        if (-not $BackupDir) { throw 'BackupDir is required for registry targets.' }
        if (-not (Test-Path -LiteralPath $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
        $backup = Join-Path $BackupDir ('{0}_{1}.reg' -f $t.Name, $Stamp)
        $null = Export-KitRegistryKey -Path $t.Path -Destination $backup
        $set = { param($name, $value, $type) Set-KitRegistryValue -Path $t.Path -Name $name -Value $value -Type $type -Confirm:$false }
        foreach ($c in $changes) {
            $r = $final[$c.Consumer]
            $m = Get-RectCenterMonitor $Layout.Monitors $r
            switch ($c.Consumer) {
                'VPX.Playfield' { & $set 'Display' ((Get-DisplayNumber $m.DeviceName) - 1) 'DWord'; & $set 'Width' $r.Width 'DWord'; & $set 'Height' $r.Height 'DWord' }
                'FP.Playfield'  { & $set 'PlayfieldMonitorID' $m.DeviceName 'String'; & $set 'Width' $r.Width 'DWord'; & $set 'Height' $r.Height 'DWord' }
                'FP.Backbox'    { & $set 'BackboxMonitorID' $m.DeviceName 'String'; & $set 'SecondMonitorWidth' $r.Width 'DWord'; & $set 'SecondMonitorHeight' $r.Height 'DWord' }
            }
        }
        return $backup
    }
    $backup = '{0}.bak_screens_{1}' -f $t.Path, $Stamp
    Copy-Item -LiteralPath $t.Path -Destination $backup -Force
    switch ($t.Kind) {
        'Ini'       { $null = Write-IniTarget $t $final $changes }
        'ScreenRes' { $null = Write-ScreenResTarget $t $final $Layout.Monitors }
        'VpxIni'    { $null = Write-VpxIniTarget $t $final['VPX.Playfield'] $Layout.Monitors }
    }
    $backup
}

# Writes every target that has changes. Returns one record per written target (Target, Kind, Path, Backup,
# Changes) for Restore-PinballScreenBackup.
function Invoke-PinballScreenPlan {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Plan,
        [Parameter(Mandatory)] $Layout,
        [string] $BackupDir
    )
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    foreach ($p in $Plan | Where-Object { $_.Exists -and $_.Changes.Count }) {
        if (-not $PSCmdlet.ShouldProcess($p.Path, "Write $($p.Changes.Count) screen value change(s)")) { continue }
        Assert-PinballProcessesClosed
        $backup = Write-PinballScreenTarget -Entry $p -Layout $Layout -Stamp $stamp -BackupDir $BackupDir
        Write-KitLog (Get-KitText 'Pinball.Screens.Written' -f $p.Name, $p.Changes.Count, $backup)
        [pscustomobject]@{ Target = $p.Name; Kind = $p.Target.Kind; Path = $p.Path; Backup = $backup; Changes = $p.Changes.Count }
    }
}

# Way back: puts the backups of Invoke-PinballScreenPlan back. Registry import merges (values that did not
# exist before stay).
function Restore-PinballScreenBackup {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [object[]] $Written)
    foreach ($w in $Written) {
        if (-not $PSCmdlet.ShouldProcess($w.Path, 'Restore screen values')) { continue }
        Assert-PinballProcessesClosed
        if ($w.Kind -like '*Registry') { Import-KitRegistryFile -Path $w.Backup -Confirm:$false }
        else { Copy-Item -LiteralPath $w.Backup -Destination $w.Path -Force }
    }
}

# --- separate command: foreign virtual DMD positions in table sections ---------------------------------------

function Remove-TableDmdLine([string] $Text) {
    $nl = if ($Text -match "`r`n") { "`r`n" } else { "`n" }
    $section = ''
    $kept = New-Object Collections.Generic.List[string]
    $removed = @()
    foreach ($line in $Text -split '\r?\n') {
        if ($line -match '^\s*\[(.+?)\]\s*$') { $section = $Matches[1].Trim() }
        elseif ($section -ne 'virtualdmd' -and $line -match '^\s*virtualdmd[\s.]+(left|top|width|height)\s*=') {
            $removed += [pscustomobject]@{ Section = $section; Line = $line.Trim() }
            continue
        }
        $kept.Add($line)
    }
    @{ Text = ($kept -join $nl); Removed = $removed }
}

# Table sections ([<cGameName>]) that carry "virtualdmd left/top/width/height" from someone else's cabinet
# override the global [virtualdmd] position. Returns what is (or would be, with -WhatIf) removed.
function Remove-PinballTableDmdPosition {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [string] $Path)
    $result = Remove-TableDmdLine (Read-PinballTextFile $Path)
    if ($result.Removed.Count -and $PSCmdlet.ShouldProcess($Path, "Remove $($result.Removed.Count) table DMD position line(s)")) {
        Assert-PinballProcessesClosed
        Copy-Item -LiteralPath $Path -Destination ('{0}.bak_tabledmd_{1:yyyyMMdd-HHmmss}' -f $Path, (Get-Date)) -Force
        $null = Edit-KitTextFile -Path $Path -Confirm:$false -Rewrite { param($t) $r = Remove-TableDmdLine $t; @{ Text = $r.Text; Count = $r.Removed.Count } }
    }
    $result.Removed
}

# --- value card for programs the kit cannot configure --------------------------------------------------------

# Pinball FX3 (cabinet menu) uses the unrotated desktop; Pinball Arcade uses the rotated one, where the
# playfield is only as wide as it is high in landscape (x shifts by playfield width - height).
function Get-PinballValueCard {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Layout)
    $pf = Get-PinballRoleArea -Layout $Layout -Role 'Playfield'
    $row = { param($label, $r) if ($r) { '  {0,-10} x={1}  y={2}  w={3}  h={4}' -f $label, $r.X, $r.Y, $r.Width, $r.Height } else { '  {0,-10} -' -f $label } }
    Get-KitText 'Pinball.Screens.Card.Fx3'
    & $row 'Backglass' (Get-PinballConsumerRect -Layout $Layout -Consumer 'FX3.Backglass')
    & $row 'DMD' (Get-PinballConsumerRect -Layout $Layout -Consumer 'FX3.DMD')
    Get-KitText 'Pinball.Screens.Card.Tpa'
    foreach ($pair in @(@('Backglass', 'TPA.Backglass'), @('DMD', 'TPA.DMD'))) {
        $r = Get-PinballConsumerRect -Layout $Layout -Consumer $pair[1]
        if ($r -and $pf -and $r.X -ge $pf.X + $pf.Width) { $r = New-PinballRect ($r.X - $pf.Width + $pf.Height) $r.Y $r.Width $r.Height }
        & $row $pair[0] $r
    }
}
