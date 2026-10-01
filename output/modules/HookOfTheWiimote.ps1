# HookOfTheWiimote.ps1 -- Wiimote-as-Lightgun output subsystem.
# Bridges the gap: what Sinden/Gun4IR get via Hook of the Reaper, Wiimotes get via this.
#
# Architecture (CONCEPT_hook-of-the-wiimote.md):
#   TeknoParrot/FFBBlaster --TCP 8002--┐
#   DemulShooter --WM_COPYDATA--------┼--> recoil-stretch.py --TCP 8000--> Gunmote ArcadeHook --> Wiimote
#   MAME (output windows) --WM_COPYDATA┘     (relay: translate + pulse-extend + life-LEDs)
#
# Three principles:
#   1. Stand on shoulders (uses existing: Gunmote, FFBBlaster, DemulShooter, MAME)
#   2. Simple for beginners, honest for tinkerers (checkmarks, plain-text INIs, backups)
#   3. Measure, don't guess (every claim verified on the cabinet)

# --- hotw.json schema ------------------------------------------------------------
# Per-game selection and effect settings stored in %USERPROFILE%\RetroCabinet\hotw.json

function Get-HotwSettingsPath {
    Join-Path $env:USERPROFILE 'RetroCabinet\hotw.json'
}

function Get-HotwSettings {
    $path = Get-HotwSettingsPath
    if (-not (Test-Path -LiteralPath $path)) {
        return [ordered]@{
            version     = 1
            selection   = [ordered]@{}
            effects     = [ordered]@{ HoldMs = 150; RumbleOnShot = $true; RumbleOnReload = $true; RumbleOnDamage = $true; LedMode = 'Life' }
            gunmoteInis = @()
            blockedGames = @()
        }
    }
    try {
        Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        Write-KitLog "hotw.json corrupted, using defaults: $($_.Exception.Message)" -Level Warn
        [ordered]@{ version = 1; selection = [ordered]@{}; effects = [ordered]@{ HoldMs = 150; RumbleOnShot = $true; RumbleOnReload = $true; RumbleOnDamage = $true; LedMode = 'Life' }; gunmoteInis = @(); blockedGames = @() }
    }
}

function Set-HotwSettings {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] $Settings)
    if (-not $PSCmdlet.ShouldProcess('hotw.json', 'save settings')) { return }
    $dir = Split-Path (Get-HotwSettingsPath) -Parent
    if (-not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
    $Settings | ConvertTo-Json -Depth 6 | Out-File -LiteralPath (Get-HotwSettingsPath) -Encoding UTF8 -NoNewline
}

# --- Detection ---------------------------------------------------------------

