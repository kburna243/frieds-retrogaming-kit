# Stage 2 of the PinballY adapter: give the dead absolute paths of an installation the targets of THIS
# machine. Reads first, plans, and writes only what a person approved.
#
# What may become a plan row, and what never will:
#   - only a line in Settings.txt whose value is an ABSOLUTE path that does not resolve here, or a companion
#     INI line whose value is one such path
#   - never a comment (this is where the file's own path examples live), never a value in brackets
#     ([PinballY], [STEAM], [TABLEPATH], [TABLEFILE]): PinballY expands those itself
#   - never a relative value: those are portable by design and already reported as they are
#   - never DefaultSettings.txt (the factory defaults PinballY copies back on a reset), never a
#     "Settings backup ...txt" (PinballY rolls those itself), never VersionHistory.txt, never a database
#   - a new path is planned only when it exists on this machine: the kit does not write an address it cannot
#     check, and a folder a person still has to create is a hint, not a change
#
# Written in one pass per file through the same encoding helper the relocator uses, so the UTF-8 BOM and the
# CRLF of the file survive. Before a line is touched it is met again by number, key AND value: PinballY
# rewrites Settings.txt when it closes, so a plan that no longer matches its lines is refused instead of
# guessing where a line went. Line numbers come from ONE splitter (Split-PinballYLine) for planning and for
# writing, because .NET's ReadAllLines also breaks on characters an INI writer never emits.

$script:PinballYCompanionMaxLines = 200000

function Test-PinballYAbsolutePath {
    [CmdletBinding()]
    param([AllowNull()][string] $Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $v = $Value.Trim()
    return ($v -match '^[A-Za-z]:\\' -or $v -match '^\\\\[^\\]+\\[^\\]+')
}

# A map side may be one level coarser than a value: a whole drive ('C:' to 'J:') is the common case for an
# installation copied from a machine whose data lived on another letter. UNC still needs its share.
function Test-PinballYMapRoot {
    [CmdletBinding()]
    param([AllowNull()][string] $Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $false }
    $v = $Value.Trim().TrimEnd('\')
    return ($v -match '^[A-Za-z]:$' -or $v -match '^[A-Za-z]:\\[^\\]' -or $v -match '^\\\\[^\\]+\\[^\\]+')
}

# 'Old=New' pairs, longest Old first: the specific pair must win over the general one, so a pair for a folder
# under a drive is applied before a pair for the drive itself. The FIRST '=' separates: a key never holds one,
# a value may.
function ConvertFrom-PinballYMap {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]] $Map)
    $pairs = New-Object Collections.Generic.List[object]
    foreach ($entry in $Map) {
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        $split = $entry.IndexOf('=')
        if ($split -lt 1) { throw (Get-KitText 'PinballY.Retarget.BadMap' -f $entry) }
        $old = $entry.Substring(0, $split).TrimEnd('\', ' ')
        $new = $entry.Substring($split + 1).Trim().TrimEnd('\')
        if (-not (Test-PinballYMapRoot -Value $old) -or -not (Test-PinballYMapRoot -Value $new)) {
            throw (Get-KitText 'PinballY.Retarget.BadMap' -f $entry)
        }
        $pairs.Add([pscustomobject]@{ Old = $old; New = $new; Text = "$old=$new" })
    }
    if (-not $pairs.Count) { throw (Get-KitText 'PinballY.Retarget.NoMap') }
    @($pairs.ToArray() | Sort-Object { -$_.Old.Length })
}

# The new value for one old value, or $null when no pair matches. A pair matches at a path boundary only: a
# pair for a Scripts folder must never rewrite a sibling whose name only starts with the same letters, because
# that addresses other content entirely.
function Convert-PinballYMapValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Value,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Pairs
    )
    $v = $Value.Trim()
    foreach ($pair in $Pairs) {
        $old = $pair.Old
        if ($v.Length -lt $old.Length) { continue }
        if (-not [string]::Equals($v.Substring(0, $old.Length), $old, [StringComparison]::OrdinalIgnoreCase)) { continue }
        if ($v.Length -gt $old.Length -and $v[$old.Length] -ne '\') { continue }
        $rest = $v.Substring($old.Length)
        $bare = ($pair.New + $rest).TrimEnd('\')
        $tail = if ($v.EndsWith('\')) { '\' } else { '' }
        return [pscustomobject]@{ Pair = $pair.Text; Value = $bare + $tail; Bare = $bare }
    }
    $null
}

# Reads a text file the way the kit will write it back: bytes, its own encoding, lines with their exact
# terminator kept. Returns the lines and nothing else, so plan, write and verify all count the same lines.
# Get-KitFileEncoding is the core's public eye on a file; the byte helpers behind it stay in the core module.
function Read-PinballYLine {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)
    $info = Get-KitFileEncoding -Path $Path
    $bytes = [IO.File]::ReadAllBytes($Path)
    $encoding = [Text.Encoding]::GetEncoding($info.CodePage)
    @(Split-PinballYLine -Text $encoding.GetString($bytes, $info.BomLength, $bytes.Length - $info.BomLength))
}

# One line per element, terminator included, so ($lines -join '') is the original body exactly.
function Split-PinballYLine {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string] $Text)
    $out = New-Object Collections.Generic.List[string]
    if ([string]::IsNullOrEmpty($Text)) { return $out.ToArray() }
    $start = 0
    for ($i = 0; $i -lt $Text.Length; $i++) {
        $c = $Text[$i]
        if ($c -eq "`r") {
            if ($i + 1 -lt $Text.Length -and $Text[$i + 1] -eq "`n") {
                $out.Add($Text.Substring($start, $i - $start + 2)); $i++; $start = $i + 1
            } else {
                $out.Add($Text.Substring($start, $i - $start + 1)); $start = $i + 1
            }
        } elseif ($c -eq "`n") {
            $out.Add($Text.Substring($start, $i - $start + 1)); $start = $i + 1
        }
    }
    if ($start -lt $Text.Length) { $out.Add($Text.Substring($start)) }
    $out.ToArray()
}

