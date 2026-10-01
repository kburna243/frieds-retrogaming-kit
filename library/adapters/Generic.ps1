# Generic Library Adapter
# DESCRIPTION: Fallback adapter for any ROM collection not covered by a dedicated frontend adapter.
# Treats directory structure as playlist organization. Less metadata than dedicated frontends.
# SAFETY: Read-only by default. Never delete files without explicit user confirmation.

function Test-GenericFrontend {
    [CmdletBinding()]
    param([hashtable] $Context = @{})
    $true
}

function Get-GenericFrontendInfo {
    [CmdletBinding()]
    param()
    @{
        ToolDir          = ''
        DetectProcesses  = @()
        DatabaseFormat   = 'filesystem'
        RomPathPattern   = '*/*.zip|*.iso|*.chd|*.vpx|*.gba|*.sfc|*.md|*.nes|*.smc|*.n64|*.z64'
        MediaPathPattern = '*/media/*.png|*.jpg|*.mp4'
        PlaylistFormat   = 'folder structure'
        Notes            = 'Generic filesystem scanner. Falls back to directory structure as playlist organization. Less metadata than dedicated frontends.'
    }
}

function Install-GenericFrontend {
    [CmdletBinding()]
    param()
    @{ Success = $true; Message = 'No installation needed — generic adapter works with any filesystem ROM collection.' }
}

function Configure-GenericFrontend {
    [CmdletBinding()]
    param([string] $RomPath = '')
    @{ Success = $true; Applied = @{ RomPath = $RomPath }; Message = 'Generic scanner configured' }
}

function Set-GenericInterferenceShield {
    [CmdletBinding()]
    param()
    @{ Success = $true }
}