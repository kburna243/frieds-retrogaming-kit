# DMD audit: do the table sections of VPinMAME's DmdDevice.ini fit the tables they are meant for?
#
# A table section ([<cGameName>]) may move the virtual DMD to a small strip or switch it off. Both only make
# sense when the table really loads a PuP pack: then the PuP pack fills the FullDMD screen (strip) or even
# draws the score itself (off). A table without an active PuP pack gets the strip anyway when somebody copied
# the section from another build - and the front end's menu video stays visible around the strip, or, with
# the DMD switched off, is all that is left. Measured on a cabinet: 40 of 96 strip sections were like that.
#
# What the audit reads, and only reads:
#   - DmdDevice.ini, its table sections with virtualdmd keys (the global [virtualdmd] is never a finding)
#   - every table's script, straight out of the .vpx (OLE storage GameStg, stream GameData) - opened for
#     reading only, never through VPX, never by writing a .vbs next to the table (VPX would load that one
#     instead of the table's own script)
#   - the folder names under PUPVideos (a pack whose name has dashes appended is switched off on purpose
#     and does not count)
#
# The verdict per section: Ok, NoPup (the change candidate), Mixed (one section, tables with different
# answers - never touched), Orphan (no table carries that name - harmless, never touched), Unclear (a table
# could not be read, or the answer needs a person). The repair removes only the virtualdmd lines of NoPup
# sections, after a ZIP backup, with the plan checked again against the file as it is at that moment.

$script:PinballDmdKeys = 'enabled', 'left', 'top', 'width', 'height'

