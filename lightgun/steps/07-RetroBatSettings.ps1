<#
.SYNOPSIS
    Lightgun step 7: RetroBat settings.
    - es_settings.cfg: use_guns=0 and disableautocontrollers=1 for mame, naomi, atomiswave, psx, model2, model3,
      teknoparrot; mame -> mame64 (lightgun as joystick over xinput, ctrlr profile custom1), naomi -> demul
      (use_demulshooter=0), psx -> duckstation.
    - es_input.cfg: complete "Xbox 360 Controller" block with a = button 0, b = button 1 (measured: the trigger starts the game).
    - Reported, never changed: per-game overrides and gamelist entries with a hard-wired <emulator>/<core>.
    Preview of every change first; written only while RetroBat, Gunmote, Steam and emulators are closed
    (checked again before every file), comments and order are kept, backups next to the files. A second run
    changes nothing.
.PARAMETER RetroBatRoot
    RetroBat folder (default: the one found in step 1).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $RetroBatRoot,
    [string] $StatePath,
    [string] $Culture
)
$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1')
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1')
if ($Culture) { Set-KitCulture -Culture $Culture }
if (-not $StatePath) { $StatePath = Get-LightgunDefaultStatePath }

$rb = Resolve-LightgunRetroBat -Root $RetroBatRoot -StatePath $StatePath
$paths = if (-not $rb.Problem) { Get-LightgunRetroBatPath -Root $rb.Root }
$hasInput = $paths -and (Test-Path -LiteralPath $paths.EsInput -PathType Leaf)

function Get-Plan {
    @(Get-LightgunEsSettingsPlan -Path $paths.EsSettings)
    if ($hasInput) { @(Get-LightgunEsInputPlan -Path $paths.EsInput) }
}

if ($paths) {
    $plan = @(Get-Plan)
    Write-KitLog (Get-KitText 'Lightgun.Settings.Preview' -f $plan.Count)
    foreach ($c in $plan) {
        $old = if ($null -eq $c.Old) { '-' } else { $c.Old }
        Write-KitLog ('  {0}: {1}: {2} -> {3}' -f (Split-Path -Leaf $c.File), $c.Name, $old, $c.New)
    }
    if (-not $hasInput) { Write-KitLog (Get-KitText 'Lightgun.Settings.NoInput' -f $paths.EsInput) -Level Warn }
    foreach ($o in Get-LightgunEsOverride -Path $paths.EsSettings) { Write-KitLog (Get-KitText 'Lightgun.Settings.Override' -f $o.System, $o.Game, $o.Key, $o.Value) -Level Warn }
    foreach ($g in Get-LightgunGamelistOverride -RetroBatRoot $rb.Root) { Write-KitLog (Get-KitText 'Lightgun.Settings.Gamelist' -f $g.System, $g.Game, $g.Emulator, $g.Core) -Level Warn }
}

$step = New-KitStep -Name 'lightgun-7-retrobat-settings' `
    -Test { [bool]$paths -and (Test-LightgunProcessesClosed) } `
    -Invoke {
        $null = Set-LightgunEsSettings -Path $paths.EsSettings -Confirm:$false
        if ($hasInput) { $null = Set-LightgunEsInput -Path $paths.EsInput -Confirm:$false }
    } `
    -Verify { [bool]$paths -and -not @(Get-Plan).Count }
Invoke-KitStep -Step $step -StatePath $StatePath -WhatIf:$WhatIfPreference
