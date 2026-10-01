#Requires -Version 5.1
# Output package: haptic middleware (MAMEHooker, qMameHook, Hook of the Reaper) as a device class of
# its own — the cabinet's lamps, solenoids, shakers and FFB callbacks. Sub-modules in modules\<Name>.ps1
# are dot-sourced into one module scope. Public functions follow Verb-Output*; helpers stay private.
# Core and lightgun are imported without -Force so every suite shares one instance (culture, log,
# and the audited INI writers).

Set-StrictMode -Version 2.0

$script:OutputDir = $PSScriptRoot
$script:KitRoot   = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $script:KitRoot 'core\RetroCabinetKit.Core.psd1')
Import-Module (Join-Path $script:KitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1')

foreach ($name in 'Common', 'Adapters', 'WiimoteHook', 'HookOfTheWiimote') {
    . (Join-Path $PSScriptRoot "modules\$name.ps1")
}

Export-ModuleMember -Function '*-Output*', '*-KitWiimote*', '*-HookOfTheWiimote*', '*-Hotw*'
