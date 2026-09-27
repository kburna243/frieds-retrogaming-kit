<#
.SYNOPSIS
    Output step 1: haptic middleware (MAMEHooker, qMamehook, Hook of the Reaper) on this cabinet.
    Detect reads process list, listening ports, tools folders and supported boards — read-only, and it
    detects ALL tools in use at once. Configure writes mame.ini "output windows|network" only when the
    detected tools agree on one mode (a windows-vs-network conflict is reported, never resolved by
    force) and applies the safety settings (solenoid current limit) to existing settings files.
    With -Install a user-supplied package (-PackagePath) is unpacked into tools\, but only with
    -Approved; without a package the step only names the official source. Nothing is installed as a
    service, no process is killed, no firewall rule is touched.
.PARAMETER RetroBatRoot
    RetroBat folder (default: output state, then the lightgun state).
.PARAMETER Snapshot
    Injected machine picture @{ Processes = @(); Ports = @(); Devices = @() } instead of the live one
    (tests).
.PARAMETER Install
    Unpack -PackagePath into tools\ (needs -Approved), combined with -Name.
.PARAMETER Name
    Middleware to install (one of the adapter file names).
.PARAMETER PackagePath
    Local ZIP with the portable tool.
.PARAMETER Approved
    Explicit permission for -Install to write into the RetroBat folder.
.PARAMETER StatePath
    install-state.json of the output package.
.PARAMETER Culture
    UI language (de-DE, en-US).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $RetroBatRoot,
    [hashtable] $Snapshot,
    [switch] $Install,
    [string] $Name,
    [string] $PackagePath,
    [switch] $Approved,
    [string] $StatePath,
    [string] $Culture
)
$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1')
Import-Module (Join-Path $kitRoot 'output\RetroCabinetKit.Output.psd1')
if ($Culture) { Set-KitCulture -Culture $Culture }
if (-not $StatePath) { $StatePath = Get-OutputDefaultStatePath }
if (-not $RetroBatRoot) { $RetroBatRoot = Get-OutputRetroBatRoot -StatePath $StatePath }

$scanParams = @{ RetroBatRoot = $RetroBatRoot }
if ($PSBoundParameters.ContainsKey('Snapshot')) { $scanParams.Snapshot = $Snapshot }
$found = Get-OutputDetectedMiddleware @scanParams

$detectStep = New-KitStep -Name 'output-1-middleware-detect' `
    -Test { $true } `
    -Invoke {
        Set-KitStateValue -Path $StatePath -Key 'OutputMiddleware' -Value $(if (@($found.DetectedOutputs).Count) { $found.DetectedOutputs -join '+' } else { 'None' })
        if (@($found.DetectedOutputs).Count) { Write-KitLog (Get-KitText 'Output.Adapter.Detected' -f ($found.DetectedOutputs -join ', ')) }
        else { Write-KitLog (Get-KitText 'Output.Adapter.None') }
        foreach ($c in @($found.Conflicts)) { Write-KitLog ("$($c.Kind): $($c.Detail)") -Level Warn }
    } `
    -Verify {
        $saved = [string](Get-KitStateValue -Path $StatePath -Key 'OutputMiddleware')
        $saved -eq $(if (@($found.DetectedOutputs).Count) { $found.DetectedOutputs -join '+' } else { 'None' })
    }
Invoke-KitStep -Step $detectStep -StatePath $StatePath -WhatIf:$WhatIfPreference

$names = @($found.DetectedOutputs)
$modeConflict = @($found.Conflicts | Where-Object { $_.Kind -eq 'OutputModeConflict' }).Count -gt 0

$configureStep = New-KitStep -Name 'output-1-middleware-configure' `
    -Test { $names.Count -gt 0 -and -not $modeConflict -and $RetroBatRoot } `
    -Invoke {
        if ($Install -and $Name) {
            $null = Install-OutputMiddleware -Name $Name -RetroBatRoot $RetroBatRoot -PackagePath $PackagePath -Approved:$Approved
        }
        $null = Set-OutputMiddlewareConfiguration -Names $names -RetroBatRoot $RetroBatRoot -Confirm:$false
    } `
    -Verify {
        if (-not $names.Count) { return $false }
        if ($modeConflict) { return $false }
        Test-OutputMiddlewareConfiguration -Names $names -RetroBatRoot $RetroBatRoot
    }
Invoke-KitStep -Step $configureStep -StatePath $StatePath -WhatIf:$WhatIfPreference