if (-not ('RetroCabinetKit.VpxScript' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;

namespace RetroCabinetKit {
    [ComImport, Guid("0000000b-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    internal interface IVpxStorage {
        void CreateStream();
        [PreserveSig] int OpenStream([MarshalAs(UnmanagedType.LPWStr)] string name, IntPtr reserved1, uint mode, uint reserved2, out IStream stream);
        void CreateStorage();
        [PreserveSig] int OpenStorage([MarshalAs(UnmanagedType.LPWStr)] string name, IntPtr priority, uint mode, IntPtr exclude, uint reserved, out IVpxStorage storage);
    }

    // Reads the script stream of a Visual Pinball table. STGM_READ only: the file is never opened for writing.
    public static class VpxScript {
        const uint ReadDenyWrite = 0x00000020;   // STGM_READ | STGM_SHARE_DENY_WRITE (root)
        const uint ReadExclusive = 0x00000010;   // STGM_READ | STGM_SHARE_EXCLUSIVE (children must use it)

        [DllImport("ole32.dll")]
        static extern int StgOpenStorage([MarshalAs(UnmanagedType.LPWStr)] string name, IntPtr priority, uint mode, IntPtr exclude, uint reserved, out IVpxStorage storage);

        public static byte[] ReadGameData(string path) {
            IVpxStorage root;
            int hr = StgOpenStorage(path, IntPtr.Zero, ReadDenyWrite, IntPtr.Zero, 0, out root);
            if (hr != 0) hr = StgOpenStorage(path, IntPtr.Zero, ReadExclusive, IntPtr.Zero, 0, out root);
            if (hr != 0) throw new InvalidOperationException("open 0x" + hr.ToString("X8"));
            IVpxStorage game = null; IStream stream = null;
            try {
                hr = root.OpenStorage("GameStg", IntPtr.Zero, ReadExclusive, IntPtr.Zero, 0, out game);
                if (hr != 0) throw new InvalidOperationException("GameStg 0x" + hr.ToString("X8"));
                hr = game.OpenStream("GameData", IntPtr.Zero, ReadExclusive, 0, out stream);
                if (hr != 0) throw new InvalidOperationException("GameData 0x" + hr.ToString("X8"));
                System.Runtime.InteropServices.ComTypes.STATSTG stat;
                stream.Stat(out stat, 1);
                byte[] buffer = new byte[stat.cbSize];
                IntPtr read = Marshal.AllocHGlobal(4);
                try { stream.Read(buffer, buffer.Length, read); } finally { Marshal.FreeHGlobal(read); }
                return buffer;
            } finally {
                if (stream != null) Marshal.ReleaseComObject(stream);
                if (game != null) Marshal.ReleaseComObject(game);
                Marshal.ReleaseComObject(root);
            }
        }
    }
}
'@
}

# --- table scripts -----------------------------------------------------------------------------------------

# The facts the verdict needs, from the script text alone (no file access: testable with any string).
# Comment lines are skipped; VBScript has no block comments.
function Get-PinballTableScriptFact {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Text)
    $gameNames = New-Object Collections.Generic.List[string]
    $packNames = New-Object Collections.Generic.List[string]
    $switch = ''
    $assign = New-Object Collections.Generic.List[object]
    $count = @{ PuPlayer = 0; PDmdStartUp = 0; FlexDmd = 0; UltraDmd = 0 }
    foreach ($raw in $Text -split '\r?\n') {
        $line = $raw.Trim()
        if (-not $line -or $line.StartsWith("'") -or $line -match '^(?i)rem\s') { continue }
        if ($line -match '(?i)^(?:(?:const|dim|private|public)\s+)?(?:\w+\s*:\s*)?cGameName\s*=\s*"([^"]+)"') {
            if (-not $gameNames.Contains($Matches[1])) { $gameNames.Add($Matches[1]) }
        }
        foreach ($m in [regex]::Matches($line, '(?i)\b(?:pGameName|cPuPPack|PuPPackName)\s*=\s*"([^"]+)"')) {
            if (-not $packNames.Contains($m.Groups[1].Value)) { $packNames.Add($m.Groups[1].Value) }
        }
        # Every assignment of a PuP switch at the start of a line (comparisons sit behind an If and do not
        # match). The DMD driver type is a mode, not a switch.
        if ($line -match '(?i)^(const\s+|dim\s+)?(?:\w+\s*:\s*)?((?:b?use|b?enable|has)\w*pup\w*)\s*=\s*(true|false|1|0)\b' -and
            $Matches[2] -notmatch '(?i)driver') {
            # Groups first: every further -match overwrites $Matches.
            $decl = [string]$Matches[1]; $name = $Matches[2]; $value = $Matches[3]
            if (-not $switch) { $switch = $name }
            if ($name -eq $switch) {
                $assign.Add([pscustomobject]@{ Const = ($decl -match '(?i)const'); On = ($value -match '^(?i:true|1)$') })
            }
        }
        $count.PuPlayer    += [regex]::Matches($line, '(?i)PuPlayer').Count
        $count.PDmdStartUp += [regex]::Matches($line, '(?i)pDMDStartUP').Count
        $count.FlexDmd     += [regex]::Matches($line, '(?i)FlexDMD').Count
        $count.UltraDmd    += [regex]::Matches($line, '(?i)UltraDMD').Count
    }
    # The first switch the script assigns decides, read three ways: a Const is the table's setting; a
    # variable that gets True AND False is detected at run time ("bUsePUPDMD = False ... when PinUP is there
    # bUsePUPDMD = True"), so the PuP code and the pack decide (auto); a single value is the setting.
    $on = $null
    $switchText = ''
    if ($switch) {
        $const = @($assign | Where-Object { $_.Const })
        $values = @($assign | ForEach-Object { $_.On } | Select-Object -Unique)
        if ($const.Count) { $on = $const[0].On }
        elseif ($values.Count -eq 1) { $on = $values[0] }
        $switchText = '{0}={1}' -f $switch, $(if ($null -eq $on) { 'auto' } elseif ($on) { 'True' } else { 'False' })
    }
    [pscustomobject]@{
        GameName    = @($gameNames.ToArray())
        PackName    = @($packNames.ToArray())
        PupSwitch   = $switchText
        PupSwitchOn = $on
        PuPlayer    = $count.PuPlayer
        PDmdStartUp = $count.PDmdStartUp
        FlexDmd     = $count.FlexDmd
        UltraDmd    = $count.UltraDmd
    }
}

# One table: its file name and the facts, or the reason it could not be read (a table VPX holds open, a file
# that is not an OLE storage). Western code page, as VPX stores the script.
function Read-PinballTableScript {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $full = Resolve-PinballFullPath $Path
    try {
        $bytes = [RetroCabinetKit.VpxScript]::ReadGameData($full)
        $fact = Get-PinballTableScriptFact -Text ([Text.Encoding]::GetEncoding(1252).GetString($bytes))
        $fact | Add-Member -NotePropertyName Table -NotePropertyValue (Split-Path -Leaf $full)
        $fact | Add-Member -NotePropertyName Error -NotePropertyValue ''
        $fact
    } catch {
        $msg = if ($_.Exception.InnerException) { $_.Exception.InnerException.Message } else { $_.Exception.Message }
        # STG_E_FILEALREADYEXISTS is what OLE answers for a file that is no storage at all; the share
        # violations mean another program (VPX, an editor) holds the table open.
        if ($msg -match '0x80030050') { $msg = Get-KitText 'Pinball.DmdAudit.NotStorage' }
        elseif ($msg -match '0x8003002[01]') { $msg = Get-KitText 'Pinball.DmdAudit.InUse' }
        [pscustomobject]@{
            Table = (Split-Path -Leaf $full); Error = $msg; GameName = @(); PackName = @(); PupSwitch = ''
            PupSwitchOn = $null; PuPlayer = 0; PDmdStartUp = 0; FlexDmd = 0; UltraDmd = 0
        }
    }
}

# --- DmdDevice.ini ----------------------------------------------------------------------------------------

# Table sections with virtualdmd keys. Off = "virtualdmd enabled = false", Position = left/top/width/height.
# Both spellings DmdDevice accepts are read: "virtualdmd left" and "virtualdmd.left".
function Get-PinballDmdSection {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Text)
    $sections = [ordered]@{}
    $current = ''
    $n = 0
    foreach ($line in $Text -split '\r?\n') {
        $n++
        if ($line -match '^\s*\[(.+?)\]\s*$') { $current = $Matches[1].Trim(); continue }
        if (-not $current -or $current -eq 'virtualdmd') { continue }
        if ($line -match '^\s*virtualdmd[\s.]+(\w+)\s*=\s*(.*?)\s*$' -and $script:PinballDmdKeys -contains $Matches[1].ToLowerInvariant()) {
            if (-not $sections.Contains($current)) {
                $sections[$current] = [pscustomobject]@{ Section = $current; Values = [ordered]@{}; Lines = @() }
            }
            $sections[$current].Values[$Matches[1].ToLowerInvariant()] = $Matches[2]
            $sections[$current].Lines += [pscustomobject]@{ Line = $n; Text = $line.Trim() }
        }
    }
    foreach ($s in $sections.Values) {
        $off = $s.Values.Contains('enabled') -and $s.Values['enabled'] -match '^(?i:false|0)$'
        $kind = if ($off) { 'Off' } elseif (@($s.Values.Keys | Where-Object { $_ -ne 'enabled' }).Count) { 'Position' } else { 'On' }
        $s | Add-Member -NotePropertyName Kind -NotePropertyValue $kind
        $position = if ($kind -eq 'Position') { '{0}/{1} {2}x{3}' -f $s.Values['left'], $s.Values['top'], $s.Values['width'], $s.Values['height'] } else { '' }
        $s | Add-Member -NotePropertyName Position -NotePropertyValue $position
        $s
    }
}

