<#
.SYNOPSIS
    Lightgun step 11 [W8]: game lists.
    - lightgun-11-tp-duplicates: folders in roms\teknoparrot that double an active game (same name key, e.g.
                                 .parrot vs .teknoparrot, or the same files) are MOVED to
                                 <RetroBat>\_duplicates\teknoparrot\ after the plan was confirmed. Nothing is deleted.
    - lightgun-11-tp-gamelist:   roms\teknoparrot\gamelist.xml: an entry for every registered game (name from
                                 TeknoParrot's metadata), unregistered folders hidden (<hidden>true</hidden>) until
                                 they have a profile.
    Reported only: missing media, entries without folder, and hard-wired <emulator>/<core> entries in any
    gamelist.xml (e.g. MAME light gun games on libretro).
.PARAMETER Approve
    { param($text) ... } returning $true for the move plan. The wizard passes its dialog; without it the console asks.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $RetroBatRoot,
    [scriptblock] $Approve,
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
$tp = if (-not $rb.Problem) { Get-LightgunTpPath -Root $rb.Root }
$hasRoms = [bool]$tp -and (Test-Path -LiteralPath $tp.Roms -PathType Container)
if ($tp -and -not $hasRoms) { Write-KitLog (Get-KitText 'Lightgun.Tp.NoProfiles' -f $tp.Roms) -Level Warn }

function Get-Plan { @(Get-LightgunTpGamelistPlan -RetroBatRoot $rb.Root) }

if ($hasRoms) {
    $plan = Get-Plan
    $classes = @(Get-LightgunTpFolderClass -RetroBatRoot $rb.Root)
    $n = @{}; foreach ($k in 'Active', 'Duplicate', 'Unregistered') { $n[$k] = @($classes | Where-Object { $_.Kind -eq $k }).Count }
    Write-KitLog (Get-KitText 'Lightgun.Lists.Preview' -f $n.Active, $n.Duplicate, $n.Unregistered, @($plan | Where-Object { $_.Action -eq 'Add' }).Count, @($plan | Where-Object { $_.Action -eq 'Hide' }).Count)
    foreach ($r in $plan) {
        switch ($r.Action) {
            'Move'    { Write-KitLog (Get-KitText 'Lightgun.Lists.Duplicate' -f $r.Folder, $r.Profile, $r.Detail) }
            'Hide'    { if ($r.Kind -eq 'Unregistered') { Write-KitLog (Get-KitText 'Lightgun.Lists.Unregistered' -f $r.Folder, $(if ($r.Profile) { Get-KitText 'Lightgun.Lists.Candidate' -f $r.Profile } else { '' })) } }
            'Add'     { Write-KitLog (Get-KitText 'Lightgun.Lists.Add' -f $r.Folder, $r.Name) }
            'NoMedia' { Write-KitLog (Get-KitText 'Lightgun.Lists.NoMedia' -f $r.Folder, $r.Name, $r.Detail) -Level Warn }
            'Orphan'  { Write-KitLog (Get-KitText 'Lightgun.Lists.Orphan' -f $r.Folder, $r.Name) -Level Warn }
        }
    }
}
if (-not $rb.Problem) {
    foreach ($g in Get-LightgunGamelistOverride -RetroBatRoot $rb.Root -AllSystems) { Write-KitLog (Get-KitText 'Lightgun.Lists.Hardwired' -f $g.System, $g.Game, $g.Emulator, $g.Core) -Level Warn }
}

$moveStep = New-KitStep -Name 'lightgun-11-tp-duplicates' `
    -Test { $hasRoms -and (Test-LightgunProcessesClosed) } `
    -Invoke { $null = @(Move-LightgunTpDuplicate -RetroBatRoot $rb.Root -Plan (Get-Plan) -Approve $Approve -Confirm:$false) } `
    -Verify { $hasRoms -and -not @(Get-Plan | Where-Object { $_.Action -eq 'Move' }).Count }
Invoke-KitStep -Step $moveStep -StatePath $StatePath -WhatIf:$WhatIfPreference

$listStep = New-KitStep -Name 'lightgun-11-tp-gamelist' `
    -Test { $hasRoms -and (Test-LightgunProcessesClosed) } `
    -Invoke { $null = Set-LightgunTpGamelist -Path $tp.Gamelist -Plan (Get-Plan) -Confirm:$false } `
    -Verify { $hasRoms -and -not @(Get-Plan | Where-Object { $_.Action -in 'Add', 'Hide' }).Count }
Invoke-KitStep -Step $listStep -StatePath $StatePath -WhatIf:$WhatIfPreference
