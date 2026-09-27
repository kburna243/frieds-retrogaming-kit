<#
.SYNOPSIS
    qMamehook (OpenHooker) output-middleware adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    qMamehook receives MAME's NETWORK output (mame.ini: output = network) over TCP and forwards lamp /
    feedback events to Arduino-style boards. It is DETECTED, never installed as a service and never
    started by the kit. Detection reads a snapshot (processes, ports, devices, tools folder) so tests
    can inject everything.

    Kit deviations from the downloaded draft (deliberate, permanent):
      * The draft scraped the GitHub API and downloaded release ZIPs — the kit never downloads. The
        adapter only names the official source; a user-supplied ZIP goes through
        Install-QMamehookSoftware with -PackagePath and -Approved.
      * The draft matched "any Arduino / USB Serial device" — that identifies a microcontroller, not
        this program. Program identity runs over process / port / tools folder, so BoardMatchIds is
        empty here.

    Port note: 9735 is a community convention for MAME's network output — it is official nowhere
    (neither MAME nor qMamehook documents mandate it). It stays configurable through qmhook.ini, and
    the kit only writes that Port value into a qmhook.ini that ALREADY EXISTS (installed by a person;
    the core module checks this and skips absent files). The kit never touches the Windows firewall —
    a localhost listener needs no rule.
#>

function Test-QMamehookHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [hashtable] $Snapshot)
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-OutputSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-QMamehookAdapterInfo
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

function Get-QMamehookAdapterInfo {
    @{
        ToolDir         = 'QMamehook'
        DetectProcesses = @('qMamehook', 'QMamehook')      # without .exe, case-insensitive
        DetectPorts     = @(9735)                          # MAME -output network port, community convention (see header)
        BoardMatchIds   = @()                              # generic Arduino boards identify the hardware, not the program — detection stays on process/port/dir
        MameOutput      = 'network'                        # mame.ini: output = network (TCP)
        # Only Port is managed, and only into an EXISTING qmhook.ini (the core module skips absent
        # files — the kit never creates the tool's settings). No firewall rule anywhere.
        SettingsTargets = @(
            @{ File = 'qmhook.ini'; Section = ''; Values = @{ Port = '9735' } }
        )
        Links           = @{ 'qMamehook' = 'https://github.com/SeongGino/qMamehook' }
        Notes           = 'Network output on 9735 (community convention; set Port in qmhook.ini). No firewall rule needed on localhost.'
    }
}

# Deliberately does NOT download: the kit only names the official source. The user fetches the ZIP and
# passes it as -PackagePath; with -Approved the kit unpacks it into tools\QMamehook. Without a package
# nothing happens beyond the hint — and qMamehook is never registered as a service or started.
function Install-QMamehookSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-QMamehookAdapterInfo
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

function Configure-QMamehookProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    Set-OutputMiddlewareConfiguration -Names @('QMamehook') -RetroBatRoot $RetroBatRoot -Confirm:$false
}

# Interference shield, kit style: whoever binds 9735 first steals MAME's network events (qMamehook vs
# Hook of the Reaper's TCP server, or any local web server). The shield only REPORTS the owning
# process; it never kills anything and never touches the firewall — localhost needs no rule.
function Set-QMamehookInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-QMamehookAdapterInfo
    foreach ($p in $info.DetectPorts) {
        $owner = @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name } | Select-Object -Unique)
        if ($owner.Count) { Write-KitLog (Get-KitText 'Output.Shield.PortOwner' -f $p, ($owner -join ', ')) -Level Info }
    }
}
