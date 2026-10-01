# RetroCabinetKit.Library.psm1
# Module script for RetroCabinetKit Library management

# Import the Core module
Import-Module -Name RetroCabinetKit.Core -MinimumVersion 0.8.0

# Set the library directory (relative to this module)
$script:LibraryDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Dot-source the common helpers and adapters
. (Join-Path $script:LibraryDir 'modules\Common.ps1')
. (Join-Path $script:LibraryDir 'modules\Adapters.ps1')

# Export all functions (already handled in manifest, but explicit here)
Export-ModuleMember -Function *-Library*