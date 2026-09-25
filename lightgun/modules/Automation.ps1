# Automation (step 8) [W7]: Gunmote profile per system, without the Home button.
#   %ProgramData%\RetroCabinetKit\lightgun\profile.ps1   the watcher (kit template), folder writable only for
#                                                         Administrators and SYSTEM (users may read the log)
#   tasks "RetroCabinetKit Gunmote Profile <Name>"        highest rights, the logged-on user, start profile.ps1
#   RetroBat scripts\game-start\ and game-end\            .bat hooks that ONLY run "schtasks /run /tn ..."
# Nothing with administrator rights ever runs from the RetroBat folder: a user can change the hooks, but they
# can only start the fixed tasks, which run the admin-only script with a checked layout title.

$script:LightgunTaskPrefix = 'RetroCabinetKit Gunmote Profile'
$script:LightgunHookName = 'rck-gunmote-profile.bat'

# RetroBat system -> profile. Naomi/Atomiswave get their own task (DemulShooter joins in P3b), aiming like Pad43.
$script:LightgunSystemProfiles = [ordered]@{
    teknoparrot  = 'TP'
    naomi        = 'Naomi'
    atomiswave   = 'Naomi'
    mame         = 'Pad43'
    psx          = 'Pad43'
    model2       = 'Pad43'
    model3       = 'Pad43'
    nes          = 'Mouse'
    snes         = 'Mouse'
    megadrive    = 'Mouse'
    mastersystem = 'Mouse'
    ps2          = 'Mouse'
}

# Profile -> layout kind (step 6 recorded one title per kind).
$script:LightgunProfileKinds = [ordered]@{ Menu = 'Menu'; TP = 'TP'; Pad43 = 'Pad43'; Naomi = 'Pad43'; Mouse = 'Mouse' }

function Get-LightgunSystemProfile {
    [CmdletBinding()]
    param()
    $script:LightgunSystemProfiles
}

function Get-LightgunProfileFor {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $System)
    $key = $System.ToLowerInvariant()
    if ($script:LightgunSystemProfiles.Contains($key)) { $script:LightgunSystemProfiles[$key] }
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
        [string] $TaskPrefix = $script:LightgunTaskPrefix
    )
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
        foreach ($s in $script:LightgunSystemProfiles.Keys) {
            $lines.Add(('if not defined PROFILE if not "%ROM:\roms\{0}\=%"=="%ROM%" set "PROFILE={1}"' -f $s, $script:LightgunSystemProfiles[$s]))
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
        [string] $TaskPrefix = $script:LightgunTaskPrefix
    )
    $script = Join-Path $AutomationDir 'profile.ps1'
    foreach ($p in $script:LightgunProfileKinds.Keys) {
        $kind = $script:LightgunProfileKinds[$p]
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

# Writes the two hooks into RetroBat (no administrator rights needed); other hooks are only reported.
function Install-LightgunHook {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [string] $RetroBatRoot, [string] $TaskPrefix = $script:LightgunTaskPrefix)
    $p = Get-LightgunRetroBatPath -Root $RetroBatRoot
    foreach ($h in @(@($p.HookStart, 'Start'), @($p.HookEnd, 'End'))) {
        $file = Join-Path $h[0] $script:LightgunHookName
        $text = New-LightgunHookText -Kind $h[1] -TaskPrefix $TaskPrefix
        foreach ($other in Get-ChildItem -LiteralPath $h[0] -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne $script:LightgunHookName }) {
            Write-KitLog (Get-KitText 'Lightgun.Auto.OtherHook' -f $other.FullName) -Level Warn
        }
        if ((Test-Path -LiteralPath $file) -and [IO.File]::ReadAllText($file) -ceq $text) { continue }
        if (-not $PSCmdlet.ShouldProcess($file, 'Write hook')) { continue }
        New-Item -ItemType Directory -Path $h[0] -Force | Out-Null
        [IO.File]::WriteAllText($file, $text, [Text.Encoding]::ASCII)
        Write-KitLog (Get-KitText 'Lightgun.Auto.Hook' -f $file)
    }
}

function Test-LightgunHook {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RetroBatRoot, [string] $TaskPrefix = $script:LightgunTaskPrefix)
    $p = Get-LightgunRetroBatPath -Root $RetroBatRoot
    foreach ($h in @(@($p.HookStart, 'Start'), @($p.HookEnd, 'End'))) {
        $file = Join-Path $h[0] $script:LightgunHookName
        if (-not (Test-Path -LiteralPath $file -PathType Leaf) -or [IO.File]::ReadAllText($file) -cne (New-LightgunHookText -Kind $h[1] -TaskPrefix $TaskPrefix)) { return $false }
    }
    $true
}
