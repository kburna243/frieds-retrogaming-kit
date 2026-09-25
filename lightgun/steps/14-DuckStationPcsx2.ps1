<#
.SYNOPSIS
    Lightgun step 14 [W6]: DuckStation & PCSX2 guided check and report (no automated binding).
    - lightgun-14-duckstation-pcsx2: audits existing settings in settings.ini, gamesettings\<SERIAL>.ini,
                                     and PCSX2.ini; presents guidance for Automatic Mapping to XInput-0;
                                     highlights Konami games requiring Justifier instead of GunCon
                                     (Die Hard Trilogy SLUS-00119, Crypt Killer SLUS-00335).
                                     Flycast remains omitted [W9].
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $RetroBatRoot,
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
if ($rb.Problem) {
    Write-KitLog $rb.Problem -Level Warn
    return
}

# --- Guidance explanations -------------------------------------------------------------------------------------
Write-KitLog (Get-KitText 'Lightgun.Psx.GuideIntro')
Write-KitLog (Get-KitText 'Lightgun.Psx.AutoMapGuide')
Write-KitLog (Get-KitText 'Lightgun.Psx.KonamiNote')
Write-KitLog (Get-KitText 'Lightgun.Psx.FlycastNote')

# --- Audit DuckStation -----------------------------------------------------------------------------------------
$dsAudit = Get-LightgunDuckStationAudit -RetroBatRoot $rb.Root
if ($dsAudit.DuckStationFound) {
    Write-KitLog (Get-KitText 'Lightgun.Psx.DsFound')
    if ($dsAudit.HasSettings) {
        Write-KitLog (Get-KitText 'Lightgun.Psx.DsSettingsReport' -f $(if ($dsAudit.Pad1Type) { $dsAudit.Pad1Type } else { 'None' }), $(if ($dsAudit.Pad2Type) { $dsAudit.Pad2Type } else { 'None' }))
    } else {
        Write-KitLog (Get-KitText 'Lightgun.Psx.DsNoSettings') -Level Warn
    }

    foreach ($k in $dsAudit.KonamiAudit) {
        if ($k.Valid) {
            Write-KitLog (Get-KitText 'Lightgun.Psx.KonamiValid' -f $k.Title, $k.Serial)
        } elseif ($k.HasGameSettings) {
            Write-KitLog (Get-KitText 'Lightgun.Psx.KonamiNotJustifier' -f $k.Title, $k.Serial) -Level Warn
        } else {
            Write-KitLog (Get-KitText 'Lightgun.Psx.KonamiMissing' -f $k.Title, $k.Serial) -Level Warn
        }
    }
} else {
    Write-KitLog (Get-KitText 'Lightgun.Psx.DsNotFound')
}

# --- Audit PCSX2 -----------------------------------------------------------------------------------------------
$pcsx2Audit = Get-LightgunPcsx2Audit -RetroBatRoot $rb.Root
if ($pcsx2Audit.Pcsx2Found) {
    Write-KitLog (Get-KitText 'Lightgun.Psx.Pcsx2Found')
    if ($pcsx2Audit.HasIni) {
        Write-KitLog (Get-KitText 'Lightgun.Psx.Pcsx2Report' -f $(if ($pcsx2Audit.HasGunCon2) { 'GunCon2/Pointer' } else { 'Default' }))
    }
} else {
    Write-KitLog (Get-KitText 'Lightgun.Psx.Pcsx2NotFound')
}

# --- Step definition (guided only, verify succeeds after audit) -------------------------------------------------
$guidedStep = New-KitStep -Name 'lightgun-14-duckstation-pcsx2' `
    -Test { [bool]$rb.Root } `
    -Invoke {
        Set-KitStateValue -Path $StatePath -Key 'DuckStationAuditCompleted' -Value (Get-Date).ToString('o')
    } `
    -Verify {
        [bool](Get-KitStateValue -Path $StatePath -Key 'DuckStationAuditCompleted')
    }
Invoke-KitStep -Step $guidedStep -StatePath $StatePath -WhatIf:$WhatIfPreference
