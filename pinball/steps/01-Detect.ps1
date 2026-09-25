<#
.SYNOPSIS
    Pinball step 1: detect the build (vPinball\PinUPSystem\PUPDatabase.db), check the database schema,
    derive the old root from GlobalSettings.GlobalMediaDir, find sibling folders (DOFLinx, ...), measure the size.
.PARAMETER Source
    Folder that contains vPinball (e.g. E:\My Build).
.PARAMETER StatePath
    install-state.json of the pinball package (default: pinball\install-state.json).
.PARAMETER Culture
    UI language (de-DE, en-US). Default: the Windows display language.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string] $Source,
    [string] $StatePath,
    [string] $Culture
)
$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1')
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1')
if ($Culture) { Set-KitCulture -Culture $Culture }
if (-not $StatePath) { $StatePath = Get-PinballDefaultStatePath }

function Write-BuildInfo($info) {
    Write-KitLog (Get-KitText 'Pinball.Detect.Summary' -f $info.SourceRoot, $info.OldRoot, (@($info.Siblings) -join ', '), ([math]::Round($info.SizeBytes / 1GB, 2)), $info.Files)
}

if ($WhatIfPreference -and (Test-PinballBuild -Path $Source)) { Write-BuildInfo (Get-PinballBuildInfo -Source $Source) }

$step = New-KitStep -Name 'pinball-1-detect' `
    -Test { Test-PinballBuild -Path $Source } `
    -Invoke {
        $info = Get-PinballBuildInfo -Source $Source
        Write-BuildInfo $info
        Set-KitStateValue -Path $StatePath -Key 'SourceRoot' -Value $info.SourceRoot
        Set-KitStateValue -Path $StatePath -Key 'OldRoot' -Value $info.OldRoot
        Set-KitStateValue -Path $StatePath -Key 'Siblings' -Value @($info.Siblings)
        Set-KitStateValue -Path $StatePath -Key 'BuildSizeBytes' -Value $info.SizeBytes
    } `
    -Verify {
        (Test-Path -LiteralPath $StatePath) -and
        [string](Get-KitStateValue -Path $StatePath -Key 'SourceRoot') -eq (ConvertTo-PinballRoot $Source) -and
        [bool](Get-KitStateValue -Path $StatePath -Key 'OldRoot')
    }

Invoke-KitStep -Step $step -StatePath $StatePath -WhatIf:$WhatIfPreference
