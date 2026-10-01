#Requires -Version 5.1
Set-StrictMode -Version 2.0

$script:EmulatorsDir = $PSScriptRoot
$script:KitRoot     = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $script:KitRoot 'core\RetroCabinetKit.Core.psd1')

. (Join-Path $PSScriptRoot 'modules\Common.ps1')
. (Join-Path $PSScriptRoot 'modules\Adapters.ps1')
Export-ModuleMember -Function '*-Emulator*', '*-Emulators*'