function Get-HookOfTheWiimoteInfo {
    [CmdletBinding()]
    param([string] $RetroBatRoot = (Get-OutputRetroBatRoot))

    $h = [ordered]@{
        Ok                 = $true
        WiimoteDetected    = $false
        GunmoteInstalled   = $false
        GunmoteRunning     = $false
        ViGEmBusInstalled  = $false
        PythonInstalled    = $false
        RelayInstalled     = $false
        TeknoParrotFound   = $false
        DemulShooterFound  = $false
        MameOutputWindows  = $false
        PortConflicts      = @()
        DoubleConsumers    = @()
        Warnings           = @()
        Recommendation     = ''
    }

    # Gunmote detection
    try {
        $gp = Get-Process -Name 'Gunmote' -ErrorAction SilentlyContinue
        $h.GunmoteRunning = [bool]$gp
    } catch {}
    $gunsFolder = 'C:\Program Files\Gunmote'
    if (Test-Path "$gunsFolder\ArcadeOutputs" -PathType Container) { $h.GunmoteInstalled = $true }
    if (Test-Path "$gunsFolder\Gunmote.dll" -PathType Leaf) { $h.GunmoteInstalled = $true }

    # Wiimote detection: Bluetooth or DolphinBar
    try {
        $usb = Get-CimInstance Win32_PnPEntity -ErrorAction Stop | Where-Object { $_.DeviceID -like '*USB*' }
        $ids = ($usb.DeviceID -join ' ').ToUpperInvariant()
        if ($ids -match 'VID_057E' -or $ids -match 'RVL-CNT-01') {
            $h.WiimoteDetected = $true
        }
        if ($ids -match 'VID_0079&PID_18') { $h.WiimoteDetected = $true }  # DolphinBar Wiimote
    } catch {}

    # ViGEmBus
    try { $h.ViGEmBusInstalled = [bool](Get-Service 'ViGEmBus' -ErrorAction SilentlyContinue) } catch {}

    # Python
    try { $null = & py -3 --version 2>&1; $h.PythonInstalled = $true } catch {}

    # Recoil relay
    $relayPath = if ($RetroBatRoot) { Join-Path $RetroBatRoot 'tools\HookOfTheWiimote\recoil-stretch.py' } else { '' }
    $h.RelayInstalled = [bool]$relayPath -and (Test-Path -LiteralPath $relayPath -PathType Leaf)

    # TeknoParrot
    if ($RetroBatRoot) {
        $tpDir = if ($RetroBatRoot) { Join-Path $RetroBatRoot 'emulators\teknoparrot' } else { '' }
        $h.TeknoParrotFound = Test-Path $tpDir -PathType Container
    }

    # DemulShooter
    $dsPath = if ($RetroBatRoot) { Join-Path $RetroBatRoot 'emulators\demulshooter\DemulShooter.exe' } else { '' }
    $h.DemulShooterFound = [bool]$dsPath -and (Test-Path -LiteralPath $dsPath -PathType Leaf)

    # MAME output mode
    if ($h.GunmoteInstalled -and $RetroBatRoot) {
        $mameIni = if ($RetroBatRoot) { Join-Path $RetroBatRoot 'emulators\mame\mame.ini' } else { '' }
        if (Test-Path $mameIni) {
            $ini = ConvertFrom-Ini -Path $mameIni
            $h.MameOutputWindows = ($ini.ContainsKey('') -and $ini[''].ContainsKey('output') -and $ini['']['output'] -eq 'windows')
        }
    }

    # Port conflicts: TCP 8000
    try {
        $port8000 = @(Get-NetTCPConnection -LocalPort 8000 -State Listen -ErrorAction SilentlyContinue)
        if ($port8000.Count -and -not $h.GunmoteRunning) {
            $others = @($port8000 | ForEach-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name } | Select-Object -Unique)
            if ($others -contains 'Hook of the Reaper') {
                $h.PortConflicts += 'TCP 8000: Hook of the Reaper uses port 8000. Hook of the Wiimote relay must use a different port, or HotR must be reconfigured.'
            } elseif ($others.Count) {
                $h.PortConflicts += "TCP 8000: in use by $($others -join ', '). Gunmote ArcadeHook needs this port."
            }
        }
    } catch {}

    # Double consumers
    try {
        if ((Get-Process -Name 'MAMEHooker', 'Mamehooker51' -ErrorAction SilentlyContinue) -and $h.GunmoteRunning) {
            $h.DoubleConsumers += 'MAMEHooker active alongside Gunmote: Wiimote may rumble twice per shot.'
        }
    } catch {}

    # Recommendation
    if (-not $h.WiimoteDetected) {
        $h.Recommendation = 'No Wiimote detected. Connect a Wiimote via Bluetooth (settings) or DolphinBar, then run calibration in Gunmote.'
    } elseif (-not $h.GunmoteInstalled) {
        $h.Recommendation = 'Gunmote not installed. Download from https://gunmotelabs.com/ -- the kit never downloads.'
    } elseif (-not $h.RelayInstalled) {
        $h.Recommendation = 'Recoil relay not installed. Run Install-HookOfTheWiimote to set up the relay and Windows task.'
    } else {
        $h.Recommendation = 'Hook of the Wiimote is set up. Use hotw.json to select games and adjust effects.'
    }

    if ($h.PortConflicts.Count -or $h.DoubleConsumers.Count) { $h.Ok = $false }

    [pscustomobject]$h
}

# --- Setup pipeline -------------------------------------------------------------

