# TeknoParrot (steps 10 and 11) [W8]. Ports of the proven helpers tp_fix_paths, tp_xinput_bind, es_tp_settings,
# tp_twins, tp_gamelist and tp_register, without any machine value:
#   UserProfiles\*.xml   GamePath/GamePath2 from another installation (a bought build keeps its creator's root,
#                        any drive, any folder) -> the same file below THIS RetroBat, only when it exists there.
#                        Gun games (<GunGame>true) are bound to XInput from RetroBat's own teknoparrot.yml:
#                        Wiimote 1/2 = XInputIndex 0/1, B (360 B) = shot, A (360 A) = reload, right stick aims,
#                        grenades/extra on Xbox X (no nunchuk = no LB), ButtonCode is a short (Y = -32768),
#                        Test/Service (l3/r3) stay free. Games whose yml marks a touch screen are pad games.
#   es_settings.cfg      teknoparrot["<rom folder>"].disableautocontrollers=1 per bound game (teknoparrot.use_guns=0
#                        comes from step 7); leftovers of a build creator's light gun setup are removed.
#   roms\teknoparrot     folders classified: active (a profile points there), duplicate (same name key or same
#                        content as an active folder: .parrot vs .teknoparrot) -> moved to <RetroBat>\_duplicates\
#                        after plan + confirmation (never deleted), unregistered -> hidden in gamelist.xml.
# Profiles whose file name starts with '#' are switched off in TeknoParrot and left alone.
# XML is read with XmlDocument (no DTD, no resolver, whitespace kept) and written in its own encoding.

$script:LightgunTpButtons = @{
    up = @(1, 'DPadUp'); down = @(2, 'DPadDown'); left = @(4, 'DPadLeft'); right = @(8, 'DPadRight')
    start = @(16, 'Start'); select = @(32, 'Back'); leftshoulder = @(256, 'LeftShoulder'); rightshoulder = @(512, 'RightShoulder')
    south = @(4096, 'A'); east = @(8192, 'B'); west = @(16384, 'X'); north = @(-32768, 'Y')
}
# RetroBat's yml assumes pad triggers; Gunmote's TP layout sends Wiimote B as 360 B and A as 360 A: swapping puts
# the shot on B and reload on A (also for Wiimote 2 without nunchuk). A swap, so it stays unambiguous.
$script:LightgunTpWiiSwap = @{ righttrigger = 'east'; east = 'righttrigger'; lefttrigger = 'south'; south = 'lefttrigger' }
$script:LightgunTpFree = @('l3', 'r3')
$script:LightgunTpXiFields = @('IsLeftThumbX', 'IsRightThumbX', 'IsLeftThumbY', 'IsRightThumbY', 'IsAxisMinus', 'IsLeftTrigger', 'IsRightTrigger', 'ButtonCode', 'IsButton', 'ButtonIndex', 'XInputIndex')
# Sinden/RawInput leftovers of a build creator that fight the Wiimote binding (removed per game; at system level
# only these without use_guns, which step 7 sets to 0).
$script:LightgunTpEsDrop = @('tp_inputdriver', 'use_guns', 'use_demulshooter', 'one_gun', 'gun_invert', 'tp_gunkeyboard', 'tp_nocrosshair')
$script:LightgunTpMediaDirs = @('images', 'videos', 'manuals')

function Get-LightgunTpPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Root)
    $r = (Resolve-LightgunFullPath $Root).TrimEnd('\')
    $tp = "$r\emulators\teknoparrot"
    [pscustomobject]@{
        Root         = $r
        UserProfiles = "$tp\UserProfiles"
        Metadata     = "$tp\Metadata"
        Roms         = "$r\roms\teknoparrot"
        Gamelist     = "$r\roms\teknoparrot\gamelist.xml"
        InputMapping = "$r\system\resources\inputmapping\teknoparrot.yml"
        Duplicates   = "$r\_duplicates\teknoparrot"
    }
}

# UserProfiles\*.xml (extension exactly .xml: the 8.3 name of *.xmlx would match the filter too). -All includes
# the switched-off '#' profiles.
function Get-LightgunTpProfileFile([string] $Dir, [switch] $All) {
    @(Get-ChildItem -LiteralPath $Dir -Filter '*.xml' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -eq '.xml' -and ($All -or -not $_.Name.StartsWith('#')) -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } |
        Sort-Object Name)
}

