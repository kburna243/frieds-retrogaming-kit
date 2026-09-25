<#
.SYNOPSIS
    Pinball step 8: screens. Captures the monitors (DPI aware), checks the official layout rules
    (100 % scaling, no negative coordinates, playfield = main display, others right of or below it),
    shows a diff (old -> new) for Popper Screens, PinUpPlayer.ini, both DmdDevice.ini [virtualdmd],
    ScreenRes.txt, VPinballX.ini [Player], the VPX and the Future Pinball registry, and writes it with backups.
    VPX FullScreen is never touched. -WhatIf only shows the diff.
.PARAMETER Mode
    Keep    = existing valid values stay; only missing values or values outside the desktop are proposed (default).
    Replace = every value is set from the layout (role areas and measured windows).
.PARAMETER Layout
    Object with Roles (role -> \\.\DISPLAYn) and Windows (consumer -> X, Y, Width, Height), as the wizard builds it.
    Default: the layout saved by the last run, else roles by position (playfield = main display).
.PARAMETER Monitors
    Injected monitors (tests). Default: the real monitors of this machine.
.PARAMETER Paths
    Overrides single target locations (Popper, PinUpPlayer, VpmDmdDevice, FpDmdDevice, ScreenRes, VpxIni,
    VpxRegistry, FpRegistry).
.PARAMETER AnswerFile
    Set for an unattended run: nobody can check the screens, so the step is locked.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $Root,
    [ValidateSet('Keep', 'Replace')] [string] $Mode = 'Keep',
    [object] $Layout,
    [object[]] $Monitors,
    [hashtable] $Paths = @{},
    [string] $BackupDir,
    [string] $AnswerFile,
    [string] $StatePath,
    [string] $Culture
)
$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1')
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1')
if ($Culture) { Set-KitCulture -Culture $Culture }
if (-not $StatePath) { $StatePath = Get-PinballDefaultStatePath }
if (-not $Root) { $Root = Get-KitStateValue -Path $StatePath -Key 'TargetRoot' }
if (-not $Root) { Write-KitLog (Get-KitText 'Pinball.Step.RunTargetFirst') -Level Warn }
if (-not $BackupDir) { $BackupDir = Join-Path (Split-Path -Parent $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($StatePath)) 'backups' }

$lock = Get-PinballScreenLock -AnswerFile $AnswerFile
if ($lock) { Write-KitLog $lock -Level Warn }

$monitorList = @(if (-not $lock) { Get-PinballMonitor -Monitors $Monitors })
foreach ($m in $monitorList) {
    Write-KitLog (Get-KitText 'Pinball.Screens.Monitor' -f $m.DeviceName, $m.X, $m.Y, $m.Width, $m.Height, $m.Scale, $m.RefreshRate, $(if ($m.Primary) { '*' } else { '' }))
}
if (-not $Layout) { $Layout = Get-KitStateValue -Path $StatePath -Key 'ScreenLayout' }
$saved = ConvertTo-PinballHashtable $Layout
$screenLayout = if ($monitorList) { New-PinballScreenLayout -Monitors $monitorList -Roles $saved['Roles'] -Windows $saved['Windows'] }

$violations = @(if ($screenLayout) { Test-PinballMonitorLayout -Monitors $monitorList -Roles $screenLayout.Roles })
foreach ($v in $violations) { Write-KitLog $v.Message -Level Warn }

$targets = @(if ($Root -or $Paths.Count) { Get-PinballScreenTarget -Root $Root -Paths $Paths })
function Get-Plan { Get-PinballScreenPlan -Layout $screenLayout -Targets $targets -Mode $Mode }
if ($screenLayout -and -not $violations) {
    foreach ($line in Format-PinballScreenPlan -Plan @(Get-Plan)) { Write-KitLog $line }
}

$step = New-KitStep -Name 'pinball-8-screens' `
    -Test { -not $lock -and [bool]$screenLayout -and -not $violations -and $targets.Count -gt 0 } `
    -Invoke {
        $written = @(Invoke-PinballScreenPlan -Plan @(Get-Plan) -Layout $screenLayout -BackupDir $BackupDir -Confirm:$false)
        $layoutValue = [pscustomobject]@{ Roles = $screenLayout.Roles; Windows = $screenLayout.Windows }
        Set-KitStateValue -Path $StatePath -Key 'ScreenLayout' -Value $layoutValue
        # Way back for the wizard: the backups of the last run that wrote something (Restore-PinballScreenBackup).
        if ($written.Count) { Set-KitStateValue -Path $StatePath -Key 'ScreenLastWritten' -Value $written }
    } `
    -Verify {
        if (-not $screenLayout -or $violations -or -not $targets.Count) { return $false }
        # Unresolved entries (e.g. no topper monitor, no Popper row) are warnings in the diff, not failures.
        (Get-PinballScreenChangeCount -Plan @(Get-Plan)) -eq 0 -and [bool](Get-KitStateValue -Path $StatePath -Key 'ScreenLayout')
    }

Invoke-KitStep -Step $step -StatePath $StatePath -WhatIf:$WhatIfPreference