# --- the verdict -------------------------------------------------------------------------------------------

# PuP state of one table for one section name:
#   ScriptOff  the table switches PuP off in its script
#   Active     the table wants PuP and a pack folder of that name holds files; or, without PuP code in the
#              script, a pack named like the ROM (PinUP's VPinMAME plugin loads it by ROM name)
#   NoPack     the table wants PuP, but no pack of that name holds files (missing, or switched off with dashes)
#   None       neither PuP code nor a ROM pack
function Get-PinballTablePupState {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Fact, [Parameter(Mandatory)] [string] $Section, [Parameter(Mandatory)] [hashtable] $Pack)
    $names = @(@($Fact.PackName) + $Section | Where-Object { $_ } | Select-Object -Unique)
    $withFiles = @($names | Where-Object { $Pack.ContainsKey($_.ToLowerInvariant()) -and $Pack[$_.ToLowerInvariant()] -gt 0 })
    $disabled = @($names | ForEach-Object {
        $n = $_.ToLowerInvariant()
        $Pack.Keys | Where-Object { $_ -ne $n -and $_.TrimEnd('-') -eq $n }
    })
    $wants = if ($null -ne $Fact.PupSwitchOn) { [bool]$Fact.PupSwitchOn } else { $Fact.PuPlayer -gt 0 }
    $state = if ($Fact.PupSwitchOn -eq $false) { 'ScriptOff' }
             elseif ($wants -and $withFiles.Count) { 'Active' }
             elseif ($wants) { 'NoPack' }
             elseif ($Fact.PuPlayer -eq 0 -and $Pack.ContainsKey($Section.ToLowerInvariant()) -and $Pack[$Section.ToLowerInvariant()] -gt 0) { 'Active' }
             else { 'None' }
    [pscustomobject]@{ State = $state; Pack = @($withFiles); DisabledPack = @($disabled | Select-Object -Unique) }
}

