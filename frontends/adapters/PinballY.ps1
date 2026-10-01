<#
.SYNOPSIS
    PinballY pinball frontend adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    Detects and manages the PinballY frontend by NefariousMD -- a dedicated pinball launcher
    for Visual Pinball, Future Pinball, and Pinball FX3. This adapter is DETECTED, never
    installed as a service and never started by the kit. Detection reads a snapshot (processes,
    ports, frontend folders) so tests can inject everything.

    --- SAFETY -- READ THIS ---
    PinballY uses INI-format Settings.txt. The kit supplements configuration; it does not
    replace PinballY's own management. PinballY.exe + Settings.txt in the same directory
    constitute a valid installation. Do not modify Settings.txt while PinballY is running.

    Kit deviations from the downloaded draft (deliberate, permanent):
      * The draft attempted to download PinballY binaries -- the kit never downloads.
        The adapter only names official sources; a user-supplied ZIP goes through
        Install-PinballYFrontend with -PackagePath and -Approved.
      * Configuration targets Settings.txt [PinballY] and [Display] sections.
      * Theme is set via the theme= key in Settings.txt.
      * SQLite databases are per-system and managed entirely by PinballY.
#>

function Test-PinballYFrontend {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [hashtable] $Snapshot
    )
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-FrontendSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-PinballYFrontendInfo -RetroBatRoot $RetroBatRoot
    # Check by executable path
    if ($info.ExePath -and (Test-Path -LiteralPath $info.ExePath -PathType Leaf)) { return $true }
    # Check by process
    foreach ($p in $info.DetectProcesses) {
        if (@($Snapshot.Processes) -contains $p.ToLowerInvariant()) { return $true }
    }
    # Check by frontend directory
    if ($RetroBatRoot -and $info.ToolDir) {
        if (Test-Path -LiteralPath (Join-Path $RetroBatRoot "frontends\$($info.ToolDir)") -PathType Container) { return $true }
    }
    $false
}

function Get-PinballYFrontendInfo {
    [CmdletBinding()]
    param([string] $RetroBatRoot = '')
    $toolDir = 'PinballY'
    $exeNames = @('PinballY.exe')
    $fePath = if ($RetroBatRoot) { Join-Path $RetroBatRoot "frontends\$toolDir" } else { '' }
    $exePath = if ($fePath) { Get-FrontendExecutable -FrontendPath $fePath -ExeNames $exeNames } else { '' }
    @{
        FrontendType    = 'PinballLauncher'
        ToolDir         = $toolDir
        ExePath         = $exePath
        ExeNames        = $exeNames
        DetectProcesses = @('pinbally')
        DetectPorts     = @()
        SettingsTargets = @(
            @{
                File    = 'Settings.txt'
                Section = 'PinballY'
                Values  = @{
                    GameListSort = ''
                    FullScreen   = ''
                    AutoStart    = ''
                }
            }
            @{
                File    = 'Settings.txt'
                Section = 'Display'
                Values  = @{
                    Monitor  = ''
                    Windowed = ''
                }
            }
        )
        ThemeTarget     = 'Settings.txt'
        DatabaseFormat  = 'xml'
        Links           = @{
            Official = 'https://github.com/NefariousMD/PinballY'
            PinUP    = 'https://www.nailbuster.com/wikipinup/'
        }
        Notes           = 'Pinball frontend by NefariousMD. Handles Visual Pinball, Future Pinball, Pinball FX3. SQLite databases per system. PinballY.exe + Settings.txt = installation check.'
    }
}

function Install-PinballYFrontend {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-PinballYFrontendInfo -RetroBatRoot $RetroBatRoot
    $target = Join-Path $RetroBatRoot "frontends\$($info.ToolDir)"
    if (-not $PackagePath) {
        foreach ($k in $info.Links.Keys) { Write-KitLog "Official source: $k -- $($info.Links[$k])" -Level Info }
        Write-KitLog 'Frontend must be installed manually; the kit never downloads binaries.' -Level Info
        return @{ Success = $false; Message = 'Manual install required; links provided above' }
    }
    if (-not $Approved.IsPresent) { Write-KitLog 'Install requires -Approved flag.' -Level Warn; return @{ Success = $false; Message = 'Approval required' } }
    if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) { Write-KitLog "Package not found: $PackagePath" -Level Warn; return @{ Success = $false; Message = "Package missing: $PackagePath" } }
    if (-not $PSCmdlet.ShouldProcess($target, 'unpack frontend package')) { return @{ Success = $false; Message = 'Cancelled' } }
    $null = New-Item -ItemType Directory -Path $target -Force
    Expand-Archive -LiteralPath $PackagePath -DestinationPath $target -Force
    Write-KitLog "Frontend installed: $($info.ToolDir) -> $target" -Level Info
    @{ Success = $true; Target = $target }
}

function Configure-PinballYFrontend {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    Set-FrontendsAdapterConfiguration -Names @('PinballY') -RetroBatRoot $RetroBatRoot -Confirm:$false
}

function Set-PinballYInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-PinballYFrontendInfo -RetroBatRoot $RetroBatRoot
    foreach ($p in @(Get-FrontendsAdapterValue $info 'DetectPorts')) {
        $owner = @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name } | Select-Object -Unique)
        if ($owner.Count) { Write-KitLog "Port $p is owned by: $($owner -join ', ')" -Level Info }
    }
}