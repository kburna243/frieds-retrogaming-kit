# Automation (step 8) [W7]: Gunmote profile per system, without the Home button.
#   %ProgramData%\RetroCabinetKit\lightgun\profile.ps1   the watcher (kit template), folder writable only for
#                                                         Administrators and SYSTEM (users may read the log)
#   tasks "RetroCabinetKit Gunmote Profile <Name>"        highest rights, the logged-on user, start profile.ps1
#   RetroBat scripts\game-start\ and game-end\            .bat hooks that ONLY run "schtasks /run /tn ..."
#   ...\rck-game-helper.bat                                a second pair of hooks that starts the kit's game helper
#                                                         (GameHelper.ps1) at the user's own rights, no task
# Nothing with administrator rights ever runs from the RetroBat folder: a user can change the hooks, but they
# can only start the fixed tasks, which run the admin-only script with a checked layout title, or start work
# the user may do anyway (DemulShooter, FFBBlaster settings, asking the kit for the Wiimote order).

$script:LightgunTaskPrefix = 'RetroCabinetKit Gunmote Profile'
$script:LightgunHookName = 'rck-gunmote-profile.bat'

# RetroBat system -> profile, per Wiimote connection (see Hardware.ps1). Over the DolphinBar everything whose emulator
# or DemulShooter reads RawInput needs the mouse, not a pad (cabinet 27.09.). Over Bluetooth those read the Xbox pads
# and DuckStation aims with the mouse (cabinet 01.10.2026). Naomi/Atomiswave keep their own task.
$script:LightgunSystemProfilesByConnection = @{
    DolphinBar = [ordered]@{
        teknoparrot = 'TP'; naomi = 'Naomi'; atomiswave = 'Naomi'; mame = 'Pad43'; psx = 'Pad43'
        model2 = 'Mouse43'; model3 = 'Mouse43'; singe = 'Mouse43'; daphne = 'Mouse43'
        dreamcast = 'Mouse'; nes = 'Mouse'; snes = 'Mouse'; megadrive = 'Mouse'; mastersystem = 'Mouse'; ps2 = 'Mouse'
    }
    Bluetooth = [ordered]@{
        teknoparrot = 'TP'; naomi = 'Naomi'; atomiswave = 'Naomi'; mame = 'Pad43'; psx = 'Mouse43'
        model2 = 'Pad43'; model3 = 'Pad43'; singe = 'Pad43'; daphne = 'Pad43'
        dreamcast = 'Mouse'; nes = 'Mouse'; snes = 'Mouse'; megadrive = 'Mouse'; mastersystem = 'Mouse'; ps2 = 'Mouse'
    }
}

# Profile -> layout kind (step 6 recorded one title per kind).
$script:LightgunProfileKindsByConnection = @{
    DolphinBar = [ordered]@{ Menu = 'Menu'; TP = 'TP'; Pad43 = 'Pad43'; Naomi = 'Mouse43'; Mouse = 'Mouse'; Mouse43 = 'Mouse43' }
    Bluetooth  = [ordered]@{ Menu = 'Menu'; TP = 'TP'; Pad43 = 'Pad43'; Naomi = 'Pad43'; Mouse = 'Mouse'; Mouse43 = 'Mouse43' }
}

function Get-LightgunSystemProfile {
    [CmdletBinding()]
    param([ValidateSet('DolphinBar', 'Bluetooth')] [string] $Connection = 'DolphinBar')
    $script:LightgunSystemProfilesByConnection[$Connection]
}

function Get-LightgunProfileFor {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $System, [ValidateSet('DolphinBar', 'Bluetooth')] [string] $Connection = 'DolphinBar')
    $map = $script:LightgunSystemProfilesByConnection[$Connection]
    $key = $System.ToLowerInvariant()
    if ($map.Contains($key)) { $map[$key] }
}

function Get-LightgunAutomationDir {
    [CmdletBinding()]
    param([string] $Base = (Join-Path $env:ProgramData 'RetroCabinetKit'))
    Join-Path $Base 'lightgun'
}

function Get-LightgunProfileLogPath {
    [CmdletBinding()]
    param([string] $AutomationDir = (Get-LightgunAutomationDir))
    Join-Path $AutomationDir 'logs\profile.log'
}

