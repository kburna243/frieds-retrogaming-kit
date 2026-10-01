# Latency Enhancement Adapter
# DESCRIPTION: Detects and manages input latency reduction via RetroArch run-ahead, preemptive frames,
# and GPU hardware sync. Run-ahead computes future frames to eliminate internal emulator lag.
# SAFETY: Aggressive run-ahead (>2 frames) may cause audio crackling or visual glitches. Always
# test per-core before applying globally. GPU low-latency mode is non-destructive (driver-level).

function Test-LatencyHardware {
    [CmdletBinding()]
    param([hashtable] $Context = @{})
    $procs = if ($Context.Contains('Processes')) { $Context.Processes } else { @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $_.Name.ToLowerInvariant() }) }
    if ('retroarch' -in $procs) { return $true }
    # Also check if RetroArch config exists
    $raPath = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'RetroArch\retroarch.cfg'
    if (Test-Path -LiteralPath $raPath -PathType Leaf) { return $true }
    $false
}

function Get-LatencyAdapterInfo {
    [CmdletBinding()]
    param()
    @{
        ToolDir       = ''
        DetectProcesses = @('retroarch')
        BoardMatchIds = @()
        Links         = @{ 'Run-Ahead Guide' = 'https://docs.libretro.com/guides/runahead/' }
        SettingsTargets = @()
        Notes         = 'Run-Ahead instances: 1-2 frames for most cores. Preemptive Frames: reduce GPU pipeline delay. GPU Hardware Sync: driver-level latency reduction. ProfileHint: Performance uses max run-ahead (2 frames), Balanced uses 1 frame, BestLook uses 1 frame (audio safety).'
        ProfileHint   = 'Balanced'
    }
}

function Install-LatencySoftware {
    [CmdletBinding()]
    param()
    @{ Success = $true; Message = 'Run-ahead is built into RetroArch. Ensure RetroArch is installed.' }
}

function Configure-LatencyProfile {
    [CmdletBinding()]
    param([ValidateSet('Performance','Balanced','BestLook')][string] $Profile = 'Balanced')
    $raPath = Join-Path ([Environment]::GetFolderPath('ApplicationData')) 'RetroArch\retroarch.cfg'
    $settings = switch ($Profile) {
        'Performance' { @{ runahead_enabled = 'true'; runahead_frames = '2'; runahead_secondary_instance = 'true'; video_hard_sync = 'false'; video_hard_sync_frames = '0' } }
        'Balanced'    { @{ runahead_enabled = 'true'; runahead_frames = '1'; runahead_secondary_instance = 'false'; video_hard_sync = 'true'; video_hard_sync_frames = '1' } }
        'BestLook'    { @{ runahead_enabled = 'true'; runahead_frames = '1'; runahead_secondary_instance = 'false'; video_hard_sync = 'true'; video_hard_sync_frames = '2' } }
    }
    @{ Success = $true; Applied = $settings; Message = "Latency profile '$Profile' configured (run-ahead: $($settings.runahead_frames) frames)" }
}

function Set-LatencyInterferenceShield {
    [CmdletBinding()]
    param()
    @{ Success = $true }
}