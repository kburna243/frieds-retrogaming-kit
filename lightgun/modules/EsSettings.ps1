# EsSettings (step 7): RetroBat's es_settings.cfg and es_input.cfg for Wiimotes that arrive as Xbox pads.
#   <system>.use_guns=0        must be EXPLICIT: without it RetroBat switches its gun automation on for light
#                              gun games and maps the guns to Gunmote's mice, even with disableautocontrollers
#   <system>.disableautocontrollers=1   no pad auto configuration (the kit's/user's mapping survives)
#   emulator choice: mame -> mame64 (+ lightgun as joystick over xinput, ctrlr profile custom1),
#                    naomi -> demul (use_demulshooter=0: RetroBat would overwrite DemulShooter's config),
#                    psx -> duckstation
#   es_input.cfg: complete "Xbox 360 Controller" block, a = button 1, b = button 0: RetroBat follows Batocera
#                 ("b" selects), so the trigger (Wiimote B -> Xbox A in the menu layout) selects.
# Per-game overrides (<system>["game"].use_guns) and gamelist entries with a hard-wired <emulator>/<core>
# overrule these settings; they are reported, never changed.
# XML is edited with XmlDocument and PreserveWhitespace: comments, order and formatting stay; a new key is
# inserted at its sorted place (RetroBat keeps the file sorted). Only changed files are written.

$script:LightgunGunSystems = @('mame', 'naomi', 'atomiswave', 'psx', 'model2', 'model3', 'teknoparrot')

$script:LightgunEsExtra = [ordered]@{
    'mame.emulator'               = 'mame64'
    'mame.core'                   = 'mame'
    'mame.mame_lightgun'          = 'joystick'
    'mame.mame_joystick_driver'   = 'xinput'
    'mame.mame_ctrlr_profile'     = 'custom1'
    'naomi.emulator'              = 'demul'
    'naomi.core'                  = 'naomi'
    'naomi.use_demulshooter'      = '0'
    'psx.emulator'                = 'duckstation'
    'psx.core'                    = 'duckstation'
}

# Complete Xbox 360 block (SDL numbering of the XInput pad): name, type, id, value.
$script:LightgunXboxInputs = @(
    @('a', 'button', '1', '1'), @('b', 'button', '0', '1'), @('down', 'hat', '0', '4'), @('hotkey', 'button', '6', '1'),
    @('joystick1left', 'axis', '0', '-1'), @('joystick1up', 'axis', '1', '-1'), @('joystick2left', 'axis', '2', '-1'),
    @('joystick2up', 'axis', '3', '-1'), @('l2', 'axis', '4', '1'), @('l3', 'button', '8', '1'), @('left', 'hat', '0', '8'),
    @('pagedown', 'button', '5', '1'), @('pageup', 'button', '4', '1'), @('r2', 'axis', '5', '1'), @('r3', 'button', '9', '1'),
    @('right', 'hat', '0', '2'), @('select', 'button', '6', '1'), @('start', 'button', '7', '1'), @('up', 'hat', '0', '1'),
    @('x', 'button', '3', '1'), @('y', 'button', '2', '1')
)
$script:LightgunXboxName = 'Xbox 360 Controller'
$script:LightgunXboxGuid = '030000005e0400008e02000000007200'

function Get-LightgunGunSystem {
    [CmdletBinding()]
    param()
    $script:LightgunGunSystems
}

# Target values of es_settings.cfg, in a fixed order.
function Get-LightgunEsSettingsTarget {
    [CmdletBinding()]
    param()
    $t = [ordered]@{}
    foreach ($s in $script:LightgunGunSystems) { $t["$s.use_guns"] = '0'; $t["$s.disableautocontrollers"] = '1' }
    foreach ($k in $script:LightgunEsExtra.Keys) { $t[$k] = $script:LightgunEsExtra[$k] }
    $t
}

