<#
.SYNOPSIS
    Pinball step 6: register the COM servers of the build (VPinMAME, B2S, FlexDMD, PUPDMDControl,
    PuP DllSurrogate, Popper) in the proven order. Needs administrator rights. COM and HKCU settings are
    machine/user wide: registering switches every table and frontend to THIS copy of the build.
    Verify: VPinMAME.Controller, B2S.Server, FlexDMD.FlexDMD and PinUpPlayer point into the new root.
.PARAMETER KitUserSid
    SID of the user who started the kit (passed by the elevation); registry steps stop for another user.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $Root,
    [string] $KitUserSid,
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

$sameUser = -not $KitUserSid -or (Test-KitSameUser -OriginalSid $KitUserSid)
if (-not $sameUser) { Write-KitLog (Get-KitText 'Elevation.DifferentUser') -Level Warn }
if (-not (Test-KitAdmin)) { Write-KitLog (Get-KitText 'Pinball.Step.NeedsAdmin') -Level Warn }

$plan = @(if ($Root) { Get-PinballRegisterPlan -Root $Root })
if ($WhatIfPreference) {
    foreach ($p in $plan) {
        $what = if ($p.Kind -eq 'Registry') { ($p.Values | ForEach-Object { "$($_.Path)\$($_.Name)" }) -join '; ' } else { "$($p.FilePath) $($p.Arguments)" }
        Write-KitLog (Get-KitText 'Pinball.Register.Plan' -f $p.Title, $what)
    }
}

$step = New-KitStep -Name 'pinball-6-register' `
    -Test { [bool]$Root -and (Test-KitAdmin) -and $sameUser -and (Test-Path -LiteralPath (Join-Path (ConvertTo-PinballRoot $Root) 'vPinball')) } `
    -Invoke {
        $rows = @(Invoke-PinballRegisterPlan -Root $Root -Plan $plan -Confirm:$false)
        foreach ($r in $rows) { Write-KitLog (Get-KitText 'Pinball.Register.Result' -f $r.Title, $r.Result, $r.ExitCode) }
        $bad = @($rows | Where-Object { $_.Result -in 'Failed', 'Missing' })
        if ($bad) { throw (Get-KitText 'Pinball.Register.Failed' -f (($bad | ForEach-Object { $_.Title }) -join ', ')) }
    } `
    -Verify {
        if (-not $Root) { return $false }
        $checks = @(Test-PinballComRegistration -Root $Root)
        foreach ($c in $checks | Where-Object { -not $_.Ok }) { Write-KitLog (Get-KitText 'Pinball.Register.NotPointing' -f $c.Name, ($c.Paths -join '; ')) -Level Warn }
        -not @($checks | Where-Object { -not $_.Ok }).Count
    }

Invoke-KitStep -Step $step -StatePath $StatePath -WhatIf:$WhatIfPreference
