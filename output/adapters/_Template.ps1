# ─── OUTPUT MIDDLEWARE TEMPLATE ─── copy, rename to <Tool>.ps1, fill in, never execute this file ───
# Every output\adapters\<Name>.ps1 implements the five functions below. Output middleware (rumble /
# lamps / solenoid servers like MAMEHooker, qMamehook, Hook of the Reaper) is DETECTED, NEVER
# INSTALLED as a service or started by the kit. Detection reads a SNAPSHOT (processes, ports,
# devices) so tests can inject everything.
#
# Kit rules:
#   * mame.ini "output" is the exclusive key: windows (Win32 messages) vs network (TCP). Declare it
#     in MameOutput. The core refuses to write when two detected tools disagree — report, don't force.
#   * Settings are only written into files that already exist (the tool was installed by a person).
#     Safety values (solenoid current limits!) belong in Safety — they are enforced, always.
#   * No downloads (links + -PackagePath + -Approved only), no process kills, no firewall, no
#     services, no Write-Host, no HKLM.

function Test-ExampleToolHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [hashtable] $Snapshot)
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-OutputSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-ExampleToolAdapterInfo
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

function Get-ExampleToolAdapterInfo {
    @{
        ToolDir         = 'ExampleTool'
        DetectProcesses = @('ExampleTool')        # without .exe, case-insensitive
        DetectPorts     = @()                     # TCP ports the tool listens on (its OWN server)
        BoardMatchIds   = @()                     # supported controller boards, tight signatures
        MameOutput      = 'windows'               # 'windows' | 'network' | '' (key not needed)
        # SettingsTargets: one entry per settings file the kit may manage.
        #   Path (absolute override) or ToolDir+File, Section ('' = root), Safety (enforced), Values (defaults)
        SettingsTargets = @(
            @{ File = 'settings.ini'; Section = ''; Safety = @{ DangerousThingMs = '200'; Protection = '1' }; Values = @{ Port = '8000' } }
        )
        Links           = @{ 'ExampleTool project' = 'https://example.org/' }
        Notes           = ''
    }
}

function Install-ExampleToolSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-ExampleToolAdapterInfo
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

function Configure-ExampleToolProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    Set-OutputMiddlewareConfiguration -Names @('ExampleTool') -RetroBatRoot $RetroBatRoot -Confirm:$false
}

function Set-ExampleToolInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    # Output tools share Win32 messages/ports; the shield only REPORTS rival listeners, never kills.
    if ($Disable) { return }
    $info = Get-ExampleToolAdapterInfo
    foreach ($p in $info.DetectPorts) {
        $owner = @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name } | Select-Object -Unique)
        if ($owner.Count) { Write-KitLog (Get-KitText 'Output.Shield.PortOwner' -f $p, ($owner -join ', ')) -Level Info }
    }
}
