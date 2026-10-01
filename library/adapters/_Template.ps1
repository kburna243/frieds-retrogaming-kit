# <Name> Library Adapter
# Copy and replace <Name> with the frontend moniker (e.g., RetroBat, PinballY, …).
# Five-function contract: Test, Get-Info, Install, Configure, Shield.

function Test-<Name>Frontend {
    [CmdletBinding()]
    param([hashtable] $Context = @{})
    $false
}

function Get-<Name>FrontendInfo {
    [CmdletBinding()]
    param()
    @{
        ToolDir       = ''
        DetectProcesses = @()
        DatabaseFormat = 'xml'
        RomPathPattern = ''
        MediaPathPattern = ''
        PlaylistFormat = ''
        Notes         = ''
    }
}

function Install-<Name>Frontend {
    [CmdletBinding()]
    param()
    @{ Success = $true; Message = 'Frontend must be installed manually' }
}

function Configure-<Name>Frontend {
    [CmdletBinding()]
    param([string] $RomPath = '')
    @{ Success = $true; Applied = @{}; Message = 'No-op' }
}

function Set-<Name>InterferenceShield {
    [CmdletBinding()]
    param()
    @{ Success = $true }
}