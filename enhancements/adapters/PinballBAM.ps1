<#
.SYNOPSIS
    PinballBAM adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    Manages Future Pinball BAM (Better Arcade Mode) settings: checks hardware, gets adapter info, installs software, configures profiles, and sets interference shield.
    Follows the 5-function contract: Test-*Hardware, Get-*AdapterInfo, Install-*Software, Configure-*Profile, Set-*InterferenceShield.
#>

function Test-PinballBAMHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [hashtable] $Snapshot)
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-OutputSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-PinballBAMAdapterInfo
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
    $false
}

function Get-PinballBAMAdapterInfo {
    @{
        ToolDir         = ''
        DetectProcesses = @('Future Pinball')
        BoardMatchIds   = @()
        Links           = @{ 'BAM (Ravarcade)'='https://www.ravarcade.pl/' }
        Notes           = 'Dynamic Lights, Shadowmaps, Normal Maps (4-GB patch required for large textures), Post-Processing (SSAO, God Rays, Stereoscopic 3D), PinEvent support (TerryRed tables). ProfileHint: ''BestLook'' enables dynamic lights + shadowmaps + normal maps + 4GB patch, ''Balanced'' uses dynamic lights only, ''Performance'' uses baked lights only.'
    }
}

function Install-PinballBAMSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-PinballBAMAdapterInfo
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

function Configure-PinballBAMProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    # Routes through the core so the Safety hashtable is always enforced on the existing registry values — this function must never write registry by hand.
    Set-OutputMiddlewareConfiguration -Names @('PinballBAM') -RetroBatRoot $RetroBatRoot -Confirm:$false
}

function Set-PinballBAMInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-PinballBAMAdapterInfo
    foreach ($p in $info.DetectPorts) {
        $owner = @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name } | Select-Object -Unique)
        if ($owner.Count) { Write-KitLog (Get-KitText 'Output.Shield.PortOwner' -f $p, ($owner -join ', ')) -Level Info }
    }
}