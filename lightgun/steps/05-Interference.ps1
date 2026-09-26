<#
.SYNOPSIS
    Lightgun step 5: interference.
    - Steam: "controller_blacklist" (DolphinBar in all modes: 0x0079/0x1802, 0x0079/0x1803, 0x057e/0x0306) in
      config\config.vdf, only while Steam (and the other guarded programs) are closed; backup first.
    - Steam Input Xbox: the values in userdata\<id>\config\localconfig.vdf are reported; switch "Xbox support"
      off in Steam (Settings > Controller), the kit does not write that file.
    - GunmoteVMultiGuard task: found (administrator rights needed to see it) and, with -DisableVMultiGuard and
      a confirmation, disabled. Way back: Enable-ScheduledTask (named in the log).
.PARAMETER SteamPath
    Steam folder (default: HKCU\Software\Valve\Steam\SteamPath). No Steam = nothing to do.
.PARAMETER DisableVMultiGuard
    Allows disabling the GunmoteVMultiGuard task.
.PARAMETER Approve
    { param($text) ... } returning $true to disable the task (the wizard passes its dialog).
.PARAMETER Tasks
    Injected task list instead of Get-ScheduledTask (tests).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $SteamPath,
    [switch] $DisableVMultiGuard,
    [scriptblock] $Approve,
    [object[]] $Tasks,
    [string] $StatePath,
    [string] $Culture
)
$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1')
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1')
if ($Culture) { Set-KitCulture -Culture $Culture }
if (-not $StatePath) { $StatePath = Get-LightgunDefaultStatePath }

# --- Steam ---------------------------------------------------------------------------------------------------
if (-not $PSBoundParameters.ContainsKey('SteamPath')) { $SteamPath = Get-LightgunSteamPath }
$config = if ($SteamPath) { Join-Path $SteamPath 'config\config.vdf' } else { $null }
$hasSteam = $config -and (Test-Path -LiteralPath $config -PathType Leaf)
if (-not $hasSteam) { Write-KitLog (Get-KitText 'Lightgun.Steam.None') }
else {
    Write-KitLog (Get-KitText 'Lightgun.Steam.InputHint')
    foreach ($r in Get-LightgunSteamInputReport -SteamPath $SteamPath) { Write-KitLog (Get-KitText 'Lightgun.Steam.InputValue' -f $r.File, $r.Key, $r.Value) }
}

$blacklist = New-KitStep -Name 'lightgun-5-steam-blacklist' `
    -Test { $hasSteam -and (Test-LightgunProcessesClosed -IncludeSteam) } `
    -Invoke { $null = Set-LightgunSteamBlacklist -ConfigVdf $config -Confirm:$false } `
    -Verify { -not $hasSteam -or (Test-LightgunSteamBlacklist -ConfigVdf $config) }
Invoke-KitStep -Step $blacklist -StatePath $StatePath -WhatIf:$WhatIfPreference

# --- GunmoteVMultiGuard ----------------------------------------------------------------------------------------
$visible = $PSBoundParameters.ContainsKey('Tasks') -or (Test-KitAdmin)
$probe = @{}; if ($PSBoundParameters.ContainsKey('Tasks')) { $probe.Tasks = $Tasks }
$guards = @(if ($visible) { Get-LightgunVMultiGuardTask @probe | Where-Object { $_.Enabled } })
if (-not $visible) { Write-KitLog (Get-KitText 'Lightgun.Guard.NeedsAdmin') -Level Warn }
foreach ($g in $guards) { Write-KitLog (Get-KitText 'Lightgun.Guard.Found' -f "$($g.TaskPath)$($g.TaskName)") -Level Warn }
if ($guards -and -not $DisableVMultiGuard) { Write-KitLog (Get-KitText 'Lightgun.Guard.NeedsAllow') -Level Warn }

$guardStep = New-KitStep -Name 'lightgun-5-vmulti-guard' `
    -Test { [bool]$DisableVMultiGuard -and (Test-KitAdmin) } `
    -Invoke { foreach ($g in $guards) { Disable-LightgunVMultiGuardTask -Task $g -Approve $Approve -Confirm:$false } } `
    -Verify { $visible -and -not @(Get-LightgunVMultiGuardTask @probe | Where-Object { $_.Enabled }).Count }
Invoke-KitStep -Step $guardStep -StatePath $StatePath -WhatIf:$WhatIfPreference
