<#
.SYNOPSIS
    Lightgun step 8 [W7]: profile automation.
    - profile.ps1 (the kit's watcher) into %ProgramData%\RetroCabinetKit\lightgun, a folder only Administrators
      and SYSTEM can change (users may read the log);
    - scheduled tasks "RetroCabinetKit Gunmote Profile <Menu|TP|Pad43|Naomi|Mouse>" with highest rights for the
      logged-on user, each starting profile.ps1 with the layout title recorded in step 6;
    - RetroBat hooks scripts\game-start\ and scripts\game-end\rck-gunmote-profile.bat that ONLY run
      "schtasks /run /tn ..." (teknoparrot -> TP, mame/psx/model2/model3 -> Pad43, naomi/atomiswave -> Naomi,
      RetroArch light gun systems and PCSX2 -> Mouse; game end -> Menu).
    Needs administrator rights; run step 6 first.
.PARAMETER AutomationDir
    Folder for profile.ps1 (default: %ProgramData%\RetroCabinetKit\lightgun). Tests use TEMP.
.PARAMETER TaskPrefix
    Name prefix of the tasks (default: "RetroCabinetKit Gunmote Profile"). Tests use their own.
.PARAMETER Tasks
    Injected task list for the check instead of Get-ScheduledTask (tests).
.PARAMETER KitUserSid
    SID of the user who started the kit (passed by the elevation); the tasks run for this user. Locked like the
    registry steps when the kit runs elevated as a different account.
.PARAMETER Approve
    { param($text) ... } returning $true for the plan: every task with the script and arguments it starts, and
    profile.ps1 with SHA256. The wizard passes its dialog; without it the console asks.
.PARAMETER TrustedOwner
    Owners accepted for an existing automation folder (default: Administrators, SYSTEM). Tests add their own.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $RetroBatRoot,
    [string] $AutomationDir,
    [scriptblock] $Approve,
    [string[]] $TrustedOwner = @('S-1-5-32-544', 'S-1-5-18'),
    [string] $TaskPrefix = 'RetroCabinetKit Gunmote Profile',
    [object[]] $Tasks,
    [string] $KitUserSid,
    [string] $StatePath,
    [string] $Culture
)
$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1')
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1')
if ($Culture) { Set-KitCulture -Culture $Culture }
if (-not $StatePath) { $StatePath = Get-LightgunDefaultStatePath }
if (-not $AutomationDir) { $AutomationDir = Get-LightgunAutomationDir }

$rb = Resolve-LightgunRetroBat -Root $RetroBatRoot -StatePath $StatePath
$titles = Get-KitStateValue -Path $StatePath -Key 'LayoutTitles'
$plan = $null
if (-not $titles) { Write-KitLog (Get-KitText 'Lightgun.Auto.RunLayoutsFirst') -Level Warn }
else {
    try { $plan = @(Get-LightgunProfileTaskPlan -Titles $titles -AutomationDir $AutomationDir -TaskPrefix $TaskPrefix) }
    catch { Write-KitLog $_.Exception.Message -Level Warn }
}
foreach ($t in @($plan)) { if ($t) { Write-KitLog (Get-KitText 'Lightgun.Auto.TaskPlan' -f $t.TaskName, $t.Argument) } }
foreach ($s in (Get-LightgunSystemProfile).GetEnumerator()) { Write-KitLog (Get-KitText 'Lightgun.Auto.Map' -f $s.Key, $s.Value) }

$userSid = Get-KitStartUserSid -OriginalSid $KitUserSid
$admin = Test-KitAdmin
# Tasks with highest rights for another account than the one logged on are never created (N4).
$userLock = if ($admin) { Get-KitRegistryUserLock -OriginalSid $KitUserSid }
if (-not $admin) { Write-KitLog (Get-KitText 'Lightgun.Step.NeedsAdmin') -Level Warn }
elseif ($userLock) { Write-KitLog $userLock -Level Warn }
$taskProbe = @{}; if ($PSBoundParameters.ContainsKey('Tasks')) { $taskProbe.Tasks = $Tasks }

$step = New-KitStep -Name 'lightgun-8-profile-automation' `
    -Test { -not $rb.Problem -and [bool]$plan -and $admin -and [bool]$userSid -and -not $userLock } `
    -Invoke {
        $exe = Get-LightgunPowerShellPath
        $template = Get-KitFilePlan -Path (Get-LightgunTemplatePath)
        $lines = @($plan | ForEach-Object { Get-KitText 'Lightgun.Task.Plan' -f $_.TaskName, $exe, $_.Argument, (ConvertTo-LightgunUserName $userSid) })
        if (-not (Confirm-KitPlan -Lines $lines -FilePlan @($template) -Approve $Approve)) { throw (Get-KitText 'Plan.Declined') }
        Install-LightgunAutomationFile -AutomationDir $AutomationDir -TrustedOwner $TrustedOwner -Confirm:$false
        # The installed copy must be the confirmed script.
        if ((Get-FileHash -LiteralPath (Join-Path $AutomationDir 'profile.ps1') -Algorithm SHA256).Hash -ne $template.Sha256) { throw (Get-KitText 'Plan.Changed' -f $template.Path) }
        Register-LightgunProfileTask -Plan $plan -UserSid $userSid -Confirm:$false
        Install-LightgunHook -RetroBatRoot $rb.Root -TaskPrefix $TaskPrefix -Confirm:$false
        Set-KitStateValue -Path $StatePath -Key 'AutomationInstalledAt' -Value ((Get-Date).ToString('o'))
        Set-KitStateValue -Path $StatePath -Key 'AutomationDir' -Value $AutomationDir
    } `
    -Verify {
        -not $rb.Problem -and [bool]$plan -and (Test-LightgunAutomationFile -AutomationDir $AutomationDir) -and
        (Test-LightgunProfileTask -Plan $plan @taskProbe) -and (Test-LightgunHook -RetroBatRoot $rb.Root -TaskPrefix $TaskPrefix)
    }
Invoke-KitStep -Step $step -StatePath $StatePath -WhatIf:$WhatIfPreference