# The same file below -Root for a path of another installation: every "\roms\" is tried from the left (a game
# folder may have its own "roms" folder), the first candidate that exists below <Root>\roms wins. $null = none.
function Get-LightgunTpPathCandidate {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [string] $Root)
    $roms = Join-Path $Root 'roms'
    $i = 0
    while (($i = $Path.IndexOf('\roms\', $i, [StringComparison]::OrdinalIgnoreCase)) -ge 0) {
        try { $c = [IO.Path]::GetFullPath($Root.TrimEnd('\') + $Path.Substring($i)) } catch { return $null }
        if ((Test-KitPathUnder -Path $c -Root $roms) -and (Test-Path -LiteralPath $c)) { return $c } # '..' cannot leave roms
        $i++
    }
    $null
}

# One row per GamePath/GamePath2 that is not a file of this RetroBat: Action Repair (New = the file here) or
# Missing (neither the old path nor a candidate exists; left alone). A path of another installation that still
# exists and has no candidate here is left alone too (a game on another drive).
function Get-LightgunTpPathPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RetroBatRoot, [string] $ProfileDir)
    $p = Get-LightgunTpPath -Root $RetroBatRoot
    if (-not $ProfileDir) { $ProfileDir = $p.UserProfiles }
    foreach ($f in Get-LightgunTpProfileFile $ProfileDir) {
        try { $doc = Read-LightgunXml $f.FullName } catch { Write-KitLog "$($f.FullName): $($_.Exception.Message)" -Level Warn; continue }
        foreach ($field in 'GamePath', 'GamePath2') {
            $n = $doc.DocumentElement.SelectSingleNode($field)
            if (-not $n -or -not $n.InnerText) { continue }
            $old = $n.InnerText
            $exists = $false
            try { $exists = Test-Path -LiteralPath $old } catch { }
            $here = $false
            try { $here = Test-KitPathUnder -Path $old -Root $p.Root } catch { }
            if ($here -and $exists) { continue }
            $new = if ($here) { $null } else { Get-LightgunTpPathCandidate -Path $old -Root $p.Root }
            if ($new) { $action = 'Repair' } elseif ($exists) { continue } else { $action = 'Missing' }
            [pscustomobject]@{ Profile = $f.BaseName; File = $f.FullName; Field = $field; Old = $old; New = $new; Action = $action }
        }
    }
}

# Writes the Repair rows (backup per file, guarded programs closed). Returns the number of repaired paths.
function Repair-LightgunTpPath {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Plan)
    $count = 0
    foreach ($group in @($Plan | Where-Object { $_.Action -eq 'Repair' }) | Group-Object File) {
        if (-not $PSCmdlet.ShouldProcess($group.Name, "$($group.Count) path(s)")) { continue }
        $doc = Read-LightgunXml $group.Name
        foreach ($c in $group.Group) {
            $n = $doc.DocumentElement.SelectSingleNode($c.Field)
            if (-not $n -or $n.InnerText -cne $c.Old -or -not (Test-Path -LiteralPath $c.New)) { throw (Get-KitText 'Plan.Changed' -f $group.Name) }
            $n.InnerText = $c.New
        }
        Assert-LightgunProcessesClosed
        $null = Backup-LightgunFile -Path $group.Name
        Save-LightgunXml $doc $group.Name
        $count += $group.Count
    }
    $count
}

# RetroBat's teknoparrot.yml: profile (lower case) -> @{ InputMapping = value }; '#touchscreen' marks a block
# whose comments name a touch screen. Keys without a value are left out.
function Read-LightgunTpInputMapping {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $map = @{}
    $cur = $null
    foreach ($line in [IO.File]::ReadAllLines($Path)) {
        if ($line -match '^([A-Za-z0-9_.\-]+):\s*(#.*)?$') { $cur = @{}; $map[$Matches[1].ToLowerInvariant()] = $cur; continue }
        if ($null -eq $cur -or $line -notmatch '^\s+([A-Za-z0-9_]+):[ \t]*([^\s#]*)[ \t]*(?:#(.*))?$') { continue }
        if ($Matches[2]) { $cur[$Matches[1]] = $Matches[2] }
        if ($Matches[3] -match 'touch ?screen') { $cur['#touchscreen'] = '1' }
    }
    $map
}

# XInputButton values and bind name for a pad input of RetroBat's yml on pad -Index; $null for anything else
# (keyboard keys, mouse buttons).
function Get-LightgunTpXInputTarget([string] $Value, [int] $Index) {
    if ($Value -cnotmatch '^[a-z0-9]+$') { return $null } # the yml's values are lower case; "Start" is a typo there
    $f = [ordered]@{}
    foreach ($k in $script:LightgunTpXiFields) { $f[$k] = 'false' }
    $f.ButtonCode = '0'; $f.ButtonIndex = '0'; $f.XInputIndex = "$Index"
    $dev = "Input Device $Index"
    if ($script:LightgunTpButtons.ContainsKey($Value)) {
        $b = $script:LightgunTpButtons[$Value]
        $f.ButtonCode = "$($b[0])"; $f.IsButton = 'true'; $name = "$dev $($b[1])"
    } elseif ($Value -ceq 'righttrigger' -or $Value -ceq 'lefttrigger') {
        $side = if ($Value[0] -eq 'r') { 'Right' } else { 'Left' }
        $f["Is${side}Trigger"] = 'true'; $name = "$dev ${side}Trigger"
    } elseif ($Value -cmatch '^(left|right)stick(left|right|up|down)$') {
        $side = if ($Matches[1] -eq 'right') { 'Right' } else { 'Left' }
        $axis = if ($Matches[2] -in 'left', 'right') { 'X' } else { 'Y' }
        $minus = $Matches[2] -in 'left', 'down'
        $f["Is${side}Thumb$axis"] = 'true'
        $f.IsAxisMinus = if ($minus) { 'true' } else { 'false' }
        $name = "$dev ${side}Thumb$dev $axis$(if ($minus) { '-' } else { '+' })" # TeknoParrot's own spelling
    } else { return $null }
    [pscustomobject]@{ Fields = $f; Bind = $name }
}

function Get-TpChildIndent([Xml.XmlElement] $Element, [string] $Fallback) {
    foreach ($n in $Element.ChildNodes) { if ($n.NodeType -eq 'Whitespace' -or $n.NodeType -eq 'SignificantWhitespace') { return $n.Value } }
    $Fallback
}

function Set-TpChildText([Xml.XmlElement] $Parent, [string] $Name, [string] $Value, [Xml.XmlNode] $Before) {
    $n = $Parent.SelectSingleNode($Name)
    if ($n) { if ($n.InnerText -cne $Value) { $n.InnerText = $Value; return $true }; return $false }
    $doc = $Parent.OwnerDocument
    $n = $doc.CreateElement($Name); $n.InnerText = $Value
    $indent = Get-TpChildIndent $Parent "`n      "
    if ($Before) { $null = $Parent.InsertBefore($n, $Before); $null = $Parent.InsertBefore($doc.CreateWhitespace($indent), $Before) }
    else {
        $last = $Parent.LastChild
        if ($last -and $last.NodeType -eq 'Whitespace') { $null = $Parent.InsertBefore($doc.CreateWhitespace($indent), $last); $null = $Parent.InsertBefore($n, $last) }
        else { $null = $Parent.AppendChild($doc.CreateWhitespace($indent)); $null = $Parent.AppendChild($n) }
    }
    $true
}

# Binds one <JoystickButtons> entry; returns $true when something changed. Player 2 is recognised by the button
# name only (TC5 puts a P1 menu switch on P2ButtonN internally).
function Set-TpButtonBinding([Xml.XmlElement] $Button, [hashtable] $Map) {
    $im = $Button.SelectSingleNode('InputMapping'); $bn = $Button.SelectSingleNode('ButtonName')
    if (-not $im -or -not $bn) { return $false }
    $val = [string]$Map[$im.InnerText]
    if (-not $val -or $script:LightgunTpFree -contains $val) { return $false }
    $name = $bn.InnerText
    if ($name -match 'grenade' -and $val -eq 'leftshoulder') { $val = 'west' }
    $idx = if ($name -cmatch '(Player|P)\s*2\b|\s2$') { 1 } else { 0 }
    if ($script:LightgunTpWiiSwap.ContainsKey($val)) { $val = $script:LightgunTpWiiSwap[$val] }
    $t = Get-LightgunTpXInputTarget $val $idx
    if (-not $t) { return $false }
    $doc = $Button.OwnerDocument
    $changed = $false
    $xi = $Button.SelectSingleNode('XInputButton')
    $same = [bool]$xi
    if ($xi) { foreach ($k in $t.Fields.Keys) { $v = $xi.SelectSingleNode($k); if (-not $v -or $v.InnerText -cne $t.Fields[$k]) { $same = $false; break } } }
    if (-not $same) {
        $indent = Get-TpChildIndent $Button "`n      "
        if ($xi) {
            if ($xi.PreviousSibling -and $xi.PreviousSibling.NodeType -eq 'Whitespace') { $null = $Button.RemoveChild($xi.PreviousSibling) }
            $null = $Button.RemoveChild($xi)
        }
        $x = $doc.CreateElement('XInputButton')
        foreach ($k in $t.Fields.Keys) {
            $null = $x.AppendChild($doc.CreateWhitespace($indent + '  '))
            $e = $doc.CreateElement($k); $e.InnerText = $t.Fields[$k]; $null = $x.AppendChild($e)
        }
        $null = $x.AppendChild($doc.CreateWhitespace($indent))
        $anchor = $Button.SelectSingleNode('RawInputButton'); if (-not $anchor) { $anchor = $im }
        $null = $Button.InsertBefore($x, $anchor)
        $null = $Button.InsertBefore($doc.CreateWhitespace($indent), $anchor)
        $changed = $true
    }
    $bind = $Button.SelectSingleNode('BindName')
    if (Set-TpChildText $Button 'BindNameXi' $t.Bind $bind) { $changed = $true }
    if (Set-TpChildText $Button 'BindName' $t.Bind $null) { $changed = $true }
    $changed
}

# Binds all buttons of a loaded profile and sets "Input API" to XInput. Returns the number of changed entries.
function Set-TpProfileBinding([Xml.XmlDocument] $Doc, [hashtable] $Map) {
    $n = 0
    foreach ($b in @($Doc.DocumentElement.SelectNodes('JoystickButtons/JoystickButtons'))) { if (Set-TpButtonBinding $b $Map) { $n++ } }
    foreach ($fi in @($Doc.DocumentElement.SelectNodes('ConfigValues/FieldInformation'))) {
        $fn = $fi.SelectSingleNode('FieldName'); $fv = $fi.SelectSingleNode('FieldValue')
        if ($fn -and $fv -and $fn.InnerText -eq 'Input API' -and $fv.InnerText -cne 'XInput') { $fv.InnerText = 'XInput'; $n++ }
    }
    $n
}

# The folder below roms\teknoparrot a GamePath points into ('' = none).
function Get-LightgunTpRomFolder([string] $GamePath, [string] $RomsDir) {
    $base = $RomsDir.TrimEnd('\') + '\'
    if (-not $GamePath.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { return '' }
    $GamePath.Substring($base.Length).Split('\')[0]
}

# One row per gun game: Profile, File, Rom (folder), Status (Bind = changes pending, Ok, NoPath, NoMapping,
# Touch, Excluded), Changes. -Exclude: further profile names to leave alone.
function Get-LightgunTpBindPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RetroBatRoot,
        [string] $ProfileDir,
        [string] $MappingPath,
        [string[]] $Exclude = @()
    )
    $p = Get-LightgunTpPath -Root $RetroBatRoot
    if (-not $ProfileDir) { $ProfileDir = $p.UserProfiles }
    if (-not $MappingPath) { $MappingPath = $p.InputMapping }
    if (-not (Test-Path -LiteralPath $MappingPath -PathType Leaf)) { Write-KitLog (Get-KitText 'Lightgun.Tp.NoMapping' -f $MappingPath) -Level Warn; return }
    $maps = Read-LightgunTpInputMapping -Path $MappingPath
    foreach ($f in Get-LightgunTpProfileFile $ProfileDir) {
        try { $doc = Read-LightgunXml $f.FullName } catch { Write-KitLog "$($f.FullName): $($_.Exception.Message)" -Level Warn; continue }
        $gun = $doc.DocumentElement.SelectSingleNode('GunGame')
        if (-not $gun -or $gun.InnerText -ne 'true') { continue }
        $gp = $doc.DocumentElement.SelectSingleNode('GamePath')
        $path = if ($gp) { $gp.InnerText } else { '' }
        $row = [pscustomobject]@{ Profile = $f.BaseName; File = $f.FullName; Rom = (Get-LightgunTpRomFolder $path $p.Roms); Status = ''; Changes = 0 }
        $map = $maps[$f.BaseName.ToLowerInvariant()]
        $exists = $false; if ($path) { try { $exists = Test-Path -LiteralPath $path } catch { } }
        if ($Exclude -contains $f.BaseName) { $row.Status = 'Excluded' }
        elseif (-not $exists) { $row.Status = 'NoPath' }
        elseif (-not $map) { $row.Status = 'NoMapping' }
        elseif ($map.ContainsKey('#touchscreen')) { $row.Status = 'Touch' }
        else {
            $row.Changes = Set-TpProfileBinding $doc $map
            $row.Status = if ($row.Changes) { 'Bind' } else { 'Ok' }
        }
        $row
    }
}

# Binds the Bind rows (backup per file, guarded programs closed); parses the result before writing. Returns the
# number of written profiles.
function Set-LightgunTpBinding {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Plan, [Parameter(Mandatory)] [string] $MappingPath)
    $maps = Read-LightgunTpInputMapping -Path $MappingPath
    $count = 0
    foreach ($row in @($Plan | Where-Object { $_.Status -eq 'Bind' })) {
        if (-not $PSCmdlet.ShouldProcess($row.File, "XInput binding ($($row.Changes))")) { continue }
        $doc = Read-LightgunXml $row.File
        $null = Set-TpProfileBinding $doc $maps[$row.Profile.ToLowerInvariant()]
        Assert-LightgunProcessesClosed
        $null = Backup-LightgunFile -Path $row.File
        Save-LightgunXml $doc $row.File
        $null = Read-LightgunXml $row.File # still well-formed
        $count++
    }
    $count
}

# es_settings.cfg: target (teknoparrot["<rom>"].disableautocontrollers = 1) and the leftover names to remove.
function Get-LightgunTpEsTarget {
    [CmdletBinding()]
    param([AllowEmptyCollection()] [string[]] $Rom = @())
    $t = [ordered]@{ 'teknoparrot.use_guns' = '0' } # the same value as step 7
    foreach ($r in $Rom | Where-Object { $_ } | Sort-Object -Unique) { $t["teknoparrot[`"$r`"].disableautocontrollers"] = '1' }
    $t
}

function Get-LightgunTpEsRemove {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $doc = Read-LightgunXml $Path
    $keys = ($script:LightgunTpEsDrop | ForEach-Object { [regex]::Escape($_) }) -join '|'
    foreach ($e in Get-EsSettingElement $doc) {
        $n = $e.GetAttribute('name')
        if ($n -match "^teknoparrot\[`".+`"\]\.($keys)$") { $n }
        elseif ($n -match "^teknoparrot\.($keys)$" -and $Matches[1] -ne 'use_guns') { $n }
        elseif ($n -match '^teknoparrot(\[".+"\])?\.shaderset$' -and $e.GetAttribute('value') -eq 'sindenborder') { $n }
    }
}

# --- game list and duplicates (step 11) ---------------------------------------------------------------------

function Get-LightgunTpNameKey([string] $Text) { ($Text.ToLowerInvariant() -replace 'the|[^a-z0-9]', '') }

function Get-TpFolderStem([string] $Name) { $i = $Name.LastIndexOf('.'); if ($i -gt 0) { $Name.Substring(0, $i) } else { $Name } }

# Content signature of a folder: relative names and sizes of all files ('' = empty folder).
# ponytail: names + sizes, not hashes; a hash would read hundreds of GB. Add hashing if two different dumps
# with identical names and sizes ever show up.
function Get-TpFolderSignature([string] $Dir) {
    $files = @(Get-KitFileTree -Path $Dir -SkipReparseFiles)
    if (-not $files) { return '' }
    (@($files | ForEach-Object { '{0}|{1}' -f $_.FullName.Substring($Dir.Length).ToLowerInvariant(), $_.Length }) | Sort-Object) -join "`n"
}

# game_name of TeknoParrot's Metadata\<profile>.json.
function Get-LightgunTpMetadata([string] $Dir) {
    $meta = @{}
    foreach ($f in Get-ChildItem -LiteralPath $Dir -Filter '*.json' -File -ErrorAction SilentlyContinue) {
        try { $name = [string](Get-JsonProperty ([IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json) 'game_name') } catch { $name = '' }
        if ($name) { $meta[$f.BaseName] = $name }
    }
    $meta
}

# Folders of roms\teknoparrot: Folder, Kind (Active | Duplicate | Unregistered), Profile (active: the profile;
# duplicate: the active folder it doubles; unregistered: a matching TeknoParrot profile name or '').
function Get-LightgunTpFolderClass {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RetroBatRoot, [string] $ProfileDir)
    $p = Get-LightgunTpPath -Root $RetroBatRoot
    if (-not $ProfileDir) { $ProfileDir = $p.UserProfiles }
    $meta = Get-LightgunTpMetadata $p.Metadata
    $active = @{}
    foreach ($f in Get-LightgunTpProfileFile $ProfileDir -All) {
        try { $gp = (Read-LightgunXml $f.FullName).DocumentElement.SelectSingleNode('GamePath') } catch { continue }
        if ($gp) { $d = Get-LightgunTpRomFolder $gp.InnerText $p.Roms; if ($d -and -not $active.ContainsKey($d)) { $active[$d] = $f.BaseName } }
    }
    $keys = @{}
    foreach ($d in $active.Keys) {
        foreach ($k in (Get-TpFolderStem $d), $active[$d], $meta[$active[$d]]) { if ($k) { $nk = Get-LightgunTpNameKey $k; if ($nk -and -not $keys.ContainsKey($nk)) { $keys[$nk] = $d } } }
    }
    $dirs = @(Get-ChildItem -LiteralPath $p.Roms -Directory -ErrorAction SilentlyContinue | Where-Object { $script:LightgunTpMediaDirs -notcontains $_.Name } | Sort-Object Name)
    $signatures = $null
    foreach ($d in $dirs) {
        $name = $d.Name
        $real = @($active.Keys | Where-Object { $_ -eq $name }) | Select-Object -First 1
        if ($real) { [pscustomobject]@{ Folder = $name; Kind = 'Active'; Profile = $active[$real] }; continue }
        $k = Get-LightgunTpNameKey (Get-TpFolderStem $name)
        if ($keys.ContainsKey($k)) { [pscustomobject]@{ Folder = $name; Kind = 'Duplicate'; Profile = $keys[$k] }; continue }
        $sig = Get-TpFolderSignature $d.FullName
        if ($sig) {
            if ($null -eq $signatures) {
                $signatures = @{}
                foreach ($a in $active.Keys) { $full = Join-Path $p.Roms $a; if (Test-Path -LiteralPath $full -PathType Container) { $s = Get-TpFolderSignature $full; if ($s -and -not $signatures.ContainsKey($s)) { $signatures[$s] = $a } } }
            }
            if ($signatures.ContainsKey($sig)) { [pscustomobject]@{ Folder = $name; Kind = 'Duplicate'; Profile = $signatures[$sig] }; continue }
        }
        $cand = @($meta.Keys | Where-Object { (Get-LightgunTpNameKey $meta[$_]) -eq $k -or (Get-LightgunTpNameKey $_) -eq $k }) | Select-Object -First 1
        [pscustomobject]@{ Folder = $name; Kind = 'Unregistered'; Profile = [string]$cand }
    }
}

function Get-TpGamelistPath([Xml.XmlElement] $Game) {
    $n = $Game.SelectSingleNode('path')
    if (-not $n) { return '' }
    $v = $n.InnerText.Replace('\', '/')
    if ($v.StartsWith('./')) { $v = $v.Substring(2) }
    $v.TrimEnd('/')
}

# Changes and findings for roms\teknoparrot\gamelist.xml: Action Move (duplicate folder -> _duplicates), Hide
# (duplicate/unregistered entry gets <hidden>true</hidden>, a missing entry is added hidden), Add (active folder
# without entry), and reported only: NoMedia (active entry without image/video or with a missing file),
# Orphan (entry without folder or file). -GamelistPath: another gamelist (local tests).
function Get-LightgunTpGamelistPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RetroBatRoot, [string] $ProfileDir, [string] $GamelistPath)
    $p = Get-LightgunTpPath -Root $RetroBatRoot
    if (-not $GamelistPath) { $GamelistPath = $p.Gamelist }
    $meta = Get-LightgunTpMetadata $p.Metadata
    $classes = @(Get-LightgunTpFolderClass -RetroBatRoot $RetroBatRoot -ProfileDir $ProfileDir)
    $entries = @{}
    $haveList = Test-Path -LiteralPath $GamelistPath -PathType Leaf
    if ($haveList) { foreach ($g in @((Read-LightgunXml $GamelistPath).SelectNodes('/gameList/game'))) { $k = Get-TpGamelistPath $g; if ($k -and -not $entries.ContainsKey($k)) { $entries[$k] = $g } } }
    foreach ($c in $classes) {
        $g = $entries[$c.Folder]
        $row = @{ Folder = $c.Folder; Kind = $c.Kind; Profile = $c.Profile; Name = if ($g -and $g.SelectSingleNode('name')) { $g.SelectSingleNode('name').InnerText } else { '' } }
        if ($c.Kind -eq 'Active') {
            if (-not $g) {
                $row.Name = if ($meta[$c.Profile]) { $meta[$c.Profile] } else { Get-TpFolderStem $c.Folder }
                [pscustomobject]($row + @{ Action = 'Add'; Detail = '' })
                continue
            }
            $missing = @(foreach ($tag in 'image', 'video') {
                $m = $g.SelectSingleNode($tag)
                if (-not $m -or -not $m.InnerText) { $tag; continue }
                $rel = $m.InnerText.Replace('/', '\'); if ($rel.StartsWith('.\')) { $rel = $rel.Substring(2) }
                $full = if ([IO.Path]::IsPathRooted($rel)) { $rel } else { Join-Path $p.Roms $rel }
                if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { "$tag ($($m.InnerText))" }
            })
            if ($missing) { [pscustomobject]($row + @{ Action = 'NoMedia'; Detail = $missing -join ', ' }) }
            continue
        }
        if ($c.Kind -eq 'Duplicate') { [pscustomobject]($row + @{ Action = 'Move'; Detail = Join-Path $p.Duplicates $c.Folder }) }
        if (-not $g -or $g.SelectSingleNode('hidden') -eq $null -or $g.SelectSingleNode('hidden').InnerText -ne 'true') {
            [pscustomobject]($row + @{ Action = 'Hide'; Detail = '' })
        }
    }
    foreach ($k in $entries.Keys | Sort-Object) {
        if (-not (Test-Path -LiteralPath (Join-Path $p.Roms $k))) {
            $n = $entries[$k].SelectSingleNode('name')
            [pscustomobject]@{ Folder = $k; Kind = ''; Profile = ''; Name = if ($n) { $n.InnerText } else { '' }; Action = 'Orphan'; Detail = '' }
        }
    }
}

function Add-TpGame([Xml.XmlDocument] $Doc, [string] $Folder, [string] $Name, [bool] $Hidden) {
    $root = $Doc.DocumentElement
    $outer = "`n`t"
    $firstGame = $root.SelectSingleNode('game')
    if ($firstGame -and $firstGame.PreviousSibling -and $firstGame.PreviousSibling.NodeType -eq 'Whitespace') { $outer = $firstGame.PreviousSibling.Value }
    $inner = if ($firstGame) { Get-TpChildIndent $firstGame ($outer + "`t") } else { $outer + "`t" }
    $g = $Doc.CreateElement('game')
    $values = [ordered]@{ path = "./$Folder"; name = $Name }
    if ($Hidden) { $values.hidden = 'true' }
    foreach ($k in $values.Keys) { $null = $g.AppendChild($Doc.CreateWhitespace($inner)); $e = $Doc.CreateElement($k); $e.InnerText = $values[$k]; $null = $g.AppendChild($e) }
    $null = $g.AppendChild($Doc.CreateWhitespace($outer))
    $last = $root.LastChild
    if ($last -and $last.NodeType -eq 'Whitespace') { $null = $root.InsertBefore($Doc.CreateWhitespace($outer), $last); $null = $root.InsertBefore($g, $last) }
    else { $null = $root.AppendChild($Doc.CreateWhitespace($outer)); $null = $root.AppendChild($g); $null = $root.AppendChild($Doc.CreateWhitespace("`n")) }
}

# Writes the Add and Hide rows into gamelist.xml (backup, guarded programs closed). A missing gamelist.xml is
# created. Returns the change count.
function Set-LightgunTpGamelist {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Plan)
    $rows = @($Plan | Where-Object { $_.Action -in 'Add', 'Hide' })
    if (-not $rows -or -not $PSCmdlet.ShouldProcess($Path, "$($rows.Count) gamelist change(s)")) { return 0 }
    $created = -not (Test-Path -LiteralPath $Path -PathType Leaf)
    if ($created) { [IO.File]::WriteAllText($Path, "<?xml version=`"1.0`"?>`n<gameList>`n</gameList>`n", (New-Object Text.UTF8Encoding $false)) }
    $doc = Read-LightgunXml $Path
    $byPath = @{}
    foreach ($g in @($doc.SelectNodes('/gameList/game'))) { $k = Get-TpGamelistPath $g; if ($k -and -not $byPath.ContainsKey($k)) { $byPath[$k] = $g } }
    foreach ($r in $rows) {
        $g = $byPath[$r.Folder]
        if (-not $g) { Add-TpGame $doc $r.Folder $(if ($r.Name) { $r.Name } else { Get-TpFolderStem $r.Folder }) ($r.Action -eq 'Hide'); continue }
        if ($r.Action -eq 'Hide') { $null = Set-TpChildText $g 'hidden' 'true' $null }
    }
    Assert-LightgunProcessesClosed
    if (-not $created) { $null = Backup-LightgunFile -Path $Path }
    Save-LightgunXml $doc $Path
    $rows.Count
}

# Moves the duplicate folders (Move rows) to <RetroBat>\_duplicates\teknoparrot\ - never deletes, never
# overwrites, skips links. The plan (source -> target) is confirmed first (-Approve, else the console asks).
# Returns the moved folders.
function Move-LightgunTpDuplicate {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [string] $RetroBatRoot, [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Plan, [scriptblock] $Approve)
    $p = Get-LightgunTpPath -Root $RetroBatRoot
    $rows = @($Plan | Where-Object { $_.Action -eq 'Move' })
    if (-not $rows -or -not $PSCmdlet.ShouldProcess($p.Duplicates, "Move $($rows.Count) duplicate folder(s)")) { return }
    $lines = @((Get-KitText 'Lightgun.Lists.MovePlan' -f $rows.Count, $p.Duplicates)) + @($rows | ForEach-Object { Get-KitText 'Lightgun.Lists.MoveRow' -f $_.Folder, $_.Profile })
    if (-not (Confirm-KitPlan -Lines $lines -Approve $Approve)) { throw (Get-KitText 'Plan.Declined') }
    Assert-LightgunProcessesClosed
    foreach ($r in $rows) {
        $src = Join-Path $p.Roms $r.Folder
        $dst = Join-Path $p.Duplicates $r.Folder
        $item = Get-Item -LiteralPath $src -Force -ErrorAction SilentlyContinue
        if (-not $item -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { Write-KitLog (Get-KitText 'Lightgun.Lists.MoveSkipped' -f $src) -Level Warn; continue }
        if (Test-Path -LiteralPath $dst) { Write-KitLog (Get-KitText 'Lightgun.Lists.MoveExists' -f $dst) -Level Warn; continue }
        New-Item -ItemType Directory -Path $p.Duplicates -Force | Out-Null
        Move-Item -LiteralPath $src -Destination $dst
        Write-KitLog (Get-KitText 'Lightgun.Lists.Moved' -f $src, $dst)
        $r.Folder
    }
}
