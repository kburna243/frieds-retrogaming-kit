#Requires -Version 5.1
# Pinball package. Sub-modules in modules\<Name>.ps1 are dot-sourced into one module scope.
# Public functions follow Verb-Pinball*; helpers without "-Pinball" stay private.
# The core module is imported without -Force so callers and this module share one core instance
# (culture, log file).

Set-StrictMode -Version 2.0

$script:PinballDir = $PSScriptRoot
$script:KitRoot    = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $script:KitRoot 'core\RetroCabinetKit.Core.psd1')

foreach ($name in 'Common', 'Build', 'Dependencies', 'Copy', 'Relocate', 'Register', 'FpBam') {
    . (Join-Path $PSScriptRoot "modules\$name.ps1")
}

Export-ModuleMember -Function '*-Pinball*'
