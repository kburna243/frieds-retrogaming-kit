#Requires -Version 5.1
# Pads package. Sub-modules in modules\<Name>.ps1 are dot-sourced into one module scope.
# Public functions follow Verb-Pad*; helpers without "-Pad" stay private.
#
# The core, the lightgun AND the arcade module are imported without -Force so the whole kit shares one
# instance of each: pads reuses lightgun's audited INI writer (Set-LightgunIniValue) instead of
# duplicating backup/encoding/process-guard logic, and it needs the arcade catalog because a pad scan
# has to know which devices the two stronger device classes already claim (lightgun > arcade > pads).

Set-StrictMode -Version 2.0

$script:PadsDir = $PSScriptRoot
$script:KitRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $script:KitRoot 'core\RetroCabinetKit.Core.psd1')
Import-Module (Join-Path $script:KitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1')
Import-Module (Join-Path $script:KitRoot 'arcade\RetroCabinetKit.Arcade.psd1')

foreach ($name in 'Common', 'Adapters') {
    . (Join-Path $PSScriptRoot "modules\$name.ps1")
}

Export-ModuleMember -Function '*-Pad*'
