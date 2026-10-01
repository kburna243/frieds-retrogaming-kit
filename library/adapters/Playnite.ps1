<#
.SYNOPSIS
    Playnite frontend library adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    Detects and manages Playnite frontend library. It is DETECTED, never installed as a service and never
    started by the kit. Detection reads a snapshot (processes, ports, devices, tools folder) so tests
    can inject everything.

    ─── SAFETY — READ THIS ───
    This adapter does not enforce hardware limits; configuration is read-only for safety.

    Kit deviations from the downloaded draft (deliberate, permanent):
      * The draft attempted to download Playnite - the kit never downloads.
        The adapter only names official sources; a user-supplied ZIP goes through
        Install-PlayniteFrontend with -PackagePath and -Approved.
      * No specific tools folder or processes are required for basic Playnite detection.
      * Configuration suggests Playnite settings but does not write files directly -
        routes through core configuration system.
#>

function Test-PlayniteFrontend {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [hashtable] $Snapshot)
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-OutputSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-PlayniteFrontendInfo
    foreach ($p in $info.DetectProcesses) {
        if (@($Snapshot.Processes) -contains $p.ToLowerInvariant()) { return $true }
    }
    # Check known paths for Playnite installation
    $localAppData = $env:LOCALAPPDATA
    $appData = $env:APPDATA
    $knownPaths = @(
        Join-Path $localAppData 'Playnite',
        Join-Path $appData 'Playnite'
    )
    foreach ($path in $knownPaths) {
        if (Test-Path -LiteralPath $path -PathType Container) {
            # Additionally check for library\games\ database
            $dbPath = Join-Path $path 'library\games.db'
            if (Test-Path -LiteralPath $dbPath -PathType Leaf) {
                return $true
            }
        }
    }
    $false
}

function Get-PlayniteFrontendInfo {
    @{
        ToolDir         = 'Playnite'
        DetectProcesses = @('Playnite.DesktopApp','Playnite.FullscreenApp')
        DetectPorts     = @()              # Playnite doesn't use specific ports for detection
        BoardMatchIds   = @()              # no device IDs to match for Playnite detection
        MameOutput      = ''               # not applicable to Playnite detection
        SettingsTargets = @()              # Playnite configuration is read via SQLite, not direct file edits
        Links           = @{ 'Playnite Official'='https://playnite.link' }
        Notes           = 'Playnite uses SQLite database. Supports all emulators via plugin system. Media stored in library/files/. Metadata includes icons, covers, backgrounds.'
    }
}

# Deliberately does NOT download: the kit only names the official source. The user fetches the ZIP and
# passes it as -PackagePath; with -Approved the kit unpacks it into tools\Playnite. Without a
# package nothing happens beyond the hint — and Playnite is never registered as a service or started.
function Install-PlayniteFrontend {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-PlayniteFrontendInfo
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

function Configure-PlayniteFrontend {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    # Routes through the core so Playnite configuration can be processed
    Set-OutputMiddlewareConfiguration -Names @('Playnite') -RetroBatRoot $RetroBatRoot -Confirm:$false
}

# Interference shield, kit style: Playnite doesn't typically own ports that interfere,
# but we report any conflicts if detected.
function Set-PlayniteInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-PlayniteFrontendInfo
    foreach ($p in @(Get-OutputAdapterValue $info 'DetectPorts')) {
        $owner = @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name } | Select-Object -Unique)
        if ($owner.Count) { Write-KitLog (Get-KitText 'Output.Shield.PortOwner' -f $p, ($owner -join ', ')) -Level Info }
    }
}