# The value of an INI-style line: everything after the FIRST '=', trimmed. Empty when the line is no
# assignment (a comment or free text), which is why a comment can never be a candidate.
function Get-PinballYLineValue {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string] $Line)
    if ($Line -match '^\s*#') { return '' }
    $eq = $Line.IndexOf('=')
    if ($eq -lt 1) { return '' }
    $Line.Substring($eq + 1).Trim()
}

# The name on the left of the first '='. '' when the line is not an assignment.
function Get-PinballYLineKey {
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyString()][AllowNull()][string] $Line)
    if ($Line -match '^\s*#') { return '' }
    $eq = $Line.IndexOf('=')
    if ($eq -lt 1) { return '' }
    $Line.Substring(0, $eq).Trim()
}

# Replaces the value of one line and nothing else: the padding around the '=' and at the end of the line is
# kept exactly, so a diff of the file shows the path and no other character. Returns '' when this line is
# not the planned one - the caller turns that into a refusal of the whole file, with the line number.
function Set-PinballYLineValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Line,
        [Parameter(Mandatory)][string] $Key,
        [Parameter(Mandatory)][string] $Old,
        [Parameter(Mandatory)][string] $New
    )
    $body = ($Line -replace '[\r\n]+$', '')
    $terminator = $Line.Substring($body.Length)
    $eq = $body.IndexOf('=')
    if ($eq -lt 1) { return '' }
    if ($body.Substring(0, $eq).Trim() -ne $Key) { return '' }
    $rest = $body.Substring($eq + 1)
    $value = $rest.Trim()
    if ($value -ne $Old) { return '' }
    $lead = $rest.Length - $rest.TrimStart().Length
    $tail = $rest.Length - $lead - $value.Length
    $body.Substring(0, $eq + 1) + $rest.Substring(0, $lead) + $New + $rest.Substring($rest.Length - $tail) + $terminator
}

# Companion configuration inside the installation: one path per assignment line, no sections. Reported with
# its line number, because a plan that cannot name the line cannot be checked afterwards.
function Get-PinballYCompanionValue {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)
    $root = (ConvertTo-PinballRoot $Path)
    $rows = New-Object Collections.Generic.List[object]
    foreach ($rel in $script:PinballYCompanionIni) {
        $file = Join-Path $root $rel
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        if ((Get-Item -LiteralPath $file).Length -gt $script:PinballYCompanionMaxBytes) { continue }
        $lines = @(Read-PinballYLine -Path $file)
        if ($lines.Count -gt $script:PinballYCompanionMaxLines) { continue }
        for ($i = 0; $i -lt $lines.Count; $i++) {
            $value = Get-PinballYLineValue -Line $lines[$i]
            if (-not (Test-PinballYAbsolutePath -Value $value)) { continue }
            $rows.Add([pscustomobject]@{
                File = $file; FileKind = 'Companion'; Line = $i + 1
                Key = (Get-PinballYLineKey -Line $lines[$i]); Value = $value
            })
        }
    }
    $rows.ToArray()
}

