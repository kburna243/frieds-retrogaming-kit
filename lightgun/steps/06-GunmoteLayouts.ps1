<#
.SYNOPSIS
    Lightgun step 6: Gunmote layouts from the kit's own templates (menu pad without pointer as Default, pad 4:3,
    TeknoParrot with the right stick, mouse only for RetroArch/PCSX2; OffScreen set explicitly, Home off) and
    the program entries in Keymaps.json. The planned changes are listed first (preview). Written only while
    Gunmote (and the other guarded programs) are closed; for a Gunmote below Program Files administrator
    rights are needed. Backups next to the files.
.PARAMETER GunmotePath
    Gunmote folder (default: the one found in step 4).
.PARAMETER RetroBatRoot
    RetroBat folder (default: the one found in step 1); program entries point below it.
.PARAMETER Mode
    Keep (default): existing entries whose layout already does the right thing stay. Replace: the kit's
    layouts everywhere.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $GunmotePath,
    [string] $RetroBatRoot,
    [ValidateSet('Keep', 'Replace')] [string] $Mode = 'Keep',
    [string] $StatePath,
    [string] $Culture
)
$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1')
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1')
if ($Culture) { Set-KitCulture -Culture $Culture }
if (-not $StatePath) { $StatePath = Get-LightgunDefaultStatePath }

$rb = Resolve-LightgunRetroBat -Root $RetroBatRoot -StatePath $StatePath
if (-not $GunmotePath) { $GunmotePath = [string](Get-KitStateValue -Path $StatePath -Key 'GunmoteDir') }
$find = @{}; if ($GunmotePath) { $find.Path = $GunmotePath }
$gunmote = Find-LightgunGunmote @find
if (-not $gunmote) { Write-KitLog (Get-KitText 'Lightgun.Gunmote.Missing' -f (Get-LightgunGunmoteReleaseUrl)) -Level Warn }
$needsAdmin = $gunmote -and $gunmote.InProgramFiles -and -not (Test-KitAdmin)
if ($needsAdmin) { Write-KitLog (Get-KitText 'Lightgun.Step.NeedsAdmin') -Level Warn }

$usable = $gunmote -and -not $rb.Problem
$plan = $null
if ($usable) {
    try { $plan = Get-LightgunLayoutPlan -KeymapsDir $gunmote.Keymaps -RetroBatRoot $rb.Root -Mode $Mode }
    catch { Write-KitLog $_.Exception.Message -Level Warn; $usable = $false }
}
if ($plan) {
    Write-KitLog (Get-KitText 'Lightgun.Layouts.Preview' -f $plan.Count, $Mode)
    foreach ($c in $plan.Changes) { Write-KitLog "  $c" }
}

$step = New-KitStep -Name 'lightgun-6-layouts' `
    -Test { $usable -and -not $needsAdmin -and (Test-LightgunProcessesClosed) } `
    -Invoke { $null = Invoke-LightgunLayoutPlan -Plan $plan -Confirm:$false } `
    -Verify { $usable -and (Get-LightgunLayoutPlan -KeymapsDir $gunmote.Keymaps -RetroBatRoot $rb.Root -Mode $Mode).Count -eq 0 }
$result = Invoke-KitStep -Step $step -StatePath $StatePath -WhatIf:$WhatIfPreference
$result

# The titles the profile automation (step 8) selects, taken from the finished Keymaps.json.
if ($result.Status -in 'Done', 'Skipped' -and -not $result.WhatIf) {
    $titles = (Get-LightgunLayoutPlan -KeymapsDir $gunmote.Keymaps -RetroBatRoot $rb.Root -Mode $Mode).Titles
    Set-KitStateValue -Path $StatePath -Key 'LayoutTitles' -Value ([pscustomobject]$titles)
    foreach ($k in $titles.Keys) { Write-KitLog (Get-KitText 'Lightgun.Layouts.Title' -f $k, $titles[$k]) }
}
