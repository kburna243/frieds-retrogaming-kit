# Recovery: one view over the kit's two backup kinds.
#   Zip   New-KitBackup archives (manifest.json with SHA-256 per file, registry exports), e.g. pinball\backups
#   File  copies next to a changed file: <file>.bak_<purpose>_<yyyyMMdd-HHmmss[-fff]> (lightgun, SQLite,
#         screens). The original is the name before ".bak_" in the same folder.
# Listing, checking and exporting are read-only for the backups. Restoring a file copy first saves the current
# file as <file>.bak_recovery_<time>, so a restore can itself be undone. Zip backups are restored with
# Restore-KitBackup (the caller names the allowed roots; the manifest is never trusted on its own).

$script:KitFileBackupPattern = '^(?<orig>.+)\.bak_(?<purpose>[A-Za-z0-9]+)_(?<stamp>\d{8}-\d{6}(?:-\d{3})?)$'

# @{ Original; Purpose; Created } for a file backup name, $null for anything else.
function ConvertFrom-KitFileBackupName {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $leaf = Split-Path -Leaf $Path
    $m = [regex]::Match($leaf, $script:KitFileBackupPattern)
    if (-not $m.Success) { return $null }
    $format = if ($m.Groups['stamp'].Value.Length -gt 15) { 'yyyyMMdd-HHmmss-fff' } else { 'yyyyMMdd-HHmmss' }
    $created = [datetime]::MinValue
    $null = [datetime]::TryParseExact($m.Groups['stamp'].Value, $format, [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::None, [ref] $created)
    [pscustomobject]@{
        Original = Join-Path (Split-Path -Parent $Path) $m.Groups['orig'].Value
        Purpose  = $m.Groups['purpose'].Value
        Created  = $created
    }
}

function Test-ZipBackupFile([string] $Path) {
    try {
        $zip = [IO.Compression.ZipFile]::OpenRead($Path)
        try { [bool]$zip.GetEntry('manifest.json') } finally { $zip.Dispose() }
    } catch { $false }
}

# All backups below the folders. Zip backups are looked for directly in -Path (backup folders), file copies
# in the whole tree (links are not followed). Newest first.
function Get-KitBackup {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $Path)
    $rows = New-Object Collections.Generic.List[object]
    $seen = @{}
    foreach ($p in $Path | Where-Object { $_ }) {
        $full = Resolve-FullPath $p
        if (-not (Test-Path -LiteralPath $full -PathType Container)) { continue }
        foreach ($z in Get-ChildItem -LiteralPath $full -Filter '*.zip' -File -ErrorAction SilentlyContinue) {
            if ($seen.ContainsKey($z.FullName.ToLowerInvariant()) -or -not (Test-ZipBackupFile $z.FullName)) { continue }
            $seen[$z.FullName.ToLowerInvariant()] = $true
            $m = Get-KitBackupManifest -Path $z.FullName
            $created = $z.LastWriteTime
            if ($m.PSObject.Properties['Created']) { try { $created = [datetime]::Parse([string]$m.Created, [Globalization.CultureInfo]::InvariantCulture) } catch { Write-Verbose $_.Exception.Message } }
            $rows.Add([pscustomobject]@{
                PSTypeName = 'RetroCabinetKit.Backup'
                Kind = 'Zip'; Path = $z.FullName; Created = $created; Purpose = $z.BaseName; Original = ''
                Files = @($m.Files).Count; Registry = @($m.Registry).Count; Skipped = @($m.Skipped).Count; SizeBytes = $z.Length
            })
        }
        foreach ($f in Get-KitFileTree -Path $full -Filter '*.bak_*' -SkipReparseFiles) {
            if ($seen.ContainsKey($f.FullName.ToLowerInvariant())) { continue }
            $info = ConvertFrom-KitFileBackupName -Path $f.FullName
            if (-not $info) { continue }
            $seen[$f.FullName.ToLowerInvariant()] = $true
            $created = if ($info.Created -ne [datetime]::MinValue) { $info.Created } else { $f.LastWriteTime }
            $rows.Add([pscustomobject]@{
                PSTypeName = 'RetroCabinetKit.Backup'
                Kind = 'File'; Path = $f.FullName; Created = $created; Purpose = $info.Purpose; Original = $info.Original
                Files = 1; Registry = 0; Skipped = 0; SizeBytes = $f.Length
            })
        }
    }
    $rows | Sort-Object Created -Descending
}