function Get-PinballDmdTableVerdict([string] $Kind, $Fact, $Pup) {
    if ($Fact.Error) { return @{ Verdict = 'Unclear'; Reason = (Get-KitText 'Pinball.DmdAudit.Reason.Unreadable' -f $Fact.Error) } }
    $why = switch ($Pup.State) {
        'ScriptOff' { Get-KitText 'Pinball.DmdAudit.Reason.ScriptOff' -f $Fact.PupSwitch }
        'NoPack'    { if ($Pup.DisabledPack.Count) { Get-KitText 'Pinball.DmdAudit.Reason.PackDisabled' -f ($Pup.DisabledPack -join ', ') }
                      else { Get-KitText 'Pinball.DmdAudit.Reason.NoPack' } }
        'None'      { if ($Pup.DisabledPack.Count) { Get-KitText 'Pinball.DmdAudit.Reason.RomPackDisabled' -f ($Pup.DisabledPack -join ', ') }
                      else { Get-KitText 'Pinball.DmdAudit.Reason.None' } }
        default     { Get-KitText 'Pinball.DmdAudit.Reason.Active' -f ($Pup.Pack -join ', ') }
    }
    if ($Pup.State -ne 'Active') { return @{ Verdict = 'NoPup'; Reason = $why } }
    # Off is right when the PuP pack draws the score itself; a strip is right whenever the pack is active.
    if ($Kind -eq 'Off' -and $Fact.PDmdStartUp -eq 0) { return @{ Verdict = 'Unclear'; Reason = (Get-KitText 'Pinball.DmdAudit.Reason.OffNoScore' -f $why) } }
    @{ Verdict = 'Ok'; Reason = $why }
}

# The build root: the one given, else the one the pinball setup recorded (target before source, like the doctor).
function Resolve-PinballDmdAuditRoot {
    [CmdletBinding()]
    param([string] $Root, [string] $StatePath = (Get-PinballDefaultStatePath))
    if ($Root) { return (ConvertTo-PinballRoot $Root) }
    if (Test-Path -LiteralPath $StatePath -PathType Leaf) {
        foreach ($key in 'TargetRoot', 'SourceRoot') {
            $v = [string](Get-KitStateValue -Path $StatePath -Key $key)
            if ($v) { return (ConvertTo-PinballRoot $v) }
        }
    }
    throw (Get-KitText 'Pinball.DmdAudit.NoRoot')
}

