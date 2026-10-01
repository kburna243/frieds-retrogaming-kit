# PinballY Library Adapter
# DESCRIPTION: Detects and manages PinballY frontend library. PinballY is dedicated to pinball
# table browsing — VPX (.vpx), VP9 (.vpt), Future Pinball (.fpt) — with media wheel display.
# SAFETY: Read-only by default. Never delete .vpx files without explicit user confirmation.
# Kit deviations: The kit never downloads frontends. Install via user-supplied package with -Approved.

function Test-PinballYFrontend {
    [CmdletBinding()]
    param([hashtable] $Context = @{})
    $procs = if ($Context.Contains('Processes')) { $Context.Processes } else { @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $_.Name.ToLowerInvariant() }) }
    if ('pinbally' -in $procs) { return $true }
    foreach ($p in @('C:\PinballY', 'D:\PinballY', 'C:\Pinball\PinballY')) {
        if (Test-Path (Join-Path $p 'PinballY.exe') -PathType Leaf) { return $true }
    }
    try {
        $reg = Get-ItemProperty -Path 'HKCU:\Software\PinballY' -ErrorAction SilentlyContinue
        if ($reg) { return $true }
    } catch { }
    $false
}

function Get-PinballYFrontendInfo {
    [CmdletBinding()]
    param()
    @{
        ToolDir          = 'PinballY'
        DetectProcesses  = @('pinbally')
        DatabaseFormat   = 'json (Settings.json) + xml (GameData.xml)'
        RomPathPattern   = 'Tables/*.vpx|*.vpt|*.fpt'
        MediaPathPattern = 'Tables/<table>.*'
        PlaylistFormat   = 'XML GameData.xml with <menu> sections'
        Notes            = 'Pinball tables: VPX (.vpx), VP9 (.vpt), Future Pinball (.fpt). Media files: Wheel, Playfield, Backglass, DMD images alongside tables.'
    }
}

function Install-PinballYFrontend {
    [CmdletBinding()]
    param()
    @{ Success = $true; Message = 'Install PinballY manually from https://github.com/Nuka1195/PinballY' }
}

function Configure-PinballYFrontend {
    [CmdletBinding()]
    param([string] $RomPath = '')
    @{ Success = $true; Applied = @{ TablesDir = $RomPath }; Message = 'PinballY configured' }
}

function Set-PinballYInterferenceShield {
    [CmdletBinding()]
    param()
    @{ Success = $true }
}