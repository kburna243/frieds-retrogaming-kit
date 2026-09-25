<#
.SYNOPSIS
    Pinball step 2: validate the target root (local drive, not inside the source build,
    free space >= build size + 10 %). The build will live in <TargetRoot>\vPinball.
.PARAMETER TargetRoot
    New root folder, e.g. E:\Games. The same folder as the source means "keep the build where it is".
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [string] $TargetRoot,
    [string] $StatePath,
    [string] $Culture
)
$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1')
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1')
if ($Culture) { Set-KitCulture -Culture $Culture }
if (-not $StatePath) { $StatePath = Get-PinballDefaultStatePath }

$sourceRoot = Get-KitStateValue -Path $StatePath -Key 'SourceRoot'
$size = [long](Get-KitStateValue -Path $StatePath -Key 'BuildSizeBytes')
if (-not $sourceRoot) { Write-KitLog (Get-KitText 'Pinball.Step.RunDetectFirst') -Level Warn }

$step = New-KitStep -Name 'pinball-2-target' `
    -Test { [bool]$sourceRoot } `
    -Invoke {
        $check = Test-PinballTarget -TargetRoot $TargetRoot -SourceRoot $sourceRoot -SizeBytes $size
        Write-KitLog (Get-KitText 'Pinball.Target.Summary' -f $check.TargetRoot, ([math]::Round($check.FreeBytes / 1GB, 2)), ([math]::Round($check.RequiredBytes / 1GB, 2)))
        if (-not $check.IsValid) { throw $check.Reason }
        Set-KitStateValue -Path $StatePath -Key 'TargetRoot' -Value $check.TargetRoot
    } `
    -Verify {
        $saved = [string](Get-KitStateValue -Path $StatePath -Key 'TargetRoot')
        [bool]$saved -and $saved -eq (ConvertTo-PinballRoot $TargetRoot) -and (New-Object IO.DriveInfo ($saved.Substring(0, 1))).IsReady
    }

Invoke-KitStep -Step $step -StatePath $StatePath -WhatIf:$WhatIfPreference
