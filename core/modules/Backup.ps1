# Backup: ZIP with exact original paths + manifest.json (SHA256 per file) + registry exports.
# Files are read with FileShare.ReadWrite so files open in other programs can still be saved;
# files that are locked exclusively are reported in manifest.Skipped instead of aborting.
# Restore takes -PathFilter / -RegistryFilter hooks so later phases can rewrite paths on the way back.

Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

# All files below the folders (hidden ones too). Subfolders that are reparse points (junctions, symbolic
# links) are not entered, so a scan never leaves the build through a link. The given folders themselves
# are taken as they are.
function Get-KitFileTree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]] $Path,
        [string] $Filter = '*'
    )
    $queue = New-Object Collections.Generic.Queue[IO.DirectoryInfo]
    foreach ($p in $Path) {
        $d = New-Object IO.DirectoryInfo (Resolve-FullPath $p)
        if ($d.Exists) { $queue.Enqueue($d) }
    }
    while ($queue.Count) {
        $d = $queue.Dequeue()
        try { $files = $d.GetFiles($Filter); $dirs = $d.GetDirectories() }
        catch { Write-Verbose "$($d.FullName): $($_.Exception.Message)"; continue }
        $files
        foreach ($s in $dirs) { if (-not ($s.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $queue.Enqueue($s) } }
    }
}

# $true when the path (normalized, '..' resolved) lies inside one of the roots.
# ponytail: textual check; a junction INSIDE an allowed root still leads elsewhere (scans skip junctions).
function Test-KitPathUnder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $Root
    )
    $full = [IO.Path]::GetFullPath($Path)
    foreach ($r in $Root | Where-Object { $_ }) {
        if ($r -match '^[A-Za-z]:$') { $r += '\' } # 'C:' alone would mean the current folder of drive C
        $base = [IO.Path]::GetFullPath($r).TrimEnd('\') + '\'
        if ($full.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    $false
}

function Get-ZipEntryName([string] $FullPath) {
    if ($FullPath -match '^\\\\([^\\]+)\\(.+)$') { return 'files/UNC/' + $Matches[1] + '/' + ($Matches[2] -replace '\\', '/') }
    if ($FullPath -match '^([A-Za-z]):\\(.+)$') { return 'files/' + $Matches[1].ToUpperInvariant() + '/' + ($Matches[2] -replace '\\', '/') }
    throw "Unsupported path for backup: $FullPath"
}

function Get-Sha256Hex([IO.Stream] $Stream) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash($Stream))) -replace '-', '' } finally { $sha.Dispose() }
}

function New-KitBackup {
    [CmdletBinding()]
    param(
        [string[]] $Files = @(),
        [string[]] $Registry = @(),
        [Parameter(Mandatory)] [string] $Destination
    )
    $zipPath = Resolve-FullPath $Destination
    if (Test-Path -LiteralPath $zipPath) { throw "Backup already exists: $zipPath" }
    $zipDir = Split-Path -Parent $zipPath
    if (-not (Test-Path -LiteralPath $zipDir)) { New-Item -ItemType Directory -Path $zipDir -Force | Out-Null }

    # Expand folders, drop duplicates (case-insensitive, like the file system).
    $paths = [ordered]@{}
    foreach ($f in $Files) {
        $full = Resolve-FullPath $f
        if (Test-Path -LiteralPath $full -PathType Container) {
            Get-KitFileTree -Path $full | ForEach-Object { $paths[$_.FullName.ToLowerInvariant()] = $_.FullName }
        } else { $paths[$full.ToLowerInvariant()] = $full }
    }

    $manifest = [ordered]@{ Format = 1; Created = (Get-Date).ToString('o'); Files = @(); Registry = @(); Skipped = @() }
    $zip = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($full in $paths.Values) {
            $stream = $null
            try {
                $stream = [IO.File]::Open($full, 'Open', 'Read', 'ReadWrite')
            } catch {
                $reason = $_.Exception.InnerException, $_.Exception | Where-Object { $_ } | Select-Object -First 1
                $manifest.Skipped += [ordered]@{ Path = $full; Reason = $reason.Message }
                Write-KitLog (Get-KitText 'Backup.Locked' -f $full) -Level Warn
                continue
            }
            try {
                $hash = Get-Sha256Hex $stream
                $stream.Position = 0
                $entryName = Get-ZipEntryName $full
                $entry = $zip.CreateEntry($entryName, [IO.Compression.CompressionLevel]::Optimal)
                $out = $entry.Open()
                try { $stream.CopyTo($out) } finally { $out.Dispose() }
                $manifest.Files += [ordered]@{
                    Path = $full; Entry = $entryName; Size = $stream.Length; Sha256 = $hash
                    LastWriteTimeUtc = [IO.File]::GetLastWriteTimeUtc($full).ToString('o')
                }
            } finally { $stream.Dispose() }
        }

        $i = 0
        foreach ($key in $Registry) {
            $i++
            $tmp = Join-Path $env:TEMP ("rck-export-{0}.reg" -f [guid]::NewGuid())
            try {
                $null = Export-KitRegistryKey -Path $key -Destination $tmp
                $entryName = 'registry/{0:d3}.reg' -f $i
                $null = [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $tmp, $entryName)
                $fs = [IO.File]::OpenRead($tmp)
                try { $hash = Get-Sha256Hex $fs } finally { $fs.Dispose() }
                $manifest.Registry += [ordered]@{ Key = $key; Entry = $entryName; Sha256 = $hash }
            } finally {
                if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force }
            }
        }

        $entry  = $zip.CreateEntry('manifest.json')
        $writer = New-Object IO.StreamWriter ($entry.Open(), (New-Object Text.UTF8Encoding $false))
        try { $writer.Write((ConvertTo-Json -InputObject $manifest -Depth 5)) } finally { $writer.Dispose() }
        $zip.Dispose(); $zip = $null
    } catch {
        if ($zip) { $zip.Dispose() }
        if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
        throw
    }
    Write-KitLog (Get-KitText 'Backup.Created' -f $zipPath, $manifest.Files.Count)
    [pscustomobject]@{ Path = $zipPath; Files = $manifest.Files.Count; Registry = $manifest.Registry.Count; Skipped = @($manifest.Skipped | ForEach-Object { $_.Path }) }
}

