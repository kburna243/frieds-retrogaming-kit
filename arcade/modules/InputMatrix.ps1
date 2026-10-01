# Input matrix: one button layout for the whole cabinet, translated into each emulator's own format.
# A profile maps what the player wants (MAME port types: START1, COIN1, P1_BUTTON1, P2_JOYSTICK_UP ...)
# to what the panel sends (KEY_LCONTROL, JOY1_BUTTON2, MOUSE1_BUTTON1, NONE). Change the panel, change
# one profile; the dialect writers do the rest. MAME (a ctrlr file) is the first dialect.
#
# RetroBat rewrites controller files at every game start unless its automatic is off for the system, and
# it writes retrobat_auto.cfg itself. So the matrix only writes a ctrlr file of its own, never a file it
# did not write (custom1.cfg holds the gun layout), and the plan says which es_settings keys make RetroBat
# load it. It does not change es_settings: the lightgun suite owns those keys.

$script:InputMarker = 'kit:input-matrix'
# Own profiles live next to the user's presets. A variable, not a re-read of USERPROFILE, so tests point it
# elsewhere without bending the environment other modules cache paths from.
$script:InputUserDir = Join-Path $env:USERPROFILE 'RetroCabinet\InputProfiles'

function Get-ArcadeInputProfileDir {
    [CmdletBinding()]
    param()
    @((Join-Path $script:ArcadeDir 'input-profiles'), $script:InputUserDir)
}

# Intents are MAME port types: the most complete arcade vocabulary there is, and the other dialects map from it.
function Test-ArcadeInputIntent([string] $Intent) {
    $Intent -cmatch '^(START[1-8]|COIN[1-8]|SERVICE[1-4]?|TILT|P[1-8]_(JOYSTICK|JOYSTICKLEFT|JOYSTICKRIGHT)_(UP|DOWN|LEFT|RIGHT)|P[1-8]_BUTTON([1-9]|1[0-6])|P[1-8]_(START|SELECT)|P[1-8]_(LIGHTGUN|AD_STICK)_[XYZ]|UI_[A-Z_]+)$'
}

# One generic source -> MAME code. Unknown names are an error, never a silent drop: a typo would leave a
# button dead on the cabinet with nobody knowing why.
function ConvertTo-ArcadeMameCode {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Source)
    $keys = '^(?:[A-Z]|[0-9]|F([1-9]|1[0-5])|UP|DOWN|LEFT|RIGHT|[LR](CONTROL|ALT|SHIFT|WIN)|SPACE|ENTER|ESC|TAB|BACKSPACE|INSERT|DEL|HOME|END|PGUP|PGDN|MINUS|EQUALS|OPENBRACE|CLOSEBRACE|COLON|QUOTE|BACKSLASH|COMMA|STOP|SLASH|TILDE|[0-9]_PAD|(PLUS|MINUS|SLASH|ASTERISK|DEL|ENTER)_PAD|PRTSCR|PAUSE|MENU)$'
    if ($Source -ceq 'NONE') { return 'NONE' }
    # A+B: both pressed together (MAME writes the codes side by side), e.g. JOY1_SELECT+JOY1_START.
    if ($Source.Contains('+')) { return (@($Source.Split('+') | ForEach-Object { ConvertTo-ArcadeMameCode $_ }) -join ' ') }
    if ($Source -cmatch '^KEY_(.+)$') {
        $key = $Matches[1]   # the next -cmatch overwrites $Matches
        if ($key -cmatch $keys) { return "KEYCODE_$key" }
    }
    if ($Source -cmatch '^JOY([1-8])_BUTTON([1-9]|[1-3][0-9])$') { return "JOYCODE_$($Matches[1])_BUTTON$($Matches[2])" }
    if ($Source -cmatch '^JOY([1-8])_(START|SELECT)$') { return "JOYCODE_$($Matches[1])_$($Matches[2])" }
    if ($Source -cmatch '^JOY([1-8])_(UP|DOWN|LEFT|RIGHT)$') {
        $axis = @{ UP = 'YAXIS_UP_SWITCH'; DOWN = 'YAXIS_DOWN_SWITCH'; LEFT = 'XAXIS_LEFT_SWITCH'; RIGHT = 'XAXIS_RIGHT_SWITCH' }
        return "JOYCODE_$($Matches[1])_$($axis[$Matches[2]])"
    }
    if ($Source -cmatch '^JOY([1-8])_HAT_(UP|DOWN|LEFT|RIGHT)$') { return "JOYCODE_$($Matches[1])_HAT1$($Matches[2])" }
    # XInput pads (Gunmote's Wiimotes): the d-pad and the analog axes the gun aims with.
    if ($Source -cmatch '^JOY([1-8])_DPAD_(UP|DOWN|LEFT|RIGHT)$') { return "JOYCODE_$($Matches[1])_DPAD$($Matches[2])" }
    if ($Source -cmatch '^JOY([1-8])_(R?[XYZ])AXIS$') { return "JOYCODE_$($Matches[1])_$($Matches[2])AXIS" }
    if ($Source -cmatch '^MOUSE([1-8])_BUTTON([1-9])$') { return "MOUSECODE_$($Matches[1])_BUTTON$($Matches[2])" }
    throw "Unknown input source '$Source' (KEY_<name>, JOY<n>_BUTTON<m>, JOY<n>_UP/DOWN/LEFT/RIGHT, JOY<n>_HAT_<dir>, JOY<n>_DPAD_<dir>, JOY<n>_XAXIS/YAXIS/ZAXIS/RXAXIS/RYAXIS/RZAXIS, JOY<n>_START/SELECT, MOUSE<n>_BUTTON<m>, NONE, A+B)"
}

