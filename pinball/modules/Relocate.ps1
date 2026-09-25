# Relocate (step 5): rewrite absolute build paths from the old root to the new root.
#
# Rules (plan section 2.5, A1/B1/W1/W2):
# - Only the prefixes <old>\vPinball and <old>\<sibling> (DOFLinx, ...) are rewritten, at path boundaries and
#   case-insensitively; only the root part is replaced, so the original spelling (vPinball\pinupsystem) stays.
#   Foreign paths (C:\Program Files (x86)\Steam) never match, also not when the old root is a bare drive.
# - No double replacement: a match that already starts with <new>\vPinball is skipped, so the new root may
#   contain the old one (D:\Pin -> D:\Pin\Cab) and a second run changes nothing (idempotent).
# - Database: every TEXT value of every table (generic scan), counted as occurrences, applied through
#   Update-KitDatabaseSafely (copy, transaction, integrity check, atomic swap, .bak_relocate_<stamp>).
# - Text files by extension incl. the Tables folder; log files are left alone; encoding kept by the core.
# - Registry: value DATA below the Future Pinball, VPinMAME and B2S keys (recursive). Value NAMES that contain
#   a path (AppCompatFlags\Layers) are never renamed, only reported as legacy; step 7 sets new flags.
# - Shortcuts through WScript.Shell; dead targets are reported, never "repaired" by guessing. A dead .lnk in a
#   B2S plugins folder whose plugin folder exists next to it is reported as redundant and harmless.

$script:PinballRegistryRoots = @(
    'HKCU:\Software\Future Pinball'
    'HKCU:\Software\Freeware\Visual PinMame'
    'HKCU:\Software\B2S'
)
$script:PinballAppCompatRoots = @(
    'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
    'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
)
$script:PinballTextExtensions = @('.ini', '.bat', '.cmd', '.txt', '.xml', '.vbs', '.res', '.cfg', '.json', '.reg', '.ahk', '.ps1')
$script:PinballTextExcludedNames = @('log.txt', 'puplog.txt')
$script:PinballTextMaxBytes = 16MB

function Get-PinballRegistryRoot { [CmdletBinding()] param() $script:PinballRegistryRoots }

# Every key the kit backs up (step 9) and may import again (rebuild, screens undo): the settings roots plus
# Visual Pinball (VP10 player settings). Nothing else of HKCU is ever imported; PinUP Popper keeps its
# settings in its database, not in the registry, so it is not part of the list.
function Get-PinballRegistryImportRoot { [CmdletBinding()] param() @($script:PinballRegistryRoots) + 'HKCU:\Software\Visual Pinball' }
function Get-PinballAppCompatRoot { [CmdletBinding()] param() $script:PinballAppCompatRoots }

# -RegFileEscaping: for the text of .reg files, where every backslash is doubled.
function New-PinballRelocator {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $OldRoot,
        [Parameter(Mandatory)] [string] $NewRoot,
        [string[]] $Siblings = @(),
        [switch] $RegFileEscaping
    )
    $old = ConvertTo-PinballRoot $OldRoot
    $new = ConvertTo-PinballRoot $NewRoot
    $sep = if ($RegFileEscaping) { '\\\\' } else { '[\\/]' }
    $end = if ($RegFileEscaping) { '(?:\\\\|["'';,|&<>\r\n\t]|$)' } else { '(?:[\\/"'';,|&<>\r\n\t]|$)' }
    $names = (@('vPinball') + @($Siblings) | Where-Object { $_ } | ForEach-Object { [regex]::Escape($_) }) -join '|'
    $rootPattern = { param($r) (($r -split '\\') | ForEach-Object { [regex]::Escape($_) }) -join $sep }
    $options = [Text.RegularExpressions.RegexOptions]'IgnoreCase, CultureInvariant'
    [pscustomobject]@{
        PSTypeName = 'RetroCabinetKit.PinballRelocator'
        OldRoot    = $old
        NewRoot    = $new
        Siblings   = @($Siblings)
        Escaped    = [bool]$RegFileEscaping
        Pattern    = New-Object regex ('(?<![A-Za-z0-9_])' + (& $rootPattern $old) + "(?=$sep(?:$names)$end)"), $options
        Guard      = New-Object regex ('\G' + (& $rootPattern $new) + "$sep(?:$names)$end"), $options
    }
}

