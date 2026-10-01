# Diagnostics.ps1 -- Fast-Path system health (sub-2-second hardware/storage/interference check).
# Returns a structured object with Status='OK' or 'Degraded', not a wall of text.
# The MCP agent loads this at session start so it never guesses about hardware state.
#
# Three vital pillars:
# 1. Hardware Matrix (USB VID): Lightguns, DolphinBars, Arcade Encoders, Xbox controllers.
# 2. Storage & Network: Local directories and UNC NAS mounts (Test-Path, no deep scan).
# 3. Interference (Stoerfaktoren): Processes that eat XInput, exclusive fullscreen, or resources.

# Vendor IDs that identify critical cabinet hardware.
$script:HealthHardwareVids = @{
    DolphinBar    = @('VID_057E')          # Nintendo / Mayflash DolphinBar
    ArcadeEncoder = @('VID_16C0', 'VID_2341', 'VID_2E8A', 'VID_0079')  # Xin-Mo, Arduino, Pico, generic
    SindenLightgun = @('VID_16C0&PID_0F01', 'VID_16C0&PID_0F02')
    Gun4IR        = @('VID_2341&PID_8037', 'VID_2E8A')   # Arduino Micro, Pico
    AimTrak       = @('VID_D209&PID_1601')
    OpenFIRE      = @('VID_2E8A&PID_000A')
    RetroShooter  = @('VID_0079&PID_0011')
}

# Process names that interfere with cabinet operation.
$script:HealthBadProcesses = @(
    'EpicGamesLauncher', 'JoyToKey', 'AnyDesk', 'TeamViewer',
    'GOG Galaxy', 'Battle.net', 'UbisoftConnect', 'Razer Synapse'
)

# Process names that are only flagged when they ALSO consume input devices (context-sensitive).
# Steam is the prime example: running Steam is normal; only Steam Input hijacking XInput is bad.
$script:HealthContextProcesses = @('Steam', 'Discord')

# Critical storage paths (local + UNC). Configurable per cabinet via state.
$script:HealthStoragePaths = @()

function Get-KitHealthStorageDefaults {
    [CmdletBinding()]
    param([string] $RetroBatRoot = '')
    $paths = [ordered]@{}
    # The caller resolves the root from the kit state (the API does); no guessed drive letters,
    # they would be wrong on most cabinets and the release check refuses them.
    if ($RetroBatRoot) { $paths['RetroBat'] = $RetroBatRoot }
    if ($env:ProgramData) { $paths['PinballY'] = Join-Path $env:ProgramData 'PinballY' }
    $paths['KitRoot'] = $script:KitRoot
    $paths
}

