# Common: process guard, state location, root/path helpers shared by all pinball steps.

# Programs that hold the database, the INIs or the COM servers open. Wildcards allowed (Get-Process -Name).
$script:PinballProcessNames = @(
    'PinUpMenu', 'PinUpDisplay*', 'PinUpPlayer', 'VPinballX*', 'Future Pinball', 'FPLoader',
    'dmdext', 'B2SBackglassServerEXE', 'DOFLinx'
)

# Build folders that sit next to vPinball and are referenced by absolute paths. Only these are relocated
# besides vPinball itself: a root like C:\ has unrelated siblings (Program Files, Steam) that must stay.
$script:PinballKnownSiblings = @('DOFLinx', 'DirectOutput')

function Resolve-PinballFullPath([string] $Path) {
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

function Get-PinballProcessName {
    [CmdletBinding()]
    param()
    $script:PinballProcessNames
}

# Checked again right before every write. The kit never ends programs, it only asks.
function Assert-PinballProcessesClosed {
    [CmdletBinding()]
    param([string[]] $Names = $script:PinballProcessNames)
    $running = @(Test-KitProcessesClosed -Names $Names)
    if ($running) {
        $list = ($running | ForEach-Object { $_.Name } | Sort-Object -Unique) -join ', '
        throw (Get-KitText 'Process.PleaseClose' -f $list)
    }
}

function Get-PinballDefaultStatePath {
    [CmdletBinding()]
    param()
    Join-Path $script:PinballDir 'install-state.json'
}

# Build root without trailing separator: 'D:\Games', 'C:' (build directly on a drive), '\\nas\share'.
function ConvertTo-PinballRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $p = $Path.Trim().Replace('/', '\')
    if ($p -notmatch '^([A-Za-z]:|\\\\[^\\]+\\[^\\]+)') { throw (Get-KitText 'Pinball.Root.NotAbsolute' -f $Path) }
    $p = $p.TrimEnd('\')
    if ($p -match '^[A-Za-z]:$') { return $p.Substring(0, 1).ToUpperInvariant() + ':' }
    $p
}

# Plain string join: Join-Path fails for drives that do not exist (yet) on this machine.
function Join-PinballPath([string] $Root, [string] $Child) { "$Root\$Child" }

function Get-PinballBuildFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Root,
        [string[]] $Siblings = @()
    )
    foreach ($name in @('vPinball') + @($Siblings)) {
        $dir = Join-PinballPath (ConvertTo-PinballRoot $Root) $name
        if (Test-Path -LiteralPath $dir -PathType Container) { $dir }
    }
}

function Get-PinballDatabasePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Root)
    Join-PinballPath (ConvertTo-PinballRoot $Root) 'vPinball\PinUPSystem\PUPDatabase.db'
}

# Checked again by every executing step (the state file is user-writable, only a hint): a folder on a local
# drive letter (no UNC, no network drive) that contains the build database (-NoDatabase: not yet, step 4).
# Returns $null or the reason.
function Get-PinballRootProblem {
    [CmdletBinding()]
    param(
        [AllowEmptyString()] [string] $Root,
        [switch] $NoDatabase
    )
    if (-not $Root) { return Get-KitText 'Pinball.Step.RunTargetFirst' }
    try { $r = ConvertTo-PinballRoot $Root } catch { return $_.Exception.Message }
    if ($r -notmatch '^[A-Za-z]:') { return Get-KitText 'Pinball.Target.LocalOnly' -f $r }
    # The root ends up in .bat and .ini files of the build: & % ^ ! and quotes would change their meaning (N7:
    # checked by every step, the state file could carry any root).
    if (($r + '\') -notmatch '^[A-Za-z]:\\[A-Za-z0-9 _.\-\\()]*$') { return Get-KitText 'Pinball.Target.BadChars' -f $r }
    $drive = New-Object IO.DriveInfo ($r.Substring(0, 1))
    if ($drive.DriveType -notin 'Fixed', 'Removable') { return Get-KitText 'Pinball.Target.LocalOnly' -f $r }
    $db = Get-PinballDatabasePath -Root $r
    if (-not $NoDatabase -and -not (Test-Path -LiteralPath $db -PathType Leaf)) { return Get-KitText 'Pinball.Detect.NotABuild' -f $r, $db }
    $null
}
