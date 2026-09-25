<#
.SYNOPSIS
    Lightgun step 12: Demul & DemulShooter (Naomi & Atomiswave lightgun support).
    - lightgun-12-demul:           Demul 0.7a checks: user supplies Demul 0.7a (demul.exe, nvram folder,
                                   BIOS files naomi.zip and awbios.zip). Closed source, no download provided.
    - lightgun-12-demulshooter:    DemulShooter checks and HID raw input configuration for Gunmote Xbox pads
                                   (left stick axes 0x30/0x31, triggers 2/1, action 3, outputs enabled).
                                   Guided download from official GitHub releases (argonlefou/DemulShooter).
    - lightgun-12-demul-settings:  RetroBat es_settings.cfg: naomi.emulator=demul, atomiswave.emulator=demul,
                                   use_guns=0, use_demulshooter=0, disableautocontrollers=1.
    - lightgun-12-demul-gamelist:  checks roms\naomi\gamelist.xml and roms\atomiswave\gamelist.xml for
                                   hardwired <emulator> (flycast/libretro) on gun games; reports and removes them.
.PARAMETER DemulShooterPath
    Custom path to DemulShooter folder or DemulShooter.exe if not located in RetroBat system\tools\demulshooter.
.PARAMETER RemoveHardwired
    Remove hardwired emulator tags for gun games in naomi/atomiswave gamelists.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $RetroBatRoot,
    [string] $DemulShooterPath,
    [switch] $RemoveHardwired,
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

$paths = Get-LightgunDemulPath -RetroBatRoot $rb.Root
$esPath = (Get-LightgunRetroBatPath -Root $rb.Root).EsSettings

# --- 1. Demul 0.7a --------------------------------------------------------------------------------------------
$demulInfo = Test-LightgunDemulInstalled -RetroBatRoot $rb.Root
if (-not $demulInfo.Installed) {
    Write-KitLog (Get-KitText 'Lightgun.Demul.Missing' -f $paths.DemulDir) -Level Warn
    Write-KitLog (Get-KitText 'Lightgun.Demul.UserSupplied') -Level Warn
} else {
    Write-KitLog (Get-KitText 'Lightgun.Demul.Found' -f $paths.DemulDir)
    if (-not $demulInfo.HasBios) {
        Write-KitLog (Get-KitText 'Lightgun.Demul.BiosMissing') -Level Warn
    }
}

$demulStep = New-KitStep -Name 'lightgun-12-demul' `
    -Test { $demulInfo.Installed } `
    -Invoke {
        Set-KitStateValue -Path $StatePath -Key 'DemulDir' -Value $paths.DemulDir
    } `
    -Verify {
        (Test-LightgunDemulInstalled -RetroBatRoot $rb.Root).Installed
    }
Invoke-KitStep -Step $demulStep -StatePath $StatePath -WhatIf:$WhatIfPreference

# --- 2. DemulShooter ------------------------------------------------------------------------------------------
$dsInfo = Test-LightgunDemulShooterInstalled -RetroBatRoot $rb.Root -CustomPath $DemulShooterPath
$configFile = Join-Path $dsInfo.DirPath 'config.ini'

if (-not $dsInfo.Installed) {
    Write-KitLog (Get-KitText 'Lightgun.Demul.DsMissing' -f $paths.DemulShooterDir) -Level Warn
    Write-KitLog (Get-KitText 'Lightgun.Demul.DsDownload' -f (Get-LightgunDemulShooterReleaseUrl)) -Level Warn
} else {
    Write-KitLog (Get-KitText 'Lightgun.Demul.DsFound' -f $dsInfo.ExePath, $(if ($dsInfo.Version) { "v$($dsInfo.Version)" } else { '?' }))
}

function Get-DsPlan { @(Get-LightgunDemulShooterConfigPlan -ConfigPath $configFile) }

if ($dsInfo.Installed) {
    $plan = Get-DsPlan
    Write-KitLog (Get-KitText 'Lightgun.Demul.DsConfigPreview' -f $plan.Count)
    foreach ($p in $plan) {
        Write-KitLog ('  {0}: {1} -> {2}' -f $p.Key, $(if ($null -eq $p.Old) { '-' } else { $p.Old }), $p.New)
    }
}

$dsStep = New-KitStep -Name 'lightgun-12-demulshooter' `
    -Test { $dsInfo.Installed } `
    -Invoke {
        $null = Set-LightgunDemulShooterConfig -ConfigPath $configFile -Plan (Get-DsPlan)
        Set-KitStateValue -Path $StatePath -Key 'DemulShooterDir' -Value $dsInfo.DirPath
    } `
    -Verify {
        $dsInfo.Installed -and -not @(Get-DsPlan).Count
    }