function Get-KitBackupManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $zip = [IO.Compression.ZipFile]::OpenRead((Resolve-FullPath $Path))
    try {
        $reader = New-Object IO.StreamReader ($zip.GetEntry('manifest.json').Open(), [Text.Encoding]::UTF8)
        try { $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
    } finally { $zip.Dispose() }
}

# -PathFilter { param($Path) ... } returns the target path ($null = skip the file).
# -RegistryFilter { param($Text) ... } returns the (rewritten) .reg text before import.
# The manifest comes from a file the user picked, so it is not trusted: every target (after -PathFilter,
# normalized) must lie inside -AllowedRoots, checked for ALL files before the first one is written, and
# every .reg text must pass Assert-KitRegText against -AllowedRegistryRoots (default: none).
# Every file is extracted to a temp file next to the target and checked against its manifest
# hash before it replaces anything. Registry import merges and never deletes values.
function Restore-KitBackup {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $AllowedRoots,
        [string[]] $AllowedRegistryRoots = @(),
        [scriptblock] $PathFilter,
        [scriptblock] $RegistryFilter,
        [switch] $SkipRegistry
    )
    $manifest = Get-KitBackupManifest -Path $Path
    $files = @(foreach ($f in @($manifest.Files)) {
        $target = if ($PathFilter) { & $PathFilter $f.Path } else { $f.Path }
        if (-not $target) { continue }
        $target = [IO.Path]::GetFullPath([string]$target)
        if (-not (Test-KitPathUnder -Path $target -Root $AllowedRoots)) { throw (Get-KitText 'Backup.OutsideRoots' -f $target, ($AllowedRoots -join '; ')) }
        [pscustomobject]@{ Manifest = $f; Target = $target }
    })
    $zip = [IO.Compression.ZipFile]::OpenRead((Resolve-FullPath $Path))
    try {
        foreach ($entry in $files) {
            $f = $entry.Manifest
            $target = $entry.Target
            $action = 'WhatIf'
            if ($PSCmdlet.ShouldProcess($target, 'Restore file')) {
                $dir = Split-Path -Parent $target
                if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
                $tmp = "$target.restore_tmp"
                [IO.Compression.ZipFileExtensions]::ExtractToFile($zip.GetEntry($f.Entry), $tmp, $true)
                $fs = [IO.File]::OpenRead($tmp)
                try { $hash = Get-Sha256Hex $fs } finally { $fs.Dispose() }
                if ($hash -ne $f.Sha256) { Remove-Item -LiteralPath $tmp -Force; throw "Hash mismatch for $($f.Entry)" }
                if (Test-Path -LiteralPath $target) { [IO.File]::Replace($tmp, $target, [NullString]::Value) } else { [IO.File]::Move($tmp, $target) }
                $action = 'Restored'
            }
            [pscustomobject]@{ Type = 'File'; Source = $f.Path; Target = $target; Action = $action }
        }

        if ($SkipRegistry) { return }
        foreach ($r in @($manifest.Registry)) {
            $reader = New-Object IO.StreamReader ($zip.GetEntry($r.Entry).Open(), $true)
            try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
            if ($RegistryFilter) { $text = & $RegistryFilter $text }
            Assert-KitRegText -Text $text -AllowedRoots $AllowedRegistryRoots # also in a dry run
            $action = 'WhatIf'
            if ($PSCmdlet.ShouldProcess($r.Key, 'Import registry (merge)')) {
                $tmp = Join-Path $env:TEMP ("rck-import-{0}.reg" -f [guid]::NewGuid())
                try {
                    [IO.File]::WriteAllText($tmp, $text.TrimStart([char]0xFEFF), [Text.Encoding]::Unicode)
                    Import-KitRegistryFile -Path $tmp -AllowedRoots $AllowedRegistryRoots -Confirm:$false
                } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
                $action = 'Restored'
            }
            [pscustomobject]@{ Type = 'Registry'; Source = $r.Key; Target = $r.Key; Action = $action }
        }
    } finally { $zip.Dispose() }
}