# The two hook files. Only "schtasks /run" is ever called; the ROM path (argument 1) is compared with cmd's
# case-insensitive substring replacement inside quotes, so characters like & or ^ in a ROM name stay text.
function New-LightgunHookText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('Start', 'End')] [string] $Kind,
        [string] $TaskPrefix = $script:LightgunTaskPrefix,
        [ValidateSet('DolphinBar', 'Bluetooth')] [string] $Connection = 'DolphinBar'
    )
    $map = $script:LightgunSystemProfilesByConnection[$Connection]
    $lines = New-Object Collections.Generic.List[string]
    $lines.Add('@echo off')
    $lines.Add('rem retro-cabinet-kit: selects the Gunmote profile. Only starts the kit''s scheduled tasks; the scripts')
    $lines.Add('rem they run live in the admin-only kit folder below ProgramData. Argument 1 = ROM path from RetroBat.')
    if ($Kind -eq 'End') {
        $lines.Add("schtasks /run /tn `"$TaskPrefix Menu`" >nul 2>&1")
    } else {
        $lines.Add('setlocal DisableDelayedExpansion')
        $lines.Add('set "ROM=%~1"')
        $lines.Add('if not defined ROM goto :eof')
        $lines.Add('set "PROFILE="')
        foreach ($s in $map.Keys) {
            $lines.Add(('if not defined PROFILE if not "%ROM:\roms\{0}\=%"=="%ROM%" set "PROFILE={1}"' -f $s, $map[$s]))
        }
        $lines.Add("if defined PROFILE schtasks /run /tn `"$TaskPrefix %PROFILE%`" >nul 2>&1")
        $lines.Add('endlocal')
    }
    ($lines -join "`r`n") + "`r`n"
}

function Get-LightgunTemplatePath {
    [CmdletBinding()]
    param()
    Join-Path $script:LightgunDir 'templates\profile.ps1'
}

# Protected ACL: Administrators and SYSTEM full control, Users read (the wizard shows the log without
# elevation). As administrator the owner becomes Administrators, so a folder created beforehand by a user
# loses its owner rights. Links (junctions) are refused.
function Set-LightgunAdminOnlyAcl {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw (Get-KitText 'Path.ReparsePoint' -f $Path) }
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($r in @(@('S-1-5-32-544', 'FullControl'), @('S-1-5-18', 'FullControl'), @('S-1-5-32-545', 'ReadAndExecute'))) {
        $id = New-Object Security.Principal.SecurityIdentifier $r[0]
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule ($id, $r[1], 'ContainerInherit, ObjectInherit', 'None', 'Allow')))
    }
    if (Test-KitAdmin) { $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-544')) }
    $item.SetAccessControl($acl)
}

# $true when the folder and every file in it grant write/modify rights to nobody but Administrators and SYSTEM,
# the folder's ACL is protected against inherited rights and the folder is owned by -TrustedOwner (an owner can
# always rewrite the rules). Tests in TEMP add their own SID as owner.
function Test-LightgunAdminOnlyAcl {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path, [string[]] $TrustedOwner = @('S-1-5-32-544', 'S-1-5-18'), [switch] $NoRecurse)
    # Only the bits that change something (Modify/FullControl would also contain the read bits), plus the
    # generic GENERIC_ALL / GENERIC_WRITE bits that inherited rules can carry.
    $write = [int]([Security.AccessControl.FileSystemRights]'WriteData, AppendData, WriteExtendedAttributes, WriteAttributes, DeleteSubdirectoriesAndFiles, Delete, ChangePermissions, TakeOwnership') -bor 0x10000000 -bor 0x40000000
    $allowed = @('S-1-5-32-544', 'S-1-5-18') + $TrustedOwner # tests: their own SID, like Initialize-KitDownloadDir grants it
    $dirAcl = [IO.Directory]::GetAccessControl($Path)
    if (-not $dirAcl.AreAccessRulesProtected) { return $false }
    if ($TrustedOwner -notcontains $dirAcl.GetOwner([Security.Principal.SecurityIdentifier]).Value) { return $false }
    $children = if ($NoRecurse) { @() } else { @(Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue) }
    if (@($children | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count) { return $false }
    $acls = @($dirAcl) + @($children | ForEach-Object {
        if ($_.PSIsContainer) { [IO.Directory]::GetAccessControl($_.FullName) } else { [IO.File]::GetAccessControl($_.FullName) }
    })
    foreach ($acl in $acls) {
        foreach ($rule in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
            if ($rule.AccessControlType -ne 'Allow' -or $allowed -contains $rule.IdentityReference.Value) { continue }
            if ([int]$rule.FileSystemRights -band $write) { return $false }
        }
    }
    $true
}

