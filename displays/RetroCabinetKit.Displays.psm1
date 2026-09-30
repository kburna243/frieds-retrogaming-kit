#Requires -Version 5.1
# Display package: monitors, DMD, backglass, topper detection and configuration via EDID and adapter plugins.
# Sub-modules in modules\<Name>.ps1 are dot-sourced into one module scope. Public functions follow Verb-Displays*; helpers stay private.
# Core is imported without -Force so every suite shares one instance (culture, log, and the audited INI writers).

Set-StrictMode -Version 2.0

$script:DisplaysDir = $PSScriptRoot
$script:KitRoot   = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $script:KitRoot 'core\RetroCabinetKit.Core.psd1')

foreach ($name in 'Common', 'Adapters') {
    . (Join-Path $PSScriptRoot "modules\$name.ps1")
}

Export-ModuleMember -Function '*-Displays*'