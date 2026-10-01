# Frame Pacing Enhancement Adapter
# DESCRIPTION: Detects and manages frame pacing via V-Sync modes, FreeSync/GSync, MPO (Multi-Plane
# Overlay) support, and Flip Model presentation. Smooth frame delivery eliminates microstutter and tearing.
# SAFETY: Disabling V-Sync entirely may cause tearing on fixed-refresh displays. Forcing MPO
# on unsupported drivers may cause black screens. Always check display capabilities first.

function Test-FramePacingHardware {
    [CmdletBinding()]
    param([hashtable] $Context = @{})
    # Always present — every GPU has some form of frame pacing
    $gpu = if ($Context.Contains('Gpu')) { $Context.Gpu } else { @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue) }
    @($gpu).Count -gt 0
}

function Get-FramePacingAdapterInfo {
    [CmdletBinding()]
    param()
    @{
        ToolDir       = ''
        DetectProcesses = @()
        BoardMatchIds = @()
        Links         = @{ 'MPO Info' = 'https://learn.microsoft.com/en-us/windows-hardware/drivers/display/multiplane-overlay-support' }
        SettingsTargets = @()
        Notes         = 'V-Sync modes: off (tearing, low latency), on (no tearing, higher latency), adaptive (auto-switch). FreeSync/GSync: variable refresh rate. MPO: reduces GPU copy overhead for windowed apps. Flip Model: independent flip for lower latency. ProfileHint: Performance uses V-Sync off + adaptive, Balanced uses adaptive sync, BestLook uses strict V-Sync.'
        ProfileHint   = 'Balanced'
    }
}

function Install-FramePacingSoftware {
    [CmdletBinding()]
    param()
    @{ Success = $true; Message = 'Frame pacing is GPU driver-level. Configure via driver control panel or RetroArch video settings.' }
}

function Configure-FramePacingProfile {
    [CmdletBinding()]
    param([ValidateSet('Performance','Balanced','BestLook')][string] $Profile = 'Balanced')
    $settings = switch ($Profile) {
        'Performance' { @{ Vsync = 'off'; FreeSync = 'on'; Mpo = 'off'; FlipModel = 'true' } }
        'Balanced'    { @{ Vsync = 'adaptive'; FreeSync = 'on'; Mpo = 'auto'; FlipModel = 'true' } }
        'BestLook'    { @{ Vsync = 'on'; FreeSync = 'on'; Mpo = 'on'; FlipModel = 'true' } }
    }
    @{ Success = $true; Applied = $settings; Message = "Frame pacing profile '$Profile' (V-Sync: $($settings.Vsync))" }
}

function Set-FramePacingInterferenceShield {
    [CmdletBinding()]
    param()
    @{ Success = $true }
}