# Copies profile.ps1 into the automation folder and locks it. The parent (kit data folder) is checked and locked
# first: admin-only, or a user could rename the folder and put his own in its place. Existing folders are only
# used with an owner from -TrustedOwner (N3; tests add their own SID). Existing kit files are removed first so
# the new ones inherit the folder's ACL (a file a user created beforehand keeps its own rules otherwise).
function Install-LightgunAutomationFile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string] $AutomationDir = (Get-LightgunAutomationDir),
        [string[]] $TrustedOwner = @('S-1-5-32-544', 'S-1-5-18')
    )
    if (-not $PSCmdlet.ShouldProcess($AutomationDir, 'Install profile.ps1 (admin-only folder)')) { return }
    $logs = Join-Path $AutomationDir 'logs'
    $null = Initialize-KitDownloadDir -Base (Split-Path -Parent $AutomationDir) -TrustedOwner $TrustedOwner
    foreach ($d in $AutomationDir, $logs) { $null = Initialize-KitTrustedFolder -Path $d -TrustedOwner $TrustedOwner }
    $target = Join-Path $AutomationDir 'profile.ps1'
    if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Force }
    Copy-Item -LiteralPath (Get-LightgunTemplatePath) -Destination $target
    # Deepest first: once the folder is locked, a non-administrator (tests) could not reach the child any more.
    Set-LightgunAdminOnlyAcl -Path $logs
    Set-LightgunAdminOnlyAcl -Path $AutomationDir
    Write-KitLog (Get-KitText 'Lightgun.Auto.Installed' -f $AutomationDir)
}

function Test-LightgunAutomationFile {
    [CmdletBinding()]
    param([string] $AutomationDir = (Get-LightgunAutomationDir), [string[]] $TrustedOwner = @('S-1-5-32-544', 'S-1-5-18'))
    $target = Join-Path $AutomationDir 'profile.ps1'
    (Test-Path -LiteralPath $target -PathType Leaf) -and
        (Get-FileHash -LiteralPath $target).Hash -eq (Get-FileHash -LiteralPath (Get-LightgunTemplatePath)).Hash -and
        (Test-LightgunAdminOnlyAcl -Path $AutomationDir -TrustedOwner $TrustedOwner) -and
        (Test-LightgunAdminOnlyAcl -Path (Split-Path -Parent $AutomationDir) -TrustedOwner $TrustedOwner -NoRecurse)
}

# Task definitions: Name, TaskName, Argument (for powershell.exe). Titles come from step 6 and are checked.
function Get-LightgunProfileTaskPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $Titles,
        [string] $AutomationDir = (Get-LightgunAutomationDir),
        [string] $TaskPrefix = $script:LightgunTaskPrefix,
        [ValidateSet('DolphinBar', 'Bluetooth')] [string] $Connection = 'DolphinBar'
    )
    $script = Join-Path $AutomationDir 'profile.ps1'
    $kinds = $script:LightgunProfileKindsByConnection[$Connection]
    foreach ($p in $kinds.Keys) {
        $kind = $kinds[$p]
        $title = if ($Titles -is [Collections.IDictionary]) { $Titles[$kind] } else { $Titles.$kind }
        if (-not (Test-LightgunLayoutTitle $title)) { throw (Get-KitText 'Lightgun.Auto.BadTitle' -f $kind, $title) }
        $arg = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Layout "{1}"' -f $script, $title
        if ($p -eq 'Menu') { $arg += ' -Once' }
        [pscustomobject]@{ Name = $p; TaskName = "$TaskPrefix $p"; Argument = $arg }
    }
}

function Get-LightgunPowerShellPath {
    [CmdletBinding()]
    param()
    Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
}

function Register-LightgunProfileTask {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [object[]] $Plan, [Parameter(Mandatory)] [string] $UserSid)
    foreach ($t in $Plan) {
        Register-LightgunTask -TaskName $t.TaskName -Execute (Get-LightgunPowerShellPath) -Argument $t.Argument -UserSid $UserSid -WhatIf:$WhatIfPreference -Confirm:$false
    }
}

# $true when every planned task exists with highest rights and exactly the planned program and arguments.
function Test-LightgunProfileTask {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object[]] $Plan, [object[]] $Tasks)
    if (-not $PSBoundParameters.ContainsKey('Tasks')) { $Tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue) }
    $exe = Get-LightgunPowerShellPath
    foreach ($p in $Plan) {
        $t = @($Tasks | Where-Object { $_.TaskName -eq $p.TaskName }) | Select-Object -First 1
        if (-not $t -or [string]$t.Principal.RunLevel -ne 'Highest') { return $false }
        $a = @($t.Actions)
        if ($a.Count -ne 1 -or -not [string]::Equals("$(Get-JsonProperty $a[0] 'Execute')".Trim('"'), $exe, [StringComparison]::OrdinalIgnoreCase) -or
            "$(Get-JsonProperty $a[0] 'Arguments')" -ne $p.Argument) { return $false }
    }
    $true
}

