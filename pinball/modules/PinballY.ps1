# PinballY: the second front end for the same tables (https://pinbally.com).
#
# What an installation actually is, measured on a real one and not guessed from another program's habits:
#   PinballY.exe                        the program. It rewrites Settings.txt when it closes.
#   Settings.txt                        the whole configuration: "Key = Value" lines with "#" comments,
#                                       UTF-8 with BOM, CRLF. NOT an INI file: there are no [Section] headers.
#   Databases\<system>\<system>.xml     one HyperList export per system: <game name="..."> with metadata
#                                       (description, manufacturer, year, rating). They contain no absolute
#                                       path at all, so a move has nothing to do in them.
#   Media\<system>\                     media, addressed by the folder NAME in SystemN.MediaDir.
#
# There is no "PinballY.ini" and no "Media Database.xml", and a plain install has no .cmd/.bat launcher:
# PinballY starts the tables itself from SystemN.Exe, SystemN.Parameters and the [TOKEN]s below.
#
# Three rules follow from that, and they are the reason this module reads line by line:
#   1. A comment line is not a setting. The help text of the file carries its own path examples (a folder such
#      as D:\Pin and a quoted program path under C:\Program). A replace over the raw text would rewrite the
#      help, not the cabinet.
#   2. A value in brackets ([PinballY], [STEAM], [TABLEPATH], [TABLEFILE]) is a token PinballY expands itself.
#      It is never a location to fix, and a drive-letter regex must not touch it.
#   3. A relative value is not an error. PinballY is portable by design: MediaPath = Media,
#      TableDatabasePath = Databases, and a SystemN.TablePath like "steamapps\common\Pinball FX3\data\steam"
#      is relative to that system's own install. Only an absolute path pins the install to one machine.
#
# Stage 1 reads only. Get-PinballYInfo answers "what is here and which of it does not exist on this
# computer"; the change that retargets the few absolute paths is a separate, later operation.

$script:PinballYExeName = 'PinballY.exe'
$script:PinballYSettingsName = 'Settings.txt'
$script:PinballYDatabaseDir = 'Databases'
$script:PinballYMediaDir = 'Media'
# The program and its helpers hold Settings.txt open; the kit never closes a program (see Process.PleaseClose).
$script:PinballYProcessNames = @('PinballY', 'PinballY Watchdog', 'PinballY Admin Mode')
# Settings keys whose value addresses something on disk.
$script:PinballYPathKeys = @('Exe', 'TablePath', 'NVRAMPath', 'RunBeforePre', 'RunBefore', 'RunAfter', 'RunAfterPost')
# Keys that are relative to the PinballY folder itself, and therefore checkable against it.
$script:PinballYRootKeys = @('MediaPath', 'TableDatabasePath', 'MediaDir', 'DatabaseDir')
$script:PinballYCompanionIni = @('PINemHi\pinemhi.ini')
$script:PinballYCompanionMaxBytes = 4MB

function Get-PinballYDriveLetter {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][string] $Path)
    if ($Path -match '^([A-Za-z]):') { return $Path.Substring(0, 1).ToUpperInvariant() }
    ''
}

function Get-PinballYMountedDrive {
    [CmdletBinding()]
    param()
    # Drive letters that answer right now. A path on a letter that is not here did not come from this
    # machine: it is a copy of an installation from another one, not a broken setting on this one.
    $mounted = @{}
    foreach ($d in [IO.DriveInfo]::GetDrives()) {
        if ($d.DriveType -eq 'Network' -or -not $d.IsReady) { continue }
        $mounted[(Get-PinballYDriveLetter -Path $d.Name)] = $true
    }
    $mounted
}

function Test-PinballYInstall {
    [CmdletBinding()]
    param([string] $Path)
    if (-not $Path) { return $false }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    (Test-Path -LiteralPath (Join-Path $Path $script:PinballYSettingsName) -PathType Leaf) -and
    (Test-Path -LiteralPath (Join-Path $Path $script:PinballYExeName) -PathType Leaf)
}

function Get-PinballYVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)
    $exe = Join-Path $Path $script:PinballYExeName
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
        return [pscustomobject]@{ Version = ''; Source = 'no executable' }
    }
    $vi = (Get-Item -LiteralPath $exe).VersionInfo
    $v = [string]$vi.ProductVersion
    if (-not $v) { $v = [string]$vi.FileVersion }
    [pscustomobject]@{ Version = $v; Source = $script:PinballYExeName }
}

