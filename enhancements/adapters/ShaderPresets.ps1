<#
.SYNOPSIS
    Shader Presets enhancement-middleware adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    Detects and manages CRT/retro shader presets for RetroArch. It is DETECTED, never installed as a service and never
    started by the kit. Detection reads a snapshot (processes, ports, devices, tools folder) so tests
    can inject everything.

    ─── SAFETY — READ THIS ───
    This adapter does not enforce hardware safety limits; shader configuration is user-preference based.

    Kit deviations from the downloaded draft (deliberate, permanent):
      * The draft attempted to download shader packs - the kit never downloads.
        The adapter only names official sources; a user-supplied ZIP goes through
        Install-ShaderPresetsSoftware with -PackagePath and -Approved.
      * No specific tools folder or processes are required for basic shader detection.
      * Configuration suggests shader presets but does not write files directly -
        routes through core configuration system.
#>

function Test-ShaderPresetsHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [hashtable] $Snapshot)
    # No snapshot: read the live machine. With snapshot: pure data, nothing touched.
    if (-not $PSBoundParameters.ContainsKey('Snapshot') -or -not $Snapshot) {
        $Snapshot = Get-OutputSystemSnapshot -RetroBatRoot $RetroBatRoot
    }
    $info = Get-ShaderPresetsAdapterInfo
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

function Get-ShaderPresetsAdapterInfo {
    @{
        ToolDir         = 'RetroArch'
        DetectProcesses = @('retroarch')   # without .exe, case-insensitive
        DetectPorts     = @()              # RetroArch doesn't use specific ports for detection
        BoardMatchIds   = @()              # no device IDs to match for shader detection
        MameOutput      = ''               # not applicable to shader detection
        SettingsTargets = @(
            @{
                File    = 'retroarch.cfg'
                Section = 'video'
                Values  = @{ video_filter = ''; video_shader = ''; video_shader_dir = '' }
            }
        )
        Links           = @{ 'HSM Mega Bezel'='https://github.com/HyperspaceMadness/Mega_Bezel' }
        Notes           = 'CRT shader types: crt-lottes, crt-royale, hsm-mega-bezel. ProfileHint: &quot;BestLook&quot; uses hsm-mega-bezel, &quot;Balanced&quot; uses crt-lottes, &quot;Performance&quot; uses none.'
    }
}

# Deliberately does NOT download: the kit only names the official source. The user fetches the ZIP and
# passes it as -PackagePath; with -Approved the kit unpacks it into tools\RetroArch. Without a
# package nothing happens beyond the hint — and RetroArch is never registered as a service or started.
function Install-ShaderPresetsSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-ShaderPresetsAdapterInfo
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

function Configure-ShaderPresetsProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot)
    # Routes through the core so shader configuration can be processed
    Set-OutputMiddlewareConfiguration -Names @('ShaderPresets') -RetroBatRoot $RetroBatRoot -Confirm:$false
}

# Interference shield, kit style: shader presets don't typically own ports that interfere,
# but we report any conflicts if detected.
function Set-ShaderPresetsInterferenceShield {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-ShaderPresetsAdapterInfo
    foreach ($p in @(Get-OutputAdapterValue $info 'DetectPorts')) {
        $owner = @(Get-NetTCPConnection -State Listen -LocalPort $p -ErrorAction SilentlyContinue |
            ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name } | Select-Object -Unique)
        if ($owner.Count) { Write-KitLog (Get-KitText 'Output.Shield.PortOwner' -f $p, ($owner -join ', ')) -Level Info }
    }
}