function Install-HookOfTheWiimote {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string] $RetroBatRoot = (Get-OutputRetroBatRoot),
        [switch] $Approved
    )
    # A write needs a known root; without one it would build relative paths into the current folder.
    if (-not $RetroBatRoot) { throw 'RetroBat folder unknown: pass -RetroBatRoot or run the lightgun detect step first.' }
    $info = Get-HookOfTheWiimoteInfo -RetroBatRoot $RetroBatRoot
    if (-not $PSCmdlet.ShouldProcess('Hook of the Wiimote', 'install')) {
        return [pscustomobject]@{ Info = $info; Applied = $false; Changes = @() }
    }

    $changes = @()

    # 1. Install recoil relay
    $relayDir = if ($RetroBatRoot) { Join-Path $RetroBatRoot 'tools\HookOfTheWiimote' } else { '' }
    $relayPath = Join-Path $relayDir 'recoil-stretch.py'
    $sourceRelay = Join-Path $script:KitRoot 'output\tools\recoil-stretch.py'
    if (-not (Test-Path $relayPath) -and (Test-Path $sourceRelay)) {
        $null = New-Item -ItemType Directory -Path $relayDir -Force
        Copy-Item -LiteralPath $sourceRelay -Destination $relayPath
        $changes += 'Recoil relay installed'
    }

    # 2. Register Windows task for relay (pythonw, hidden, auto-restart)
    $taskName = 'HookOfTheWiimote Relay'
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if (-not $existing) {
        try {
            $action = New-ScheduledTaskAction -Execute 'pythonw' -Argument "`"$relayPath`"" -WorkingDirectory $relayDir
            $trigger = New-ScheduledTaskTrigger -AtLogon
            $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -Hidden
            $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
            Start-ScheduledTask -TaskName $taskName
            $changes += 'Windows task registered (auto-start, 3 restarts)'
        } catch {
            Write-KitLog "Cannot register task: $($_.Exception.Message)" -Level Warn
        }
    }

    # 3. Configure FFBBlaster (TeknoParrot) -- OutputsSystem=1, NetOutputsTCPPort=8002
    $ffbIni = if ($RetroBatRoot) { Join-Path $RetroBatRoot 'emulators\teknoparrot\FFBBlaster.ini' } else { '' }
    if (Test-Path $ffbIni) {
        $ffb = ConvertFrom-Ini -Path $ffbIni
        $modified = $false
        if (-not $ffb.ContainsKey('') -or -not $ffb[''].ContainsKey('OutputsSystem') -or $ffb['']['OutputsSystem'] -ne '1') {
            if (-not $ffb.ContainsKey('')) { $ffb[''] = @{} }
            $ffb['']['OutputsSystem'] = '1'; $modified = $true
        }
        if (-not $ffb.ContainsKey('') -or -not $ffb[''].ContainsKey('NetOutputsTCPPort') -or $ffb['']['NetOutputsTCPPort'] -ne '8002') {
            if (-not $ffb.ContainsKey('')) { $ffb[''] = @{} }
            $ffb['']['NetOutputsTCPPort'] = '8002'; $modified = $true
        }
        if ($modified -and $Approved) {
            ConvertTo-Ini -IniData $ffb -Path $ffbIni
            $changes += 'FFBBlaster configured (OutputsSystem=1, TCP=8002)'
        }
    }

    # 4. Configure DemulShooter -- Windows Messages output
    $dsIni = if ($RetroBatRoot) { Join-Path $RetroBatRoot 'emulators\demulshooter\config.ini' } else { '' }
    if (Test-Path $dsIni) {
        $ds = ConvertFrom-Ini -Path $dsIni
        $modified = $false
        foreach ($kv in @{ OutputEnabled = 'True'; WM_OutputsEnabled = 'True'; Net_OutputsEnabled = 'False' }) {
            if (-not $ds.ContainsKey('') -or -not $ds[''].ContainsKey($kv.Key) -or $ds[''][$kv.Key] -ne $kv.Value) {
                if (-not $ds.ContainsKey('')) { $ds[''] = @{} }
                $ds[''][$kv.Key] = $kv.Value; $modified = $true
            }
        }
        if ($modified -and $Approved) {
            ConvertTo-Ini -IniData $ds -Path $dsIni
            $changes += 'DemulShooter configured (Windows Messages output)'
        }
    }

    # 5. MAME: output = windows
    $mameIni = if ($RetroBatRoot) { Join-Path $RetroBatRoot 'emulators\mame\mame.ini' } else { '' }
    if (Test-Path $mameIni) {
        $mame = ConvertFrom-Ini -Path $mameIni
        if (-not $mame.ContainsKey('') -or -not $mame[''].ContainsKey('output') -or $mame['']['output'] -ne 'windows') {
            if (-not $mame.ContainsKey('')) { $mame[''] = @{} }
            $mame['']['output'] = 'windows'
            if ($Approved) {
                ConvertTo-Ini -IniData $mame -Path $mameIni
                $changes += 'MAME output set to windows'
            }
        }
    }

    # 6. Initialize hotw.json if not present
    $hotwPath = Get-HotwSettingsPath
    if (-not (Test-Path $hotwPath)) {
        $default = Get-HotwSettings
        Set-HotwSettings -Settings $default
        $changes += 'hotw.json initialized with defaults'
    }

    [pscustomobject]@{
        Info    = $info
        Applied = $Approved
        Changes = $changes
    }
}

# Gunmote INI writer: writes unified INIs per source (TeknoParrot FFB.ini, DemulShooter.ini)
# to C:\Program Files\Gunmote\ArcadeOutputs\. Requires admin (Gunmote is in Program Files).
function Write-HotwGunmoteIni {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $IniName,     # e.g. "TeknoParrot FFB" or "DemulShooter"
        [Parameter(Mandatory)] [hashtable] $Outputs,  # @{ 'P1_Shot' = 'wii 1 5'; 'P1_Damage' = 'wii 1 5'; ... }
        [string] $GunmoteDir = 'C:\Program Files\Gunmote\ArcadeOutputs'
    )
    if (-not $PSCmdlet.ShouldProcess("$GunmoteDir\$IniName.ini", 'write Gunmote INI')) { return }
    
    $path = Join-Path $GunmoteDir "$IniName.ini"
    $lines = @()
    foreach ($key in $Outputs.Keys) { $lines += "$key = $($Outputs[$key])" }
    
    # Backup existing
    if (Test-Path -LiteralPath $path) {
        Copy-Item -LiteralPath $path -Destination "$path.bak_$(Get-Date -Format 'yyyyMMddHHmmss')" -Force
    }
    
    # Sort lines for readability, with comment header
    $content = "# Auto-generated by Hook of the Wiimote -- $(Get-Date -Format 'yyyy-MM-dd HH:mm')`n" + ($lines | Sort-Object | Out-String)
    [IO.File]::WriteAllText($path, $content, [Text.UTF8Encoding]::new($false))
    Write-KitLog "Gunmote INI written: $IniName ($($Outputs.Count) outputs)"
}