# Profiles: Get-ArcadeInputProfile lists them; -Name returns one with its mapping (intent -> sources[]).
# A user profile of the same name wins over the built-in one. ConvertFrom-Json (PS 5.1, no -AsHashtable)
# gives a PSCustomObject; the mapping is read from its properties.
function Get-ArcadeInputProfile {
    [CmdletBinding()]
    param([string] $Name = '')
    $found = [ordered]@{}
    $builtinDir = (Get-ArcadeInputProfileDir)[0]
    foreach ($dir in Get-ArcadeInputProfileDir) {
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
        foreach ($f in Get-ChildItem -LiteralPath $dir -Filter '*.json' -File | Sort-Object Name) { $found[$f.BaseName] = $f }
    }
    $names = if ($Name) { @($Name) } else { @($found.Keys) }
    foreach ($n in $names) {
        if (-not $found.Contains($n)) { throw "Input profile '$n' not found (folders: $((Get-ArcadeInputProfileDir) -join ', '))" }
        $f = $found[$n]
        try { $json = [IO.File]::ReadAllText($f.FullName) | ConvertFrom-Json } catch { throw "Input profile '$n' is not valid JSON: $($_.Exception.Message)" }
        if (-not $json.PSObject.Properties['Mapping']) { throw "Input profile '$n' has no Mapping" }
        $mapping = [ordered]@{}
        foreach ($prop in $json.Mapping.PSObject.Properties) {
            if (-not (Test-ArcadeInputIntent $prop.Name)) { throw "Input profile '$n': unknown intent '$($prop.Name)' (MAME port types: START1, COIN1, P1_BUTTON1, P2_JOYSTICK_UP ...)" }
            $sources = @($prop.Value | ForEach-Object { [string]$_ } | Where-Object { $_ })
            if (-not $sources.Count) { throw "Input profile '$n': intent '$($prop.Name)' has no source" }
            foreach ($s in $sources) { $null = ConvertTo-ArcadeMameCode $s }   # validates
            $mapping[$prop.Name] = $sources
        }
        [pscustomobject]@{
            Name        = $n
            Description = if ($json.PSObject.Properties['Description']) { [string]$json.Description } else { '' }
            Builtin     = $f.DirectoryName -eq $builtinDir
            Path        = $f.FullName
            Mapping     = $mapping
        }
    }
}

