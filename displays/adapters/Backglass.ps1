<#
.SYNOPSIS
    B2S Backglass Server output-middleware adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    B2S Backglass Server mirrors the backglass display (DMD/backglass/topper) from
    Visual Pinball or Future Pinball onto a second monitor or window. It is DETECTED,
    never installed as a service and never started by the kit. Detection reads a
    snapshot (processes, ports, devices, tools folder) so tests can inject everything.

    ─── SAFETY — READ THIS ───
    This adapter does not enforce safety limits; safety is handled by the core module.

    Kit deviations from the downloaded draft (deliberate, permanent):
      * The draft scraped the GitHub API, downloaded the release ZIP and Unblock-File'd it into
        tools\B2SBackglassServer - the kit never downloads. The adapter only names the official
        source; a user-supplied ZIP goes through Install-BackglassSoftware with -PackagePath and -Approved.
      * MameOutput is EMPTY on purpose: the backglass frame path does not run over the mame.ini
        "output" key (no Win32 output messages, no TCP events). The core truth-guards the mode list,
        so an empty MameOutput contributes no mode and can never raise an OutputModeConflict - verified
        against modules\Adapters.ps1 before this line was written.
      * BoardMatchIds is EMPTY because backglass server is identified by process and tools folder only.
      * SettingsTargets is EMPTY with full intent: ScreenRes.txt belongs to individual pinball tables
        and is managed by the pinball package, not the backglass server adapter.
      * The draft's machine-scope configuration environment variable is out: it was unverified
        and a system-wide intervention the kit does not make.
#>

function Test-BackglassHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [hashtable] $Snapshot)
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-OutputSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-BackglassAdapterInfo
    foreach ($p in @(Get-OutputAdapterValue $info 'DetectProcesses')) {
        if (@($Snapshot.Processes) -contains $p.ToLowerInvariant()) { return $true }
    }
    foreach ($port in @(Get-OutputAdapterValue $info 'DetectPorts')) {
        if (@($Snapshot.Ports) -contains [int]$port) { return $true }
    }
    foreach ($d in @($Snapshot.Devices | Where-Object { $_ })) {
        $id = (Get-LightgunDeviceId $d).ToUpperInvariant()
        foreach ($m in @(Get-OutputAdapterValue $info 'BoardMatchIds')) { if ($id -like $m.ToUpperInvariant()) { return $true } }
    }
    $toolDir = [string](Get-OutputAdapterValue $info 'ToolDir')
    if ($RetroBatRoot -and $toolDir) {
        if (Test-Path -LiteralPath (Join-Path $RetroBatRoot "tools\$toolDir") -PathType Container) { return $true }
    }
    # Check for ScreenRes.txt in pinball tables directory (common location)
    if ($RetroBatRoot) {
        $pinballDir = Join-Path $RetroBatRoot "Pinball\Tables"
        if (Test-Path -LiteralPath $pinballDir -PathType Container) {
            $screenRes = Join-Path $pinballDir "ScreenRes.txt"
            if (Test-Path -LiteralPath $screenRes -PathType Leaf) { return $true }
        }
        # Also check in Visual Pinball tables
        $vpTables = Join-Path $RetroBatRoot "Visual Pinball\Tables"
        if (Test-Path -LiteralPath $vpTables -PathType Container) {
            $screenRes = Join-Path $vpTables "ScreenRes.txt"
            if (Test-Path -LiteralPath $screenRes -PathType Leaf) { return $true }
        }
    }
    $false
}

function Get-BackglassAdapterInfo {
    @{
        ToolDir         = ''                               # B2SBackglassServer is portable; no specific tools folder
        DetectProcesses = @('B2SBackglassServer', 'B2SBackglassServerEXE')  # without .exe, case-insensitive
        DetectPorts     = @()                              # backglass server owns no TCP port for detection
        BoardMatchIds   = @()                              # identified by process/tools folder only
        MameOutput      = ''                               # the backglass is NOT fed by the mame.ini output key
        SettingsTargets = @()                              # ScreenRes.txt belongs to pinball tables, not adapter
        Links           = @{ 'B2S Backglass Server' = 'https://github.com/vpinball/b2s-backglass' }
        Notes           = 'B2SBackglassServer process; ScreenRes.txt belongs to pinball tables.'
    }
}

# Deliberately does NOT download: the kit only names the official source. The user fetches the ZIP
# and passes it as -PackagePath; with -Approved the kit unpacks it into tools\ (if needed). Without a
# package nothing happens beyond the hint - and B2S Backglass Server is never registered as a service.
function Install-BackglassSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-BackglassAdapterInfo
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

function Configure-BackglassProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    # Routes through the core on purpose: with MameOutput = '' and SettingsTargets = @() the core
    # touches neither mame.ini nor any settings file - that IS the configuration contract of v1
    # (ScreenRes.txt belongs to pinball tables, see header). Never hand-write anything here.
    Set-OutputMiddlewareConfiguration -Names @('Backglass') -RetroBatRoot $RetroBatRoot -Confirm:$false
}

# Interference shield, kit style: backglass server doesn't typically own ports that interfere.
function Set-BackglassInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-BackglassAdapterInfo
    foreach ($p in @(Get-OutputAdapterValue $info 'DetectPorts')) {
        $owner = @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name } | Select-Object -Unique)
        if ($owner.Count) { Write-KitLog (Get-KitText 'Output.Shield.PortOwner' -f $p, ($owner -join ', ')) -Level Info }
    }
}