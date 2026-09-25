<#
.SYNOPSIS
    Lightgun step 13: Model 2 & Supermodel (Sega Model 2 and Model 3 lightgun setup).
    - lightgun-13-model2:          Model 2 emulator checks: user supplies Model 2 emulator (EMULATOR.EXE,
                                   emulator_multicpu.exe, Emulator.ini). Closed source, no download provided.
                                   DemulShooter hooks via -target=model2m.
    - lightgun-13-supermodel:      Supermodel checks and configuration (Crosshairs=1, XInput gun bindings).
                                   Official releases from trzy/Supermodel.
    - lightgun-13-model-settings:  RetroBat es_settings.cfg: model2.use_guns=0, model3.use_guns=0,
                                   model2.disableautocontrollers=1, model3.disableautocontrollers=1.
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
if ($rb.Problem) {
    Write-KitLog $rb.Problem -Level Warn
    return
}

$paths = Get-LightgunModel2Path -RetroBatRoot $rb.Root
$esPath = (Get-LightgunRetroBatPath -Root $rb.Root).EsSettings

# --- 1. Model 2 -----------------------------------------------------------------------------------------------
$m2Info = Test-LightgunModel2Installed -RetroBatRoot $rb.Root
if (-not $m2Info.Installed) {
    Write-KitLog (Get-KitText 'Lightgun.Model2.Missing' -f $paths.Model2Dir) -Level Warn
    Write-KitLog (Get-KitText 'Lightgun.Model2.UserSupplied') -Level Warn
} else {
    Write-KitLog (Get-KitText 'Lightgun.Model2.Found' -f $m2Info.ExePath)
    Write-KitLog (Get-KitText 'Lightgun.Model2.DsHint')
}

$m2Step = New-KitStep -Name 'lightgun-13-model2' `
    -Test { $m2Info.Installed } `
    -Invoke {
        Set-KitStateValue -Path $StatePath -Key 'Model2Dir' -Value $paths.Model2Dir
    } `
    -Verify {
        (Test-LightgunModel2Installed -RetroBatRoot $rb.Root).Installed
    }
Invoke-KitStep -Step $m2Step -StatePath $StatePath -WhatIf:$WhatIfPreference

# --- 2. Supermodel --------------------------------------------------------------------------------------------
$smInfo = Test-LightgunSupermodelInstalled -RetroBatRoot $rb.Root
if (-not $smInfo.Installed) {
    Write-KitLog (Get-KitText 'Lightgun.Supermodel.Missing' -f $paths.SupermodelDir) -Level Warn
    Write-KitLog (Get-KitText 'Lightgun.Supermodel.Download' -f (Get-LightgunSupermodelReleaseUrl)) -Level Warn
} else {
    Write-KitLog (Get-KitText 'Lightgun.Supermodel.Found' -f $smInfo.ExePath)
}

function Get-SmPlan { @(Get-LightgunSupermodelConfigPlan -ConfigPath $paths.SupermodelIni) }

if ($smInfo.Installed) {
    $plan = Get-SmPlan
    Write-KitLog (Get-KitText 'Lightgun.Supermodel.ConfigPreview' -f $plan.Count)
    foreach ($p in $plan) {
        Write-KitLog ('  [{0}] {1}: {2} -> {3}' -f $p.Section, $p.Key, $(if ($null -eq $p.Old) { '-' } else { $p.Old }), $p.New)
    }
}

$smStep = New-KitStep -Name 'lightgun-13-supermodel' `
    -Test { $smInfo.Installed } `
    -Invoke {
        $null = Set-LightgunSupermodelConfig -ConfigPath $paths.SupermodelIni -Plan (Get-SmPlan)
        Set-KitStateValue -Path $StatePath -Key 'SupermodelDir' -Value $paths.SupermodelDir
    } `
    -Verify {
        $smInfo.Installed -and -not @(Get-SmPlan).Count
    }
Invoke-KitStep -Step $smStep -StatePath $StatePath -WhatIf:$WhatIfPreference

# --- 3. RetroBat es_settings.cfg -------------------------------------------------------------------------------
$targetSettings = [ordered]@{
    'model2.use_guns'                  = '0'
    'model2.disableautocontrollers'    = '1'
    'model3.use_guns'                  = '0'
    'model3.disableautocontrollers'    = '1'
}

function Get-ModelEsPlan { @(Get-LightgunEsSettingsPlan -Path $esPath -Target $targetSettings) }

$esPlan = Get-ModelEsPlan
Write-KitLog (Get-KitText 'Lightgun.Model2.EsPreview' -f $esPlan.Count)
foreach ($c in $esPlan) {
    Write-KitLog ('  {0}: {1} -> {2}' -f $c.Name, $(if ($null -eq $c.Old) { '-' } else { $c.Old }), $c.New)
}

$settingsStep = New-KitStep -Name 'lightgun-13-model-settings' `
    -Test { Test-LightgunProcessesClosed } `
    -Invoke {
        $null = Set-LightgunEsSettings -Path $esPath -Target $targetSettings -Confirm:$false
    } `
    -Verify {
        -not @(Get-ModelEsPlan).Count
    }
Invoke-KitStep -Step $settingsStep -StatePath $StatePath -WhatIf:$WhatIfPreference
