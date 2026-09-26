# Common: process guard [W5], state location, RetroBat paths, file backup, uninstall entries, scheduled tasks.

# Programs that read or write es_settings.cfg, es_input.cfg or Keymaps.json, plus running emulators (RetroBat
# writes its settings back when a game ends). Checked again right before EVERY write.
$script:LightgunProcessNames = @(
    'emulationstation', 'emulatorLauncher', 'Gunmote',
    'retroarch', 'mame', 'mame64', 'duckstation*', 'pcsx2*', 'TeknoParrotUi', 'demul', 'DemulShooter*',
    'supermodel', 'emulator_multicpu', 'Dolphin*'
)

# Steam only matters where the kit writes Steam's own files (config.vdf): Steam rewrites them on exit. Every other
# step may run while Steam is open, so a running Steam client does not block the RetroBat or TeknoParrot steps.
$script:LightgunSteamProcessNames = @('steam')

function Get-LightgunProcessName {
    [CmdletBinding()]
    param([switch] $IncludeSteam)
    if ($IncludeSteam) { @($script:LightgunProcessNames) + @($script:LightgunSteamProcessNames) } else { $script:LightgunProcessNames }
}

# The kit never ends programs, it only asks. -IncludeSteam before writing Steam's files.
function Assert-LightgunProcessesClosed {
    [CmdletBinding()]
    param([string[]] $Names, [switch] $IncludeSteam)
    if (-not $Names) { $Names = Get-LightgunProcessName -IncludeSteam:$IncludeSteam }
    $running = @(Test-KitProcessesClosed -Names $Names)
    if ($running) {
        $list = ($running | ForEach-Object { $_.Name } | Sort-Object -Unique) -join ', '
        throw (Get-KitText 'Process.PleaseClose' -f $list)
    }
}

# For a step's Test: $true when all guarded programs are closed, otherwise logs which ones and returns $false.
function Test-LightgunProcessesClosed {
    [CmdletBinding()]
    param([string[]] $Names, [switch] $IncludeSteam)
    try { Assert-LightgunProcessesClosed -Names $Names -IncludeSteam:$IncludeSteam; $true } catch { Write-KitLog $_.Exception.Message -Level Warn; $false }
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

# Folders that hold the lightgun backups (<file>.bak_lightgun_* copies): RetroBat, Gunmote and Steam's config
# folder. Only existing folders.
function Get-LightgunBackupRoot {
    [CmdletBinding()]
    param([string] $StatePath = (Get-LightgunDefaultStatePath))
    $roots = @()
    if (Test-Path -LiteralPath $StatePath -PathType Leaf) { $roots += [string](Get-KitStateValue -Path $StatePath -Key 'RetroBatRoot') }
    $g = Find-LightgunGunmote
    if ($g) { $roots += $g.Dir }
    $steam = Get-LightgunSteamPath
    if ($steam) { $roots += Join-Path $steam 'config' }
    @($roots | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Container) } | Sort-Object -Unique)
}

# Copy next to the file (<file>.bak_lightgun_<time>) before it is changed; returns the backup path.
function Backup-LightgunFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $backup = '{0}.bak_lightgun_{1:yyyyMMdd-HHmmss-fff}' -f $Path, (Get-Date)
    Copy-Item -LiteralPath $Path -Destination $backup
    Add-KitStepBackup -Path $backup
    Add-KitStepChange -Kind File -Target $Path -Detail 'backed up, then changed'
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
    Write-KitLog (Get-KitText 'Lightgun.Task.Plan' -f $TaskName, $Execute, $Argument, $user) # what runs with highest rights (N4)
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
            $exe = "$(Get-JsonProperty $a 'Execute')".Trim('"') # COM handler actions have no Execute
            if (-not $exe) { continue }
            try { $full = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($exe)) } catch { continue }
            if ([string]::Equals($full, $want, [StringComparison]::OrdinalIgnoreCase)) {
                [pscustomobject]@{ TaskName = $t.TaskName; TaskPath = $t.TaskPath; RunLevel = [string]$t.Principal.RunLevel; State = [string]$t.State }
                break
            }
        }
    }
}

# --- INI files (DemulShooter config.ini, Supermodel.ini, DuckStation/PCSX2 settings) ---------------------------
# Section '' = the keys before the first section (DemulShooter has no sections). Section and key names are
# compared case-insensitively and trimmed (Supermodel names its section "[ Global ]").