$script:LightgunHelperHookName = 'rck-game-helper.bat'

function Get-LightgunGameHelperPath {
    [CmdletBinding()]
    param()
    Join-Path $script:LightgunDir 'tools\GameHelper.ps1'
}

# The game helper hook: starts the kit's GameHelper.ps1 with the user's own rights. "start /b" runs it in the hook's
# own hidden console (no window, RetroBat keeps the focus) and returns at once (the game does not wait). The ROM path
# is passed quoted, so & ^ and spaces stay text. The kit's path is fixed at installation; a path cmd would expand
# (% or ") is refused.
function New-LightgunGameHelperHookText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('Start', 'End')] [string] $Kind,
        [ValidateSet('DolphinBar', 'Bluetooth')] [string] $Connection = 'DolphinBar',
        [string] $HelperPath = (Get-LightgunGameHelperPath)
    )
    if ($HelperPath -match '[%"]') { throw (Get-KitText 'Lightgun.Auto.BadHelperPath' -f $HelperPath) }
    $lines = @(
        '@echo off'
        'rem retro-cabinet-kit: game helper at the user''s own rights (no task, no administrator rights): DemulShooter for'
        'rem Naomi/Atomiswave/Model 2, FFBBlaster network outputs for TeknoParrot, Wiimote player order. Argument 1 = ROM path.'
        ('start "" /b "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Phase {1} -Connection {2} -Rom "%~1"' -f $HelperPath, $Kind, $Connection)
    )
    ($lines -join "`r`n") + "`r`n"
}

# Every hook file the kit owns: the profile hook and the game helper hook, at game start and game end.
function Get-LightgunHookFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RetroBatRoot,
        [string] $TaskPrefix = $script:LightgunTaskPrefix,
        [ValidateSet('DolphinBar', 'Bluetooth')] [string] $Connection = 'DolphinBar'
    )
    $p = Get-LightgunRetroBatPath -Root $RetroBatRoot
    foreach ($h in @(@($p.HookStart, 'Start'), @($p.HookEnd, 'End'))) {
        [pscustomobject]@{ Dir = $h[0]; File = Join-Path $h[0] $script:LightgunHookName; Text = New-LightgunHookText -Kind $h[1] -TaskPrefix $TaskPrefix -Connection $Connection }
        [pscustomobject]@{ Dir = $h[0]; File = Join-Path $h[0] $script:LightgunHelperHookName; Text = New-LightgunGameHelperHookText -Kind $h[1] -Connection $Connection }
    }
}

# Writes the kit's hooks into RetroBat (no administrator rights needed); other hooks are only reported.
function Install-LightgunHook {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $RetroBatRoot,
        [string] $TaskPrefix = $script:LightgunTaskPrefix,
        [ValidateSet('DolphinBar', 'Bluetooth')] [string] $Connection = 'DolphinBar'
    )
    $own = @($script:LightgunHookName, $script:LightgunHelperHookName)
    $hooks = @(Get-LightgunHookFile -RetroBatRoot $RetroBatRoot -TaskPrefix $TaskPrefix -Connection $Connection)
    foreach ($dir in @($hooks | ForEach-Object { $_.Dir } | Select-Object -Unique)) {
        foreach ($other in Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Where-Object { $own -notcontains $_.Name }) {
            Write-KitLog (Get-KitText 'Lightgun.Auto.OtherHook' -f $other.FullName) -Level Warn
        }
    }
    foreach ($h in $hooks) {
        if ((Test-Path -LiteralPath $h.File) -and [IO.File]::ReadAllText($h.File) -ceq $h.Text) { continue }
        if (-not $PSCmdlet.ShouldProcess($h.File, 'Write hook')) { continue }
        New-Item -ItemType Directory -Path $h.Dir -Force | Out-Null
        [IO.File]::WriteAllText($h.File, $h.Text, [Text.Encoding]::ASCII)
        Write-KitLog (Get-KitText 'Lightgun.Auto.Hook' -f $h.File)
    }
}

function Test-LightgunHook {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RetroBatRoot,
        [string] $TaskPrefix = $script:LightgunTaskPrefix,
        [ValidateSet('DolphinBar', 'Bluetooth')] [string] $Connection = 'DolphinBar'
    )
    foreach ($h in Get-LightgunHookFile -RetroBatRoot $RetroBatRoot -TaskPrefix $TaskPrefix -Connection $Connection) {
        if (-not (Test-Path -LiteralPath $h.File -PathType Leaf) -or [IO.File]::ReadAllText($h.File) -cne $h.Text) { return $false }
    }
    $true
}
