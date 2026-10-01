<#
.SYNOPSIS
    Frontends step 01: detect, configure, and theme all installed frontends.
    - frontends-01-detect:     Scan all frontend adapters, report installed/not-installed.
    - frontends-01-configure:  Apply best-practice configuration to installed frontends.
    - frontends-01-genre:      Configure genre routing (which emulator for which system).
    - frontends-01-catalog:    Export unified catalog from each frontend.
    This step is read-only by default; writes only with -Apply.
    Designed for extensibility: drop a new adapter .ps1 -> auto-detected.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $RetroBatRoot,
    [string] $StatePath,
    [string] $Culture,
    [string] $Theme = ''
)
$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1')
Import-Module (Join-Path $kitRoot 'frontends\RetroCabinetKit.Frontends.psd1')
if ($Culture) { Set-KitCulture -Culture $Culture }
if (-not $StatePath) { $StatePath = Get-FrontendsDefaultStatePath }
if (-not $RetroBatRoot) { $RetroBatRoot = Get-FrontendsRetroBatRoot }

$catalog = Get-FrontendsAdapterCatalog
$detected = Get-FrontendsDetectedAdapters -RetroBatRoot $RetroBatRoot

Write-KitLog "=== Frontends v1.0.0 ==="
Write-KitLog "Scanned $($catalog.Count) adapter(s), detected $($detected.DetectedFrontends.Count) installed: $($detected.DetectedFrontends -join ', ')"

foreach ($a in $catalog) {
    $installed = $detected.DetectedFrontends -contains $a.Name
    $mark = if ($installed) { '[INSTALLED]' } else { '[not found]' }
    Write-KitLog "  $mark $($a.Name)"
}

# --- 1. Detect ---------------------------------------------------------------------------------------
$detectStep = New-KitStep -Name 'frontends-01-detect' `
    -Test { $true } `
    -Invoke {
        Set-KitStateValue -Path $StatePath -Key 'DetectedFrontends' -Value ($detected.DetectedFrontends -join ',')
    } `
    -Verify { (Get-KitStateValue -Path $StatePath -Key 'DetectedFrontends') -eq ($detected.DetectedFrontends -join ',') }
Invoke-KitStep -Step $detectStep -StatePath $StatePath -WhatIf:$WhatIfPreference

# --- 2. Configure ------------------------------------------------------------------------------------
$configStep = New-KitStep -Name 'frontends-01-configure' `
    -Test { $detected.DetectedFrontends.Count -gt 0 } `
    -Invoke {
        $null = Set-FrontendsAdapterConfiguration -Names $detected.DetectedFrontends -RetroBatRoot $RetroBatRoot -Confirm:$false
    } `
    -Verify { Test-FrontendsAdapterConfiguration -Names $detected.DetectedFrontends -RetroBatRoot $RetroBatRoot }
Invoke-KitStep -Step $configStep -StatePath $StatePath -WhatIf:$WhatIfPreference

# --- 3. Theme (if specified) -------------------------------------------------------------------------
if ($Theme) {
    $themeStep = New-KitStep -Name 'frontends-01-theme' `
        -Test { $detected.DetectedFrontends.Count -gt 0 } `
        -Invoke {
            foreach ($fe in $detected.DetectedFrontends) {
                $null = Set-FrontendsTheme -FrontendName $fe -RetroBatRoot $RetroBatRoot -ThemeName $Theme
            }
        } `
        -Verify { $true }
    Invoke-KitStep -Step $themeStep -StatePath $StatePath -WhatIf:$WhatIfPreference
}

# --- 4. Genre Routing --------------------------------------------------------------------------------
$genreStep = New-KitStep -Name 'frontends-01-genre' `
    -Test { $detected.DetectedFrontends.Count -gt 0 } `
    -Invoke {
        foreach ($fe in $detected.DetectedFrontends) {
            $null = Set-FrontendsGenreRouting -FrontendName $fe -RetroBatRoot $RetroBatRoot
        }
    } `
    -Verify { $true }
Invoke-KitStep -Step $genreStep -StatePath $StatePath -WhatIf:$WhatIfPreference

# --- 5. Catalog Export -------------------------------------------------------------------------------
$catalogStep = New-KitStep -Name 'frontends-01-catalog' `
    -Test { $detected.DetectedFrontends.Count -gt 0 } `
    -Invoke {
        foreach ($fe in $detected.DetectedFrontends) {
            $dest = Join-Path $RetroBatRoot "catalog_${fe}_$(Get-Date -Format 'yyyyMMdd').json"
            $null = Export-FrontendsCatalog -FrontendName $fe -RetroBatRoot $RetroBatRoot -Destination $dest
        }
    } `
    -Verify { $true }
Invoke-KitStep -Step $catalogStep -StatePath $StatePath -WhatIf:$WhatIfPreference

Write-KitLog "=== Frontends step complete ==="