function Get-EnhancementsAdapterDir {
    Join-Path $script:EnhancementsDir 'adapters'
}

function Get-EnhancementsDefaultStatePath {
    Join-Path $script:EnhancementsDir 'state.json'
}

function Get-EnhancementsRetroBatRoot {
    # Assuming RetroBat is installed in a sibling directory or via environment variable
    $retroBatPath = $env:RETROBAT_PATH
    if (-not $retroBatPath) {
        # Default to a common location relative to the kit root
        $retroBatPath = Join-Path $script:KitRoot '..\RetroBat'
    }
    return $retroBatPath
}

function Get-EnhancementGpuInfo {
    # Returns GPU name, VRAM, driver version via Get-CimInstance Win32_VideoController
    $gpus = Get-CimInstance -ClassName Win32_VideoController | Select-Object -Property Name, AdapterRAM, DriverVersion
    foreach ($gpu in $gpus) {
        [PSCustomObject]@{
            Name          = $gpu.Name
            VRAM_MB       = [math]::Round($gpu.AdapterRAM / 1MB, 2)
            DriverVersion = $gpu.DriverVersion
        }
    }
}

function Test-EnhancementMpoSupport {
    # Check HKLM:\SOFTWARE\Microsoft\Windows\Dwm for OverlayTestMode
    $path = 'HKLM:\SOFTWARE\Microsoft\Windows\Dwm'
    if (Test-Path $path) {
        $value = Get-ItemProperty -Path $path -Name 'OverlayTestMode' -ErrorAction SilentlyContinue
        if ($value -and $value.OverlayTestMode -eq 1) {
            return $true
        }
    }
    return $false
}

function Get-EnhancementAudioDevices {
    # Get-CimInstance Win32_SoundDevice, return names + channels
    $audioDevices = Get-CimInstance -ClassName Win32_SoundDevice | Select-Object -Property Name, NumberOfChannels
    foreach ($device in $audioDevices) {
        [PSCustomObject]@{
            Name      = $device.Name
            Channels  = $device.NumberOfChannels
        }
    }
}

function Get-EnhancementProfile {
    param([ValidateSet('Performance','Balanced','BestLook')][string]$Name)
    switch ($Name) {
        'Performance' { return @{
            Label = 'Performance'; Motto = 'Max FPS, min latency'
            Shader = 'none'; Upscaling = 'integer'; Vsync = 'off'
            RunAhead = 'max'; FramePacing = 'adaptive'
            AntiAliasing = 'off'; AmbientLighting = 'off'; AudioEnhance = 'off'
        }}
        'Balanced' { return @{
            Label = 'Gesunde Mischung'; Motto = 'Gut aussehen, flüssig laufen'
            Shader = 'crt-lottes'; Upscaling = '2x'; Vsync = 'adaptive'
            RunAhead = 1; FramePacing = 'auto'
            AntiAliasing = 'fxaa'; AmbientLighting = 'basic'; AudioEnhance = 'stereo-upmix'
        }}
        'BestLook' { return @{
            Label = 'Best Look'; Motto = 'Maximale Optik'
            Shader = 'hsm-mega-bezel'; Upscaling = '4k'; Vsync = 'on'
            RunAhead = 1; FramePacing = 'strict'
            AntiAliasing = 'msaa4x'; AmbientLighting = 'full'; AudioEnhance = 'virtual-7.1'
        }}
    }
}