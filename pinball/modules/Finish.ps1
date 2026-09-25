# Finish (step 9): what goes into the final kit backup, and the build's own Popper autostart batch file.

$script:PinballStartupBatName = 'RunWindowsStartup.bat'

# Files and registry keys of the configured cabinet that exist right now (database, INIs, ScreenRes,
# VPX settings; Future Pinball, VPinMAME, B2S and VPX registry). -Paths / -RegistryKeys override (tests).
function Get-PinballFinishBackupSet {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Root, [hashtable] $Paths = @{}, [string[]] $RegistryKeys)
    $files = @(Get-PinballScreenTarget -Root $Root -Paths $Paths | Where-Object { $_.Kind -notlike '*Registry' } | ForEach-Object { $_.Path })
    if (-not $PSBoundParameters.ContainsKey('RegistryKeys')) {
        $RegistryKeys = @(Get-PinballRegistryRoot) + 'HKCU:\Software\Visual Pinball'
    }
    [pscustomobject]@{
        Files    = @($files | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Sort-Object -Unique)
        Registry = @($RegistryKeys | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
    }
}

function Find-PinballStartupBat {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Root)
    $pup = Join-PinballPath (ConvertTo-PinballRoot $Root) 'vPinball\PinUPSystem'
    Get-ChildItem -LiteralPath $pup -Recurse -File -Filter $script:PinballStartupBatName -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}
