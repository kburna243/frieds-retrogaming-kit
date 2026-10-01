<#
.SYNOPSIS
    Playnite universal game launcher frontend adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    Detects and manages the Playnite frontend -- a universal game launcher supporting all
    emulators and PC games with a fullscreen cabinet mode. This adapter is DETECTED, never
    installed as a service and never started by the kit. Detection reads a snapshot (processes,
    ports, frontend folders) so tests can inject everything.

    --- SAFETY -- READ THIS ---
    Playnite stores configuration in config.json (JSON) and game data in Playnite.db (SQLite).
    The kit supplements configuration; it does not replace Playnite's own library management.
    Do not modify config.json or the SQLite database while Playnite is running.

    Kit deviations from the downloaded draft (deliberate, permanent):
      * The draft attempted to download Playnite binaries -- the kit never downloads.
        The adapter only names official sources; a user-supplied ZIP goes through
        Install-PlayniteFrontend with -PackagePath and -Approved.
      * Configuration targets config.json top-level keys for Fullscreen, Theme, AutoClose.
      * The Playnite.db SQLite database is managed entirely by Playnite; the kit does not
        write to it directly.
      * Desktop and Fullscreen modes share the same config.json but use different executables.
#>

function Test-PlayniteFrontend {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [hashtable] $Snapshot
    )
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-FrontendSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-PlayniteFrontendInfo -RetroBatRoot $RetroBatRoot
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

function Get-PlayniteFrontendInfo {
    [CmdletBinding()]
    param([string] $RetroBatRoot = '')
    $toolDir = 'Playnite'
    $exeNames = @('Playnite.DesktopApp.exe', 'Playnite.FullscreenApp.exe')
    $fePath = if ($RetroBatRoot) { Join-Path $RetroBatRoot "frontends\$toolDir" } else { '' }
    $exePath = if ($fePath) { Get-FrontendExecutable -FrontendPath $fePath -ExeNames $exeNames } else { '' }
    @{
        FrontendType    = 'UniversalLauncher'
        ToolDir         = $toolDir
        ExePath         = $exePath
        ExeNames        = $exeNames
        DetectProcesses = @('playnite')
        DetectPorts     = @()
        SettingsTargets = @(
            @{
                File    = 'config.json'
                Section = ''
                Values  = @{
                    Fullscreen = ''
                    Theme      = ''
                    AutoClose  = ''
                }
            }
        )
        ThemeTarget     = 'config.json'
        DatabaseFormat  = 'sqlite'
        Links           = @{
            Official = 'https://playnite.link/'
            Themes   = 'https://playnite.link/themes.html'
        }
        Notes           = 'Universal game launcher. Supports all emulators and PC games. JSON config + SQLite database. Fullscreen mode for cabinet use. Extensive plugin/theming ecosystem.'
    }
}

function Install-PlayniteFrontend {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-PlayniteFrontendInfo -RetroBatRoot $RetroBatRoot
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

function Configure-PlayniteFrontend {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    Set-FrontendsAdapterConfiguration -Names @('Playnite') -RetroBatRoot $RetroBatRoot -Confirm:$false
}

function Set-PlayniteInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-PlayniteFrontendInfo -RetroBatRoot $RetroBatRoot
    foreach ($p in @(Get-FrontendsAdapterValue $info 'DetectPorts')) {
        $owner = @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name } | Select-Object -Unique)
        if ($owner.Count) { Write-KitLog "Port $p is owned by: $($owner -join ', ')" -Level Info }
    }
}