# Returns Text (rewritten) and Count (occurrences that were, or with a dry run would be, replaced).
function Convert-PinballPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $Relocator,
        [Parameter(Mandatory)] [AllowEmptyString()] [AllowNull()] [string] $Text
    )
    $count = 0
    $sb = $null
    $last = 0
    foreach ($m in $Relocator.Pattern.Matches($Text)) {
        if ($Relocator.Guard.Match($Text, $m.Index).Success) { continue }
        if (-not $sb) { $sb = New-Object Text.StringBuilder ($Text.Length + 64) }
        $null = $sb.Append($Text, $last, $m.Index - $last)
        $replacement = if ($Relocator.Escaped) { $Relocator.NewRoot.Replace('\', '\\') }
                       elseif ($Text[$m.Index + $m.Length] -eq '/') { $Relocator.NewRoot.Replace('\', '/') }
                       else { $Relocator.NewRoot }
        $null = $sb.Append($replacement)
        $last = $m.Index + $m.Length
        $count++
    }
    if (-not $count) { return [pscustomobject]@{ Text = $Text; Count = 0 } }
    $null = $sb.Append($Text, $last, $Text.Length - $last)
    [pscustomobject]@{ Text = $sb.ToString(); Count = $count }
}

# ---------------------------------------------------------------- database

function Get-PinballDatabaseChange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [RetroCabinetKit.SqliteConnection] $Connection,
        [Parameter(Mandatory)] [psobject] $Relocator
    )
    # Pre-filter in SQL on the folder names (ASCII, so lower() is exact); the relocator decides.
    $needles = [ordered]@{}
    $i = 0
    foreach ($n in @('vPinball') + @($Relocator.Siblings)) { $needles["n$i"] = $n.ToLowerInvariant(); $i++ }
    foreach ($table in Get-KitSqlTable -Connection $Connection) {
        $qt = '"' + $table.Replace('"', '""') + '"'
        foreach ($column in Get-KitSqlColumn -Connection $Connection -Table $table) {
            $qc = '"' + $column.Name.Replace('"', '""') + '"'
            $any = ($needles.Keys | ForEach-Object { "instr(lower($qc), @$_) > 0" }) -join ' OR '
            $sql = "SELECT rowid AS rid, $qc AS v FROM $qt WHERE typeof($qc) = 'text' AND ($any)"
            foreach ($row in Invoke-KitSqlQuery -Connection $Connection -Sql $sql -Parameters $needles) {
                $r = Convert-PinballPath -Relocator $Relocator -Text $row.v
                if ($r.Count) {
                    [pscustomobject]@{ Table = $table; Column = $column.Name; RowId = $row.rid; Old = $row.v; New = $r.Text; Count = $r.Count }
                }
            }
        }
    }
}

function Get-CountSum([object[]] $Rows) { $sum = 0; foreach ($r in $Rows) { $sum += [int]$r.Count }; $sum }

function Get-PinballChangeSummary([object[]] $Changes) {
    $Changes = @($Changes)
    [pscustomobject]@{
        Occurrences = Get-CountSum $Changes
        Cells       = $Changes.Count
        Rows        = @($Changes | ForEach-Object { "$($_.Table)|$($_.RowId)" } | Sort-Object -Unique).Count
        Columns     = @($Changes | ForEach-Object { "$($_.Table).$($_.Column)" } | Sort-Object -Unique)
        Applied     = $false
        Backup      = $null
    }
}

# Counts first on a read-only connection; only when something is left the safe update runs, so a second
# run neither changes the database nor leaves another backup.
function Invoke-PinballDatabaseRelocation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [psobject] $Relocator,
        [switch] $DryRun
    )
    $db = Open-KitSqlite -Path $Path -ReadOnly
    try { $changes = @(Get-PinballDatabaseChange -Connection $db -Relocator $Relocator) } finally { Close-KitSqlite $db }
    $summary = Get-PinballChangeSummary $changes
    if (-not $changes.Count -or $DryRun) { return $summary }

    Assert-PinballProcessesClosed
    $update = Update-KitDatabaseSafely -Path $Path -Purpose 'relocate' -Confirm:$false -ScriptBlock {
        param($connection)
        $inTransaction = @(Get-PinballDatabaseChange -Connection $connection -Relocator $Relocator)
        foreach ($c in $inTransaction) {
            $sql = 'UPDATE "{0}" SET "{1}" = @v WHERE rowid = @id' -f $c.Table.Replace('"', '""'), $c.Column.Replace('"', '""')
            $null = Invoke-KitSqlNonQuery -Connection $connection -Sql $sql -Parameters @{ v = $c.New; id = $c.RowId }
        }
        $inTransaction.Count
    }
    $summary.Applied = $true
    $summary.Backup = $update.Backup
    $summary
}

