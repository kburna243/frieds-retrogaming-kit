<#
.SYNOPSIS
    Pads step 1: USB/Bluetooth gamepads (8BitDo, Xbox, PlayStation, Switch Pro) as the third input
    class beside lightguns and arcade devices. Detect reads the PnP list only and hands every device a
    lightgun or arcade adapter claims to that class (lightgun > arcade > pads), then collects ALL pads -
    up to four players in one cabinet, not just the first hit. Configure writes retrobat.ini
    [Controllers] through lightgun's audited writer, with backup and -WhatIf support.
    With -Install the kit unpacks a user-supplied package (-PackagePath) into tools\<ToolDir>, but only
    with -Approved; without a package it only names the official source.
.PARAMETER RetroBatRoot
    RetroBat folder (default: pads state, then the lightgun state - one cabinet, one RetroBat).
.PARAMETER Devices
    Injected device list (objects or hashtables with InstanceId/Name) instead of the present PnP
    devices (tests). Bound = injected, unbound = read the machine; an explicitly empty list stays empty.
.PARAMETER Install
    Unpack -PackagePath into tools\ (needs -Approved).
.PARAMETER Name
    Restrict configure/install to one pad adapter (filter over what was detected; never a guess).
.PARAMETER PackagePath
    Local ZIP with the vendor tool (portable; the kit never downloads it itself).
.PARAMETER Approved
    Explicit permission for -Install to write into the RetroBat folder.
.PARAMETER StatePath
    install-state.json of the pads package.
.PARAMETER Culture
    UI language (de-DE, en-US).
.NOTES
    Why NO Steam parameter exists here, unlike arcade\steps\01-Adapter.ps1: pads are the one input class
    that Steam must keep visible (key Pad.NoBlacklist) - a blacklisted gamepad removes the navigation
    device from the very UI where the user would opt back in. The Steam route is therefore not "wired
    differently" in this step, it does not exist. Same for -DetectedDeviceId plumbing: the [Controllers]
    section is a cabinet-wide switch, not a per-instance one.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $RetroBatRoot,
    [object[]] $Devices,
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
Import-Module (Join-Path $kitRoot 'pads\RetroCabinetKit.Pads.psd1')
if ($Culture) { Set-KitCulture -Culture $Culture }
if (-not $StatePath) { $StatePath = Get-PadDefaultStatePath }
if (-not $RetroBatRoot) { $RetroBatRoot = Get-PadRetroBatRoot -StatePath $StatePath }

$detectParams = @{ RetroBatRoot = $RetroBatRoot }
if ($PSBoundParameters.ContainsKey('Devices')) { $detectParams.Devices = $Devices }
$found = Get-PadDetectedGamepad @detectParams

# Names, distinct and ordered like the catalog (alphabetical), so the state value is reproducible.
$pads = @($found.DetectedPads | ForEach-Object { $_.Name } | Select-Object -Unique)
$joined = if (@($pads).Count) { $pads -join '+' } else { 'None' }
# -Name is a filter over what is really plugged in, not a way to configure an absent pad family.
$names = if ($Name) { @($pads | Where-Object { $_ -eq $Name }) } else { @($pads) }

$detectStep = New-KitStep -Name 'pads-1-gamepad-detect' `
    -Test { $true } `
    -Invoke {
        Set-KitStateValue -Path $StatePath -Key 'PadsDetected' -Value $joined
        Set-KitStateValue -Path $StatePath -Key 'PadsExcluded' -Value (@($found.Excluded).Count)
        if (@($pads).Count) { Write-KitLog (Get-KitText 'Pad.Adapter.Detected' -f $joined) }
        else { Write-KitLog (Get-KitText 'Pad.Adapter.None') }
        foreach ($n in $pads) { Write-KitLog (Get-KitText 'Pad.Adapter.NextStep' -f "Configure-$($n)Profile") }
    } `
    -Verify {
        $saved = [string](Get-KitStateValue -Path $StatePath -Key 'PadsDetected')
        $saved -eq $joined
    }
Invoke-KitStep -Step $detectStep -StatePath $StatePath -WhatIf:$WhatIfPreference

# $PSBoundParameters inside the Invoke/Verify scriptblocks would see the scriptblock call (always empty);
# capture the caller's binding once here, outside.

$configureStep = New-KitStep -Name 'pads-1-gamepad-configure' `
    -Test { [bool](@($names).Count) -and $RetroBatRoot } `
    -Invoke {
        foreach ($n in @($names)) {
            if ($Install) {
                $null = Install-PadAdapter -Name $n -RetroBatRoot $RetroBatRoot -PackagePath $PackagePath -Approved:$Approved
            }
            # $names comes out of the detection above, so the -DetectedPads gate inside each adapter's
            # Configure-<Name>Profile is satisfied by construction. The central writer is called directly
            # here exactly like arcade's step does it - one audited route per package, not two.
            $null = Set-PadGamepadConfiguration -Name $n -RetroBatRoot $RetroBatRoot -Confirm:$false
        }
    } `
    -Verify {
        if (-not @($names).Count) { return $false }
        foreach ($n in @($names)) {
            if (-not (Test-PadGamepadConfiguration -Name $n -RetroBatRoot $RetroBatRoot)) { return $false }
        }
        $true
    }
Invoke-KitStep -Step $configureStep -StatePath $StatePath -WhatIf:$WhatIfPreference
