<#
.SYNOPSIS
    Lightgun step 1: detect RetroBat (emulationstation\emulationstation.exe and
    emulationstation\.emulationstation\es_settings.cfg). A missing or never started RetroBat only gets a hint
    and the link to the official releases; the kit does not install RetroBat.
.PARAMETER RetroBatRoot
    RetroBat folder (the one that contains emulationstation, emulators, roms).
.PARAMETER StatePath
    install-state.json of the lightgun package (default: lightgun\install-state.json).
.PARAMETER Culture
    UI language (de-DE, en-US). Default: the Windows display language.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string] $RetroBatRoot,
    [string] $StatePath,
    [string] $Culture
)
$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1')
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1')
if ($Culture) { Set-KitCulture -Culture $Culture }
if (-not $StatePath) { $StatePath = Get-LightgunDefaultStatePath }

$info = Get-LightgunRetroBatInfo -Root $RetroBatRoot
$problem = Get-LightgunRetroBatProblem -Root $info.Root
if ($info.Kind -eq 'Build') { Write-KitLog (Get-KitText 'Lightgun.Detect.Found' -f $info.Root, $(if ($info.Version) { $info.Version } else { '?' })) }
elseif ($problem) { Write-KitLog $problem -Level Warn }
if ($info.Kind -ne 'Build') { Write-KitLog (Get-KitText 'Lightgun.Detect.GetRetroBat' -f (Get-LightgunRetroBatReleaseUrl)) -Level Warn }

$step = New-KitStep -Name 'lightgun-1-detect' `
    -Test { -not $problem } `
    -Invoke {
        Set-KitStateValue -Path $StatePath -Key 'RetroBatRoot' -Value $info.Root
        Set-KitStateValue -Path $StatePath -Key 'RetroBatVersion' -Value $info.Version
    } `
    -Verify {
        -not $problem -and (Test-Path -LiteralPath $StatePath) -and
        [string](Get-KitStateValue -Path $StatePath -Key 'RetroBatRoot') -eq $info.Root
    }
Invoke-KitStep -Step $step -StatePath $StatePath -WhatIf:$WhatIfPreference