function Get-PinballYSetting {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)
    $file = Join-Path $Path $script:PinballYSettingsName
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw (Get-KitText 'PinballY.NoSettings' -f $file) }
    # The same encoding helper the relocator uses, so a read and a later write agree on what the file is.
    $codePage = (Get-KitFileEncoding -Path $file).CodePage
    $encoding = [Text.Encoding]::GetEncoding($codePage)
    $bytes = [IO.File]::ReadAllBytes($file)
    $bom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $lines = [IO.File]::ReadAllLines($file, $encoding)
    $rows = New-Object Collections.Generic.List[object]
    $comment = 0; $blank = 0; $other = 0
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i]
        if ($line -match '^\s*$') { $blank++; continue }
        # A comment is kept as it is and never a setting: this is where the file's own path examples live.
        if ($line -match '^\s*#') { $comment++; continue }
        if ($line -match '^\s*([A-Za-z0-9_.\-]+)\s*=\s*(.*)$') {
            $rows.Add([pscustomobject]@{ Line = $i + 1; Key = $matches[1]; Value = $matches[2] })
            continue
        }
        $other++
    }
    [pscustomobject]@{
        File = $file; CodePage = $codePage; Bom = [bool]$bom; Lines = $lines.Length
        Comment = $comment; Blank = $blank; Unreadable = $other; Setting = $rows.ToArray()
    }
}

