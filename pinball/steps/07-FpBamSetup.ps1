<#
.SYNOPSIS
    Pinball step 7: Future Pinball / BAM first-time setup.
    - "Disable fullscreen optimizations" for FPLoader.exe and Future Pinball.exe below the new root
    - BAM settings - Cabinet - Reset and Install.bat (run as cmd /c "<bat>" < nul)
    - mandatory checklist: start FPLoader.exe once as administrator (confirm with -ConfirmFpLoaderAdminRun)
.PARAMETER LayersKey
    AppCompatFlags\Layers key (default: HKCU). Tests pass a test key.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $Root,
    [switch] $ConfirmFpLoaderAdminRun,
    [string] $LayersKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers',
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

$exes = @(if ($Root) { Get-PinballFpExecutable -Root $Root })
$bat = if ($Root) { Find-PinballBamBat -Root $Root }
if ($Root -and -not $bat) { Write-KitLog (Get-KitText 'Pinball.FpBam.NoBat') -Level Warn }
$guide = if ($Root) { Find-PinballInstallGuide -Root $Root }
if ($guide) { Write-KitLog (Get-KitText 'Pinball.FpBam.Guide' -f $guide) }

$oldRoot = Get-KitStateValue -Path $StatePath -Key 'OldRoot'
if ($Root -and $oldRoot) {
    $relocator = New-PinballRelocator -OldRoot $oldRoot -NewRoot $Root
    foreach ($l in Get-PinballLegacyAppCompat -Roots $LayersKey -Relocator $relocator) { Write-KitLog (Get-KitText 'Pinball.Relocate.Legacy' -f $l.Key, $l.Name) -Level Warn }
}

$setup = New-KitStep -Name 'pinball-7-fpbam' `
    -Test { [bool]$Root -and [bool]$bat -and -not @($exes | Where-Object { -not (Test-Path -LiteralPath $_) }).Count } `
    -Invoke {
        foreach ($c in Set-PinballFullscreenOptimizationOff -Executable $exes -LayersKey $LayersKey -Confirm:$false) {
            Write-KitLog (Get-KitText 'Pinball.FpBam.Flag' -f $c.Name, $c.New)
        }
        $code = Invoke-PinballBat -Path $bat -Confirm:$false
        if ($code -ne 0) { throw (Get-KitText 'Pinball.FpBam.BatFailed' -f $bat, $code) }
        Set-KitStateValue -Path $StatePath -Key 'BamBatDone' -Value $true
    } `
    -Verify {
        [bool]$Root -and (Test-PinballFullscreenOptimizationOff -Executable $exes -LayersKey $LayersKey) -and
        [bool](Get-KitStateValue -Path $StatePath -Key 'BamBatDone')
    }
Invoke-KitStep -Step $setup -StatePath $StatePath -WhatIf:$WhatIfPreference

if ($exes) { Write-KitLog (Get-KitText 'Pinball.FpBam.AdminChecklist' -f $exes[0]) -Level Warn }
$admin = New-KitStep -Name 'pinball-7-fploader-admin' `
    -Test { [bool]$ConfirmFpLoaderAdminRun } `
    -Invoke { Set-KitStateValue -Path $StatePath -Key 'FpLoaderAdminConfirmed' -Value $true } `
    -Verify { [bool](Get-KitStateValue -Path $StatePath -Key 'FpLoaderAdminConfirmed') }
Invoke-KitStep -Step $admin -StatePath $StatePath -WhatIf:$WhatIfPreference