# The ctrlr file the profile becomes. Kit-owned: the marker comment is what lets a later run overwrite it.
function ConvertTo-ArcadeMameCtrlr {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $InputProfile)
    $sb = New-Object Text.StringBuilder
    $null = $sb.Append("<?xml version=`"1.0`"?>`r`n<mameconfig version=`"10`">`r`n`t<system name=`"default`">`r`n")
    $null = $sb.Append("`t`t<!-- $script:InputMarker profile=$($InputProfile.Name). Written by Fried's Retrogaming Kit: change the profile, not this file. -->`r`n")
    $null = $sb.Append("`t`t<input>`r`n")
    foreach ($intent in $InputProfile.Mapping.Keys) {
        $seq = (@($InputProfile.Mapping[$intent] | ForEach-Object { ConvertTo-ArcadeMameCode $_ })) -join ' OR '
        $null = $sb.Append("`t`t`t<port type=`"$intent`">`r`n`t`t`t`t<newseq type=`"standard`">$seq</newseq>`r`n`t`t`t</port>`r`n")
    }
    $null = $sb.Append("`t`t</input>`r`n`t</system>`r`n</mameconfig>`r`n")
    $sb.ToString()
}

# Port -> sequence of the default block of an existing ctrlr file (for Old values in the plan).
function Read-ArcadeMameCtrlrPorts([string] $Path) {
    $ports = @{}
    $settings = New-Object Xml.XmlReaderSettings
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $reader = [Xml.XmlReader]::Create($Path, $settings)
    try { $doc = New-Object Xml.XmlDocument; $doc.XmlResolver = $null; $doc.Load($reader) } finally { $reader.Dispose() }
    foreach ($port in $doc.SelectNodes("/mameconfig/system[@name='default']/input/port")) {
        $seq = $port.SelectSingleNode('newseq')
        if ($seq) { $ports[$port.GetAttribute('type')] = $seq.InnerText.Trim() }
    }
    $ports
}

# What RetroBat must have set so MAME loads <CtrlrName>.cfg: standalone MAME and the ctrlr profile name.
# (mame.disableautocontrollers is not needed: the cabinet loads custom1.cfg without it.)
# Read only; missing keys and other values come back as warnings.
function Get-ArcadeMameRetroBatWarnings([string] $RetroBatRoot, [string] $CtrlrName) {
    $esPath = Join-Path $RetroBatRoot 'emulationstation\.emulationstation\es_settings.cfg'
    if (-not (Test-Path -LiteralPath $esPath -PathType Leaf)) { return @("es_settings.cfg not found ($esPath): RetroBat's MAME settings could not be checked") }
    $values = @{}
    $settings = New-Object Xml.XmlReaderSettings
    $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
    $settings.XmlResolver = $null
    $settings.ConformanceLevel = [Xml.ConformanceLevel]::Fragment   # es_settings.cfg has no single root in every version
    $reader = [Xml.XmlReader]::Create($esPath, $settings)
    try {
        while ($reader.Read()) {
            if ($reader.NodeType -eq [Xml.XmlNodeType]::Element -and $reader.GetAttribute('name')) { $values[$reader.GetAttribute('name')] = $reader.GetAttribute('value') }
        }
    } finally { $reader.Dispose() }
    $want = [ordered]@{ 'mame.emulator' = 'mame64'; 'mame.mame_ctrlr_profile' = $CtrlrName }
    $warnings = @()
    foreach ($k in $want.Keys) {
        $have = if ($values.ContainsKey($k)) { [string]$values[$k] } else { '' }
        if ($have -ne $want[$k]) {
            $warnings += "es_settings.cfg: $k is '$have', RetroBat loads $CtrlrName.cfg only with '$($want[$k])'"
        }
    }
    $warnings
}

# The plan: target file, port changes (Port, Old, New) and the RetroBat warnings. Refuses a file the kit did
# not write and RetroBat's own retrobat_auto.cfg.
function Get-ArcadeInputMatrixPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ProfileName,
        [string] $CtrlrName = '',
        [string] $RetroBatRoot = (Get-ArcadeRetroBatRoot)
    )
    if (-not $RetroBatRoot) { throw 'RetroBat folder unknown: pass -RetroBatRoot or run the lightgun detect step first.' }
    $prof = Get-ArcadeInputProfile -Name $ProfileName
    if (-not $CtrlrName) { $CtrlrName = "kit-$ProfileName" }
    if ($CtrlrName -notmatch '^[A-Za-z0-9_.-]+$') { throw "Ctrlr name '$CtrlrName' may only hold letters, digits, '.', '_' and '-'" }
    if ($CtrlrName -eq 'retrobat_auto') { throw 'retrobat_auto.cfg is written by RetroBat itself at every start; pick another name' }
    $target = Join-Path $RetroBatRoot "saves\mame\ctrlr\$CtrlrName.cfg"
    $content = ConvertTo-ArcadeMameCtrlr -InputProfile $prof
    $old = @{}
    $exists = Test-Path -LiteralPath $target -PathType Leaf
    if ($exists) {
        if (-not ([IO.File]::ReadAllText($target)).Contains($script:InputMarker)) {
            throw "$target was not written by the kit (it may hold a hand-made layout, like custom1.cfg with the guns); pick another -CtrlrName"
        }
        $old = Read-ArcadeMameCtrlrPorts $target
    }
    $changes = @()
    foreach ($intent in $prof.Mapping.Keys) {
        $new = (@($prof.Mapping[$intent] | ForEach-Object { ConvertTo-ArcadeMameCode $_ })) -join ' OR '
        $was = if ($old.ContainsKey($intent)) { $old[$intent] } else { $null }
        if ($was -ne $new) { $changes += [pscustomobject]@{ Port = $intent; Old = $was; New = $new } }
    }
    foreach ($gone in @($old.Keys | Where-Object { -not $prof.Mapping.Contains($_) })) {
        $changes += [pscustomobject]@{ Port = $gone; Old = $old[$gone]; New = $null }
    }
    [pscustomobject]@{
        Profile  = $prof.Name
        Target   = $target
        Exists   = $exists
        Changes  = $changes
        Content  = $content
        Warnings = @(Get-ArcadeMameRetroBatWarnings -RetroBatRoot $RetroBatRoot -CtrlrName $CtrlrName)
    }
}

