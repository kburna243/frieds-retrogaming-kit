<#
.SYNOPSIS
    RetroBat frontend adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    Detects and manages RetroBat frontend library. It is DETECTED, never installed as a service and never
    started by the kit. Detection reads a snapshot (processes, ports, devices, tools folder) so tests
    can inject everything.

    ─── SAFETY — READ THIS ───
    This adapter does not enforce hardware limits; configuration is user-preference based.

    Kit deviations from the downloaded draft (deliberate, permanent):
      * The draft attempted to download frontend packs - the kit never downloads.
        The adapter only names official sources; a user-supplied ZIP goes through
        Install-RetroBatFrontend with -PackagePath and -Approved.
      * No specific tools folder or processes are required for basic frontend detection.
      * Configuration suggests frontend settings but does not write files directly -
        routes through core configuration system.
#>

function Test-RetroBatFrontend {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [hashtable] $Snapshot)
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-OutputSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-RetroBatFrontendInfo
    foreach ($p in $info.DetectProcesses) {
        if (@($Snapshot.Processes) -contains $p.ToLowerInvariant()) { return $true }
    }
    foreach ($port in $info.DetectPorts) {
        if (@($Snapshot.Ports) -contains [int]$port) { return $true }
    }
    foreach ($d in @($Snapshot.Devices | Where-Object { $_ })) {
        $id = (Get-LightgunDeviceId $d).ToUpperInvariant()
        foreach ($m in $info.BoardMatchIds) { if ($id -like $m.ToUpperInvariant()) { return $true } }
    }
    if ($RetroBatRoot -and $info.ToolDir) {
        if (Test-Path -LiteralPath (Join-Path $RetroBatRoot "tools\$($info.ToolDir)") -PathType Container) { return $true }
    }
    # Additional checks for RetroBat: roms subdirectory and gamelist.xml pattern
    if ($RetroBatRoot) {
        $romsPath = Join-Path $RetroBatRoot 'roms'
        if (Test-Path -LiteralPath $romsPath -PathType Container) {
            # Check for at least one system folder with gamelist.xml
            $systemFolders = Get-ChildItem -Path $romsPath -Directory -ErrorAction SilentlyContinue
            foreach ($system in $systemFolders) {
                $gamelist = Join-Path $system.FullName 'gamelist.xml'
                if (Test-Path -LiteralPath $gamelist -PathType Leaf) {
                    return $true
                }
            }
        }
    }
    $false
}

function Get-RetroBatFrontendInfo {
    @{
        ToolDir         = 'RetroBat'
        DetectProcesses = @('retrobat')   # without .exe, case-insensitive
        DetectPorts     = @()              # RetroBat doesn't use specific ports for detection
        BoardMatchIds   = @()              # no device IDs to match for frontend detection
        MameOutput      = ''               # not applicable to frontend detection
        SettingsTargets = @(
            @{
                File    = 'retrobat.conf'
                Section = 'system'
                Values  = @{ language = ''; theme = '' }
            }
        )
        Links           = @{ 'RetroBat Official'='https://www.retrobat.org/' }
        Notes           = 'RetroBat ES gamelist.xml structure. ROMs organized per system under roms/. Media in images/videos subfolders.'
        DatabaseFormat  = 'xml'
        RomPathPattern  = 'roms/<system>/*.zip|*.iso|*.chd'
        MediaPathPattern= 'roms/<system>/media/'
        PlaylistFormat  = 'xml gamelist files'
    }
}

function Install-RetroBatFrontend {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-RetroBatFrontendInfo
    $target = Join-Path $RetroBatRoot "tools\$($info.ToolDir)"
    if (-not $PackagePath) {
        foreach ($k in $info.Links.Keys) { Write-KitLog (Get-KitText 'Output.Adapter.SoftwareLink' -f $k, $info.Links[$k]) }
        Write-KitLog (Get-KitText 'Output.Adapter.NoService') -Level Info
        return $false
    }
    if (-not $Approved.IsPresent) { Write-KitLog (Get-KitText 'Output.Adapter.NeedsApproval') -Level Warn; return $false }
    if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) { Write-KitLog (Get-KitText 'Output.Adapter.PackageMissing' -f $PackagePath) -Level Warn; return $false }
    if (-not $PSCmdlet.ShouldProcess($target, 'unpack middleware package')) { return $false }
    $null = New-Item -ItemType Directory -Path $target -Force
    Write-KitLog (Get-KitText 'Output.Adapter.PackageHash' -f (Split-Path -Leaf $PackagePath), (Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash)
    Expand-Archive -LiteralPath $PackagePath -DestinationPath $target -Force
    Write-KitLog (Get-KitText 'Output.Adapter.SoftwareInstalled' -f $info.ToolDir, $target)
    $true
}

function Configure-RetroBatFrontend {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    # Routes through the core so frontend configuration can be processed
    Set-OutputMiddlewareConfiguration -Names @('RetroBat') -RetroBatRoot $RetroBatRoot -Confirm:$false
}

function Set-RetroBatInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-RetroBatFrontendInfo
    foreach ($p in @(Get-OutputAdapterValue $info 'DetectPorts')) {
        $owner = @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name } | Select-Object -Unique)
        if ($owner.Count) { Write-KitLog (Get-KitText 'Output.Shield.PortOwner' -f $p, ($owner -join ', ')) -Level Info }
    }
}