function Read-LightgunXml([string] $Path) {
    $doc = New-Object Xml.XmlDocument
    $doc.PreserveWhitespace = $true
    $doc.XmlResolver = $null # never fetch anything (DTD, entities)
    $settings = New-Object Xml.XmlReaderSettings
    $settings.DtdProcessing = 'Prohibit'
    $settings.XmlResolver = $null
    $reader = [Xml.XmlReader]::Create($Path, $settings)
    try { $doc.Load($reader) } finally { $reader.Dispose() }
    $doc
}

# UTF-8 without BOM (as RetroBat writes it), whitespace exactly as in the document, via temp file + replace.
# The XML parser turns CRLF into LF; a file that used CRLF gets CRLF back. The XML declaration is copied
# verbatim from the file (the writer would rewrite its quotes and add an encoding).
function Save-LightgunXml([Xml.XmlDocument] $Doc, [string] $Path) {
    $original = [IO.File]::ReadAllText($Path)
    $settings = New-Object Xml.XmlWriterSettings
    $settings.Encoding = New-Object Text.UTF8Encoding $false
    $settings.Indent = $false
    $settings.OmitXmlDeclaration = $true
    if ($original.Contains("`r`n")) { $settings.NewLineHandling = 'Replace'; $settings.NewLineChars = "`r`n" }
    else { $settings.NewLineHandling = 'None' }
    $declaration = ''
    if ($original.TrimStart([char]0xFEFF).StartsWith('<?xml')) { $declaration = $original.TrimStart([char]0xFEFF).Substring(0, $original.TrimStart([char]0xFEFF).IndexOf('?>') + 2) }
    $copy = $Doc.Clone()
    if ($copy.FirstChild -is [Xml.XmlDeclaration]) { $null = $copy.RemoveChild($copy.FirstChild) }
    $buffer = New-Object IO.MemoryStream
    $writer = [Xml.XmlWriter]::Create($buffer, $settings)
    try { $copy.Save($writer) } finally { $writer.Dispose() }
    $bytes = [Text.Encoding]::UTF8.GetBytes($declaration) + $buffer.ToArray()
    $tmp = "$Path.tmp"
    [IO.File]::WriteAllBytes($tmp, $bytes)
    [IO.File]::Replace($tmp, $Path, [NullString]::Value)
}

function Get-EsSettingElement([Xml.XmlDocument] $Doc) {
    @($Doc.DocumentElement.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $_.HasAttribute('name') })
}

# Changes (Name, Old, New, Action Add|Change) that es_settings.cfg needs.
function Get-LightgunEsSettingsPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $doc = Read-LightgunXml $Path
    $byName = @{}
    foreach ($e in Get-EsSettingElement $doc) { $byName[$e.GetAttribute('name')] = $e }
    $target = Get-LightgunEsSettingsTarget
    foreach ($name in $target.Keys) {
        $want = $target[$name]
        if ($byName.ContainsKey($name)) {
            $old = $byName[$name].GetAttribute('value')
            if ($old -cne $want) { [pscustomobject]@{ File = $Path; Name = $name; Old = $old; New = $want; Action = 'Change' } }
        } else { [pscustomobject]@{ File = $Path; Name = $name; Old = $null; New = $want; Action = 'Add' } }
    }
}

