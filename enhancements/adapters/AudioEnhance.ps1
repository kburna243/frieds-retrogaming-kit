# Audio Enhancement Adapter
# DESCRIPTION: Detects and manages audio enhancements — virtual 7.1 surround, stereo upmix,
# FxSound equalizer, and audio latency monitoring. Optimizes cabinet audio output.
# SAFETY: Audio latency below 10ms may cause crackling or dropouts. Virtual 7.1 on stereo-only
# output devices wastes CPU. Always verify the audio device capabilities before enabling surround.

function Test-AudioEnhanceHardware {
    [CmdletBinding()]
    param([hashtable] $Context = @{})
    $procs = if ($Context.Contains('Processes')) { $Context.Processes } else { @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $_.Name.ToLowerInvariant() }) }
    if ('fxsound' -in $procs) { return $true }
    # Always present — every PC has audio
    $audio = @(Get-CimInstance -ClassName Win32_SoundDevice -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' })
    @($audio).Count -gt 0
}

function Get-AudioEnhanceAdapterInfo {
    [CmdletBinding()]
    param()
    @{
        ToolDir       = ''
        DetectProcesses = @('fxsound')
        BoardMatchIds = @()
        Links         = @{ 'FxSound' = 'https://www.fxsound.com/' }
        SettingsTargets = @()
        Notes         = 'Virtual 7.1: spatial audio for multi-speaker cabinets. Stereo upmix: expands stereo to all channels. Audio latency: warn if < 10ms (crackling risk). FxSound: system-wide equalizer with presets. ProfileHint: BestLook uses virtual 7.1 + FxSound, Balanced uses stereo upmix, Performance uses off (lowest latency).'
        ProfileHint   = 'Balanced'
    }
}

function Install-AudioEnhanceSoftware {
    [CmdletBinding()]
    param()
    @{ Success = $true; Message = 'FxSound is free. Install from https://www.fxsound.com/ for system-wide EQ. Virtual 7.1 requires capable audio hardware.' }
}

function Configure-AudioEnhanceProfile {
    [CmdletBinding()]
    param([ValidateSet('Performance','Balanced','BestLook')][string] $Profile = 'Balanced')
    $settings = switch ($Profile) {
        'Performance' { @{ Surround = 'off'; Upmix = 'off'; Equalizer = 'off'; LatencyTarget = 'low' } }
        'Balanced'    { @{ Surround = 'off'; Upmix = 'stereo-upmix'; Equalizer = 'flat'; LatencyTarget = 'balanced' } }
        'BestLook'    { @{ Surround = 'virtual-7.1'; Upmix = 'stereo-upmix'; Equalizer = 'on'; LatencyTarget = 'quality' } }
    }
    $warnings = @()
    $latency = try {
        $audio = @(Get-CimInstance -ClassName Win32_SoundDevice -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'OK' })
        if ($audio.Count) { 'ok' } else { 'no-device' }
    } catch { 'unknown' }
    if ($latency -eq 'no-device') { $warnings += 'No active audio device found' }
    $result = @{ Success = ($warnings.Count -eq 0); Applied = $settings; Message = "Audio profile '$Profile' (surround: $($settings.Surround), eq: $($settings.Equalizer))" }
    if ($warnings.Count) { $result.Warnings = $warnings }
    $result
}

function Set-AudioEnhanceInterferenceShield {
    [CmdletBinding()]
    param()
    @{ Success = $true; Warning = 'Audio latency below 10ms may cause crackling. Reduce surround channels if issues occur.' }
}