# Every absolute path value that is dead on this machine, in the settings file and in the companions, with
# its status from the same resolver the read operation uses.
function Get-PinballYRetargetCandidate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string] $Path)
    $root = (ConvertTo-PinballRoot $Path)
    $settingsFile = Join-Path $root $script:PinballYSettingsName
    $rows = New-Object Collections.Generic.List[object]
    foreach ($r in @(Get-PinballYReference -Path $root)) {
        if ($r.Kind -ne 'absolute') { continue }
        if ($r.Status -notin @('Missing', 'ForeignDrive')) { continue }
        $rows.Add([pscustomobject]@{
            File = $settingsFile; FileKind = 'Settings'; Line = $r.Line; Key = $r.Key; Value = $r.Value
        })
    }
    foreach ($c in @(Get-PinballYCompanionValue -Path $root)) {
        $resolved = Resolve-PinballYValue -Root $root -Value $c.Value -Key $c.Key
        if ($resolved.Status -notin @('Missing', 'ForeignDrive')) { continue }
        $rows.Add($c)
    }
    $rows.ToArray()
}

# The plan: one row per dead value, with the target the map produces and whether that target exists.
function Get-PinballYRetargetPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Pairs
    )
    $rows = New-Object Collections.Generic.List[object]
    foreach ($c in @(Get-PinballYRetargetCandidate -Path $Path)) {
        $mapped = Convert-PinballYMapValue -Value $c.Value -Pairs $Pairs
        if (-not $mapped) {
            $rows.Add([pscustomobject]@{
                File = $c.File; FileKind = $c.FileKind; Line = $c.Line; Key = $c.Key
                Old = $c.Value; New = ''; Pair = ''; Target = ''
                Status = 'NoMap'; Reason = (Get-KitText 'PinballY.Retarget.NoMapValue' -f $c.Value)
            })
            continue
        }
        $exists = Test-Path -LiteralPath $mapped.Bare
        $rows.Add([pscustomobject]@{
            File = $c.File; FileKind = $c.FileKind; Line = $c.Line; Key = $c.Key
            Old = $c.Value; New = $mapped.Value; Pair = $mapped.Pair; Target = $mapped.Bare
            Status = $(if ($exists) { 'Ready' } else { 'NoTarget' })
            Reason = $(if ($exists) { '' } else { (Get-KitText 'PinballY.Retarget.NoTarget' -f $mapped.Bare) })
        })
    }
    $rows.ToArray()
}

# True as soon as no line could be retargeted any more: this is what makes the second run answer Skipped.
function Test-PinballYRetarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Pairs
    )
    -not @(Get-PinballYRetargetPlan -Path $Path -Pairs $Pairs | Where-Object { $_.Status -eq 'Ready' }).Count
}

# Every planned line is met again in the file BEFORE anything is written or backed up: the line must still
# carry this key and this value. A plan that does not fit is refused with nothing created, because a half
# written settings file is worse than no change at all - and because a backup nobody needed fills the folder.
function Test-PinballYRetargetFit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $File,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]] $Rows
    )
    $lines = @(Read-PinballYLine -Path $File)
    foreach ($row in $Rows) {
        $index = $row.Line - 1
        if ($index -lt 0 -or $index -ge $lines.Count) { return $row.Line }
        if ((Get-PinballYLineKey -Line $lines[$index]) -ne $row.Key) { return $row.Line }
        if ((Get-PinballYLineValue -Line $lines[$index]) -ne $row.Old) { return $row.Line }
    }
    0
}

