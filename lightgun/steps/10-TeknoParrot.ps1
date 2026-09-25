<#
.SYNOPSIS
    Lightgun step 10 [W8]: TeknoParrot profiles.
    - lightgun-10-tp-paths:    GamePath/GamePath2 in UserProfiles\*.xml that point into another installation (a
                               bought build keeps its creator's folder) -> the same file below this RetroBat, only
                               when it exists here; missing games are only reported.
    - lightgun-10-tp-bind:     gun games bound to XInput from RetroBat's own teknoparrot.yml: Wiimote 1/2 =
                               XInputIndex 0/1, B = shot, A = reload, right stick aims, grenades/extra on Xbox X.
                               Touch screen games (pad games) and -Exclude stay as they are.
    - lightgun-10-tp-settings: es_settings.cfg: teknoparrot.use_guns=0, per bound game
                               teknoparrot["<rom>"].disableautocontrollers=1, build creator leftovers removed
                               (tp_inputdriver, gun settings, sindenborder).
    Preview first; written only while RetroBat, TeknoParrot and the other guarded programs are closed, backup
    next to every file, a second run changes nothing.
.PARAMETER Exclude
    Further profile names (file name without .xml) that keep their binding.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $RetroBatRoot,
    [string[]] $Exclude = @(),
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
$es = if ($tp) { (Get-LightgunRetroBatPath -Root $rb.Root).EsSettings }
$hasProfiles = [bool]$tp -and @(Get-ChildItem -LiteralPath $tp.UserProfiles -Filter '*.xml' -File -ErrorAction SilentlyContinue).Count -gt 0
$hasMapping = [bool]$tp -and (Test-Path -LiteralPath $tp.InputMapping -PathType Leaf)
if ($tp -and -not $hasProfiles) { Write-KitLog (Get-KitText 'Lightgun.Tp.NoProfiles' -f $tp.UserProfiles) -Level Warn }

function Get-PathPlan { @(Get-LightgunTpPathPlan -RetroBatRoot $rb.Root) }
function Get-BindPlan { @(Get-LightgunTpBindPlan -RetroBatRoot $rb.Root -Exclude $Exclude) }
function Get-EsPlan {
    $roms = @(Get-BindPlan | Where-Object { $_.Status -in 'Bind', 'Ok' -and $_.Rom } | ForEach-Object { $_.Rom })
    @(Get-LightgunEsSettingsPlan -Path $es -Target (Get-LightgunTpEsTarget -Rom $roms) -Remove @(Get-LightgunTpEsRemove -Path $es))
}

if ($hasProfiles) {
    $paths = Get-PathPlan
    $repair = @($paths | Where-Object { $_.Action -eq 'Repair' }); $missing = @($paths | Where-Object { $_.Action -eq 'Missing' })
    Write-KitLog (Get-KitText 'Lightgun.Tp.PathPreview' -f $repair.Count, $missing.Count)
    foreach ($r in $repair) { Write-KitLog (Get-KitText 'Lightgun.Tp.PathRepair' -f $r.Profile, $r.Field, $r.Old, $r.New) }
    foreach ($r in $missing) { Write-KitLog (Get-KitText 'Lightgun.Tp.PathMissing' -f $r.Profile, $r.Field, $r.Old) -Level Warn }
    if ($hasMapping) {
        $bind = Get-BindPlan
        $count = @{}; foreach ($s in 'Bind', 'Ok', 'Touch', 'NoPath', 'NoMapping', 'Excluded') { $count[$s] = @($bind | Where-Object { $_.Status -eq $s }).Count }
        Write-KitLog (Get-KitText 'Lightgun.Tp.BindPreview' -f $count.Bind, $count.Ok, $count.Touch, $count.NoPath, $count.NoMapping, $count.Excluded)
        foreach ($b in $bind | Where-Object { $_.Status -ne 'Ok' }) { Write-KitLog (Get-KitText "Lightgun.Tp.Bind.$($b.Status)" -f $b.Profile, $b.Changes) }
        $esPlan = Get-EsPlan
        Write-KitLog (Get-KitText 'Lightgun.Tp.EsPreview' -f $esPlan.Count)
        foreach ($c in $esPlan) { Write-KitLog ('  {0}: {1} -> {2}' -f $c.Name, $(if ($null -eq $c.Old) { '-' } else { $c.Old }), $(if ($null -eq $c.New) { '(remove)' } else { $c.New })) }
    } else { Write-KitLog (Get-KitText 'Lightgun.Tp.NoMapping' -f $tp.InputMapping) -Level Warn }
}

$pathStep = New-KitStep -Name 'lightgun-10-tp-paths' `
    -Test { $hasProfiles -and (Test-LightgunProcessesClosed) } `
    -Invoke { $null = Repair-LightgunTpPath -Plan (Get-PathPlan) -Confirm:$false } `
    -Verify { $hasProfiles -and -not @(Get-PathPlan | Where-Object { $_.Action -eq 'Repair' }).Count }
Invoke-KitStep -Step $pathStep -StatePath $StatePath -WhatIf:$WhatIfPreference

$bindStep = New-KitStep -Name 'lightgun-10-tp-bind' `
    -Test { $hasProfiles -and $hasMapping -and (Test-LightgunProcessesClosed) } `
    -Invoke { $null = Set-LightgunTpBinding -Plan (Get-BindPlan) -MappingPath $tp.InputMapping -Confirm:$false } `
    -Verify { $hasProfiles -and $hasMapping -and -not @(Get-BindPlan | Where-Object { $_.Status -eq 'Bind' }).Count }
Invoke-KitStep -Step $bindStep -StatePath $StatePath -WhatIf:$WhatIfPreference

$esStep = New-KitStep -Name 'lightgun-10-tp-settings' `
    -Test { $hasProfiles -and $hasMapping -and (Test-LightgunProcessesClosed) } `
    -Invoke {
        $roms = @(Get-BindPlan | Where-Object { $_.Status -in 'Bind', 'Ok' -and $_.Rom } | ForEach-Object { $_.Rom })
        $null = Set-LightgunEsSettings -Path $es -Target (Get-LightgunTpEsTarget -Rom $roms) -Remove @(Get-LightgunTpEsRemove -Path $es) -Confirm:$false
    } `
    -Verify { $hasProfiles -and $hasMapping -and -not @(Get-EsPlan).Count }
Invoke-KitStep -Step $esStep -StatePath $StatePath -WhatIf:$WhatIfPreference