# ---------------------------------------------------------------- text files

function Get-PinballTextFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string[]] $Folder)
    # Junctions and symbolic links inside the build are not followed (a scan never leaves the build).
    Get-KitFileTree -Path $Folder | Where-Object {
        $script:PinballTextExtensions -contains $_.Extension.ToLowerInvariant() -and
        $script:PinballTextExcludedNames -notcontains $_.Name.ToLowerInvariant() -and
        $_.Length -le $script:PinballTextMaxBytes
    }
}

function Invoke-PinballTextRelocation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]] $Folder,
        [Parameter(Mandatory)] [psobject] $Relocator,
        [switch] $DryRun
    )
    foreach ($file in Get-PinballTextFile -Folder $Folder) {
        if ($DryRun) {
            # Read-only count in the detected encoding (Edit-KitTextFile -WhatIf would print a line per file).
            $encoding = [Text.Encoding]::GetEncoding((Get-KitFileEncoding -Path $file.FullName).CodePage)
            $n = (Convert-PinballPath -Relocator $Relocator -Text ([IO.File]::ReadAllText($file.FullName, $encoding))).Count
            if ($n) { [pscustomobject]@{ Path = $file.FullName; Count = $n; Status = 'WouldChange'; Reason = '' } }
            continue
        }
        Assert-PinballProcessesClosed
        try {
            $n = Edit-KitTextFile -Path $file.FullName -WhatIf:$DryRun -Confirm:$false -Rewrite {
                param($t) Convert-PinballPath -Relocator $Relocator -Text $t
            }
            if ($n) { [pscustomobject]@{ Path = $file.FullName; Count = $n; Status = $(if ($DryRun) { 'WouldChange' } else { 'Changed' }); Reason = '' } }
        } catch {
            # Not editable without damage: count on a lossy read so Verify still sees what is left.
            $n = (Convert-PinballPath -Relocator $Relocator -Text ([IO.File]::ReadAllText($file.FullName))).Count
            if ($n) { [pscustomobject]@{ Path = $file.FullName; Count = $n; Status = 'Skipped'; Reason = $_.Exception.Message } }
        }
    }
}

# ---------------------------------------------------------------- registry

function Get-PinballRegistryKeyTree([string[]] $Roots) {
    foreach ($root in $Roots) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        Get-Item -LiteralPath $root
        Get-ChildItem -LiteralPath $root -Recurse -ErrorAction SilentlyContinue
    }
}

# Value data is rewritten (String, ExpandString, MultiString keep their type); value names are reported.
function Invoke-PinballRegistryRelocation {
    [CmdletBinding()]
    param(
        [string[]] $Roots = $script:PinballRegistryRoots,
        [Parameter(Mandatory)] [psobject] $Relocator,
        [switch] $DryRun
    )
    foreach ($key in Get-PinballRegistryKeyTree $Roots) {
        foreach ($name in $key.GetValueNames()) {
            if ((Convert-PinballPath -Relocator $Relocator -Text $name).Count) {
                [pscustomobject]@{ Key = $key.Name; Name = $name; Count = 1; Status = 'Legacy' }
            }
            $kind = $key.GetValueKind($name)
            if ($kind -notin 'String', 'ExpandString', 'MultiString') { continue }
            $data = $key.GetValue($name, $null, 'DoNotExpandEnvironmentNames')
            $count = 0
            $newData = foreach ($d in @($data)) { $r = Convert-PinballPath -Relocator $Relocator -Text $d; $count += $r.Count; $r.Text }
            if (-not $count) { continue }
            if ($kind -ne 'MultiString') { $newData = [string]$newData } else { $newData = [string[]]@($newData) }
            if (-not $DryRun) {
                Assert-PinballProcessesClosed
                Set-KitRegistryValue -Path "Registry::$($key.Name)" -Name $name -Value $newData -Type ([string]$kind) -Confirm:$false
            }
            [pscustomobject]@{ Key = $key.Name; Name = $name; Count = $count; Status = $(if ($DryRun) { 'WouldChange' } else { 'Changed' }) }
        }
    }
}

