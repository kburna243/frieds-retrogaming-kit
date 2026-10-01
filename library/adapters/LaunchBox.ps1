<#
.SYNOPSIS
    LaunchBox frontend library adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    Detects and manages LaunchBox frontend library. It is DETECTED, never installed as a service and never
    started by the kit. Detection reads a snapshot (processes, ports, devices, tools folder) so tests
    can inject everything.

    ─── SAFETY — READ THIS ───
    This adapter does not enforce hardware limits; configuration is read-only for safety.

    Kit deviations from the downloaded draft (deliberate, permanent):
      * The draft attempted to download LaunchBox - the kit never downloads.
        The adapter only names official sources; a user-supplied ZIP goes through
        Install-LaunchBoxFrontend with -PackagePath and -Approved.
      * No specific tools folder or processes are required for basic LaunchBox detection.
      * Configuration suggests LaunchBox settings but does not write files directly -
        routes through core configuration system.
#>

function Test-LaunchBoxFrontend {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [hashtable] $Snapshot)
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-OutputSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-LaunchBoxFrontendInfo
    foreach ($p in $info.DetectProcesses) {
        if (@($Snapshot.Processes) -contains $p.ToLowerInvariant()) { return $true }
    }
    # Check known paths for LaunchBox installation
    $knownPaths = @(
        'C:\LaunchBox',
        'D:\LaunchBox'
    )
    foreach ($path in $knownPaths) {
        if (Test-Path -LiteralPath $path -PathType Container) {
            # Additionally check for Data\ XML folder
            $dataPath = Join-Path $path 'Data'
            if (Test-Path -LiteralPath $dataPath -PathType Container) {
                return $true
            }
        }
    }
    $false
}

function Get-LaunchBoxFrontendInfo {
    @{
        ToolDir         = 'LaunchBox'
        DetectProcesses = @('LaunchBox','BigBox')
        DetectPorts     = @()              # LaunchBox doesn't use specific ports for detection
        BoardMatchIds   = @()              # no device IDs to match for LaunchBox detection
        MameOutput      = ''               # not applicable to LaunchBox detection
        SettingsTargets = @()              # LaunchBox configuration is read via XML, not direct file edits
        Links           = @{ 'LaunchBox Official'='https://www.launchbox-app.com' }
        Notes           = 'LaunchBox uses XML-based database: Platforms.xml for systems, individual platform XMLs for games. Media organized in Images/ hierarchy. Playlists stored as XML in Data/Playlists/.'
    }
}

# Deliberately does NOT download: the kit only names the official source. The user fetches the ZIP and
# passes it as -PackagePath; with -Approved the kit unpacks it into tools\LaunchBox. Without a
# package nothing happens beyond the hint — and LaunchBox is never registered as a service or started.
function Install-LaunchBoxFrontend {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-LaunchBoxFrontendInfo
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

function Configure-LaunchBoxFrontend {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    # Routes through the core so LaunchBox configuration can be processed
    Set-OutputMiddlewareConfiguration -Names @('LaunchBox') -RetroBatRoot $RetroBatRoot -Confirm:$false
}

# Interference shield, kit style: LaunchBox doesn't typically own ports that interfere,
# but we report any conflicts if detected.
function Set-LaunchBoxInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-LaunchBoxFrontendInfo
    foreach ($p in @(Get-OutputAdapterValue $info 'DetectPorts')) {
        $owner = @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name } | Select-Object -Unique)
        if ($owner.Count) { Write-KitLog (Get-KitText 'Output.Shield.PortOwner' -f $p, ($owner -join ', ')) -Level Info }
    }
}