# Writes the plan into es_settings.cfg (backup first, guarded programs closed). Returns the change count.
function Set-LightgunEsSettings {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [string] $Path)
    $plan = @(Get-LightgunEsSettingsPlan -Path $Path)
    if (-not $plan) { return 0 }
    if (-not $PSCmdlet.ShouldProcess($Path, "$($plan.Count) setting(s)")) { return 0 }
    $doc = Read-LightgunXml $Path
    $root = $doc.DocumentElement
    foreach ($c in $plan) {
        $existing = @(Get-EsSettingElement $doc | Where-Object { $_.GetAttribute('name') -ceq $c.Name }) | Select-Object -First 1
        if ($existing) { $existing.SetAttribute('value', $c.New); continue }
        $new = $doc.CreateElement('string')
        $new.SetAttribute('name', $c.Name)
        $new.SetAttribute('value', $c.New)
        $elements = Get-EsSettingElement $doc
        $after = @($elements | Where-Object { [string]::CompareOrdinal($_.GetAttribute('name'), $c.Name) -gt 0 }) | Select-Object -First 1
        $indent = $null
        foreach ($n in $root.ChildNodes) { if ($n.NodeType -eq 'Whitespace' -and $n.NextSibling -and $n.NextSibling.NodeType -eq 'Element') { $indent = $n.Value; break } }
        if (-not $indent) { $indent = "`n  " }
        if ($after) {
            $null = $root.InsertBefore($new, $after)
            $null = $root.InsertBefore($doc.CreateWhitespace($indent), $after)
        } else {
            $last = if ($elements) { $elements[-1] } else { $null }
            if ($last) {
                $null = $root.InsertAfter($new, $last)
                $null = $root.InsertAfter($doc.CreateWhitespace($indent), $last)
            } else {
                $null = $root.AppendChild($doc.CreateWhitespace($indent))
                $null = $root.AppendChild($new)
                $null = $root.AppendChild($doc.CreateWhitespace("`n"))
            }
        }
    }
    Assert-LightgunProcessesClosed
    $null = Backup-LightgunFile -Path $Path
    Save-LightgunXml $doc $Path
    $plan.Count
}

# Per-game entries of the gun systems that overrule the system settings (reported only).
function Get-LightgunEsOverride {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $doc = Read-LightgunXml $Path
    $systems = ($script:LightgunGunSystems | ForEach-Object { [regex]::Escape($_) }) -join '|'
    foreach ($e in Get-EsSettingElement $doc) {
        $n = $e.GetAttribute('name')
        if ($n -match "^($systems)\[`"(.+)`"\]\.(use_guns|emulator|core)$") {
            $v = $e.GetAttribute('value')
            if ($Matches[3] -eq 'use_guns' -and $v -eq '0') { continue }
            [pscustomobject]@{ System = $Matches[1]; Game = $Matches[2]; Key = $Matches[3]; Value = $v }
        }
    }
}

# Games of the gun systems whose gamelist.xml hard-wires an <emulator>/<core> OTHER than the kit's choice for
# the system (reported only; an entry that names the same emulator changes nothing).
function Get-LightgunGamelistOverride {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RetroBatRoot)
    $target = Get-LightgunEsSettingsTarget
    foreach ($s in $script:LightgunGunSystems) {
        $wantEmu = if ($target.Contains("$s.emulator")) { $target["$s.emulator"] } else { $null }
        $wantCore = if ($target.Contains("$s.core")) { $target["$s.core"] } else { $null }
        $file = Join-Path $RetroBatRoot "roms\$s\gamelist.xml"
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        try { $doc = Read-LightgunXml $file } catch { Write-KitLog "$file`: $($_.Exception.Message)" -Level Warn; continue }
        foreach ($g in @($doc.SelectNodes('/gameList/game'))) {
            $emu = $g.SelectSingleNode('emulator'); $core = $g.SelectSingleNode('core')
            if ($emu -or $core) {
                $same = $wantEmu -and $emu -and $emu.InnerText -eq $wantEmu -and (-not $core -or $core.InnerText -eq $wantCore)
                if ($same) { continue }
                $path = $g.SelectSingleNode('path')
                [pscustomobject]@{
                    System = $s; Game = if ($path) { $path.InnerText } else { '' }
                    Emulator = if ($emu) { $emu.InnerText } else { '' }; Core = if ($core) { $core.InnerText } else { '' }
                }
            }
        }
    }
}

function Get-XboxBlock([Xml.XmlDocument] $Doc) {
    @($Doc.DocumentElement.ChildNodes | Where-Object { $_.NodeType -eq 'Element' -and $_.GetAttribute('deviceName') -eq $script:LightgunXboxName -and $_.GetAttribute('type') -eq 'joystick' }) | Select-Object -First 1
}

# Differences of the Xbox block (Name, Old, New); the whole block is missing -> one row 'block'.
function Get-LightgunEsInputPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $block = Get-XboxBlock (Read-LightgunXml $Path)
    if (-not $block) { return [pscustomobject]@{ File = $Path; Name = 'block'; Old = $null; New = $script:LightgunXboxName; Action = 'Add' } }
    $have = @{}
    foreach ($i in @($block.ChildNodes | Where-Object { $_.NodeType -eq 'Element' })) { $have[$i.GetAttribute('name')] = '{0} {1} {2}' -f $i.GetAttribute('type'), $i.GetAttribute('id'), $i.GetAttribute('value') }
    foreach ($w in $script:LightgunXboxInputs) {
        $want = '{0} {1} {2}' -f $w[1], $w[2], $w[3]
        $old = if ($have.ContainsKey($w[0])) { $have[$w[0]] } else { $null }
        if ($old -ne $want) { [pscustomobject]@{ File = $Path; Name = $w[0]; Old = $old; New = $want; Action = $(if ($old) { 'Change' } else { 'Add' }) } }
    }
}

