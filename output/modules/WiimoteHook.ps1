# WiimoteHook.ps1 -- Wiimote-as-Lightgun output hook configuration.
# When the Wiimote is used as a lightgun (via DolphinBar + Gunmote), the output chain
# must be configured so rumble goes to the Wiimote motor, not a solenoid.
#
# The chain: MAME/Emulator -> FFBBlaster/DemulShooter -> Gunmote (TCP 8000) -> Wiimote
# The recoil-stretch.py relay translates multiple sources into Gunmote's single-stream format.
#
# Safety rules:
# 1. Wiimote rumble threshold must be reasonable (not 100% continuous).
# 2. Only ONE output path may drive the Wiimote motor at a time.
# 3. Hook of the Reaper solenoid guard still applies if HoTR is also present.

function Get-KitWiimoteHookInfo {
    [CmdletBinding()]
    param([string] $RetroBatRoot = (Get-OutputRetroBatRoot))
    
    $info = [ordered]@{
        WiimoteDetected    = $false
        DolphinBarDetected = $false
        GunmoteDetected    = $false
        RecoilRelayPresent = $false
        DoubleConsumers    = @()
        RumbleSafe         = $true
        Warnings           = @()
        Recommendation     = ''
    }

    # 1. DolphinBar detection (VID_057E = Nintendo/Mayflash)
    try {
        $usb = Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop |
            Where-Object { $_.DeviceID -like '*USB*' }
        $ids = ($usb.DeviceID -join ' ').ToUpperInvariant()
        if ($ids -match 'VID_057E') {
            $info.DolphinBarDetected = $true
            # Wiimote is connected when a Bluetooth HID device with Nintendo VID is present
            # and there are exactly 1-4 HID devices from VID_057E (Wiimotes pair as separate HID nodes)
            $nintendoDevices = @($usb | Where-Object { $_.DeviceID -match 'VID_057E' }).Count
            $info.WiimoteDetected = ($nintendoDevices -ge 2)  # DolphinBar itself + at least 1 Wiimote
        }
    } catch {
        $info.Warnings += "DolphinBar check failed: $($_.Exception.Message)"
    }

    # 2. Gunmote detection (process + ArcadeOutputs folder)
    try {
        $gunmoteProcess = Get-Process -Name 'Gunmote' -ErrorAction SilentlyContinue
        $gunmoteFolder = Test-Path 'C:\Program Files\Gunmote\ArcadeOutputs' -PathType Container
        if ($gunmoteProcess -or $gunmoteFolder) {
            $info.GunmoteDetected = $true
        }
    } catch {
        # Get-Process with unknown name throws -- fine
    }

    # 3. Recoil stretch relay (recoil-stretch.py in output/tools/)
    $relayPath = if ($RetroBatRoot) { Join-Path $RetroBatRoot 'tools\output\recoil-stretch.py' } else { '' }
    $info.RecoilRelayPresent = [bool]$relayPath -and (Test-Path -LiteralPath $relayPath -PathType Leaf)

    # 4. Double-consumer check: Gunmote + HookOfTheReaper both active
    try {
        $hotrProcess = Get-Process -Name 'Hook of the Reaper', 'HookOfTheReaper', 'HOTR' -ErrorAction SilentlyContinue
        if ($info.GunmoteDetected -and $hotrProcess) {
            $info.DoubleConsumers += [pscustomobject]@{
                Consumers = @('Gunmote', 'HookOfTheReaper')
                Issue     = 'Gunmote drives Wiimote rumble; Hook of the Reaper drives solenoid. Ensure they target different guns.'
            }
        }
    } catch {}

    # 5. Gunmote + MAMEHooker double-consumer
    try {
        $mhProcess = Get-Process -Name 'MameHooker', 'Mamehooker51' -ErrorAction SilentlyContinue
        if ($info.GunmoteDetected -and $mhProcess) {
            $info.DoubleConsumers += [pscustomobject]@{
                Consumers = @('Gunmote', 'MAMEHooker')
                Issue     = 'Both Gunmote and MAMEHooker consume output events. Wiimote may rumble twice per shot.'
            }
        }
    } catch {}

    # 6. Rumble safety: Gunmote settings.json rumble threshold check
    if ($gunmoteFolder) {
        $settingsPath = 'C:\Program Files\Gunmote\settings.json'
        if (Test-Path -LiteralPath $settingsPath) {
            try {
                $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($settings.RumbleStrength) {
                    $strength = [int]$settings.RumbleStrength
                    if ($strength -gt 80) {
                        $info.RumbleSafe = $false
                        $info.Warnings += "Gunmote RumbleStrength is $strength% (>80%). Reduce to prevent motor wear."
                    }
                }
                if ($settings.MotorMaxOnTimeMs) {
                    $maxOn = [int]$settings.MotorMaxOnTimeMs
                    if ($maxOn -gt 500) {
                        $info.RumbleSafe = $false
                        $info.Warnings += "MotorMaxOnTimeMs is $maxOn ms (>500). Wiimote rumble motor is not a solenoid -- keep under 500ms."
                    }
                }
            } catch {
                $info.Warnings += "Cannot read Gunmote settings.json: $($_.Exception.Message)"
            }
        }
    }

    # 7. Recommendation
    if ($info.WiimoteDetected -and $info.GunmoteDetected) {
        if ($info.RecoilRelayPresent) {
            $info.Recommendation = 'Wiimote lightgun output chain is configured. Recoil relay handles FFBBlaster/DemulShooter translation. Verify Gunmote INIs in C:\Program Files\Gunmote\ArcadeOutputs\ match your emulator mame_start names.'
        } else {
            $info.Recommendation = 'Wiimote detected with Gunmote, but recoil-stretch.py relay is missing. Install it so FFBBlaster/DemulShooter output reaches Gunmote via TCP.'
        }
    } elseif ($info.WiimoteDetected -and -not $info.GunmoteDetected) {
        $info.Recommendation = 'Wiimote detected but Gunmote is not installed. Gunmote is required for Wiimote rumble feedback as a lightgun.'
    } elseif (-not $info.WiimoteDetected) {
        $info.Recommendation = 'No Wiimote detected via DolphinBar. If you use a different lightgun (Sinden, Gun4IR, AimTrak), configure its output via outputs.verify_safety.'
    }

    [pscustomobject]$info
}