function Resolve-PinballYValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Root,
        [Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string] $Value,
        [string] $Key = '',
        # The folder a RELATIVE value is addressed from. Not always the install root: SystemN.MediaDir names a
        # folder inside MediaPath and SystemN.DatabaseDir inside TableDatabasePath, so resolving them against the
        # root would report media as missing while it sits in front of the eyes of the cabinet owner.
        [string] $Anchor = ''
    )
    if (-not $Anchor) { $Anchor = $Root }
    $v = if ($Value) { $Value.Trim() } else { '' }
    if (-not $v) { return [pscustomobject]@{ Kind = 'empty'; Resolved = ''; Status = 'Unset'; TokenName = '' } }
    # A whole value that is one token ([STEAM]) says "the program knows where this is". Not our business.
    if ($v -match '^\[([A-Za-z][A-Za-z0-9_]*)\]$') {
        return [pscustomobject]@{ Kind = 'token'; Resolved = ''; Status = 'Token'; TokenName = $matches[1] }
    }
    # A value that STARTS with [PinballY] is relative to the install: expandable and checkable.
    if ($v -match '^\[PinballY\](.*)$') {
        $resolved = (Join-PinballPath $Root ($matches[1].TrimStart('\', '/')))
        return [pscustomobject]@{
            Kind = 'token'; Resolved = $resolved; TokenName = 'PinballY'
            Status = $(if (Test-Path -LiteralPath $resolved) { 'Present' } else { 'Missing' })
        }
    }
    if ($v -match '^\\\\') { return [pscustomobject]@{ Kind = 'unc'; Resolved = $v; Status = 'Network'; TokenName = '' } }
    if ($v -match '^[A-Za-z]:[\\/]') {
        $mounted = Get-PinballYMountedDrive
        $letter = Get-PinballYDriveLetter -Path $v
        $status = 'Present'
        if (-not (Test-Path -LiteralPath $v)) { $status = if ($mounted.ContainsKey($letter)) { 'Missing' } else { 'ForeignDrive' } }
        return [pscustomobject]@{ Kind = 'absolute'; Resolved = $v; Status = $status; TokenName = '' }
    }
    # Relative: correct for the PinballY-own folders, meaningless to check for another program's folder.
    $checkable = ($script:PinballYRootKeys -contains (($Key -split '\.')[-1]) -or $script:PinballYRootKeys -contains $Key)
    $status = 'Relative'
    $resolved = ''
    if ($checkable) {
        $resolved = Join-PinballPath $Anchor $v
        $status = if (Test-Path -LiteralPath $resolved) { 'Present' } else { 'Missing' }
    }
    [pscustomobject]@{ Kind = 'relative'; Resolved = $resolved; Status = $status; TokenName = '' }
}

function Get-PinballYSystem {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)
    $settings = Get-PinballYSetting -Path $Path
    $byNumber = @{}
    foreach ($s in $settings.Setting) {
        if ($s.Key -notmatch '^System(\d+)\.(.+)$') { continue }
        $n = [int]$matches[1]
        if (-not $byNumber.ContainsKey($n)) { $byNumber[$n] = @{} }
        $byNumber[$n][$matches[2]] = $s.Value
    }
    foreach ($n in ($byNumber.Keys | Sort-Object)) {
        $s = $byNumber[$n]
        $raw = if ($s.ContainsKey('Enabled')) { [string]$s['Enabled'] } else { '' }
        $enabled = ($raw -match '^(?i)(true|1|yes)$')
        $exe = Resolve-PinballYValue -Root $Path -Value $(if ($s.ContainsKey('Exe')) { $s['Exe'] } else { '' }) -Key 'SystemN.Exe'
        [pscustomobject]@{
            Number = $n
            Enabled = $enabled
            Class = $(if ($s.ContainsKey('Class')) { [string]$s['Class'] } else { '' })
            Process = $(if ($s.ContainsKey('Process')) { [string]$s['Process'] } else { '' })
            Exe = $(if ($s.ContainsKey('Exe')) { [string]$s['Exe'] } else { '' })
            ExeKind = $exe.Kind
            ExeStatus = $exe.Status
            ExeToken = $exe.TokenName
            TablePath = $(if ($s.ContainsKey('TablePath')) { [string]$s['TablePath'] } else { '' })
            MediaDir = $(if ($s.ContainsKey('MediaDir')) { [string]$s['MediaDir'] } else { '' })
            DatabaseDir = $(if ($s.ContainsKey('DatabaseDir')) { [string]$s['DatabaseDir'] } else { '' })
            NVRAMPath = $(if ($s.ContainsKey('NVRAMPath')) { [string]$s['NVRAMPath'] } else { '' })
            RunBeforePre = $(if ($s.ContainsKey('RunBeforePre')) { [string]$s['RunBeforePre'] } else { '' })
            RunAfter = $(if ($s.ContainsKey('RunAfter')) { [string]$s['RunAfter'] } else { '' })
            Parameters = $(if ($s.ContainsKey('Parameters')) { [string]$s['Parameters'] } else { '' })
        }
    }
}

function Get-PinballYReference {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)
    $root = (ConvertTo-PinballRoot $Path)
    $settings = Get-PinballYSetting -Path $root
    # PinballY keeps its own anchors inside the settings: media folders live in MediaPath, table databases in
    # TableDatabasePath. Both may be relative to the install or absolute, so the anchor is resolved the same way.
    $media = ''; $database = ''
    foreach ($s in $settings.Setting) {
        if ($s.Key -eq 'MediaPath') { $media = $s.Value.Trim() }
        if ($s.Key -eq 'TableDatabasePath') { $database = $s.Value.Trim() }
    }
    $mediaAnchor = if (-not $media) { $root } elseif ($media -match '^[A-Za-z]:[\\/]') { $media } else { Join-PinballPath $root $media }
    $dbAnchor = if (-not $database) { $root } elseif ($database -match '^[A-Za-z]:[\\/]') { $database } else { Join-PinballPath $root $database }
    $rows = New-Object Collections.Generic.List[object]
    foreach ($s in $settings.Setting) {
        $leaf = ($s.Key -split '\.')[-1]
        $isPathKey = ($script:PinballYPathKeys -contains $leaf -or $script:PinballYRootKeys -contains $leaf)
        $hasDrive = ($s.Value -match '[A-Za-z]:[\\/]')
        if (-not $isPathKey -and -not $hasDrive) { continue }
        $anchor = switch ($leaf) { 'MediaDir' { $mediaAnchor } 'DatabaseDir' { $dbAnchor } default { $root } }
        $r = Resolve-PinballYValue -Root $root -Value $s.Value -Key $s.Key -Anchor $anchor
        if ($r.Kind -eq 'empty') { continue }
        $rows.Add([pscustomobject]@{
            Line = $s.Line; Key = $s.Key; Value = $s.Value; Kind = $r.Kind; Status = $r.Status
            TokenName = $r.TokenName; Anchor = $anchor; Resolved = $r.Resolved
        })
    }
    $rows.ToArray()
}

function Get-PinballYDatabase {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)
    $dir = Join-Path $Path $script:PinballYDatabaseDir
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return @() }
    $rows = New-Object Collections.Generic.List[object]
    foreach ($f in (Get-ChildItem -LiteralPath $dir -Recurse -Filter '*.xml' -File | Sort-Object FullName)) {
        $games = 0; $drives = 0; $error = ''
        $text = ''
        try {
            $text = [IO.File]::ReadAllText($f.FullName, [Text.Encoding]::UTF8)
            # An absolute path in a table database would be the one thing that has to be rewritten there.
            $drives = @([regex]::Matches($text, '[A-Za-z]:[\\/]')).Count
            [xml] $x = $text
            $games = @($x.SelectNodes('//game')).Count
        } catch { $error = $_.Exception.Message }
        $rows.Add([pscustomobject]@{
            System = $f.Directory.Name; File = $f.Name; Games = $games
            AbsolutePath = $drives; ParseError = $error
        })
    }
    $rows.ToArray()
}

