<#
.SYNOPSIS
    Lightgun step 9: measured checks instead of guessing (changes nothing on the system).
    - lightgun-9-xinput:   which virtual Xbox pads exist (XInputGetState); per pad "press the trigger now" with a
                           timeout. No pad at all = Gunmote not running, ViGEmBus missing or DolphinBar not in Mode 4.
    - lightgun-9-profile:  the profile automation's log shows that a game start sent a game layout
                           (start a MAME or TeknoParrot game from RetroBat, then run the check again).
    - lightgun-9-launcher: the last start in emulatorLauncher.log: system, emulator, core; for the kit's gun
                           systems RetroBat must NOT have assigned guns itself (use_guns=0 works).
.PARAMETER XInputTimeoutSeconds
    Time per pad to press the trigger.
.PARAMETER Again
    Measure the pads again even when an earlier measurement succeeded.
.PARAMETER XInputReader
    { param($pad) ... } returning Connected/Buttons instead of the real XInput query (tests).
.PARAMETER ProfileLog
    Log of the profile automation (default: logs\profile.log in the automation folder of step 8).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $RetroBatRoot,
    [ValidateRange(1, 120)] [int] $XInputTimeoutSeconds = 15,
    [switch] $Again,
    [scriptblock] $XInputReader,
    [string] $ProfileLog,
    [string] $StatePath,
    [string] $Culture
)
$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1')
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1')
if ($Culture) { Set-KitCulture -Culture $Culture }
if (-not $StatePath) { $StatePath = Get-LightgunDefaultStatePath }
$reader = @{}; if ($XInputReader) { $reader.Reader = $XInputReader }

# --- XInput ----------------------------------------------------------------------------------------------------
if ($Again -and -not $WhatIfPreference) { Set-KitStateValue -Path $StatePath -Key 'XInputPressed' -Value $null }
$pads = @(Get-LightgunXInputPad @reader)
if ($pads) { Write-KitLog (Get-KitText 'Lightgun.Verify.Pads' -f (($pads | ForEach-Object { $_.Pad }) -join ', ')) }
else { Write-KitLog (Get-KitText 'Lightgun.Verify.NoPad') -Level Warn }
$xinput = New-KitStep -Name 'lightgun-9-xinput' `
    -Test { [bool]$pads } `
    -Invoke {
        $ok = @(foreach ($p in $pads) {
            Write-KitLog (Get-KitText 'Lightgun.Verify.PressNow' -f $p.Pad, $XInputTimeoutSeconds) -Level Warn
            $r = Wait-LightgunXInputPress -Pad $p.Pad -TimeoutSeconds $XInputTimeoutSeconds @reader
            if ($r.Status -eq 'Pressed') { Write-KitLog (Get-KitText 'Lightgun.Verify.Pressed' -f $r.Pad, ($r.Buttons -join '+')); $r.Pad }
            else { Write-KitLog (Get-KitText "Lightgun.Verify.$($r.Status)" -f $r.Pad) -Level Warn }
        })
        # As text: pad 0 alone would read back as the number 0, which counts as "false".
        if ($ok.Count) { Set-KitStateValue -Path $StatePath -Key 'XInputPressed' -Value ($ok -join ',') }
    } `
    -Verify { [bool][string](Get-KitStateValue -Path $StatePath -Key 'XInputPressed') }
Invoke-KitStep -Step $xinput -StatePath $StatePath -WhatIf:$WhatIfPreference

# --- profile switch -------------------------------------------------------------------------------------------
if (-not $ProfileLog) {
    $dir = [string](Get-KitStateValue -Path $StatePath -Key 'AutomationDir')
    $ProfileLog = if ($dir) { Get-LightgunProfileLogPath -AutomationDir $dir } else { Get-LightgunProfileLogPath }
}
$titles = Get-KitStateValue -Path $StatePath -Key 'LayoutTitles'
$menu = if ($titles) { [string]$titles.Menu } else { '' }
$since = [datetime]::MinValue
$installed = [string](Get-KitStateValue -Path $StatePath -Key 'AutomationInstalledAt')
if ($installed) { $since = [datetime]::Parse($installed, [Globalization.CultureInfo]::InvariantCulture, 'RoundtripKind').ToLocalTime().AddSeconds(-1) }
foreach ($e in @(Get-LightgunProfileEvent -LogPath $ProfileLog) | Select-Object -Last 8) { Write-KitLog ('  {0:HH:mm:ss} {1} {2}' -f $e.Time, $e.Kind, $e.Detail) }
$switched = [bool]$menu -and (Test-LightgunProfileSwitch -LogPath $ProfileLog -MenuTitle $menu -Since $since)
if (-not $switched) { Write-KitLog (Get-KitText 'Lightgun.Verify.NoSwitch' -f $ProfileLog) -Level Warn }
$profileStep = New-KitStep -Name 'lightgun-9-profile' -Test { $switched } -Invoke { } -Verify { $switched }
Invoke-KitStep -Step $profileStep -StatePath $StatePath -WhatIf:$WhatIfPreference

# --- emulatorLauncher.log --------------------------------------------------------------------------------------
$rb = Resolve-LightgunRetroBat -Root $RetroBatRoot -StatePath $StatePath
$report = if (-not $rb.Problem) { Get-LightgunLauncherReport -Path (Get-LightgunRetroBatPath -Root $rb.Root).LauncherLog }
$launcherOk = $false
if (-not $report) { if (-not $rb.Problem) { Write-KitLog (Get-KitText 'Lightgun.Verify.NoStart') -Level Warn } }
else {
    Write-KitLog (Get-KitText 'Lightgun.Verify.LastStart' -f $report.Time, $report.System, $report.Emulator, $report.Core, $report.Rom)
    if ($report.Running) { Write-KitLog "  $($report.Running)" }
    $gunSystem = (Get-LightgunGunSystem) -contains $report.System
    if ($gunSystem -and $report.GunAutomation) { Write-KitLog (Get-KitText 'Lightgun.Verify.GunAutomation' -f $report.System) -Level Warn }
    elseif ($report.GunAutomation) { Write-KitLog (Get-KitText 'Lightgun.Verify.GunAutomationOther' -f $report.System) }
    $launcherOk = -not ($gunSystem -and $report.GunAutomation)
}
$launcher = New-KitStep -Name 'lightgun-9-launcher' -Test { $launcherOk } -Invoke { } -Verify { $launcherOk }
Invoke-KitStep -Step $launcher -StatePath $StatePath -WhatIf:$WhatIfPreference