Invoke-KitStep -Step $dsStep -StatePath $StatePath -WhatIf:$WhatIfPreference

# --- 3. RetroBat es_settings.cfg -------------------------------------------------------------------------------
$targetSettings = [ordered]@{
    'naomi.emulator'                  = 'demul'
    'naomi.core'                      = 'naomi'
    'naomi.use_guns'                  = '0'
    'naomi.use_demulshooter'          = '0'
    'naomi.disableautocontrollers'    = '1'
    'atomiswave.emulator'             = 'demul'
    'atomiswave.core'                 = 'atomiswave'
    'atomiswave.use_guns'             = '0'
    'atomiswave.use_demulshooter'     = '0'
    'atomiswave.disableautocontrollers' = '1'
}

function Get-DemulEsPlan { @(Get-LightgunEsSettingsPlan -Path $esPath -Target $targetSettings) }

$esPlan = Get-DemulEsPlan
Write-KitLog (Get-KitText 'Lightgun.Demul.EsPreview' -f $esPlan.Count)
foreach ($c in $esPlan) {
    Write-KitLog ('  {0}: {1} -> {2}' -f $c.Name, $(if ($null -eq $c.Old) { '-' } else { $c.Old }), $c.New)
}

$settingsStep = New-KitStep -Name 'lightgun-12-demul-settings' `
    -Test { Test-LightgunProcessesClosed } `
    -Invoke {
        $null = Set-LightgunEsSettings -Path $esPath -Target $targetSettings -Confirm:$false
    } `
    -Verify {
        -not @(Get-DemulEsPlan).Count
    }
Invoke-KitStep -Step $settingsStep -StatePath $StatePath -WhatIf:$WhatIfPreference

# --- 4. Gamelist Overrides -------------------------------------------------------------------------------------
$overrides = @(Get-LightgunDemulGamelistOverride -RetroBatRoot $rb.Root)
if ($overrides.Count -gt 0) {
    Write-KitLog (Get-KitText 'Lightgun.Demul.GamelistOverridesFound' -f $overrides.Count) -Level Warn
    foreach ($o in $overrides) {
        Write-KitLog (Get-KitText 'Lightgun.Demul.GamelistOverrideItem' -f $o.System, $o.Game, $o.Emulator, $o.Core) -Level Warn
    }
} else {
    Write-KitLog (Get-KitText 'Lightgun.Demul.NoGamelistOverrides')
}

$gamelistStep = New-KitStep -Name 'lightgun-12-demul-gamelist' `
    -Test { Test-LightgunProcessesClosed } `
    -Invoke {
        if ($RemoveHardwired -or $overrides.Count -eq 0) {
            $null = Remove-LightgunDemulGamelistOverride -RetroBatRoot $rb.Root -Overrides $overrides
        } else {
            Write-KitLog (Get-KitText 'Lightgun.Demul.GamelistRemovalPrompt') -Level Warn
        }
    } `
    -Verify {
        if ($RemoveHardwired) {
            -not @(Get-LightgunDemulGamelistOverride -RetroBatRoot $rb.Root).Count
        } else {
            $true
        }
    }
Invoke-KitStep -Step $gamelistStep -StatePath $StatePath -WhatIf:$WhatIfPreference