# Writes the plan's file. Without changes nothing is written; an existing kit file goes into a ZIP backup first.
# Returns the plan with Backup (path or $null) and Written.
function Set-ArcadeInputMatrix {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $ProfileName,
        [string] $CtrlrName = '',
        [string] $RetroBatRoot = (Get-ArcadeRetroBatRoot),
        [string] $BackupDir = ''
    )
    $plan = Get-ArcadeInputMatrixPlan -ProfileName $ProfileName -CtrlrName $CtrlrName -RetroBatRoot $RetroBatRoot
    $backup = $null; $written = $false
    if (@($plan.Changes).Count -and $PSCmdlet.ShouldProcess($plan.Target, "write MAME ctrlr from input profile $ProfileName")) {
        if ($plan.Exists) {
            if (-not $BackupDir) { $BackupDir = Join-Path (Split-Path -Parent (Get-ArcadeDefaultStatePath)) 'backups' }
            $stamp = '{0:yyyyMMdd-HHmmss}' -f (Get-Date)
            $zip = Join-Path $BackupDir "input-matrix_$stamp.zip"
            for ($n = 2; Test-Path -LiteralPath $zip; $n++) { $zip = Join-Path $BackupDir "input-matrix_$stamp-$n.zip" }
            $backup = (New-KitBackup -Files @($plan.Target) -Destination $zip).Path
        }
        $dir = Split-Path -Parent $plan.Target
        if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
        [IO.File]::WriteAllText($plan.Target, $plan.Content, (New-Object Text.UTF8Encoding $false))
        $written = $true
    }
    $plan | Add-Member -NotePropertyName Backup -NotePropertyValue $backup -PassThru |
        Add-Member -NotePropertyName Written -NotePropertyValue $written -PassThru
}