# Rewrites the Xbox block completely (a block with only a few inputs left is the known failure) or adds it.
# The device GUID of an existing block is kept. Returns the change count.
function Set-LightgunEsInput {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [string] $Path)
    $plan = @(Get-LightgunEsInputPlan -Path $Path)
    if (-not $plan) { return 0 }
    if (-not $PSCmdlet.ShouldProcess($Path, 'Xbox 360 Controller block')) { return 0 }
    $doc = Read-LightgunXml $Path
    $root = $doc.DocumentElement
    $block = Get-XboxBlock $doc
    $outer = "`n`t"; $inner = "`n`t`t"
    if (-not $block) {
        $block = $doc.CreateElement('inputConfig')
        $block.SetAttribute('type', 'joystick')
        $block.SetAttribute('deviceName', $script:LightgunXboxName)
        $block.SetAttribute('deviceGUID', $script:LightgunXboxGuid)
        $lastElement = @($root.ChildNodes | Where-Object { $_.NodeType -eq 'Element' }) | Select-Object -Last 1
        if ($lastElement -and $lastElement.PreviousSibling -and $lastElement.PreviousSibling.NodeType -eq 'Whitespace') { $outer = $lastElement.PreviousSibling.Value; $inner = $outer + "`t" }
        if ($lastElement) { $null = $root.InsertAfter($block, $lastElement); $null = $root.InsertAfter($doc.CreateWhitespace($outer), $lastElement) }
        else { $null = $root.AppendChild($doc.CreateWhitespace($outer)); $null = $root.AppendChild($block); $null = $root.AppendChild($doc.CreateWhitespace("`n")) }
    } else {
        $ws = @($block.ChildNodes | Where-Object { $_.NodeType -eq 'Whitespace' }) | Select-Object -First 1
        if ($ws) { $inner = $ws.Value }
        $closing = $block.LastChild
        if ($closing -and $closing.NodeType -eq 'Whitespace') { $outer = $closing.Value } else { $outer = $inner -replace "`t$", '' }
        while ($block.HasChildNodes) { $null = $block.RemoveChild($block.FirstChild) }
    }
    if ($outer -notmatch "`n") { $outer = "`n" + $outer }
    foreach ($w in $script:LightgunXboxInputs) {
        $null = $block.AppendChild($doc.CreateWhitespace($inner))
        $i = $doc.CreateElement('input')
        $i.SetAttribute('name', $w[0]); $i.SetAttribute('type', $w[1]); $i.SetAttribute('id', $w[2]); $i.SetAttribute('value', $w[3])
        $null = $block.AppendChild($i)
    }
    $null = $block.AppendChild($doc.CreateWhitespace($outer))
    Assert-LightgunProcessesClosed
    $null = Backup-LightgunFile -Path $Path
    Save-LightgunXml $doc $Path
    $plan.Count
}
