<#
.SYNOPSIS
    Display step 1: monitors, DMD, backglass, topper detection and configuration.
    Detect reads process list, listening ports, tools folders, supported boards and monitor EDID — read-only, and it
    detects ALL display adapters in use at once. Configure writes configuration files based on EDID and adapter
    detection, applying safety settings (backlight limits, DMD frame timing) to existing settings files.
    With -Install a user-supplied package (-PackagePath) is unpacked into tools\, but only with
    -Approved; without a package the step only names the official source. Nothing is installed as a
    service, no process is killed, no firewall rule is touched.
.PARAMETER RetroBatRoot
    RetroBat folder (default: output state, then the lightgun state).
.PARAMETER Snapshot
    Injected machine picture @{ Processes = @(); Ports = @(); Devices = @(); Monitors = @() } instead of the live one
    (tests).
.PARAMETER Install
    Unpack -PackagePath into tools\ (needs -Approved), combined with -Name.
.PARAMETER Name
    Display adapter to install (one of the adapter file names).
.PARAMETER PackagePath
    Local ZIP with the portable tool.
.PARAMETER Approved
    Explicit permission for -Install to write into the RetroBat folder.
.PARAMETER StatePath
    install-state.json of the displays package.
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
Import-Module (Join-Path $kitRoot 'displays\RetroCabinetKit.Displays.psd1')
if ($Culture) { Set-KitCulture -Culture $Culture }
if (-not $StatePath) { $StatePath = Get-DisplaysDefaultStatePath }
if (-not $RetroBatRoot) { $RetroBatRoot = Get-DisplaysRetroBatRoot -StatePath $StatePath }

$scanParams = @{ RetroBatRoot = $RetroBatRoot }
if ($PSBoundParameters.ContainsKey('Snapshot')) { $scanParams.Snapshot = $Snapshot }
$found = Get-DisplaysDetectedAdapters @scanParams

$detectStep = New-KitStep -Name 'displays-1-adapters-detect' `
    -Test { $true } `
    -Invoke {
        Set-KitStateValue -Path $StatePath -Key 'DisplaysAdapters' -Value $(if (@($found.DetectedAdapters).Count) { $found.DetectedAdapters -join '+' } else { 'None' })
        if (@($found.DetectedAdapters).Count) { Write-KitLog (Get-KitText 'Displays.Adapter.Detected' -f ($found.DetectedAdapters -join ', ')) }
        else { Write-KitLog (Get-KitText 'Displays.Adapter.None') }
        foreach ($c in @($found.Conflicts)) { Write-KitLog ("$($c.Kind): $($c.Detail)") -Level Warn }
    } `
    -Verify {
        $saved = [string](Get-KitStateValue -Path $StatePath -Key 'DisplaysAdapters')
        $saved -eq $(if (@($found.DetectedAdapters).Count) { $found.DetectedAdapters -join '+' } else { 'None' })
    }
Invoke-KitStep -Step $detectStep -StatePath $StatePath -WhatIf:$WhatIfPreference

$names = @($found.DetectedAdapters)
$edidConflict = @($found.Conflicts | Where-Object { $_.Kind -eq 'EdidConflict' }).Count -gt 0
$portConflict = @($found.Conflicts | Where-Object { $_.Kind -eq 'PortConflict' }).Count -gt 0

$configureStep = New-KitStep -Name 'displays-1-adapters-configure' `
    -Test { $names.Count -gt 0 -and -not $edidConflict -and -not $portConflict -and $RetroBatRoot } `
    -Invoke {
        if ($Install -and $Name) {
            $null = Install-DisplaysAdapter -Name $Name -RetroBatRoot $RetroBatRoot -PackagePath $PackagePath -Approved:$Approved
        }
        $null = Set-DisplaysAdapterConfiguration -Names $names -RetroBatRoot $RetroBatRoot -Confirm:$false
    } `
    -Verify {
        if (-not $names.Count) { return $false }
        if ($edidConflict -or $portConflict) { return $false }
        Test-DisplaysAdapterConfiguration -Names $names -RetroBatRoot $RetroBatRoot
    }
Invoke-KitStep -Step $configureStep -StatePath $StatePath -WhatIf:$WhatIfPreference