# AppCompatFlags\Layers keeps the program path in the value NAME: never renamed, reported as outdated.
function Get-PinballLegacyAppCompat {
    [CmdletBinding()]
    param(
        [string[]] $Roots = $script:PinballAppCompatRoots,
        [Parameter(Mandatory)] [psobject] $Relocator
    )
    foreach ($root in $Roots) {
        $key = Get-Item -LiteralPath $root -ErrorAction SilentlyContinue
        if (-not $key) { continue }
        foreach ($name in $key.GetValueNames()) {
            if ((Convert-PinballPath -Relocator $Relocator -Text $name).Count) {
                [pscustomobject]@{ Key = $key.Name; Name = $name; Count = 1; Status = 'Legacy' }
            }
        }
    }
}

# ---------------------------------------------------------------- shortcuts

function Invoke-PinballShortcutRelocation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]] $Folder,
        [Parameter(Mandatory)] [psobject] $Relocator,
        [switch] $DryRun
    )
    foreach ($file in Get-KitFileTree -Path $Folder -Filter '*.lnk') {
        $link = Get-KitShortcut -Path $file.FullName
        $changes = @{}
        $count = 0
        foreach ($p in 'TargetPath', 'Arguments', 'WorkingDirectory', 'IconLocation') {
            $r = Convert-PinballPath -Relocator $Relocator -Text $link.$p
            if ($r.Count) { $changes[$p] = $r.Text; $count += $r.Count }
        }
        if ($count -and -not $DryRun) {
            Assert-PinballProcessesClosed
            $null = Set-KitShortcut -Path $file.FullName -Confirm:$false @changes
        }
        $target = if ($changes.ContainsKey('TargetPath')) { $changes.TargetPath } else { $link.TargetPath }
        $state = 'Ok'
        # A network target outside the old and new build folders is only reported: checking it would make
        # Windows contact a server a foreign shortcut names (and send the user's credentials there).
        $known = $target -and ($Relocator.Guard.Match($target, 0).Success -or
                 @($Relocator.Pattern.Matches($target) | Where-Object { $_.Index -eq 0 }).Count)
        if ($target -match '^\\\\' -and -not $known) { $state = 'Unc' }
        elseif ($target -and -not (Test-Path -LiteralPath $target)) {
            $plugin = Join-Path $file.DirectoryName (Split-Path -Leaf $target)
            $state = if ($file.Directory.Name -match '^plugins(64)?$' -and (Test-Path -LiteralPath $plugin -PathType Container)) { 'Redundant' } else { 'Dead' }
        }
        if ($count -or $state -ne 'Ok') {
            [pscustomobject]@{ Path = $file.FullName; Count = $count; Target = $target; Link = $state
                               Status = $(if (-not $count) { 'Unchanged' } elseif ($DryRun) { 'WouldChange' } else { 'Changed' }) }
        }
    }
}

# ---------------------------------------------------------------- rebuild mode: registry sources

# Kit backup: only the registry part is restored; every .reg text goes through the relocation first and
# then through Assert-KitRegText (only -AllowedRoots, no deletions), also in a dry run.
function Import-PinballRegistryFromBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [psobject] $Relocator,
        [string[]] $AllowedRoots = (Get-PinballRegistryImportRoot),
        [switch] $DryRun
    )
    $escaped = New-PinballRelocator -OldRoot $Relocator.OldRoot -NewRoot $Relocator.NewRoot -Siblings $Relocator.Siblings -RegFileEscaping
    if (-not $DryRun) { Assert-PinballProcessesClosed }
    Restore-KitBackup -Path $Path -WhatIf:$DryRun -Confirm:$false -AllowedRoots @() -AllowedRegistryRoots $AllowedRoots -PathFilter { $null } -RegistryFilter {
        param($text) (Convert-PinballPath -Relocator $escaped -Text $text).Text
    }
}

# Export of a key below a mounted hive (HKEY_USERS\<mount>\...) -> the same keys in HKCU, paths relocated.
function ConvertFrom-PinballHiveExport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Text,
        [Parameter(Mandatory)] [string] $MountName,
        [Parameter(Mandatory)] [psobject] $Relocator
    )
    $escaped = New-PinballRelocator -OldRoot $Relocator.OldRoot -NewRoot $Relocator.NewRoot -Siblings $Relocator.Siblings -RegFileEscaping
    $t = [regex]::Replace($Text, '(?im)^(\[-?)HKEY_USERS\\' + [regex]::Escape($MountName) + '\\', '$1HKEY_CURRENT_USER\')
    (Convert-PinballPath -Relocator $escaped -Text $t).Text
}

