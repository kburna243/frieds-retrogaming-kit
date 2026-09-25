<#
.SYNOPSIS
    Pinball step 5: rewrite the build paths from the old root to the new root (database, text files,
    registry value data, shortcuts). Only runs when the root changed; a second run changes nothing.
.PARAMETER Mode
    Move    = the build moved on THIS computer; registry settings exist and are rewritten.
    Rebuild = fresh Windows; registry settings are imported from -RegistryBackup (kit backup ZIP) or
              -OldUserHive (NTUSER.DAT of the old installation, needs administrator rights), always through
              the path rewrite. Without a source the programs start with defaults and a list of missing
              settings is shown.
.PARAMETER RegistryRoots
    Registry keys whose value data is rewritten (default: Future Pinball, VPinMAME, B2S below HKCU\Software).
.PARAMETER AppCompatRoots
    AppCompatFlags\Layers keys that are only checked for outdated entries.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [ValidateSet('Move', 'Rebuild')] [string] $Mode = 'Move',
    [string] $RegistryBackup,
    [string] $OldUserHive,
    [string] $NewRoot,
    [string] $OldRoot,
    [string[]] $RegistryRoots,
    [string[]] $AppCompatRoots,
    [string] $StatePath,
    [string] $Culture
)
$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1')
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1')
if ($Culture) { Set-KitCulture -Culture $Culture }
if (-not $StatePath) { $StatePath = Get-PinballDefaultStatePath }
if (-not $NewRoot) { $NewRoot = Get-KitStateValue -Path $StatePath -Key 'TargetRoot' }
if (-not $OldRoot) { $OldRoot = Get-KitStateValue -Path $StatePath -Key 'OldRoot' }
if (-not $RegistryRoots) { $RegistryRoots = Get-PinballRegistryRoot }
if (-not $AppCompatRoots) { $AppCompatRoots = Get-PinballAppCompatRoot }
$siblings = @(Get-KitStateValue -Path $StatePath -Key 'Siblings' | Where-Object { $_ })
if (-not ($NewRoot -and $OldRoot)) { Write-KitLog (Get-KitText 'Pinball.Step.RunTargetFirst') -Level Warn }

$common = @{ OldRoot = $OldRoot; NewRoot = $NewRoot; Siblings = $siblings; RegistryRoots = $RegistryRoots; AppCompatRoots = $AppCompatRoots }
if ($WhatIfPreference -and $NewRoot -and $OldRoot) {
    Write-PinballRelocationReport (Invoke-PinballRelocation @common -Mode $Mode -RegistryBackup $RegistryBackup -OldUserHive $OldUserHive -DryRun)
}

$step = New-KitStep -Name 'pinball-5-relocate' `
    -Test { [bool]($NewRoot -and $OldRoot) -and (Test-Path -LiteralPath (Get-PinballDatabasePath -Root $NewRoot)) } `
    -Invoke {
        $report = Invoke-PinballRelocation @common -Mode $Mode -RegistryBackup $RegistryBackup -OldUserHive $OldUserHive
        Write-PinballRelocationReport $report
        $files = @(@(Get-KitStateValue -Path $StatePath -Key 'RelocatedFiles') + $report.ChangedFiles | Where-Object { $_ } | Sort-Object -Unique)
        Set-KitStateValue -Path $StatePath -Key 'RelocatedFiles' -Value $files
        Set-KitStateValue -Path $StatePath -Key 'RelocateDone' -Value $true
        if ($Mode -eq 'Rebuild') { Set-KitStateValue -Path $StatePath -Key 'RebuildRegistryDone' -Value $true }
    } `
    -Verify {
        if (-not ($NewRoot -and $OldRoot)) { return $false }
        $check = Test-PinballRelocation @common
        if (-not $check.Clean) { Write-KitLog (Get-KitText 'Pinball.Relocate.Remaining' -f $check.Remaining) -Level Warn }
        # A rebuild is only done once its registry import ran, even if nothing old is left.
        $check.Clean -and ($Mode -eq 'Move' -or [bool](Get-KitStateValue -Path $StatePath -Key 'RebuildRegistryDone'))
    }

Invoke-KitStep -Step $step -StatePath $StatePath -WhatIf:$WhatIfPreference
