#Requires -Version 5.1
# Lightgun package. Sub-modules in modules\<Name>.ps1 are dot-sourced into one module scope.
# Public functions follow Verb-Lightgun*; helpers without "-Lightgun" stay private.
# The core module is imported without -Force so callers and this module share one core instance.

Set-StrictMode -Version 2.0

$script:LightgunDir = $PSScriptRoot
$script:KitRoot     = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $script:KitRoot 'core\RetroCabinetKit.Core.psd1')

foreach ($name in 'Common', 'Detect', 'Hardware', 'ViGEm', 'Gunmote', 'Steam', 'Layouts', 'EsSettings', 'Automation', 'Verify') {
    . (Join-Path $PSScriptRoot "modules\$name.ps1")
}

Export-ModuleMember -Function '*-Lightgun*'