# Old profile (NTUSER.DAT of the previous Windows): reg load needs administrator rights.
function Import-PinballRegistryFromHive {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $HivePath,
        [Parameter(Mandatory)] [psobject] $Relocator,
        [string[]] $Roots = $script:PinballRegistryRoots,
        [switch] $DryRun
    )
    $mount = 'RetroCabinetKit_OldProfile'
    $ErrorActionPreference = 'Continue' # reg.exe writes to stderr; judge by exit code only
    $out = & reg.exe load "HKU\$mount" (Resolve-PinballFullPath $HivePath) 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw (Get-KitText 'Pinball.Relocate.HiveLoadFailed' -f $HivePath, $out.Trim()) }
    try {
        foreach ($root in $Roots) {
            $sub = $root -replace '^HKCU:\\', ''
            if (-not (Test-Path -LiteralPath "Registry::HKEY_USERS\$mount\$sub")) { continue }
            $tmp = Join-Path $env:TEMP ("rck-hive-{0}.reg" -f [guid]::NewGuid())
            try {
                $null = Export-KitRegistryKey -Path "HKU\$mount\$sub" -Destination $tmp
                $text = ConvertFrom-PinballHiveExport -Text ([IO.File]::ReadAllText($tmp)) -MountName $mount -Relocator $Relocator
                # Only the settings root itself may come back (a crafted old profile could hold anything).
                $null = Assert-KitRegText -Text $text -AllowedRoots @($root)
                [IO.File]::WriteAllText($tmp, $text.TrimStart([char]0xFEFF), [Text.Encoding]::Unicode)
                if (-not $DryRun) { Assert-PinballProcessesClosed; Import-KitRegistryFile -Path $tmp -AllowedRoots @($root) -Confirm:$false }
                [pscustomobject]@{ Type = 'Registry'; Source = "HKU\$mount\$sub"; Target = $root; Action = $(if ($DryRun) { 'WhatIf' } else { 'Restored' }) }
            } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        }
    } finally {
        [GC]::Collect(); [GC]::WaitForPendingFinalizers()
        $null = & reg.exe unload "HKU\$mount" 2>&1
    }
}

# No source: the programs write their defaults on first start; list what the user has to set again.
function Get-PinballMissingSetting {
    [CmdletBinding()]
    param([string[]] $Roots = $script:PinballRegistryRoots)
    foreach ($root in $Roots) {
        if (-not (Test-Path -LiteralPath $root)) { Get-KitText 'Pinball.Relocate.MissingKey' -f $root }
    }
    Get-KitText 'Pinball.Relocate.MissingVpmDmd'
}

# ---------------------------------------------------------------- whole step

