# Build: detect a PinUP Popper build (step 1) and validate the target (step 2).
# A build is the folder that contains vPinball\PinUPSystem\PUPDatabase.db. The root the build was
# created at is taken from GlobalSettings.GlobalMediaDir (measured: ...\vPinball\pinupsystem\POPMedia\Default,
# so the match on "\vPinball\" is case-insensitive).

# Tables and columns the kit relies on. Anything missing means an unknown Popper version: stop and explain.
$script:PinballExpectedSchema = [ordered]@{
    Emulators      = @('EMUID', 'EmuName', 'DirGames', 'DirMedia', 'LaunchScript')
    Games          = @('GameID', 'EMUID', 'GameFileName')
    GlobalSettings = @('GlobalMediaDir')
    Screens        = @('ScreenName')
}

function Test-PinballBuild {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    Test-Path -LiteralPath (Get-PinballDatabasePath -Root $Path) -PathType Leaf
}

function Test-PinballDatabaseSchema {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $db = Open-KitSqlite -Path $Path -ReadOnly
    try {
        $tables = @(Get-KitSqlTable -Connection $db)
        $missing = @(foreach ($t in $script:PinballExpectedSchema.Keys) {
            $real = @($tables | Where-Object { $_ -eq $t })
            if (-not $real) { $t; continue }
            $columns = @(Get-KitSqlColumn -Connection $db -Table $real[0] | ForEach-Object { $_.Name })
            foreach ($c in $script:PinballExpectedSchema[$t]) { if ($columns -notcontains $c) { "$t.$c" } }
        })
    } finally { Close-KitSqlite $db }
    [pscustomobject]@{ IsValid = ($missing.Count -eq 0); Missing = $missing }
}

function Get-PinballOldRoot {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $DatabasePath)
    $db = Open-KitSqlite -Path $DatabasePath -ReadOnly
    try {
        $media = @(Invoke-KitSqlQuery -Connection $db -Sql "SELECT GlobalMediaDir FROM GlobalSettings WHERE COALESCE(GlobalMediaDir, '') <> ''" |
            ForEach-Object { $_.GlobalMediaDir }) | Select-Object -First 1
    } finally { Close-KitSqlite $db }
    $m = [regex]::Match([string]$media, '^(.*?)[\\/]vPinball(?:[\\/]|$)', 'IgnoreCase')
    if (-not $m.Success -or -not $m.Groups[1].Value) { throw (Get-KitText 'Pinball.Detect.NoRoot' -f $media) }
    ConvertTo-PinballRoot $m.Groups[1].Value
}

function Find-PinballBuildSibling {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Root)
    $r = ConvertTo-PinballRoot $Root
    foreach ($name in $script:PinballKnownSiblings) {
        if (Test-Path -LiteralPath (Join-PinballPath $r $name) -PathType Container) { $name }
    }
}

function Measure-PinballFolder {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string[]] $Path)
    # Same folders robocopy excludes (NAS metadata, recycle bin), so source and target sizes compare.
    # Junctions are skipped like robocopy /XJ does.
    $m = Get-KitFileTree -Path $Path |
        Where-Object { $_.FullName -notmatch '\\(@eaDir|@tmp|System Volume Information|\$RECYCLE\.BIN)\\' } |
        Measure-Object -Property Length -Sum
    [pscustomobject]@{ Files = [long]$m.Count; Bytes = [long]$(if ($m.Sum) { $m.Sum } else { 0 }) }
}

# Step 1 result. Throws with an explanation when the folder is no build or the schema is unknown.
function Get-PinballBuildInfo {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Source)
    $root = ConvertTo-PinballRoot $Source
    if (-not (Test-PinballBuild -Path $root)) { throw (Get-KitText 'Pinball.Detect.NotABuild' -f $root, (Get-PinballDatabasePath -Root $root)) }
    $dbPath = Get-PinballDatabasePath -Root $root
    $schema = Test-PinballDatabaseSchema -Path $dbPath
    if (-not $schema.IsValid) { throw (Get-KitText 'Pinball.Detect.SchemaUnknown' -f ($schema.Missing -join ', ')) }
    $siblings = @(Find-PinballBuildSibling -Root $root)
    $size = Measure-PinballFolder -Path @(Get-PinballBuildFolder -Root $root -Siblings $siblings)
    [pscustomobject]@{
        SourceRoot   = $root
        DatabasePath = $dbPath
        OldRoot      = Get-PinballOldRoot -DatabasePath $dbPath
        Siblings     = $siblings
        Files        = $size.Files
        SizeBytes    = $size.Bytes
    }
}

# Step 2: local drive, not inside the source build, free space >= size + 10 % (unless it is the source itself).
function Test-PinballTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $TargetRoot,
        [Parameter(Mandatory)] [string] $SourceRoot,
        [Parameter(Mandatory)] [long] $SizeBytes
    )
    $target = ConvertTo-PinballRoot $TargetRoot
    $source = ConvertTo-PinballRoot $SourceRoot
    $result = [pscustomobject]@{ TargetRoot = $target; IsValid = $false; Reason = ''; SameAsSource = $false; FreeBytes = [long]0; RequiredBytes = [long]0 }
    if ($target -notmatch '^[A-Za-z]:') { $result.Reason = Get-KitText 'Pinball.Target.LocalOnly' -f $target; return $result }
    # The root ends up in .bat and .ini files of the build: & % ^ ! and quotes would change their meaning.
    if (($target + '\') -notmatch '^[A-Za-z]:\\[A-Za-z0-9 _.\-\\()]*$') { $result.Reason = Get-KitText 'Pinball.Target.BadChars' -f $target; return $result }

    $drive = New-Object IO.DriveInfo ($target.Substring(0, 1))
    if (-not $drive.IsReady) { $result.Reason = Get-KitText 'Pinball.Target.NoDrive' -f $drive.Name; return $result }
    if ($drive.DriveType -notin 'Fixed', 'Removable') { $result.Reason = Get-KitText 'Pinball.Target.LocalOnly' -f $target; return $result }
    $result.FreeBytes = $drive.AvailableFreeSpace

    if ([string]::Equals($target, $source, [StringComparison]::OrdinalIgnoreCase)) {
        $result.SameAsSource = $true; $result.IsValid = $true; return $result
    }
    foreach ($folder in Get-PinballBuildFolder -Root $source -Siblings @(Find-PinballBuildSibling -Root $source)) {
        if (($target + '\').StartsWith($folder + '\', [StringComparison]::OrdinalIgnoreCase)) {
            $result.Reason = Get-KitText 'Pinball.Target.InsideSource' -f $target, $folder; return $result
        }
    }
    $result.RequiredBytes = [long][math]::Ceiling($SizeBytes * 1.1)
    if ($result.FreeBytes -lt $result.RequiredBytes) {
        $result.Reason = Get-KitText 'Pinball.Target.NoSpace' -f ([math]::Round($result.FreeBytes / 1GB, 2)), ([math]::Round($result.RequiredBytes / 1GB, 2))
        return $result
    }
    $result.IsValid = $true
    $result
}