function Get-PinballYCompanion {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)
    # Other programs living INSIDE the PinballY folder, with configuration of their own. An adapter that
    # only knows PinballY's files leaves them pointing at the old machine.
    $rows = New-Object Collections.Generic.List[object]
    foreach ($rel in $script:PinballYCompanionIni) {
        $file = Join-Path $Path $rel
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        if ((Get-Item -LiteralPath $file).Length -gt $script:PinballYCompanionMaxBytes) { continue }
        $hits = @([IO.File]::ReadAllLines($file, [Text.Encoding]::Default) |
            Where-Object { $_ -notmatch '^\s*#' -and $_ -match '[A-Za-z]:[\\/]' })
        $broken = 0
        foreach ($h in $hits) {
            $m = [regex]::Match($h, '([A-Za-z]:[\\/][^"'';|]*?)(?=["'';|\s]|$)')
            if ($m.Success -and -not (Test-Path -LiteralPath $m.Value)) { $broken++ }
        }
        $rows.Add([pscustomobject]@{
            File = $rel; PathLine = $hits.Count; Broken = $broken
            Sample = $(if ($hits.Count) { [string]$hits[0] } else { '' })
        })
    }
    $rows.ToArray()
}

function Get-PinballYProcess {
    [CmdletBinding()]
    param()
    @(Test-KitProcessesClosed -Names $script:PinballYProcessNames | ForEach-Object { $_.Name } | Sort-Object -Unique)
}

function Assert-PinballYProcessesClosed {
    [CmdletBinding()]
    param()
    $running = @(Get-PinballYProcess)
    if ($running.Count) { throw (Get-KitText 'Process.PleaseClose' -f ($running -join ', ')) }
}

function Get-PinballYInfo {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)
    $root = (ConvertTo-PinballRoot $Path)
    if (-not (Test-PinballYInstall -Path $root)) {
        $why = if (-not (Test-Path -LiteralPath $root -PathType Container)) { 'no folder' }
               elseif (-not (Test-Path -LiteralPath (Join-Path $root $script:PinballYSettingsName) -PathType Leaf)) { $script:PinballYSettingsName }
               else { $script:PinballYExeName }
        throw (Get-KitText 'PinballY.NotAnInstall' -f $root, $why)
    }
    $settings = Get-PinballYSetting -Path $root
    $refs = @(Get-PinballYReference -Path $root)
    $systems = @(Get-PinballYSystem -Path $root)
    $databases = @(Get-PinballYDatabase -Path $root)
    $companions = @(Get-PinballYCompanion -Path $root)
    $version = Get-PinballYVersion -Path $root
    # @() is required, not decoration: a function that returns an empty array hands back $null through the
    # pipeline, and under Set-StrictMode -Version 2.0 a property of $null is an error, not an empty list.
    $running = @(Get-PinballYProcess)
    $missing = @($refs | Where-Object { $_.Status -eq 'Missing' })
    $foreign = @($refs | Where-Object { $_.Status -eq 'ForeignDrive' })
    # Counted by kind, not by status: [PinballY]\Farsight IS a token even though it resolves to a folder that
    # exists. Sorting by status would hide half of the values the kit must never rewrite.
    $tokens = @($refs | Where-Object { $_.Kind -eq 'token' })
    $absolute = @($refs | Where-Object { $_.Kind -eq 'absolute' })
    [pscustomobject]@{
        Root = $root
        Version = $version.Version
        VersionSource = $version.Source
        Encoding = $(if ($settings.Bom) { 'utf-8-bom' } else { 'utf-8' })
        SettingsLine = $settings.Lines
        SettingsComment = $settings.Comment
        Setting = $settings.Setting.Count
        System = $systems
        SystemEnabled = @($systems | Where-Object { $_.Enabled }).Count
        Reference = $refs
        ReferenceAbsolute = $absolute.Count
        ReferenceToken = $tokens.Count
        ReferenceMissing = $missing
        ReferenceForeign = $foreign
        Database = $databases
        Game = $(@($databases | ForEach-Object { $_.Games } | Measure-Object -Sum).Sum)
        Companion = $companions
        Running = $running
        WriteSafe = ($running.Count -eq 0)
        Detail = (Get-KitText 'PinballY.Summary' -f $version.Version, $root,
            @($systems | Where-Object { $_.Enabled }).Count, $settings.Setting.Count,
            $refs.Count, $missing.Count, $foreign.Count)
    }
}