# Default locations under a build root, like the screen targets; -Paths overrides single ones (tests).
function Get-PinballDmdAuditPath {
    [CmdletBinding()]
    param([string] $Root, [hashtable] $Paths = @{})
    $p = @{}
    if ($Root) {
        $v = Join-PinballPath (ConvertTo-PinballRoot $Root) 'vPinball'
        $p.DmdDevice = "$v\VisualPinball\VPinMAME\DmdDevice.ini"
        $p.Tables    = "$v\VisualPinball\Tables"
        $p.PupVideos = "$v\PinUPSystem\PUPVideos"
    }
    foreach ($k in $Paths.Keys) { $p[$k] = $Paths[$k] }
    foreach ($k in 'DmdDevice', 'Tables', 'PupVideos') {
        if (-not $p.ContainsKey($k) -or -not $p[$k]) { throw (Get-KitText 'Pinball.DmdAudit.NoRoot') }
    }
    $p
}

function Get-PinballDmdAudit {
    [CmdletBinding()]
    param([string] $Root, [hashtable] $Paths = @{})
    $p = Get-PinballDmdAuditPath -Root $Root -Paths $Paths
    if (-not (Test-Path -LiteralPath $p.DmdDevice -PathType Leaf)) { throw (Get-KitText 'Pinball.DmdAudit.NoIni' -f $p.DmdDevice) }
    if (-not (Test-Path -LiteralPath $p.Tables -PathType Container)) { throw (Get-KitText 'Pinball.DmdAudit.NoTables' -f $p.Tables) }

    $sections = @(Get-PinballDmdSection -Text (Read-PinballTextFile $p.DmdDevice))
    $pack = @{}
    if (Test-Path -LiteralPath $p.PupVideos -PathType Container) {
        foreach ($d in Get-ChildItem -LiteralPath $p.PupVideos -Directory) {
            $pack[$d.Name.ToLowerInvariant()] = @(Get-ChildItem -LiteralPath $d.FullName -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1).Count
        }
    }
    $byName = @{}
    $tables = @(Get-ChildItem -LiteralPath $p.Tables -Filter '*.vpx' -File | Sort-Object Name | ForEach-Object { Read-PinballTableScript -Path $_.FullName })
    foreach ($t in $tables) {
        foreach ($g in @($t.GameName)) {
            $k = $g.ToLowerInvariant()
            if (-not $byName.ContainsKey($k)) { $byName[$k] = New-Object Collections.Generic.List[object] }
            $byName[$k].Add($t)
        }
    }
    $unreadable = @($tables | Where-Object { $_.Error })

    $rows = foreach ($s in $sections) {
        if ($s.Kind -eq 'On') { continue }
        $hits = if ($byName.ContainsKey($s.Section.ToLowerInvariant())) { @($byName[$s.Section.ToLowerInvariant()].ToArray()) } else { @() }
        $tableRows = @(foreach ($f in $hits) {
            $pup = Get-PinballTablePupState -Fact $f -Section $s.Section -Pack $pack
            $v = Get-PinballDmdTableVerdict $s.Kind $f $pup
            [pscustomobject]@{ Table = $f.Table; PupState = $pup.State; PupSwitch = $f.PupSwitch; Pack = @($pup.Pack); DisabledPack = @($pup.DisabledPack)
                               PDmdStartUp = $f.PDmdStartUp; Verdict = $v.Verdict; Reason = $v.Reason }
        })
        $verdicts = @($tableRows | ForEach-Object { $_.Verdict } | Select-Object -Unique)
        # No table of that name: a section for a table that is not (or no longer) here, or one a frontend
        # copied by table title. It changes nothing, so it is reported and left alone; the repair never plans
        # an Orphan, so an unreadable table elsewhere only adds a hint instead of blocking the report.
        $verdict = if (-not $tableRows.Count) { 'Orphan' }
                   elseif ($verdicts.Count -gt 1) { if ($verdicts -contains 'Unclear') { 'Unclear' } else { 'Mixed' } }
                   else { $verdicts[0] }
        $reason = if (-not $tableRows.Count) {
                      $r = Get-KitText 'Pinball.DmdAudit.Reason.Orphan'
                      if ($unreadable.Count) { $r += ' ' + (Get-KitText 'Pinball.DmdAudit.Reason.OrphanUnreadable' -f $unreadable.Count) }
                      $r
                  }
                  elseif ($verdict -eq 'Mixed') { Get-KitText 'Pinball.DmdAudit.Reason.Mixed' -f $tableRows.Count }
                  else { $tableRows[0].Reason }
        [pscustomobject]@{
            Section = $s.Section; Kind = $s.Kind; Position = $s.Position; Lines = @($s.Lines)
            Verdict = $verdict; Reason = $reason; Tables = $tableRows
        }
    }
    $rows = @($rows)
    $count = [ordered]@{}
    foreach ($v in 'Ok', 'NoPup', 'Mixed', 'Orphan', 'Unclear') { $count[$v] = @($rows | Where-Object { $_.Verdict -eq $v }).Count }
    [pscustomobject]@{
        DmdDevice = $p.DmdDevice; Tables = $p.Tables; PupVideos = $p.PupVideos
        TableCount = $tables.Count; Unreadable = @($unreadable | ForEach-Object { [pscustomobject]@{ Table = $_.Table; Error = $_.Error } })
        Section = $rows; Count = [pscustomobject]$count
    }
}

