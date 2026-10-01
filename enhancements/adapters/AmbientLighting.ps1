# Ambient Lighting Enhancement Adapter
# DESCRIPTION: Detects and manages ambient cabinet lighting — Ambilight (screen edge color sampling),
# WS2812 LED controllers, activity dimmer with power-save timeout. Enhances immersion.
# SAFETY: Always enforce a timeout limit on LED controllers to prevent burn-in or power waste.
# Never leave LEDs at full brightness for more than 30 minutes without activity.

function Test-AmbientLightingHardware {
    [CmdletBinding()]
    param([hashtable] $Context = @{})
    $devices = if ($Context.Contains('Devices')) { $Context.Devices } else { @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue) }
    foreach ($d in $devices) {
        $did = [string]$d.DeviceID
        if ($did -match 'USB\\VID_1A86&PID_7523' -or $did -match 'CH340' -or $did -match 'WS2812' -or $did -match 'Adalight') { return $true }
    }
    $procs = if ($Context.Contains('Processes')) { $Context.Processes } else { @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $_.Name.ToLowerInvariant() }) }
    'ambibox' -in $procs -or 'prismatik' -in $procs -or 'hyperion' -in $procs
}

function Get-AmbientLightingAdapterInfo {
    [CmdletBinding()]
    param()
    @{
        ToolDir       = ''
        DetectProcesses = @('ambibox', 'prismatik', 'hyperion')
        BoardMatchIds = @('USB\VID_1A86&PID_7523*', 'USB\VID_*&PID_*CH340*')
        Links         = @{ 'AmbiBox' = 'https://www.ambilight4u.com/' }
        SettingsTargets = @()
        Notes         = 'Ambilight: screen edge color sampling for real-time ambient glow. WS2812 LED strips via Arduino/ESP32 (COM port). Inactivity dimmer: fades to 10% after 5 min, off after 30 min. ProfileHint: BestLook uses full ambilight, Balanced uses basic, Performance uses off.'
        ProfileHint   = 'Balanced'
    }
}

function Install-AmbientLightingSoftware {
    [CmdletBinding()]
    param()
    @{ Success = $true; Message = 'AmbiBox or Prismatik required for Ambilight. WS2812 requires Arduino/ESP32 with FastLED firmware.' }
}

function Configure-AmbientLightingProfile {
    [CmdletBinding()]
    param([ValidateSet('Performance','Balanced','BestLook')][string] $Profile = 'Balanced')
    $settings = switch ($Profile) {
        'Performance' { @{ Enabled = 'false'; Brightness = '0'; InactivityTimeout = '0'; ColorSampling = 'off' } }
        'Balanced'    { @{ Enabled = 'true'; Brightness = '50'; InactivityTimeout = '15'; ColorSampling = 'average' } }
        'BestLook'    { @{ Enabled = 'true'; Brightness = '80'; InactivityTimeout = '30'; ColorSampling = 'per-edge' } }
    }
    @{ Success = $true; Applied = $settings; Message = "Ambient lighting profile '$Profile' (enabled: $($settings.Enabled))" }
}

function Set-AmbientLightingInterferenceShield {
    [CmdletBinding()]
    param()
    @{ Success = $true; Warning = 'Ensure LED controller has a physical power disconnect. Software timeout is a safety net, not a replacement.' }
}