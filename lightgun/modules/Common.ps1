# Common: process guard [W5], state location, RetroBat paths, file backup, uninstall entries, scheduled tasks.

# Programs that read or write es_settings.cfg, es_input.cfg, Keymaps.json or the Steam VDFs, plus running
# emulators (RetroBat writes its settings back when a game ends). Checked again right before EVERY write.
$script:LightgunProcessNames = @(
    'emulationstation', 'emulatorLauncher', 'Gunmote', 'steam',
    'retroarch', 'mame', 'mame64', 'duckstation*', 'pcsx2*', 'TeknoParrotUi', 'demul', 'DemulShooter*',
    'supermodel', 'emulator_multicpu', 'Dolphin*'
)

function Get-LightgunProcessName {
    [CmdletBinding()]
    param()
    $script:LightgunProcessNames
}

# The kit never ends programs, it only asks.
function Assert-LightgunProcessesClosed {
    [CmdletBinding()]
    param([string[]] $Names = $script:LightgunProcessNames)
    $running = @(Test-KitProcessesClosed -Names $Names)
    if ($running) {
        $list = ($running | ForEach-Object { $_.Name } | Sort-Object -Unique) -join ', '
        throw (Get-KitText 'Process.PleaseClose' -f $list)
    }
}

# For a step's Test: $true when all guarded programs are closed, otherwise logs which ones and returns $false.
function Test-LightgunProcessesClosed {
    [CmdletBinding()]
    param([string[]] $Names = $script:LightgunProcessNames)
    try { Assert-LightgunProcessesClosed -Names $Names; $true } catch { Write-KitLog $_.Exception.Message -Level Warn; $false }
}

function Get-LightgunDefaultStatePath {
    [CmdletBinding()]
    param()
    Join-Path $script:LightgunDir 'install-state.json'
}

function Resolve-LightgunFullPath([string] $Path) {
    $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Path)
}

# Files of a RetroBat installation the kit reads or writes.
function Get-LightgunRetroBatPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Root)
    $r = (Resolve-LightgunFullPath $Root).TrimEnd('\')
    $es = "$r\emulationstation"
    $cfg = "$es\.emulationstation"
    [pscustomobject]@{
        Root        = $r
        EsExe       = "$es\emulationstation.exe"
        EsSettings  = "$cfg\es_settings.cfg"
        EsInput     = "$cfg\es_input.cfg"
        HookStart   = "$cfg\scripts\game-start"
        HookEnd     = "$cfg\scripts\game-end"
        LauncherLog = "$es\emulatorLauncher.log"
        Roms        = "$r\roms"
        Emulators   = "$r\emulators"
    }
}

# Checked again by every executing step (the state file is user-writable, only a hint): a folder on a local
# drive (no UNC, no network drive) with emulationstation.exe and es_settings.cfg. Returns $null or the reason.
function Get-LightgunRetroBatProblem {
    [CmdletBinding()]
    param([AllowEmptyString()] [string] $Root)
    if (-not $Root) { return Get-KitText 'Lightgun.Step.RunDetectFirst' }
    if ($Root -notmatch '^[A-Za-z]:\\') { return Get-KitText 'Lightgun.Detect.LocalOnly' -f $Root }
    $drive = New-Object IO.DriveInfo ($Root.Substring(0, 1))
    if ($drive.DriveType -notin 'Fixed', 'Removable') { return Get-KitText 'Lightgun.Detect.LocalOnly' -f $Root }
    $p = Get-LightgunRetroBatPath -Root $Root
    if (-not (Test-Path -LiteralPath $p.EsExe -PathType Leaf)) { return Get-KitText 'Lightgun.Detect.NotRetroBat' -f $Root, $p.EsExe }
    if (-not (Test-Path -LiteralPath $p.EsSettings -PathType Leaf)) { return Get-KitText 'Lightgun.Detect.Fresh' -f $p.EsSettings }
    $null
}

