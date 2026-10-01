<#
.SYNOPSIS
    RetroBat (EmulationStation-based) frontend adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    Detects and manages the RetroBat frontend -- the primary frontend for Frieds Retrogaming Kit.
    RetroBat wraps EmulationStation with per-system ROM and media folders. This adapter is
    DETECTED, never installed as a service and never started by the kit. Detection reads a
    snapshot (processes, ports, frontend folders) so tests can inject everything.

    --- SAFETY -- READ THIS ---
    RetroBat configuration is spread across multiple files (retrobat.conf, es_settings.cfg,
    es_systems.cfg). Modifications should route through the kit's configuration system, never
    write directly while RetroBat is running. RetroBat manages its own emulator launchers;
    the kit supplements, it does not replace them.

    Kit deviations from the downloaded draft (deliberate, permanent):
      * The draft attempted to download RetroBat binaries -- the kit never downloads.
        The adapter only names official sources; a user-supplied ZIP goes through
        Install-RetroBatFrontend with -PackagePath and -Approved.
      * Configuration targets retrobat.conf [system] and es_settings.cfg [global] sections.
      * Theme configuration routes through retrobat.conf, not es_settings.cfg alone.
      * ROMs live in roms/<system>/; media in roms/<system>/media/; themes in system/themes/.
      * This is the primary frontend for Frieds Retrogaming Kit.
#>

function Test-RetroBatFrontend {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [hashtable] $Snapshot
    )
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-FrontendSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-RetroBatFrontendInfo -RetroBatRoot $RetroBatRoot
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

function Get-RetroBatFrontendInfo {
    [CmdletBinding()]
    param([string] $RetroBatRoot = '')
    $toolDir = 'retrobat'
    $exeNames = @('retrobat.exe', 'emulationstation.exe')
    $fePath = if ($RetroBatRoot) { Join-Path $RetroBatRoot "frontends\$toolDir" } else { '' }
    $exePath = if ($fePath) { Get-FrontendExecutable -FrontendPath $fePath -ExeNames $exeNames } else { '' }
    @{
        FrontendType    = 'EmulationStation'
        ToolDir         = $toolDir
        ExePath         = $exePath
        ExeNames        = $exeNames
        DetectProcesses = @('retrobat', 'emulationstation')
        DetectPorts     = @()
        SettingsTargets = @(
            @{
                File    = 'system\configs\retrobat.conf'
                Section = 'system'
                Values  = @{
                    language     = ''
                    theme        = ''
                    collection   = ''
                }
            }
            @{
                File    = 'system\.emulationstation\es_settings.cfg'
                Section = 'global'
                Values  = @{
                    use_guns                = ''
                    disableautocontrollers   = ''
                }
            }
        )
        ThemeTarget     = 'system\configs\retrobat.conf'
        DatabaseFormat  = 'xml'
        Links           = @{
            Official = 'https://www.retrobat.org/'
            Wiki     = 'https://wiki.retrobat.org/'
        }
        Notes           = 'EmulationStation-based frontend for Windows. ROMs in roms/<system>/. Media in roms/<system>/media/. Themes in system/themes/. Primary frontend for Frieds Retrogaming Kit.'
    }
}

function Install-RetroBatFrontend {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-RetroBatFrontendInfo -RetroBatRoot $RetroBatRoot
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

function Configure-RetroBatFrontend {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    Set-FrontendsAdapterConfiguration -Names @('RetroBat') -RetroBatRoot $RetroBatRoot -Confirm:$false
}

function Set-RetroBatInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-RetroBatFrontendInfo -RetroBatRoot $RetroBatRoot
    foreach ($p in @(Get-FrontendsAdapterValue $info 'DetectPorts')) {
        $owner = @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name } | Select-Object -Unique)
        if ($owner.Count) { Write-KitLog "Port $p is owned by: $($owner -join ', ')" -Level Info }
    }
}