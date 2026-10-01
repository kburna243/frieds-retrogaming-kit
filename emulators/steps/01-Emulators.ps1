<#
.SYNOPSIS
    Emulators step 01: detect and configure all installed emulators.
    - emulators-01-detect:     Scan all emulator adapters, report installed/not-installed.
    - emulators-01-configure:  Apply configuration to all installed emulators.
    - emulators-01-shaders:    Apply shader preset to all supported emulators.
    - emulators-01-integrity:  Verify integrity of all installed emulators.
    This step is read-only by default; writes only with -Apply.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $RetroBatRoot,
    [string] $StatePath,
    [string] $Culture,
    [ValidateSet('none','crt-lottes','crt-royale','hsm-mega-bezel','lcd-grid','scanlines')] [string] $ShaderPreset = 'crt-lottes'
)
$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1')
Import-Module (Join-Path $kitRoot 'emulators\RetroCabinetKit.Emulators.psd1')
if ($Culture) { Set-KitCulture -Culture $Culture }
if (-not $StatePath) { $StatePath = Get-EmulatorsDefaultStatePath }
if (-not $RetroBatRoot) { $RetroBatRoot = Get-EmulatorsRetroBatRoot }

$catalog = Get-EmulatorsAdapterCatalog
$detected = Get-EmulatorsDetectedAdapters -RetroBatRoot $RetroBatRoot

Write-KitLog "=== Emulators v0.9.0 ==="
Write-KitLog "Scanned $($catalog.Count) adapter(s), detected $($detected.DetectedEmulators.Count) installed: $($detected.DetectedEmulators -join ', ')"

foreach ($a in $catalog) {
    $installed = $detected.DetectedEmulators -contains $a.Name
    $mark = if ($installed) { '[INSTALLED]' } else { '[not found]' }
    Write-KitLog "  $mark $($a.Name)"
}

# --- 1. Detect ---------------------------------------------------------------------------------------
$detectStep = New-KitStep -Name 'emulators-01-detect' `
    -Test { $true } `
    -Invoke {
        Set-KitStateValue -Path $StatePath -Key 'DetectedEmulators' -Value ($detected.DetectedEmulators -join ',')
    } `
    -Verify { (Get-KitStateValue -Path $StatePath -Key 'DetectedEmulators') -eq ($detected.DetectedEmulators -join ',') }
Invoke-KitStep -Step $detectStep -StatePath $StatePath -WhatIf:$WhatIfPreference

# --- 2. Configure ------------------------------------------------------------------------------------
$configStep = New-KitStep -Name 'emulators-01-configure' `
    -Test { $detected.DetectedEmulators.Count -gt 0 } `
    -Invoke {
        $null = Set-EmulatorsAdapterConfiguration -Names $detected.DetectedEmulators -RetroBatRoot $RetroBatRoot -Confirm:$false
    } `
    -Verify { Test-EmulatorsAdapterConfiguration -Names $detected.DetectedEmulators -RetroBatRoot $RetroBatRoot }
Invoke-KitStep -Step $configStep -StatePath $StatePath -WhatIf:$WhatIfPreference

# --- 3. Shaders --------------------------------------------------------------------------------------
$shaderStep = New-KitStep -Name 'emulators-01-shaders' `
    -Test { $detected.DetectedEmulators.Count -gt 0 -and $ShaderPreset -ne 'none' } `
    -Invoke {
        foreach ($emu in $detected.DetectedEmulators) {
            $null = Set-EmulatorsShaderPreset -EmulatorName $emu -RetroBatRoot $RetroBatRoot -Preset $ShaderPreset
        }
    } `
    -Verify { $true }
Invoke-KitStep -Step $shaderStep -StatePath $StatePath -WhatIf:$WhatIfPreference

# --- 4. Integrity ------------------------------------------------------------------------------------
$integrityStep = New-KitStep -Name 'emulators-01-integrity' `
    -Test { $detected.DetectedEmulators.Count -gt 0 } `
    -Invoke {
        foreach ($emu in $detected.DetectedEmulators) {
            $result = Test-EmulatorsIntegrity -EmulatorName $emu -RetroBatRoot $RetroBatRoot
            $status = if ($result.AllOk) { 'OK' } else { 'ISSUES' }
            Write-KitLog "  $emu integrity: $status"
        }
    } `
    -Verify { $true }
Invoke-KitStep -Step $integrityStep -StatePath $StatePath -WhatIf:$WhatIfPreference

Write-KitLog "=== Emulators step complete ==="