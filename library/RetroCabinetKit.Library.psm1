#Requires -Version 5.1
Set-StrictMode -Version 2.0

$script:LibraryDir = $PSScriptRoot
$script:KitRoot   = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $script:KitRoot 'core\RetroCabinetKit.Core.psd1')

foreach ($name in 'Common', 'Adapters') {
    . (Join-Path $PSScriptRoot "modules\$name.ps1")
}

Export-ModuleMember -Function '*-Library*'