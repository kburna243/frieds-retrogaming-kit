<#
.SYNOPSIS
    Lightgun step 4 (guided): Gunmote. The user downloads and installs Gunmote from the official releases
    himself (link in the log); the kit finds the installation, shows the version and registers the task
    "RetroCabinetKit Gunmote" (at logon, highest rights, the starting user) unless a task with highest rights
    already starts this Gunmote.exe. Only for a Gunmote below Program Files. Needs administrator rights.
.PARAMETER GunmotePath
    Gunmote folder when it is not found automatically.
.PARAMETER Tasks
    Injected task list instead of Get-ScheduledTask (tests).
.PARAMETER KitUserSid
    SID of the user who started the kit (passed by the elevation); the task runs for this user.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $GunmotePath,
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

$find = @{}; if ($GunmotePath) { $find.Path = $GunmotePath }
$gunmote = Find-LightgunGunmote @find
$taskProbe = @{}; if ($PSBoundParameters.ContainsKey('Tasks')) { $taskProbe.Tasks = $Tasks }
$userSid = Get-KitStartUserSid -OriginalSid $KitUserSid
if (-not $gunmote) {
    Write-KitLog (Get-KitText 'Lightgun.Gunmote.Missing' -f (Get-LightgunGunmoteReleaseUrl)) -Level Warn
} else {
    Write-KitLog (Get-KitText 'Lightgun.Gunmote.Found' -f $gunmote.Dir, $(if ($gunmote.Version) { $gunmote.Version } else { '?' }))
    if (-not $gunmote.InProgramFiles) { Write-KitLog (Get-KitText 'Lightgun.Gunmote.NotProgramFiles' -f $gunmote.Dir) -Level Warn }
    if (-not (Test-KitAdmin)) { Write-KitLog (Get-KitText 'Lightgun.Step.NeedsAdmin') -Level Warn }
    elseif (-not $userSid) { Write-KitLog (Get-KitRegistryUserLock -OriginalSid $KitUserSid) -Level Warn }
}

$step = New-KitStep -Name 'lightgun-4-gunmote' `
    -Test { [bool]$gunmote -and $gunmote.InProgramFiles -and (Test-KitAdmin) -and [bool]$userSid } `
    -Invoke { Register-LightgunGunmoteTask -Gunmote $gunmote -UserSid $userSid -Confirm:$false } `
    -Verify { [bool]$gunmote -and (Test-LightgunGunmoteTask -Exe $gunmote.Exe @taskProbe) }
Invoke-KitStep -Step $step -StatePath $StatePath -WhatIf:$WhatIfPreference
# Where Gunmote lives is a finding, not a change: later steps (layouts) read it.
if ($gunmote -and -not $WhatIfPreference) { Set-KitStateValue -Path $StatePath -Key 'GunmoteDir' -Value $gunmote.Dir }