function Invoke-PinballRelocation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $OldRoot,
        [Parameter(Mandatory)] [string] $NewRoot,
        [string[]] $Siblings = @(),
        [ValidateSet('Move', 'Rebuild')] [string] $Mode = 'Move',
        [string[]] $RegistryRoots = $script:PinballRegistryRoots,
        [string[]] $AppCompatRoots = $script:PinballAppCompatRoots,
        [string] $RegistryBackup,
        [string] $OldUserHive,
        [switch] $DryRun
    )
    $relocator = New-PinballRelocator -OldRoot $OldRoot -NewRoot $NewRoot -Siblings $Siblings
    $folders = @(Get-PinballBuildFolder -Root $relocator.NewRoot -Siblings $Siblings)
    $dbPath = Get-PinballDatabasePath -Root $relocator.NewRoot
    if (-not (Test-Path -LiteralPath $dbPath)) { throw (Get-KitText 'Pinball.Detect.NotABuild' -f $relocator.NewRoot, $dbPath) }
    if (-not $DryRun) { Assert-PinballProcessesClosed }

    $imported = @(); $missing = @()
    if ($Mode -eq 'Rebuild') {
        if ($RegistryBackup) {
            $allowed = @($RegistryRoots) + 'HKCU:\Software\Visual Pinball'
            $imported = @(Import-PinballRegistryFromBackup -Path $RegistryBackup -Relocator $relocator -AllowedRoots $allowed -DryRun:$DryRun)
        }
        elseif ($OldUserHive) { $imported = @(Import-PinballRegistryFromHive -HivePath $OldUserHive -Relocator $relocator -Roots $RegistryRoots -DryRun:$DryRun) }
        else { $missing = @(Get-PinballMissingSetting -Roots $RegistryRoots) }
    }

    $database  = Invoke-PinballDatabaseRelocation -Path $dbPath -Relocator $relocator -DryRun:$DryRun
    $text      = @(Invoke-PinballTextRelocation -Folder $folders -Relocator $relocator -DryRun:$DryRun)
    $registry  = @(Invoke-PinballRegistryRelocation -Roots $RegistryRoots -Relocator $relocator -DryRun:$DryRun)
    $shortcuts = @(Invoke-PinballShortcutRelocation -Folder $folders -Relocator $relocator -DryRun:$DryRun)
    $legacy    = @($registry | Where-Object { $_.Status -eq 'Legacy' }) + @(Get-PinballLegacyAppCompat -Roots $AppCompatRoots -Relocator $relocator)
    $regData   = @($registry | Where-Object { $_.Status -ne 'Legacy' })

    $changedFiles = @($text | Where-Object { $_.Status -ne 'Skipped' } | ForEach-Object { $_.Path }) +
                    @($shortcuts | Where-Object { $_.Count } | ForEach-Object { $_.Path })
    if ($database.Occurrences) { $changedFiles += $dbPath }
    [pscustomobject]@{
        OldRoot      = $relocator.OldRoot
        NewRoot      = $relocator.NewRoot
        Mode         = $Mode
        DryRun       = [bool]$DryRun
        Database     = $database
        TextFiles    = $text
        Registry     = $regData
        Shortcuts    = $shortcuts
        Legacy       = $legacy
        Imported     = $imported
        Missing      = $missing
        ChangedFiles = $changedFiles
        # Old occurrences still left (in a dry run: that would be changed). Legacy entries are not counted.
        Remaining    = [int]$database.Occurrences + (Get-CountSum $text) +
                       (Get-CountSum $regData) + (Get-CountSum $shortcuts)
    }
}

function Write-PinballRelocationReport {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Report)
    $db = $Report.Database
    Write-KitLog (Get-KitText 'Pinball.Relocate.Summary' -f $Report.OldRoot, $Report.NewRoot, $db.Occurrences, $db.Rows, $db.Columns.Count,
        @($Report.TextFiles).Count, @($Report.Registry).Count, @($Report.Shortcuts | Where-Object { $_.Count }).Count)
    foreach ($t in $Report.TextFiles | Where-Object { $_.Status -eq 'Skipped' }) { Write-KitLog (Get-KitText 'Pinball.Relocate.FileSkipped' -f $t.Path, $t.Reason) -Level Warn }
    foreach ($s in $Report.Shortcuts | Where-Object { $_.Link -eq 'Dead' }) { Write-KitLog (Get-KitText 'Pinball.Relocate.DeadLink' -f $s.Path, $s.Target) -Level Warn }
    foreach ($s in $Report.Shortcuts | Where-Object { $_.Link -eq 'Redundant' }) { Write-KitLog (Get-KitText 'Pinball.Relocate.RedundantLink' -f $s.Path, $s.Target) }
    foreach ($s in $Report.Shortcuts | Where-Object { $_.Link -eq 'Unc' }) { Write-KitLog (Get-KitText 'Pinball.Relocate.UncLink' -f $s.Path, $s.Target) -Level Warn }
    foreach ($l in $Report.Legacy) { Write-KitLog (Get-KitText 'Pinball.Relocate.Legacy' -f $l.Key, $l.Name) -Level Warn }
    foreach ($m in $Report.Missing) { Write-KitLog $m -Level Warn }
}

# Verify: a full dry run with the same coverage (registry incl. value names) must find 0 old occurrences;
# legacy value names are reported, not counted.
function Test-PinballRelocation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $OldRoot,
        [Parameter(Mandatory)] [string] $NewRoot,
        [string[]] $Siblings = @(),
        [string[]] $RegistryRoots = $script:PinballRegistryRoots,
        [string[]] $AppCompatRoots = $script:PinballAppCompatRoots
    )
    $r = Invoke-PinballRelocation -OldRoot $OldRoot -NewRoot $NewRoot -Siblings $Siblings -RegistryRoots $RegistryRoots -AppCompatRoots $AppCompatRoots -DryRun
    $r | Add-Member -NotePropertyName Clean -NotePropertyValue ($r.Remaining -eq 0) -PassThru
}
