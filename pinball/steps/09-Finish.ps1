<#
.SYNOPSIS
    Pinball step 9: finish. Final kit backup (ZIP with manifest: Popper database, INIs, ScreenRes, VPX
    settings and the Future Pinball, VPinMAME, B2S and VPX registry keys), optionally the Popper autostart
    through the build's own RunWindowsStartup.bat (only with -EnableAutostart, the wizard asks first),
    and the reminder to restart Windows (B2S and COM registrations take effect after a restart).
.PARAMETER Paths
    Overrides single file locations as in step 8 (tests).
.PARAMETER RegistryKeys
    Registry keys to back up (default: Future Pinball, VPinMAME, B2S, Visual Pinball below HKCU\Software).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $Root,
    [switch] $EnableAutostart,
    [string] $BackupDir,
    [hashtable] $Paths = @{},
    [string[]] $RegistryKeys,
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

$setArgs = @{ Paths = $Paths }
if ($PSBoundParameters.ContainsKey('RegistryKeys')) { $setArgs.RegistryKeys = $RegistryKeys }
$set = if ($Root) { Get-PinballFinishBackupSet -Root $Root @setArgs }
if ($set) { Write-KitLog (Get-KitText 'Pinball.Finish.Plan' -f $set.Files.Count, $set.Registry.Count, $BackupDir) }

$backup = New-KitStep -Name 'pinball-9-backup' `
    -Test { [bool]$set -and ($set.Files.Count + $set.Registry.Count) -gt 0 } `
    -Invoke {
        $zip = New-KitBackup -Files $set.Files -Registry $set.Registry -Destination (Join-Path $BackupDir ('pinball-finish_{0:yyyyMMdd-HHmmss}.zip' -f (Get-Date)))
        Set-KitStateValue -Path $StatePath -Key 'FinishBackup' -Value $zip.Path
    } `
    -Verify {
        $zip = [string](Get-KitStateValue -Path $StatePath -Key 'FinishBackup')
        [bool]$zip -and (Test-Path -LiteralPath $zip) -and [bool](Get-KitBackupManifest -Path $zip)
    }
Invoke-KitStep -Step $backup -StatePath $StatePath -WhatIf:$WhatIfPreference

if ($EnableAutostart) {
    $bat = if ($Root) { Find-PinballStartupBat -Root $Root }
    if (-not $bat) { Write-KitLog (Get-KitText 'Pinball.Finish.NoStartupBat') -Level Warn }
    $autostart = New-KitStep -Name 'pinball-9-autostart' `
        -Test { [bool]$bat } `
        -Invoke {
            $code = Invoke-PinballBat -Path $bat -Confirm:$false
            if ($code -ne 0) { throw (Get-KitText 'Pinball.FpBam.BatFailed' -f $bat, $code) }
            Set-KitStateValue -Path $StatePath -Key 'AutostartDone' -Value $true
        } `
        -Verify { [bool](Get-KitStateValue -Path $StatePath -Key 'AutostartDone') }
    Invoke-KitStep -Step $autostart -StatePath $StatePath -WhatIf:$WhatIfPreference
}

Write-KitLog (Get-KitText 'Pinball.Finish.Reboot') -Level Warn