# Integrity: a zip backup's files and registry exports against the SHA-256 values of its manifest; a file copy
# is readable and its original's folder still exists. Differs: the file copy is not the current content.
function Test-KitBackup {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $full = Resolve-FullPath $Path
    $problems = New-Object Collections.Generic.List[string]
    $info = ConvertFrom-KitFileBackupName -Path $full
    if ($info) {
        $differs = $true
        if (-not (Test-Path -LiteralPath (Split-Path -Parent $info.Original) -PathType Container)) { $problems.Add((Get-KitText 'Recovery.NoTargetFolder' -f $info.Original)) }
        elseif (Test-Path -LiteralPath $info.Original -PathType Leaf) {
            $differs = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash -ne (Get-FileHash -LiteralPath $info.Original -Algorithm SHA256).Hash
        }
        return [pscustomobject]@{ Path = $full; Kind = 'File'; Ok = ($problems.Count -eq 0); Differs = $differs; Problems = @($problems) }
    }
    if (-not (Test-ZipBackupFile $full)) { throw (Get-KitText 'Recovery.NotABackup' -f $full) }
    $manifest = Get-KitBackupManifest -Path $full
    $zip = [IO.Compression.ZipFile]::OpenRead($full)
    try {
        foreach ($e in @($manifest.Files) + @($manifest.Registry)) {
            if ($null -eq $e) { continue }
            $entry = $zip.GetEntry([string]$e.Entry)
            if (-not $entry) { $problems.Add((Get-KitText 'Recovery.EntryMissing' -f $e.Entry)); continue }
            $stream = $entry.Open()
            try { $hash = Get-Sha256Hex $stream } finally { $stream.Dispose() }
            if ($hash -ne [string]$e.Sha256) { $problems.Add((Get-KitText 'Recovery.HashMismatch' -f $e.Entry)) }
        }
    } finally { $zip.Dispose() }
    [pscustomobject]@{ Path = $full; Kind = 'Zip'; Ok = ($problems.Count -eq 0); Differs = $true; Problems = @($problems) }
}

# Puts a file copy back over its original. The current original is saved first (<file>.bak_recovery_<time>);
# the copy goes to a temp file next to the target and replaces it in one step.
function Restore-KitFileBackup {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [string] $Path)
    $full = Resolve-FullPath $Path
    $info = ConvertFrom-KitFileBackupName -Path $full
    if (-not $info) { throw (Get-KitText 'Recovery.NotABackup' -f $full) }
    $item = Get-Item -LiteralPath $full -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw (Get-KitText 'Recovery.Link' -f $full) }
    $target = $info.Original
    $saved = $null
    $action = 'WhatIf'
    if ($PSCmdlet.ShouldProcess($target, (Get-KitText 'Recovery.RestoreAction' -f $full))) {
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            $saved = '{0}.bak_recovery_{1:yyyyMMdd-HHmmss-fff}' -f $target, (Get-Date)
            [IO.File]::Copy($target, $saved)
        }
        $tmp = "$target.restore_tmp"
        [IO.File]::Copy($full, $tmp, $true)
        if (Test-Path -LiteralPath $target -PathType Leaf) { [IO.File]::Replace($tmp, $target, [NullString]::Value) } else { [IO.File]::Move($tmp, $target) }
        Write-KitLog (Get-KitText 'Recovery.Restored' -f $target, $full)
        $action = 'Restored'
    }
    [pscustomobject]@{ Type = 'File'; Source = $full; Target = $target; SavedCurrent = $saved; Action = $action }
}

# Copies a backup into -Destination and appends its SHA-256 to SHA256SUMS.txt there (sha256sum format).
function Export-KitBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Destination
    )
    $full = Resolve-FullPath $Path
    if (-not (ConvertFrom-KitFileBackupName -Path $full) -and -not (Test-ZipBackupFile $full)) { throw (Get-KitText 'Recovery.NotABackup' -f $full) }
    $dest = Resolve-FullPath $Destination
    if (-not (Test-Path -LiteralPath $dest)) { New-Item -ItemType Directory -Path $dest -Force | Out-Null }
    $target = Join-Path $dest (Split-Path -Leaf $full)
    if (Test-Path -LiteralPath $target) { throw (Get-KitText 'Recovery.ExportExists' -f $target) }
    [IO.File]::Copy($full, $target)
    $hash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::AppendAllText((Join-Path $dest 'SHA256SUMS.txt'), "$hash  $(Split-Path -Leaf $target)`n", (New-Object Text.UTF8Encoding $false))
    Write-KitLog (Get-KitText 'Recovery.Exported' -f $target)
    Get-Item -LiteralPath $target
}

# Deletes one backup, only something recognized as a kit backup. Asks by default (ConfirmImpact High).
function Remove-KitBackup {
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
    param([Parameter(Mandatory)] [string] $Path)
    $full = Resolve-FullPath $Path
    if (-not (ConvertFrom-KitFileBackupName -Path $full) -and -not (Test-ZipBackupFile $full)) { throw (Get-KitText 'Recovery.NotABackup' -f $full) }
    if ($PSCmdlet.ShouldProcess($full, (Get-KitText 'Recovery.DeleteAction'))) {
        Remove-Item -LiteralPath $full -Force
        Write-KitLog (Get-KitText 'Recovery.Deleted' -f $full)
    }
}
