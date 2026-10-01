#Requires -Version 5.1
# Arcade package. Sub-modules in modules\<Name>.ps1 are dot-sourced into one module scope.
# Public functions follow Verb-Arcade*; helpers without "-Arcade" stay private.
# The core AND the lightgun module are imported without -Force so callers, lightgun and this
# module share one instance each: the arcade adapters reuse lightgun's proven writers
# (Set-LightgunMameIniValue, Set-LightgunIniValue, Set-LightgunSteamBlacklist,
# Set-LightgunSupermodelConfig) instead of duplicating backup/encoding/process-guard logic.

Set-StrictMode -Version 2.0

$script:ArcadeDir = $PSScriptRoot
$script:KitRoot   = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $script:KitRoot 'core\RetroCabinetKit.Core.psd1')
Import-Module (Join-Path $script:KitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1')

foreach ($name in 'Common', 'Adapters', 'InputMatrix') {
    . (Join-Path $PSScriptRoot "modules\$name.ps1")
}

Export-ModuleMember -Function '*-Arcade*'