# RetroBat root from -Root or the state; logs the problem and returns @{ Root; Problem }.
function Resolve-LightgunRetroBat {
    [CmdletBinding()]
    param([AllowEmptyString()] [string] $Root, [Parameter(Mandatory)] [string] $StatePath)
    if (-not $Root) { $Root = [string](Get-KitStateValue -Path $StatePath -Key 'RetroBatRoot') }
    $problem = Get-LightgunRetroBatProblem -Root $Root
    if ($problem) { Write-KitLog $problem -Level Warn }
    [pscustomobject]@{ Root = $Root; Problem = $problem }
}

# Copy next to the file (<file>.bak_lightgun_<time>) before it is changed; returns the backup path.
function Backup-LightgunFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $backup = '{0}.bak_lightgun_{1:yyyyMMdd-HHmmss-fff}' -f $Path, (Get-Date)
    Copy-Item -LiteralPath $Path -Destination $backup
    Write-KitLog (Get-KitText 'Lightgun.Backup' -f $backup)
    $backup
}

# $true for a path below Program Files (x64/x86): only administrators can change files there, so a task with
# highest rights may start a program from there.
function Test-LightgunUnderProgramFiles {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432) | Where-Object { $_ }
    Test-KitPathUnder -Path $Path -Root $roots
}

# Uninstall entries (64- and 32-bit view) whose DisplayName matches -Pattern (regex).
function Get-LightgunUninstallEntry {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Pattern)
    foreach ($key in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall') {
        foreach ($k in Get-ChildItem -LiteralPath $key -ErrorAction SilentlyContinue) {
            $name = [string]$k.GetValue('DisplayName')
            if ($name -match $Pattern) {
                [pscustomobject]@{
                    DisplayName     = $name
                    DisplayVersion  = [string]$k.GetValue('DisplayVersion')
                    Publisher       = [string]$k.GetValue('Publisher')
                    InstallLocation = [string]$k.GetValue('InstallLocation')
                }
            }
        }
    }
}

function ConvertTo-LightgunUserName([string] $Sid) {
    (New-Object Security.Principal.SecurityIdentifier $Sid).Translate([Security.Principal.NTAccount]).Value
}

# A scheduled task with highest rights for the given user (interactive logon: runs in the user's desktop
# session, which the profile automation needs for the foreground window). -AtLogOn adds a logon trigger.
# The program must lie below Program Files or in the admin-only kit folder; tests mock Register-ScheduledTask.
function Register-LightgunTask {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $TaskName,
        [Parameter(Mandatory)] [string] $Execute,
        [string] $Argument,
        [Parameter(Mandatory)] [string] $UserSid,
        [switch] $AtLogOn
    )
    $user = ConvertTo-LightgunUserName $UserSid
    $action = if ($Argument) { New-ScheduledTaskAction -Execute $Execute -Argument $Argument } else { New-ScheduledTaskAction -Execute $Execute }
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
    $params = @{ TaskName = $TaskName; Action = $action; Principal = $principal; Settings = $settings; Force = $true }
    if ($AtLogOn) { $params.Trigger = New-ScheduledTaskTrigger -AtLogOn -User $user }
    if (-not $PSCmdlet.ShouldProcess($TaskName, "Register task ($Execute $Argument), highest rights, user $user")) { return }
    $null = Register-ScheduledTask @params
    Write-KitLog (Get-KitText 'Lightgun.Task.Registered' -f $TaskName, $user)
}

# Tasks (name, path, run level, actions) whose program is -Execute; -Tasks injects the list (tests).
function Get-LightgunTaskByProgram {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Execute,
        [object[]] $Tasks
    )
    if (-not $PSBoundParameters.ContainsKey('Tasks')) { $Tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue) }
    $want = [IO.Path]::GetFullPath($Execute)
    foreach ($t in $Tasks) {
        foreach ($a in @($t.Actions)) {
            $exe = ([string]$a.Execute).Trim('"')
            if (-not $exe) { continue }
            try { $full = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($exe)) } catch { continue }
            if ([string]::Equals($full, $want, [StringComparison]::OrdinalIgnoreCase)) {
                [pscustomobject]@{ TaskName = $t.TaskName; TaskPath = $t.TaskPath; RunLevel = [string]$t.Principal.RunLevel; State = [string]$t.State }
                break
            }
        }
    }
}
