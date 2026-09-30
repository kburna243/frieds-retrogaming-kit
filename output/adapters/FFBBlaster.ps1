<#
.SYNOPSIS
    FFBBlaster output-middleware adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    FFBBlaster is a TeknoParrot force feedback plugin that sends game output events over TCP
    when OutputsSystem=1 in FFBBlaster.ini. It is DETECTED, never installed as a service and
    never started by the kit. Detection reads a snapshot (processes, ports, devices, tools folder)
    so tests can inject everything.

    ─── SAFETY — READ THIS ───
    FFBBlaster does not involve physical solenoids, but requires OutputsSystem=1 to function
    with Gunmote. If OutputsSystem=0 (default), FFBBlaster only uses Windows messages and
    Gunmote CANNOT receive events. The adapter checks and warns if OutputsSystem=0.

    Kit deviations from the downloaded draft (deliberate, permanent):
      * The draft downloaded the ZIP from the vendor site — the kit never downloads. The adapter
        only names the official source; a user-supplied ZIP goes through Install-FFBBlasterSoftware
        with -PackagePath and -Approved.
      * The draft overwrote settings.ini wholesale (Set-Content -Force) — the kit edits only files
        that ALREADY exist, through the backup/WhatIf path in Set-OutputMiddlewareConfiguration.
      * BoardMatchIds is empty: FFBBlaster has no specific hardware board ID; it works with any
        DirectInput/XInput device via TeknoParrot.
      * MameOutput is 'network' (FFBBlaster uses TCP, not Win32 messages).
      * SettingsTargets is empty (per-game FFBBlaster.ini in <Game>\teknoparrot\elf\FFBBlaster.ini).
      * Notes about OutputsSystem=1 requirement and TCP ports 8000/8002.
#>

function Test-FFBBlasterHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [hashtable] $Snapshot)
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-OutputSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-FFBBlasterAdapterInfo
    foreach ($p in $info.DetectProcesses) {
        if (@($Snapshot.Processes) -contains $p.ToLowerInvariant()) { return $true }
    }
    foreach ($port in $info.DetectPorts) {
        if (@($Snapshot.Ports) -contains [int]$port) { return $true }
    }
    if ($RetroBatRoot -and $info.ToolDir) {
        if (Test-Path -LiteralPath (Join-Path $RetroBatRoot "tools\$($info.ToolDir)") -PathType Container) { return $true }
    }
    $false
}

function Get-FFBBlasterAdapterInfo {
    @{
        ToolDir         = 'FFBBlaster'
        DetectProcesses = @('BudgieLoader')   # TeknoParrot hosts FFBBlaster.dll
        DetectPorts     = @(8000, 8002)       # FFBBlaster TCP ports (8002 for recoil-stretch.py proxy to 8000)
        BoardMatchIds   = @()                 # No specific hardware board; works via TeknoParrot
        MameOutput      = 'network'           # mame.ini: output = network (TCP)
        SettingsTargets = @()                 # Per-game: <Game>\teknoparrot\elf\FFBBlaster.ini
        Links           = @{ 'FFBBlaster (TeknoParrot FFB Plugin)' = 'https://github.com/tknoparrot/FFBBlaster' }
        Notes           = 'Requires OutputsSystem=1 in FFBBlaster.ini for TCP output; NetOutputsTCPPort typically 8002. FFBBlaster.ini is created on first game launch — network settings must be applied after. In TeknoParrot profiles, filter by FieldName "Enable" AND CategoryName "FFB Blaster" (the first Enable field may belong to Crosshair/Bezel/Cheats). 19 gun games have FFB Blaster active.'
    }
}

function Install-FFBBlasterSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-FFBBlasterAdapterInfo
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

function Configure-FFBBlasterProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    # Routes through the core so any existing FFBBlaster.ini is touched via backup/WhatIf path.
    Set-OutputMiddlewareConfiguration -Names @('FFBBlaster') -RetroBatRoot $RetroBatRoot -Confirm:$false
}

function Set-FFBBlasterInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-FFBBlasterAdapterInfo
    foreach ($p in $info.DetectPorts) {
        $owner = @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name } | Select-Object -Unique)
        if ($owner.Count) { Write-KitLog (Get-KitText 'Output.Shield.PortOwner' -f $p, ($owner -join ', ')) -Level Info }
    }
}