# <Name> Enhancement Adapter
# Copy and replace <Name> with the adapter moniker (e.g., ShaderPresets, Latency, …).
# Five-function contract: Test, Get-Info, Install, Configure, Shield.

function Test-<Name>Hardware {
    [CmdletBinding()]
    param([hashtable] $Context = @{})
    $false
}

function Get-<Name>AdapterInfo {
    [CmdletBinding()]
    param()
    @{
        ToolDir       = ''
        DetectProcesses = @()
        BoardMatchIds = @()
        Links         = @{}
        SettingsTargets = @()
        Notes         = ''
        ProfileHint   = 'Balanced'
    }
}

function Install-<Name>Software {
    [CmdletBinding()]
    param()
    @{ Success = $true; Message = 'Link-only adapter' }
}

function Configure-<Name>Profile {
    [CmdletBinding()]
    param([string] $Profile = 'Balanced')
    @{ Success = $true; Applied = @{}; Message = 'No-op' }
}

function Set-<Name>InterferenceShield {
    [CmdletBinding()]
    param()
    @{ Success = $true }
}