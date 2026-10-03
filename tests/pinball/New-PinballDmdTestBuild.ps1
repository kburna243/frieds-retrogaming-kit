# A pinball build for the DMD audit tests, with every case the audit has to tell apart: a ROM table without a
# pack, a ROM pack, a ROM pack switched off by dashes, a script with its own pack, a script that switches PuP
# off, a script pack switched off by dashes, DMD off with and without PuP drawing the score, a PuP switch
# detected at run time, one name shared by two tables, a section without a table and a file that is no table.
# Section names and positions are made up.
param([Parameter(Mandatory)] [string] $Root)

$newTable = Join-Path $PSScriptRoot 'New-PinballVpxTestTable.ps1'

$v = Join-Path $root 'vPinball'
$tables = Join-Path $v 'VisualPinball\Tables'
$pup = Join-Path $v 'PinUPSystem\PUPVideos'
$ini = Join-Path $v 'VisualPinball\VPinMAME\DmdDevice.ini'
$null = New-Item -ItemType Directory -Path $tables, $pup, (Split-Path -Parent $ini) -Force

$t = @{
    'Rom Without Pack.vpx'  = "Option Explicit`r`nConst cGameName = `"romnopack`"`r`nController.GameName = cGameName"
    'Rom Pack Off.vpx'      = "Const cGameName = `"romoff`""
    'Rom With Pack.vpx'     = "Const cGameName=`"rompack`""
    'Script Pup.vpx'        = "Const cGameName = `"scriptpup`"`r`nDim usePUP: usePUP = true`r`nDim pGameName : pGameName = `"scriptpupvideos`"`r`nPuPlayer.Init"
    'Script Off.vpx'        = "Const cGameName = `"scriptoff`"`r`nDim usePUP: usePUP = False ' no pack`r`nPuPlayer.Init"
    'Pack Disabled.vpx'     = "Const cGameName = `"disabled`"`r`nDim usePUP: usePUP = true`r`nPuPlayer.Init"
    'Draws Score.vpx'       = "Const cGameName = `"drawsscore`"`r`nConst bEnablePuP = True`r`npDMDStartUP`r`nPuPlayer.Init"
    'Off No Score.vpx'      = "Const cGameName = `"offnoscore`"`r`nDim usePUP: usePUP = true`r`nPuPlayer.Init"
    'Shared Pup.vpx'        = "Const cGameName = `"shared`"`r`nDim usePUP: usePUP = True`r`nPuPlayer.Init"
    'Shared Plain.vpx'      = "Const cGameName = `"shared`"`r`nDim usePUP: usePUP = False`r`nPuPlayer.Init"
    'Auto Detect.vpx'       = "Const cGameName = `"autodetect`"`r`nDim bUsePUPDMD`r`nbUsePUPDMD=False`r`nbUsePUPDMD = True`r`npDMDStartUP`r`nPuPlayer.Init"
    'Flex Only.vpx'         = "' Const cGameName = `"commented`"`r`nConst cGameName = `"flexonly`"`r`nConst enablePupPack = False`r`nDim PuPDMDDriverType: PuPDMDDriverType = 1`r`nDim pGameName : pGameName=`"FlexOnly`"`r`nFlexDMD.Show = True"
}
foreach ($k in $t.Keys) { $null = & $newTable -Path (Join-Path $tables $k) -Script $t[$k] }
[IO.File]::WriteAllText((Join-Path $tables 'Broken.vpx'), 'not a table')

foreach ($d in 'rompack', 'scriptpupvideos', 'disabled-----', 'drawsscore', 'offnoscore', 'shared', 'FlexOnly---', 'autodetect', 'romoff---', 'emptypack') {
    $null = New-Item -ItemType Directory -Path (Join-Path $pup $d) -Force
}
foreach ($d in 'rompack', 'scriptpupvideos', 'disabled-----', 'drawsscore', 'offnoscore', 'shared', 'FlexOnly---', 'autodetect', 'romoff---') {
    [IO.File]::WriteAllText((Join-Path $pup "$d\screens.pup"), 'x')
}

$text = @(
    '[global]', 'resizeto = fit', '',
    '[virtualdmd]', 'enabled = true', 'left = 100', 'top = 200', 'width = 800', 'height = 200', '',
    '[romnopack]', 'virtualdmd left = 10', 'virtualdmd top = 20', 'virtualdmd width = 30', 'virtualdmd height = 40', '',
    '[romoff]', 'virtualdmd left = 10', 'virtualdmd top = 20', 'virtualdmd width = 30', 'virtualdmd height = 40', '',
    '[rompack]', 'virtualdmd left = 10', 'virtualdmd top = 20', 'virtualdmd width = 30', 'virtualdmd height = 40', '',
    '[scriptpup]', 'virtualdmd left = 10', 'virtualdmd top = 20', 'virtualdmd width = 30', 'virtualdmd height = 40', '',
    '[scriptoff]', 'virtualdmd.left = 10', 'virtualdmd.top = 20', 'virtualdmd.width = 30', 'virtualdmd.height = 40', '',
    '[disabled]', 'virtualdmd left = 10', 'virtualdmd top = 20', 'virtualdmd width = 30', 'virtualdmd height = 40', '',
    '[drawsscore]', 'virtualdmd enabled = false', '',
    '[offnoscore]', 'virtualdmd enabled = false', '',
    '[autodetect]', 'virtualdmd enabled = false', '',
    '[shared]', 'virtualdmd left = 10', 'virtualdmd top = 20', 'virtualdmd width = 30', 'virtualdmd height = 40', '',
    '[flexonly]', 'virtualdmd enabled = false', 'pin2dmd enabled = false', '',
    '[nosuchtable]', 'virtualdmd left = 10', 'virtualdmd top = 20', 'virtualdmd width = 30', 'virtualdmd height = 40', '',
    '[onlyon]', 'virtualdmd enabled = true', '',
    '[otherkey]', 'pindmd2 enabled = false', ''
) -join "`r`n"
# UTF-8 with BOM and CRLF, as Freezy's own file: the repair must keep both.
[IO.File]::WriteAllText($ini, $text, (New-Object Text.UTF8Encoding($true)))
[pscustomobject]@{ Root = $root; Ini = $ini; Tables = $tables; Pup = $pup; Backup = (Join-Path $root 'backups') }