# Configure the Wiimote lightgun output chain.
# Applies safe defaults for Gunmote and verifies the chain is intact.
function Set-KitWiimoteHook {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot = (Get-OutputRetroBatRoot))
    # A write needs a known root; without one it would build relative paths into the current folder.
    if (-not $RetroBatRoot) { throw 'RetroBat folder unknown: pass -RetroBatRoot or run the lightgun detect step first.' }

    $info = Get-KitWiimoteHookInfo -RetroBatRoot $RetroBatRoot
    if (-not $PSCmdlet.ShouldProcess('Wiimote lightgun output chain', 'configure')) {
        return [pscustomobject]@{ Info = $info; Applied = $false }
    }

    $changes = @()

    # 1. Verify Gunmote rumble thresholds
    if ($info.GunmoteDetected) {
        $settingsPath = 'C:\Program Files\Gunmote\settings.json'
        if (Test-Path -LiteralPath $settingsPath) {
            try {
                $settings = Get-Content $settingsPath -Raw -Encoding UTF8 | ConvertFrom-Json
                $modified = $false
                if (-not $settings.RumbleStrength -or [int]$settings.RumbleStrength -gt 80) {
                    $settings.RumbleStrength = 80
                    $modified = $true
                    $changes += 'RumbleStrength capped at 80%'
                }
                if (-not $settings.MotorMaxOnTimeMs -or [int]$settings.MotorMaxOnTimeMs -gt 500) {
                    $settings.MotorMaxOnTimeMs = 500
                    $modified = $true
                    $changes += 'MotorMaxOnTimeMs capped at 500ms'
                }
                if ($modified) {
                    $backup = "$settingsPath.bak_$(Get-Date -Format 'yyyyMMddHHmmss')"
                    Copy-Item -LiteralPath $settingsPath -Destination $backup
                    $settings | ConvertTo-Json -Depth 5 | Out-File -LiteralPath $settingsPath -Encoding UTF8 -NoNewline
                    Write-KitLog "Gunmote settings updated: $($changes -join ', ')"
                }
            } catch {
                Write-KitLog "Cannot update Gunmote settings: $($_.Exception.Message)" -Level Warn
            }
        }
    }

    # 2. Verify recoil relay is present
    if (-not $info.RecoilRelayPresent -and $info.WiimoteDetected) {
        Write-KitLog 'Recoil-stretch.py relay not found. Without it, FFBBlaster/DemulShooter output cannot reach Gunmote.' -Level Warn
    }

    # 3. Check for double consumers
    if ($info.DoubleConsumers.Count) {
        foreach ($dc in $info.DoubleConsumers) {
            Write-KitLog "Double consumer: $($dc.Issue)" -Level Warn
        }
    }

    [pscustomobject]@{
        Info    = $info
        Applied = $true
        Changes = $changes
    }
}