function Get-SystemHealth {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [string[]] $ExtraStoragePaths = @(),
        [string[]] $ExtraBadProcesses = @()
    )
    $sw = [Diagnostics.Stopwatch]::StartNew()

    $health = [ordered]@{
        Timestamp     = (Get-Date -Format 'o')
        Status        = 'OK'
        Hardware      = [ordered]@{}
        Storage       = [ordered]@{}
        Interference  = [ordered]@{ ActiveBlockers = @(); ContextBlockers = @() }
        ExecutionTime = 0
        Vitals        = [ordered]@{}
        Warnings      = @()
    }

    # --- 1. Hardware Matrix (USB VID via CIM, no deep scan) ---
    try {
        $usb = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop |
            Where-Object { $_.DeviceID -like '*USB*' -or $_.PNPClass -in 'HIDClass', 'Ports', 'MEDIA' }
        $deviceIds = ($usb.DeviceID -join ' ') + ' ' + ($usb.Name -join ' ')
        $deviceIdsUpper = $deviceIds.ToUpperInvariant()

        $dolphin = $false
        foreach ($vid in $script:HealthHardwareVids.DolphinBar) {
            if ($deviceIdsUpper -match [regex]::Escape($vid.ToUpperInvariant())) { $dolphin = $true; break }
        }
        $health.Hardware.DolphinBar = $dolphin

        $arcade = $false
        foreach ($vid in $script:HealthHardwareVids.ArcadeEncoder) {
            if ($deviceIdsUpper -match [regex]::Escape($vid.ToUpperInvariant())) { $arcade = $true; break }
        }
        $health.Hardware.ArcadeEncoder = $arcade

        foreach ($gun in 'SindenLightgun', 'Gun4IR', 'AimTrak', 'OpenFIRE', 'RetroShooter') {
            $found = $false
            foreach ($vid in $script:HealthHardwareVids[$gun]) {
                if ($deviceIdsUpper -match [regex]::Escape($vid.ToUpperInvariant())) { $found = $true; break }
            }
            $health.Hardware[$gun] = $found
        }
        $health.Hardware.XboxControllers = ($usb | Where-Object { $_.Name -match 'Xbox|XINPUT|X-Box' }).Count
        $health.Hardware.TotalHidDevices = ($usb | Where-Object { $_.PNPClass -eq 'HIDClass' }).Count
    } catch {
        $health.Hardware.Error = $_.Exception.Message
        $health.Status = 'Degraded'
    }

    # --- 2. Storage & Network (Test-Path with ping pre-flight for UNC) ---
    $paths = Get-KitHealthStorageDefaults -RetroBatRoot $RetroBatRoot
    if ($ExtraStoragePaths) {
        for ($j = 0; $j -lt $ExtraStoragePaths.Count; $j++) {
            $paths["Extra_$j"] = $ExtraStoragePaths[$j]
        }
    }
    foreach ($key in $paths.Keys) {
        $path = $paths[$key]
        # UNC paths: pre-flight ping with .NET (PS 5.1 compatible — Test-Connection -TimeoutSeconds is PS7 only)
        if ($path -match '^\\\\') {
            $server = ($path -split '\\')[2]
            try {
                $ping = New-Object System.Net.NetworkInformation.Ping
                $reply = $ping.Send($server, 1000)
                $pingOk = ($reply.Status -eq 'Success')
            } catch { $pingOk = $false }
            if (-not $pingOk) {
                $health.Storage[$key] = $false
                $health.Status = 'Degraded'
                continue
            }
        }
        try {
            $exists = Test-Path -LiteralPath $path -ErrorAction Stop
            $health.Storage[$key] = $exists
            if (-not $exists) { $health.Status = 'Degraded' }
        } catch {
            $health.Storage[$key] = $false
            $health.Status = 'Degraded'
        }
    }

    # --- 3. Interference (context-sensitive bad actor detection) ---
    $allBad = $script:HealthBadProcesses + $ExtraBadProcesses
    try {
        $running = Get-Process -Name $allBad -ErrorAction SilentlyContinue
        if ($running) {
            $health.Interference.ActiveBlockers = @($running.Name | Select-Object -Unique)
            $health.Status = 'Degraded'
        }
    } catch {}

    # Context-sensitive: Steam/Discord only flagged as warnings (they may or may not interfere).
    # SteamInput is not a separate process — it runs inside steam.exe. We report Steam as a
    # warning if it's running, but don't degrade the health status for it.
    try {
        $contextRunning = Get-Process -Name $script:HealthContextProcesses -ErrorAction SilentlyContinue
        if ($contextRunning) {
            $blocked = @()
            foreach ($proc in $contextRunning) {
                if ($proc.Name -eq 'Steam') {
                    $blocked += 'Steam (may hijack controllers via Steam Input — verify in Steam Settings > Controller)'
                } elseif ($proc.Name -eq 'Discord') {
                    $discordOverlay = Get-Process -Name 'DiscordOverlay' -ErrorAction SilentlyContinue
                    if ($discordOverlay) { $blocked += 'Discord (Overlay active — may steal input focus)' }
                }
            }
            if ($blocked.Count) {
                $health.Interference.ContextBlockers = $blocked
                # Warning, not Degraded — Steam is usually fine
                $health.Warnings += $blocked
            }
        }
    } catch {}

    # --- 4. Quick vital signs ---
    $health.Vitals = [ordered]@{
        Uptime          = [math]::Round(((Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime).TotalHours, 1)
        MemoryFreeMB    = [math]::Round((Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory / 1024, 0)
        PrimaryDriveGB  = [math]::Round(((Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'").FreeSpace) / 1GB, 1)
        CpuLoadPercent  = [math]::Round((Get-CimInstance Win32_Processor | Measure-Object LoadPercentage -Average).Average, 0)
    }

    $sw.Stop()
    $health.ExecutionTime = "$($sw.ElapsedMilliseconds)ms"

    [pscustomobject]$health
}