# --- the repair ---------------------------------------------------------------------------------------------

# Removes the virtualdmd lines of the given sections; a section left without any line loses its header too.
# Returns the new text and the removed lines. Everything else (other keys, comments, blank lines between
# other sections, line endings) stays as it was.
function Remove-DmdSectionLine([string] $Text, [string[]] $Section) {
    $nl = if ($Text -match "`r`n") { "`r`n" } else { "`n" }
    $wanted = @{}
    foreach ($s in $Section) { $wanted[$s.ToLowerInvariant()] = $true }
    $all = @($Text -split '\r?\n')
    $out = New-Object Collections.Generic.List[string]
    $removed = @()
    $i = 0
    while ($i -lt $all.Count) {
        $line = $all[$i]
        if ($line -match '^\s*\[(.+?)\]\s*$' -and $wanted.ContainsKey($Matches[1].Trim().ToLowerInvariant())) {
            $name = $Matches[1].Trim()
            $body = New-Object Collections.Generic.List[string]
            $j = $i + 1
            while ($j -lt $all.Count -and $all[$j] -notmatch '^\s*\[.+?\]\s*$') { $body.Add($all[$j]); $j++ }
            $kept = New-Object Collections.Generic.List[string]
            foreach ($b in $body) {
                if ($b -match '^\s*virtualdmd[\s.]+(\w+)\s*=' -and $script:PinballDmdKeys -contains $Matches[1].ToLowerInvariant()) {
                    $removed += [pscustomobject]@{ Section = $name; Text = $b.Trim() }
                } else { $kept.Add($b) }
            }
            if (@($kept | Where-Object { $_.Trim() }).Count) {
                $out.Add($line); foreach ($k in $kept) { $out.Add($k) }
            }
            # Header and lines gone: the blank line that separated the section goes with it, so no gap remains.
            $i = $j
            continue
        }
        $out.Add($line)
        $i++
    }
    @{ Text = ($out -join $nl); Removed = $removed }
}

