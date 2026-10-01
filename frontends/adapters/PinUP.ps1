<#
.SYNOPSIS
    PinUP Popper pinball frontend adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    Detects and manages the PinUP Popper frontend by Nailbuster -- the standard frontend for
    virtual pinball cabinets. PinUpMenu.exe is the menu/selector and PinUpDisplay.exe drives
    the DMD/topper display. This adapter is DETECTED, never installed as a service and never
    started by the kit. Detection reads a snapshot (processes, ports, frontend folders) so
    tests can inject everything.

    --- SAFETY -- READ THIS ---
    PinUP Popper uses INI-format configuration (PinUpMenu.ini, Settings.ini) with a SQLite
    media and table database. The kit supplements configuration; it does not replace PinUP's
    own management. Do not modify INI files or SQLite databases while PinUP is running.
    The Baller Installer provides automated setup but is outside the kit's scope.

    Kit deviations from the downloaded draft (deliberate, permanent):
      * The draft attempted to download PinUP binaries -- the kit never downloads.
        The adapter only names official sources; a user-supplied ZIP goes through
        Install-PinUPFrontend with -PackagePath and -Approved.
      * Configuration targets PinUpMenu.ini [Display] and Settings.ini [System]/[Media].
      * Theme configuration routes through Settings.ini (ThemeName key).
      * The SQLite database is managed entirely by PinUP; the kit does not write to it directly.
      * Baller Installer is referenced but not invoked by the kit.
#>

function Test-PinUPFrontend {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [hashtable] $Snapshot
    )
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-FrontendSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-PinUPFrontendInfo -RetroBatRoot $RetroBatRoot
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

function Get-PinUPFrontendInfo {
    [CmdletBinding()]
    param([string] $RetroBatRoot = '')
    $toolDir = 'PinUP'
    $exeNames = @('PinUpMenu.exe', 'PinUpDisplay.exe')
    $fePath = if ($RetroBatRoot) { Join-Path $RetroBatRoot "frontends\$toolDir" } else { '' }
    $exePath = if ($fePath) { Get-FrontendExecutable -FrontendPath $fePath -ExeNames $exeNames } else { '' }
    @{
        FrontendType    = 'PinballLauncher'
        ToolDir         = $toolDir
        ExePath         = $exePath
        ExeNames        = $exeNames
        DetectProcesses = @('pinupmenu', 'pinupdisplay')
        DetectPorts     = @()
        SettingsTargets = @(
            @{
                File    = 'PinUpMenu.ini'
                Section = 'Display'
                Values  = @{
                    FullScreen = ''
                    Monitor    = ''
                }
            }
            @{
                File    = 'Settings.ini'
                Section = 'System'
                Values  = @{
                    ThemeName   = ''
                    AutoLaunch  = ''
                }
            }
            @{
                File    = 'Settings.ini'
                Section = 'Media'
                Values  = @{
                    Videos    = ''
                    Backglass = ''
                }
            }
        )
        ThemeTarget     = 'Settings.ini'
        DatabaseFormat  = 'sqlite'
        Links           = @{
            Official = 'https://www.nailbuster.com/wikipinup/'
            Baller   = 'https://www.nailbuster.com/wikipinup/doku.php?id=baller_installer'
        }
        Notes           = 'PinUP Popper by Nailbuster. The standard frontend for virtual pinball cabinets. SQLite-based media and table database. PinUpMenu.exe = menu, PinUpDisplay.exe = DMD/topper display. Baller Installer for automated setup.'
    }
}

function Install-PinUPFrontend {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-PinUPFrontendInfo -RetroBatRoot $RetroBatRoot
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

function Configure-PinUPFrontend {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    Set-FrontendsAdapterConfiguration -Names @('PinUP') -RetroBatRoot $RetroBatRoot -Confirm:$false
}

function Set-PinUPInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-PinUPFrontendInfo -RetroBatRoot $RetroBatRoot
    foreach ($p in @(Get-FrontendsAdapterValue $info 'DetectPorts')) {
        $owner = @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name } | Select-Object -Unique)
        if ($owner.Count) { Write-KitLog "Port $p is owned by: $($owner -join ', ')" -Level Info }
    }
}