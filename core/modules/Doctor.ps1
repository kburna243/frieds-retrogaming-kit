# Doctor: read-only health checks. A check (New-KitCheck) has an area, a name, a script block and a -Data table
# that is handed to the script block as its only argument (no closures: the block stays bound to its module, so
# private helpers remain visible). The block returns one or more rows @{ Level = 'Ok'|'Info'|'Warn'|'Error'; Detail = '...'; Name = optional }. Invoke-KitDoctor
# runs the checks, turns an exception into one Error row and never changes the machine. The suites add their
# own checks (Get-PinballDoctorCheck, Get-LightgunDoctorCheck); the core adds system and step state checks.

$script:KitCheckLevels = @('Ok', 'Info', 'Warn', 'Error')

function New-KitCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Area,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [scriptblock] $Script,
        [hashtable] $Data = @{}
    )
    [pscustomobject]@{ PSTypeName = 'RetroCabinetKit.Check'; Area = $Area; Name = $Name; Script = $Script; Data = $Data }
}

function New-KitCheckResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Area,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [ValidateSet('Ok', 'Info', 'Warn', 'Error')] [string] $Level,
        [AllowEmptyString()] [string] $Detail = ''
    )
    [pscustomobject]@{ PSTypeName = 'RetroCabinetKit.CheckResult'; Area = $Area; Name = $Name; Level = $Level; Detail = $Detail }
}

function Get-RowValue($Row, [string] $Name) {
    if ($Row -is [Collections.IDictionary]) { return $Row[$Name] }
    $p = $Row.PSObject.Properties[$Name]
    if ($p) { $p.Value }
}

function Invoke-KitDoctor {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Check)
    foreach ($c in $Check) {
        $rows = $null
        try { $rows = @(& $c.Script $c.Data) }
        catch {
            New-KitCheckResult -Area $c.Area -Name $c.Name -Level Error -Detail (Get-KitText 'Doctor.CheckFailed' -f $_.Exception.Message)
            continue
        }
        foreach ($r in $rows) {
            if ($null -eq $r) { continue }
            $level = [string](Get-RowValue $r 'Level')
            if ($script:KitCheckLevels -notcontains $level) { $level = 'Error' }
            $name = [string](Get-RowValue $r 'Name')
            if (-not $name) { $name = $c.Name }
            New-KitCheckResult -Area $c.Area -Name $name -Level $level -Detail ([string](Get-RowValue $r 'Detail'))
        }
    }
}

function Get-KitDoctorSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Result)
    $count = @{}
    foreach ($l in $script:KitCheckLevels) { $count[$l] = @($Result | Where-Object { $_.Level -eq $l }).Count }
    [pscustomobject]@{ Ok = $count.Ok; Info = $count.Info; Warn = $count.Warn; Error = $count.Error }
}

# Plain text report, grouped by area in the order the areas first appear.
function Format-KitDoctorReport {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Result)
    $label = @{ Ok = '[OK]   '; Info = '[INFO] '; Warn = '[WARN] '; Error = '[ERROR]' }
    $title = Get-KitText 'Doctor.Title'
    $bar = '=' * ($title.Length + 4)
    $bar
    "  $title"
    $bar
    Get-KitText 'Doctor.ReadOnly'
    $areas = @($Result | ForEach-Object { $_.Area } | Select-Object -Unique)
    foreach ($area in $areas) {
        ''
        $area
        foreach ($r in $Result | Where-Object { $_.Area -eq $area }) {
            if ($r.Detail) { '{0} {1}: {2}' -f $label[$r.Level], $r.Name, $r.Detail } else { '{0} {1}' -f $label[$r.Level], $r.Name }
        }
    }
    $s = Get-KitDoctorSummary -Result $Result
    ''
    Get-KitText 'Doctor.Result' -f $s.Error, $s.Warn, $s.Ok
}

# Step states of one suite from its install-state.json: Failed = Error, NeedsUser = Warn, the rest one Ok row.
function Get-KitStateCheck {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Area,
        [Parameter(Mandatory)] [string] $StatePath
    )
    New-KitCheck -Area $Area -Name (Get-KitText 'Doctor.State.Name') -Data @{ StatePath = $StatePath } -Script {
        param($d)
        $path = $d.StatePath
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @{ Level = 'Info'; Detail = (Get-KitText 'Doctor.State.NotRun') } }
        $steps = (Read-KitState -Path $path).Steps
        $ok = 0
        foreach ($p in $steps.PSObject.Properties) {
            switch ([string]$p.Value.Status) {
                'Failed'    { @{ Level = 'Error'; Detail = (Get-KitText 'Doctor.State.Failed' -f $p.Name, $p.Value.Message) } }
                'NeedsUser' { @{ Level = 'Warn'; Detail = (Get-KitText 'Doctor.State.NeedsUser' -f $p.Name, $p.Value.Message) } }
                default     { $ok++ }
            }
        }
        @{ Level = 'Ok'; Detail = (Get-KitText 'Doctor.State.Summary' -f $ok) }
    }
}

# Kit files that still carry the download mark (Zone.Identifier stream). Windows only; elsewhere none.
function Get-KitBlockedFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $KitRoot)
    foreach ($f in Get-ChildItem -LiteralPath $KitRoot -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1', '*.cmd' -ErrorAction SilentlyContinue) {
        if (Get-Item -LiteralPath $f.FullName -Stream 'Zone.Identifier' -ErrorAction SilentlyContinue) { $f.FullName }
    }
}