# Plan (default) or write (-Apply). Only NoPup sections are planned; a section named in -Section that is
# not NoPup lands in Pending with its verdict. Before the write the audit runs again on the file as it is
# now: a section whose lines changed since the plan refuses the whole write.
function Invoke-PinballDmdRepair {
    [CmdletBinding()]
    param(
        [string] $Root,
        [hashtable] $Paths = @{},
        [string[]] $Section = @(),
        [switch] $Apply,
        [string] $BackupDir,
        [object] $Audit
    )
    if (-not $Audit) { $Audit = Get-PinballDmdAudit -Root $Root -Paths $Paths }
    $candidates = @($Audit.Section | Where-Object { $_.Verdict -eq 'NoPup' })
    $ready = @(); $pending = @()
    $Section = @($Section | Where-Object { $_ })
    if ($Section.Count) {
        foreach ($name in $Section) {
            $row = @($Audit.Section | Where-Object { $_.Section -eq $name })[0]
            if (-not $row) { $pending += [pscustomobject]@{ Section = $name; Verdict = 'Missing'; Reason = (Get-KitText 'Pinball.DmdAudit.Repair.NotFound' -f $name) } }
            elseif ($row.Verdict -ne 'NoPup') { $pending += [pscustomobject]@{ Section = $name; Verdict = $row.Verdict; Reason = (Get-KitText 'Pinball.DmdAudit.Repair.NotNoPup' -f $name, $row.Verdict) } }
            else { $ready += $row }
        }
    } else { $ready = $candidates }
    $result = [pscustomobject]@{
        DmdDevice = $Audit.DmdDevice; Ready = @($ready); Pending = @($pending); Removed = @(); Backup = ''
        Status = if (-not $Apply) { 'Plan' } elseif (-not $ready.Count) { 'Skipped' } else { 'Written' }
    }
    if (-not $Apply -or -not $ready.Count) { return $result }

    Assert-PinballProcessesClosed
    $now = @(Get-PinballDmdSection -Text (Read-PinballTextFile $Audit.DmdDevice))
    foreach ($r in $ready) {
        $cur = @($now | Where-Object { $_.Section -eq $r.Section })[0]
        $was = @($r.Lines | ForEach-Object { $_.Text }) -join '|'
        $is = if ($cur) { @($cur.Lines | ForEach-Object { $_.Text }) -join '|' } else { '' }
        if ($was -ne $is) { throw (Get-KitText 'Pinball.DmdAudit.Repair.Drift' -f $r.Section, $Audit.DmdDevice) }
    }

    if (-not $BackupDir) { $BackupDir = Join-Path (Split-Path -Parent (Get-PinballDefaultStatePath)) 'backups' }
    if (-not (Test-Path -LiteralPath $BackupDir)) { $null = New-Item -ItemType Directory -Path $BackupDir -Force }
    $stamp = '{0:yyyyMMdd-HHmmss}' -f (Get-Date)
    $zipPath = Join-Path $BackupDir "dmd-repair_$stamp.zip"
    for ($n = 2; Test-Path -LiteralPath $zipPath; $n++) { $zipPath = Join-Path $BackupDir "dmd-repair_$stamp-$n.zip" }
    $zip = New-KitBackup -Files @($Audit.DmdDevice) -Destination $zipPath
    Add-KitStepBackup -Path $zip.Path

    # No GetNewClosure(): the block must stay bound to this module, where Remove-DmdSectionLine lives; it runs
    # while this function is still on the stack, so $names and $box resolve here (as in the PinballY retarget).
    $names = @($ready | ForEach-Object { $_.Section })
    $box = @{ Removed = @() }
    $null = Edit-KitTextFile -Path $Audit.DmdDevice -Confirm:$false -Rewrite {
        param($Text)
        $r = Remove-DmdSectionLine -Text $Text -Section $names
        $box.Removed = $r.Removed
        @{ Text = $r.Text; Count = @($r.Removed).Count }
    }
    Write-KitLog ('DMD repair: {0} section(s), {1} line(s) removed from {2}' -f $names.Count, @($box.Removed).Count, $Audit.DmdDevice)
    $result.Removed = @($box.Removed)
    $result.Backup = $zip.Path
    $result
}