function Read-LightgunIniLine([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $info = Get-KitFileEncoding -Path $Path
    $bytes = [IO.File]::ReadAllBytes($Path)
    $text = [Text.Encoding]::GetEncoding($info.CodePage).GetString($bytes, $info.BomLength, $bytes.Length - $info.BomLength)
    $text -split '\r?\n'
}

# Section -> ordered key/value table.
function Read-LightgunIni {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $ini = [ordered]@{ '' = [ordered]@{} }
    $section = ''
    foreach ($l in Read-LightgunIniLine $Path) {
        if ($l -match '^\s*\[(.*)\]\s*$') { $section = $Matches[1].Trim(); if (-not $ini.Contains($section)) { $ini[$section] = [ordered]@{} }; continue }
        if ($l -match '^\s*([^=;#\[][^=]*?)\s*=\s*(.*?)\s*$' -and -not $ini[$section].Contains($Matches[1])) { $ini[$section][$Matches[1]] = $Matches[2] }
    }
    $ini
}

# Changes (Name, Old, New, Action Add|Change) that bring -Values into -Section.
function Get-LightgunIniPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path, [AllowEmptyString()] [string] $Section = '', [Parameter(Mandatory)] [Collections.IDictionary] $Values)
    $ini = Read-LightgunIni -Path $Path
    $have = if ($ini.Contains($Section.Trim())) { $ini[$Section.Trim()] } else { @{} }
    foreach ($k in $Values.Keys) {
        $old = if ($have.Contains($k)) { $have[$k] } else { $null }
        if ($old -cne [string]$Values[$k]) { [pscustomobject]@{ File = $Path; Name = $k; Old = $old; New = [string]$Values[$k]; Action = $(if ($null -eq $old) { 'Add' } else { 'Change' }) } }
    }
}

# Writes the plan: a value is changed in its line, a missing key goes to the end of its section (a missing
# section to the end of the file). Encoding, BOM and line ends stay; backup first. Returns the change count.
function Set-LightgunIniValue {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [string] $Path, [AllowEmptyString()] [string] $Section = '', [Parameter(Mandatory)] [Collections.IDictionary] $Values)
    $plan = @(Get-LightgunIniPlan -Path $Path -Section $Section -Values $Values)
    if (-not $plan) { return 0 }
    if (-not $PSCmdlet.ShouldProcess($Path, "$($plan.Count) INI value(s)")) { return 0 }
    $exists = Test-Path -LiteralPath $Path -PathType Leaf
    $info = if ($exists) { Get-KitFileEncoding -Path $Path } else { [pscustomobject]@{ CodePage = 65001; BomLength = 0 } }
    $bytes = if ($exists) { [IO.File]::ReadAllBytes($Path) } else { [byte[]]@() }
    $nl = if ($exists -and [Text.Encoding]::GetEncoding($info.CodePage).GetString($bytes).Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = New-Object Collections.Generic.List[string]
    foreach ($l in Read-LightgunIniLine $Path) { $lines.Add($l) }
    if ($lines.Count -and $lines[$lines.Count - 1] -eq '') { $lines.RemoveAt($lines.Count - 1) }
    $want = $Section.Trim()
    foreach ($c in $plan) {
        # Lines start+1 .. end-1 belong to the section (start = -1: the part before the first header).
        $found = $want -eq ''; $start = -1; $end = $lines.Count
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -notmatch '^\s*\[(.*)\]\s*$') { continue }
            if ($found) { $end = $i; break }
            if ([string]::Equals($Matches[1].Trim(), $want, [StringComparison]::OrdinalIgnoreCase)) { $found = $true; $start = $i }
        }
        $line = '{0} = {1}' -f $c.Name, $c.New
        if (-not $found) { $lines.Add("[$Section]"); $lines.Add($line); continue }
        $done = $false
        for ($i = $start + 1; $i -lt $end; $i++) {
            if ($lines[$i] -match '^\s*([^=;#\[][^=]*?)\s*=' -and [string]::Equals($Matches[1], $c.Name, [StringComparison]::OrdinalIgnoreCase)) {
                $lines[$i] = '{0} = {1}' -f $Matches[1], $c.New; $done = $true; break
            }
        }
        if ($done) { continue }
        $at = $end
        while ($at -gt $start + 1 -and $lines[$at - 1].Trim() -eq '') { $at-- } # before the blank lines that end the section
        $lines.Insert($at, $line)
    }
    if ($exists) { Assert-LightgunProcessesClosed; $null = Backup-LightgunFile -Path $Path }
    $body = [Text.Encoding]::GetEncoding($info.CodePage).GetBytes((($lines -join $nl) + $nl))
    $out = [byte[]](@($bytes | Select-Object -First $info.BomLength) + $body)
    $tmp = "$Path.tmp"
    [IO.File]::WriteAllBytes($tmp, $out)
    if ($exists) { [IO.File]::Replace($tmp, $Path, [NullString]::Value) } else { Move-Item -LiteralPath $tmp -Destination $Path }
    $plan.Count
}