# System checks. Every measured value can be injected (tests); the defaults read the running machine.
function Get-KitSystemCheck {
    [CmdletBinding()]
    param(
        [string] $KitRoot = $script:KitRoot,
        [version] $OsVersion = [Environment]::OSVersion.Version,
        [int] $OsBuild = -1,
        [bool] $OnWindows = ([Environment]::OSVersion.Platform -eq 'Win32NT'),
        [version] $PSVersion = $PSVersionTable.PSVersion,
        [string] $PSEdition = $(if ($PSVersionTable.PSEdition) { $PSVersionTable.PSEdition } else { 'Desktop' }),
        [bool] $Is64Bit = [Environment]::Is64BitOperatingSystem,
        [object] $IsAdmin,
        [string] $FileSystem,
        [object[]] $BlockedFiles
    )
    $area = Get-KitText 'Doctor.Area.System'
    if ($OsBuild -lt 0) { $OsBuild = $OsVersion.Build }
    $d = @{
        Root = $KitRoot; OsVersion = $OsVersion; OsBuild = $OsBuild; OnWindows = $OnWindows; PSVersion = $PSVersion
        PSEdition = $PSEdition; Is64Bit = $Is64Bit; Bound = @{} + $PSBoundParameters
        IsAdmin = $IsAdmin; FileSystem = $FileSystem; BlockedFiles = $BlockedFiles
    }

    New-KitCheck -Area $area -Name (Get-KitText 'Doctor.Sys.Version') -Data $d -Script {
        param($d)
        $file = Join-Path $d.Root 'VERSION'
        $v = if (Test-Path -LiteralPath $file -PathType Leaf) { ([IO.File]::ReadAllText($file)).Trim() } else { '?' }
        @{ Level = 'Info'; Detail = $v }
    }

    New-KitCheck -Area $area -Name (Get-KitText 'Doctor.Sys.Windows') -Data $d -Script {
        param($d)
        $name = if ($d.OsBuild -ge 22000) { 'Windows 11' } else { 'Windows 10' }
        if (-not $d.OnWindows -or $d.OsVersion.Major -lt 10) { @{ Level = 'Error'; Detail = (Get-KitText 'Doctor.Sys.WindowsNo' -f $d.OsVersion) } }
        elseif ($d.OsBuild -lt 19044) { @{ Level = 'Warn'; Detail = (Get-KitText 'Doctor.Sys.WindowsOld' -f $d.OsBuild) } }
        else { @{ Level = 'Ok'; Detail = (Get-KitText 'Doctor.Sys.WindowsOk' -f $name, $d.OsBuild) } }
    }

    New-KitCheck -Area $area -Name (Get-KitText 'Doctor.Sys.PowerShell') -Data $d -Script {
        param($d)
        if ($d.PSVersion -lt [version]'5.1') { @{ Level = 'Error'; Detail = (Get-KitText 'Doctor.Sys.PsOld' -f $d.PSVersion) } }
        elseif ($d.PSEdition -eq 'Desktop') { @{ Level = 'Ok'; Detail = (Get-KitText 'Doctor.Sys.PsOk' -f $d.PSVersion) } }
        else { @{ Level = 'Info'; Detail = (Get-KitText 'Doctor.Sys.PsOther' -f $d.PSVersion) } }
    }

    New-KitCheck -Area $area -Name (Get-KitText 'Doctor.Sys.Arch') -Data $d -Script {
        param($d)
        if ($d.Is64Bit) { @{ Level = 'Ok'; Detail = (Get-KitText 'Doctor.Sys.ArchOk') } } else { @{ Level = 'Error'; Detail = (Get-KitText 'Doctor.Sys.ArchNo') } }
    }

    New-KitCheck -Area $area -Name (Get-KitText 'Doctor.Sys.Admin') -Data $d -Script {
        param($d)
        $admin = if ($d.Bound.ContainsKey('IsAdmin')) { [bool]$d.IsAdmin } else { Test-KitAdmin }
        if ($admin) { @{ Level = 'Ok'; Detail = (Get-KitText 'Doctor.Sys.AdminYes') } } else { @{ Level = 'Info'; Detail = (Get-KitText 'Doctor.Sys.AdminNo') } }
    }

    New-KitCheck -Area $area -Name (Get-KitText 'Doctor.Sys.FileSystem') -Data $d -Script {
        param($d)
        $fs = if ($d.Bound.ContainsKey('FileSystem')) { $d.FileSystem } else { (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($d.Root))).DriveFormat }
        if ($fs -eq 'NTFS') { @{ Level = 'Ok'; Detail = $fs } } else { @{ Level = 'Warn'; Detail = (Get-KitText 'Doctor.Sys.FsWarn' -f $fs) } }
    }

    New-KitCheck -Area $area -Name (Get-KitText 'Doctor.Sys.Blocked') -Data $d -Script {
        param($d)
        $blocked = @(if ($d.Bound.ContainsKey('BlockedFiles')) { $d.BlockedFiles } else { Get-KitBlockedFile -KitRoot $d.Root })
        if ($blocked.Count) { @{ Level = 'Info'; Detail = (Get-KitText 'Doctor.Sys.BlockedSome' -f $blocked.Count) } }
        else { @{ Level = 'Ok'; Detail = (Get-KitText 'Doctor.Sys.BlockedNone') } }
    }
}
