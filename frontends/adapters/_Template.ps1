# Template for frontend adapters. Copy to <Name>.ps1 and replace <Name> with the frontend moniker
# (e.g., RetroBat, PinballY, Playnite, LaunchBox, PinUP). Five-function contract: Test, Get-Info,
# Install, Configure, Shield. Designed for extensibility: drop-in adapters are auto-discovered.
# All adapters detect presence (exe, folder, process), provide info (paths, config targets, links,
# database format), install (link only; user supplies package), configure (settings targets),
# and shield (port/process conflicts).

function Test-<Name>Frontend {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [hashtable] $Snapshot
    )
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-FrontendSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-<Name>FrontendInfo -RetroBatRoot $RetroBatRoot
    if ($info.ExePath -and (Test-Path -LiteralPath $info.ExePath -PathType Leaf)) { return $true }
    foreach ($p in $info.DetectProcesses) {
        if (@($Snapshot.Processes) -contains $p.ToLowerInvariant()) { return $true }
    }
    if ($RetroBatRoot -and $info.ToolDir) {
        if (Test-Path -LiteralPath (Join-Path $RetroBatRoot "frontends\$($info.ToolDir)") -PathType Container) { return $true }
    }
    $false
}

function Get-<Name>FrontendInfo {
    [CmdletBinding()]
    param([string] $RetroBatRoot = '')
    @{
        FrontendType    = ''
        ToolDir         = ''
        ExePath         = ''
        ExeNames        = @()
        DetectProcesses = @()
        DetectPorts     = @()
        SettingsTargets = @()
        ThemeTarget     = ''
        DatabaseFormat  = 'xml'
        Links           = @{}
        Notes           = ''
    }
}

function Install-<Name>Frontend {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-<Name>FrontendInfo -RetroBatRoot $RetroBatRoot
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

function Configure-<Name>Frontend {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    Set-FrontendsAdapterConfiguration -Names @('<Name>') -RetroBatRoot $RetroBatRoot -Confirm:$false
}

function Set-<Name>InterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-<Name>FrontendInfo -RetroBatRoot $RetroBatRoot
    foreach ($p in @(Get-FrontendsAdapterValue $info 'DetectPorts')) {
        $owner = @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name } | Select-Object -Unique)
        if ($owner.Count) { Write-KitLog "Port $p is owned by: $($owner -join ', ')" -Level Info }
    }
}