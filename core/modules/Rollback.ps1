# Rollback.ps1 -- Multi-step rollback stack for complex installations.
# When a multi-step install fails partway through, the kit can unwind to a known-good state.
#
# Pattern:
#   1. Push-KitRollbackPoint -Name "install_mame"  -- saves a snapshot of everything you're about to touch
#   2. Run steps (install, configure, patch, …)
#   3. If all steps pass: clear the stack (auto on success or manual)
#   4. If ANY step fails: Pop-KitRollbackPoint restores every file from the snapshot
#
# The stack is LIFO: last point pushed is the first one restored.
# Points persist across PowerShell sessions (saved to state file).

$script:RollbackStack = New-Object Collections.Generic.Stack[object]
$script:RollbackStatePath = ''

function Get-KitRollbackStatePath {
    if (-not $script:RollbackStatePath) {
        $script:RollbackStatePath = Join-Path $env:USERPROFILE 'RetroCabinet\rollback-stack.json'
    }
    $script:RollbackStatePath
}

# Load persisted rollback stack from disk.
function Import-KitRollbackStack {
    $path = Get-KitRollbackStatePath
    if (-not (Test-Path -LiteralPath $path)) { return }
    try {
        $data = Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $script:RollbackStack.Clear()
        # Rebuild stack from persisted data (oldest first → push in reverse so LIFO is correct)
        $reversed = @($data.Points | Sort-Object { $_.Index } -Descending)
        foreach ($p in $reversed) {
            $script:RollbackStack.Push([pscustomobject]$p)
        }
    } catch {
        Write-KitLog "Rollback stack corrupted: $($_.Exception.Message)" -Level Error
    }
}

# Persist current rollback stack to disk.
function Export-KitRollbackStack {
    $points = @($script:RollbackStack | ForEach-Object { $_ }) | Select-Object Index, Name, Timestamp, SnapshotCount
    [ordered]@{
        Version = 1
        Updated = (Get-Date -Format 'o')
        Points  = @($points)
    } | ConvertTo-Json -Depth 5 -Compress | Out-File -LiteralPath (Get-KitRollbackStatePath) -Encoding UTF8 -NoNewline
}

# Take a snapshot of specific files before modifying them.
# Returns a snapshot object with copies of the original files.
function New-KitSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]] $Paths,
        [string] $Label = ''
    )
    $snapshotDir = Join-Path $env:TEMP "RetroCabKit_Snapshots\$(Get-Date -Format 'yyyyMMddHHmmss')"
    $null = New-Item -ItemType Directory -Path $snapshotDir -Force
    $files = @()
    foreach ($p in $Paths) {
        if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }
        $dest = Join-Path $snapshotDir (Split-Path -Leaf $p)
        Copy-Item -LiteralPath $p -Destination $dest -Force
        $files += [pscustomobject]@{
            OriginalPath = $p
            SnapshotPath = $dest
            Size         = (Get-Item -LiteralPath $p).Length
            Hash         = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash
        }
    }
    [pscustomobject]@{
        Label       = $Label
        Timestamp   = Get-Date -Format 'o'
        SnapshotDir = $snapshotDir
        Files       = $files
        FileCount   = $files.Count
    }
}

# Restore a snapshot: copy files back to their original locations.
function Restore-KitSnapshot {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] $Snapshot)
    if (-not $PSCmdlet.ShouldProcess("$($Snapshot.FileCount) file(s)", 'restore from snapshot')) { return 0 }
    $restored = 0
    foreach ($f in $Snapshot.Files) {
        if (Test-Path -LiteralPath $f.SnapshotPath) {
            # Backup the current (broken) file before restoring
            if (Test-Path -LiteralPath $f.OriginalPath) {
                $backup = "$($f.OriginalPath).bak_rollback_$(Get-Date -Format 'yyyyMMddHHmmss')"
                Copy-Item -LiteralPath $f.OriginalPath -Destination $backup -Force
            }
            Copy-Item -LiteralPath $f.SnapshotPath -Destination $f.OriginalPath -Force
            $restored++
        }
    }
    Write-KitLog "Snapshot restored: $restored/$($Snapshot.FileCount) file(s)"
    $restored
}

# Push a named rollback point onto the stack.
function Push-KitRollbackPoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string[]] $Paths,
        [string] $Description = ''
    )
    $index = $script:RollbackStack.Count + 1
    $snapshot = New-KitSnapshot -Paths $Paths -Label $Name
    $point = [pscustomobject]@{
        Index         = $index
        Name          = $Name
        Description   = $Description
        Timestamp     = (Get-Date -Format 'o')
        Snapshot      = $snapshot
        SnapshotCount = $snapshot.FileCount
    }
    $script:RollbackStack.Push($point)
    Export-KitRollbackStack
    Write-KitLog "Rollback point pushed: $Name ($($snapshot.FileCount) file(s) snapshotted)"
    $point
}

# Pop the most recent rollback point and restore its snapshot.
function Pop-KitRollbackPoint {
    [CmdletBinding(SupportsShouldProcess)]
    param([switch] $KeepSnapshot)
    if ($script:RollbackStack.Count -eq 0) {
        Write-KitLog "Rollback stack is empty -- nothing to restore" -Level Warn
        return $null
    }
    $point = $script:RollbackStack.Pop()
    $restored = Restore-KitSnapshot -Snapshot $point.Snapshot
    if (-not $KeepSnapshot -and (Test-Path $point.Snapshot.SnapshotDir)) {
        Remove-Item -LiteralPath $point.Snapshot.SnapshotDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Export-KitRollbackStack
    Write-KitLog "Rollback point popped: $($point.Name) -- $restored file(s) restored"
    [pscustomobject]@{ Point = $point; Restored = $restored }
}

# Pop a specific named rollback point (and all pushed AFTER it, in reverse order).
function Pop-KitRollbackPointByName {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [switch] $KeepSnapshots
    )
    $points = @($script:RollbackStack)
    $idx = $points.IndexOf(($points | Where-Object { $_.Name -eq $Name } | Select-Object -First 1))
    if ($idx -lt 0) { throw "Rollback point '$Name' not found" }
    # Pop everything up to and including the named point
    $results = @()
    for ($i = 0; $i -le $idx; $i++) {
        $results += Pop-KitRollbackPoint -KeepSnapshot:$KeepSnapshots
    }
    $results
}

# Clear the rollback stack (call after successful multi-step install).
function Clear-KitRollbackStack {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    if (-not $PSCmdlet.ShouldProcess('rollback stack', 'clear')) { return }
    while ($script:RollbackStack.Count -gt 0) {
        $point = $script:RollbackStack.Pop()
        if (Test-Path $point.Snapshot.SnapshotDir) {
            Remove-Item -LiteralPath $point.Snapshot.SnapshotDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    $path = Get-KitRollbackStatePath
    if (Test-Path $path) { Remove-Item $path -Force }
    Write-KitLog "Rollback stack cleared"
}

# Get the current rollback stack depth and top point.
function Get-KitRollbackStack {
    [CmdletBinding()]
    param()
    $points = @($script:RollbackStack)
    [pscustomobject]@{
        Depth     = $points.Count
        TopPoint  = if ($points.Count) { $points[0].Name } else { '' }
        Points    = @($points | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Timestamp = $_.Timestamp; FileCount = $_.SnapshotCount } })
    }
}

# Initialize: load persisted stack on import.
Import-KitRollbackStack