# Plan, or - when applied and approved: backup, write, verify. Returns Root, Pair, Plan, Ready, Pending,
# Written, Backup and Status ('Plan' | 'Skipped' | 'Done').
function Invoke-PinballYRetarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string] $Path,
        [Parameter(Mandatory)][string[]] $Map,
        [switch] $Apply,
        [string] $BackupDir
    )
    $root = (ConvertTo-PinballRoot $Path)
    $pairs = @(ConvertFrom-PinballYMap -Map $Map)
    $plan = @(Get-PinballYRetargetPlan -Path $root -Pairs $pairs)
    $ready = @($plan | Where-Object { $_.Status -eq 'Ready' })
    $pending = @($plan | Where-Object { $_.Status -ne 'Ready' })
    $pairText = @($pairs | ForEach-Object { $_.Text })
    if (-not $Apply) {
        return [pscustomobject]@{
            Root = $root; Pair = $pairText; Plan = $plan; Ready = $ready
            Pending = $pending; Written = @(); Backup = ''; Status = 'Plan'
        }
    }
    if (-not $ready.Count) {
        return [pscustomobject]@{
            Root = $root; Pair = $pairText; Plan = $plan; Ready = $ready
            Pending = $pending; Written = @(); Backup = ''; Status = 'Skipped'
        }
    }

    # PinballY writes its own settings when it closes: while it runs, this write would be lost at the latest
    # on exit - or would change the table the player is standing at.
    Assert-PinballYProcessesClosed

    $files = @($ready | ForEach-Object { $_.File } | Sort-Object -Unique)
    foreach ($file in $files) {
        $bad = Test-PinballYRetargetFit -File $file -Rows @($ready | Where-Object { $_.File -eq $file })
        if ($bad) { throw (Get-KitText 'PinballY.Retarget.Drift' -f $bad, $file) }
    }

    if (-not $BackupDir) {
        $BackupDir = Join-Path (Split-Path -Parent (Get-PinballDefaultStatePath)) 'backups'
    }
    if (-not (Test-Path -LiteralPath $BackupDir)) { $null = New-Item -ItemType Directory -Path $BackupDir -Force }
    # A name that is taken is not overwritten (New-KitBackup refuses, and rightly so): two runs in the same
    # second are normal when a person clicks through a plan and applies it.
    $stamp = '{0:yyyyMMdd-HHmmss}' -f (Get-Date)
    $zipPath = Join-Path $BackupDir "pinbally-retarget_$stamp.zip"
    for ($n = 2; Test-Path -LiteralPath $zipPath; $n++) { $zipPath = Join-Path $BackupDir "pinbally-retarget_$stamp-$n.zip" }
    $zip = New-KitBackup -Files $files -Destination $zipPath
    Add-KitStepBackup -Path $zip.Path

    $written = New-Object Collections.Generic.List[object]
    foreach ($file in $files) {
        $rowsForFile = @($ready | Where-Object { $_.File -eq $file })
        $null = Edit-KitTextFile -Path $file -Confirm:$false -Rewrite {
            param($Text)
            $lines = @(Split-PinballYLine -Text $Text)
            $count = 0
            foreach ($row in $rowsForFile) {
                $index = $row.Line - 1
                if ($index -lt 0 -or $index -ge $lines.Count) {
                    throw (Get-KitText 'PinballY.Retarget.Drift' -f $row.Line, $row.File)
                }
                $next = Set-PinballYLineValue -Line $lines[$index] -Key $row.Key -Old $row.Old -New $row.New
                if (-not $next) { throw (Get-KitText 'PinballY.Retarget.Drift' -f $row.Line, $row.File) }
                $lines[$index] = $next
                $count++
            }
            @{ Text = ($lines -join ''); Count = $count }
        }
        foreach ($row in $rowsForFile) {
            $written.Add([pscustomobject]@{
                File = $row.File; FileKind = $row.FileKind; Line = $row.Line; Key = $row.Key
                Old = $row.Old; New = $row.New; Pair = $row.Pair
            })
        }
    }

    # Verified by reading the files again, not by trusting the write: every written line must now carry its
    # new value, and every planned line must be gone from the plan.
    foreach ($row in $written) {
        $lines = @(Read-PinballYLine -Path $row.File)
        if ($row.Line -gt $lines.Count) { throw (Get-KitText 'PinballY.Retarget.NotWritten' -f $row.Line, $row.File) }
        if ((Get-PinballYLineValue -Line $lines[$row.Line - 1]) -ne $row.New) {
            throw (Get-KitText 'PinballY.Retarget.NotWritten' -f $row.Line, $row.File)
        }
    }
    [pscustomobject]@{
        Root = $root; Pair = $pairText; Plan = $plan; Ready = $ready
        Pending = $pending; Written = $written.ToArray(); Backup = $zip.Path; Status = 'Done'
    }
}
