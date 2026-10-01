<#
.SYNOPSIS
    LaunchBox / BigBox universal game launcher frontend adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    Detects and manages the LaunchBox frontend -- a universal game launcher with LaunchBox
    for desktop management and BigBox for cabinet mode. This adapter is DETECTED, never
    installed as a service and never started by the kit. Detection reads a snapshot (processes,
    ports, frontend folders) so tests can inject everything.

    --- SAFETY -- READ THIS ---
    LaunchBox stores settings in XML files (Settings.xml, BigBoxSettings.xml). BigBox
    requires a separate license for cabinet mode. The kit supplements configuration; it does
    not replace LaunchBox's own management. Do not modify XML settings while LaunchBox or
    BigBox is running.

    Kit deviations from the downloaded draft (deliberate, permanent):
      * The draft attempted to download LaunchBox binaries -- the kit never downloads.
        The adapter only names official sources; a user-supplied ZIP goes through
        Install-LaunchBoxFrontend with -PackagePath and -Approved.
      * Configuration targets Settings.xml for general settings and BigBoxSettings.xml
        for cabinet-mode settings.
      * Theme configuration routes through BigBoxSettings.xml (Theme key).
      * BigBox license is user-managed; the kit does not handle licensing.
#>

function Test-LaunchBoxFrontend {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [hashtable] $Snapshot
    )
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-FrontendSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-LaunchBoxFrontendInfo -RetroBatRoot $RetroBatRoot
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

function Get-LaunchBoxFrontendInfo {
    [CmdletBinding()]
    param([string] $RetroBatRoot = '')
    $toolDir = 'LaunchBox'
    $exeNames = @('LaunchBox.exe', 'BigBox.exe')
    $fePath = if ($RetroBatRoot) { Join-Path $RetroBatRoot "frontends\$toolDir" } else { '' }
    $exePath = if ($fePath) { Get-FrontendExecutable -FrontendPath $fePath -ExeNames $exeNames } else { '' }
    @{
        FrontendType    = 'UniversalLauncher'
        ToolDir         = $toolDir
        ExePath         = $exePath
        ExeNames        = $exeNames
        DetectProcesses = @('launchbox', 'bigbox')
        DetectPorts     = @()
        SettingsTargets = @(
            @{
                File    = 'Data\Settings.xml'
                Section = ''
                Values  = @{
                    Fullscreen = ''
                    AutoPlay   = ''
                    HideMouse  = ''
                }
            }
            @{
                File    = 'Data\BigBoxSettings.xml'
                Section = ''
                Values  = @{
                    Theme       = ''
                    StartupView = ''
                }
            }
        )
        ThemeTarget     = 'Data\BigBoxSettings.xml'
        DatabaseFormat  = 'xml'
        Links           = @{
            Official = 'https://www.launchbox-app.com/'
            BigBox   = 'https://www.launchbox-app.com/big-box'
        }
        Notes           = 'Universal game launcher. LaunchBox for desktop, BigBox for cabinet mode. XML-based settings and databases. BigBox license required for cabinet mode.'
    }
}

function Install-LaunchBoxFrontend {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-LaunchBoxFrontendInfo -RetroBatRoot $RetroBatRoot
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

function Configure-LaunchBoxFrontend {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    Set-FrontendsAdapterConfiguration -Names @('LaunchBox') -RetroBatRoot $RetroBatRoot -Confirm:$false
}

function Set-LaunchBoxInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-LaunchBoxFrontendInfo -RetroBatRoot $RetroBatRoot
    foreach ($p in @(Get-FrontendsAdapterValue $info 'DetectPorts')) {
        $owner = @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name } | Select-Object -Unique)
        if ($owner.Count) { Write-KitLog "Port $p is owned by: $($owner -join ', ')" -Level Info }
    }
}