# AutoDetect.ps1 -- Natural language to kit configuration.
# The user describes what they want in plain words; the kit derives:
# - target modules (emulators, lightgun, controllers, …)
# - setup mode (Easy / Custom / NerdExtreme)
# - recommended preset
# - confidence score per match
#
# This is NOT an LLM call -- it's a fast keyword/scoring engine that runs locally.
# The agent (or MCP client) sends the description as a string, gets back structured config.

# --- Keyword catalog: module triggers ------------------------------------------------
$script:AutoDetectModuleKeywords = [ordered]@{
    'emulators'     = @('emulator', 'mame', 'retroarch', 'arcade', 'spielautomat', 'arcade cabinet', 'crt',
                        'tekno', 'teknoparrot', 'model2', 'supermodel', 'demul', 'dolphin', 'cemu', 'rpcs3',
                        'xemu', 'duckstation', 'pcsx2', 'future pinball', 'visual pinball', 'pinball fx3',
                        'pinball arcade', 'rom', 'roms', 'game', 'spiele', 'retro', 'retro gaming', 'gaming')
    'lightgun'      = @('lightgun', 'gun', 'sinden', 'gun4ir', 'aimtrak', 'retro shooter', 'openfire',
                        'wiimote', 'shooter', 'light gun', 'schießen', 'gun game', 'shooting', 'recoil',
                        'rückstoß', 'arcade gun', 'ir sensor', 'dolphinbar')
    'controllers'   = @('controller', 'gamepad', 'joystick', 'arcade stick', 'fight stick', 'racing wheel',
                        'lenkrad', 'pedal', 'ffb', 'force feedback', 'hori', 'mad catz', 'logitech',
                        'thrustmaster', 'gp2040', 'brook', 'zero delay', 'ipac', 'i-pac', 'deadzone',
                        'socd', 'button', 'knopf', 'encoder', 'pad', 'stick', 'xinput', 'dinput')
    'displays'      = @('display', 'monitor', 'bildschirm', 'screen', 'marquee', 'bezel', 'bezel',
                        'bezels', 'hmdi', 'dp', 'displayport', 'vga', 'resolution', 'auflösung',
                        '1080p', '1440p', '4k', 'fullscreen', 'fps', 'refresh', 'hz')
    'outputs'       = @('output', 'rumble', 'solenoid', 'rückmeldung', 'haptik', 'haptic', 'ffb blaster',
                        'mamehooker', 'qmamehook', 'hook of the reaper', 'gunmote', 'feedback', 'vibration',
                        'motor', 'solenoid')
    'enhancements'  = @('shader', 'shader', 'crt', 'scanline', 'bezel', 'audio', 'sound', 'sound',
                        'upscaling', 'hochskalieren', 'filter', 'lottes', 'royale', 'megabezel',
                        'retroarch', 'overlay', 'reshade', 'grafik', 'graphics', 'upscaling')
    'library'       = @('library', 'bibliothek', 'rom', 'roms', 'scan', 'scannen', 'box art', 'boxart',
                        'cover', 'metadata', 'metadaten', 'playlist', 'import', 'export', 'katalog',
                        'genre', 'system', 'platform', 'plattform')
    'frontends'     = @('frontend', 'retrobat', 'pinbally', 'playnite', 'launchbox', 'pinup',
                        'emulationstation', 'theme', 'themes', 'menü', 'menu', 'oberfläche', 'ui',
                        'interface', 'launcher', 'big box', 'attract mode')
    'pinball'       = @('pinball', 'flipper', 'pinbally', 'pinballx', 'visual pinball', 'future pinball',
                        'vpx', 'vpinball', 'b2s', 'backglass', 'dmd', 'pinup', 'popper', 'tisch',
                        'table', 'tables', 'plunger', 'nudge', 'tilt', 'flipper')
}

# --- Keyword catalog: mode triggers ---------------------------------------------------
$script:AutoDetectModeKeywords = [ordered]@{
    'Easy'         = @('einfach', 'easy', 'autopilot', 'automatisch', 'automatic', 'keine fragen',
                        'no questions', 'automatik', 'ein klick', 'one click', 'schnell', 'quick',
                        'fertig', 'ready', 'out of the box', 'plug and play', 'standard')
    'Custom'       = @('custom', 'angepasst', 'customized', 'mittel', 'medium', 'normal', 'standard',
                        'auswahl', 'choice', 'optionen', 'options', 'wählen', 'choose', 'assistent',
                        'assistant', 'geführt', 'guided', 'empfehlung', 'recommendation')
    'NerdExtreme'  = @('nerd', 'extreme', 'expert', 'experte', 'deep dive', 'tief', 'deep',
                        'alle', 'all', 'jede', 'every', 'schraube', 'tinker', 'schrauben',
                        'basteln', 'raw', 'nackt', 'config', 'ini', 'alles', 'komplett', 'voll')
}

# --- Keyword catalog: preset hints ----------------------------------------------------
$script:AutoDetectPresetHints = @(
    @{ Keywords = @('arcade', 'crt', 'mame', 'retro'); Preset = 'easy_arcade' }
    @{ Keywords = @('racing', 'rennspiel', 'wheel', 'lenkrad', 'ffb'); Preset = 'custom_racing' }
    @{ Keywords = @('lightgun', 'gun', 'shooter', 'sinden', 'recoil'); Preset = 'nerd_lightgun' }
    @{ Keywords = @('balanced', 'ausgewogen', 'general', 'allgemein', 'alles', 'complete', 'komplett'); Preset = 'balanced_cabinet' }
)

# --- Detection engine ----------------------------------------------------------------

# Convert a natural-language description into a structured kit configuration.
function Get-KitAutoDetect {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [string] $Description,
        # Minimum keyword matches before a module is considered triggered.
        [int] $MinModuleMatches = 2,
        # Minimum confidence (0-100) for a match to be included.
        [int] $MinConfidence = 25
    )
    begin { $allResults = @() }
    process {
        $text = $Description.ToLowerInvariant()
        $words = $text -split '\s+' | Where-Object { $_.Length -gt 1 }

        # Module detection
        $modules = [ordered]@{}
        foreach ($mod in $script:AutoDetectModuleKeywords.Keys) {
            $score = 0; $hits = @()
            foreach ($kw in $script:AutoDetectModuleKeywords[$mod]) {
                if ($text -match [regex]::Escape($kw)) {
                    $score += [math]::Min($kw.Length * 10, 100)
                    $hits += $kw
                }
            }
            # Bonus for word-level matches (more precise)
            foreach ($w in $words) {
                foreach ($kw in $script:AutoDetectModuleKeywords[$mod]) {
                    if ($w -eq $kw) { $score += 30 }
                }
            }
            if ($score -gt 0) {
                $confidence = [math]::Min(100, [math]::Round($score / ($script:AutoDetectModuleKeywords[$mod].Count + 10) * 100, 0))
                if ($confidence -ge $MinConfidence) {
                    $modules[$mod] = [pscustomobject]@{
                        Module     = $mod
                        Confidence = $confidence
                        Hits       = $hits | Select-Object -Unique
                    }
                }
            }
        }

        # Mode detection
        $mode = 'Custom'; $modeScore = 0
        foreach ($m in $script:AutoDetectModeKeywords.Keys) {
            $score = 0
            foreach ($kw in $script:AutoDetectModeKeywords[$m]) {
                if ($text -match [regex]::Escape($kw)) { $score += $kw.Length * 8 }
            }
            if ($score -gt $modeScore) { $mode = $m; $modeScore = $score }
        }

        # Preset hint
        $preset = ''
        $presetScore = 0
        foreach ($ph in $script:AutoDetectPresetHints) {
            $score = 0
            foreach ($kw in $ph.Keywords) {
                if ($text -match [regex]::Escape($kw)) { $score += $kw.Length * 6 }
            }
            if ($score -gt $presetScore) { $preset = $ph.Preset; $presetScore = $score }
        }

        $result = [pscustomobject]@{
            Description    = $Description
            Modules        = @($modules.Values | Sort-Object Confidence -Descending)
            PrimaryModule  = if ($modules.Count) { ($modules.Values | Sort-Object Confidence -Descending | Select-Object -First 1).Module } else { '' }
            SetupMode      = $mode
            Preset         = $preset
            Context        = (Export-KitSetupContext | ConvertFrom-Json)
        }
        $allResults += $result
        $result
    }
    end { $allResults }
}

# Fast auto-detect and apply: set mode + suggest preset in one call.
function Invoke-KitAutoDetect {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Description,
        [switch] $Apply
    )
    $detection = Get-KitAutoDetect -Description $Description
    if (-not $PSCmdlet.ShouldProcess("auto-detect from: $Description", 'apply')) {
        return [pscustomobject]@{ Detection = $detection; Applied = $false }
    }
    if ($detection.SetupMode) { Set-KitSetupMode -Mode $detection.SetupMode }
    if ($detection.Preset) {
        try {
            $null = Invoke-KitPreset -Name $detection.Preset
        } catch {
            Write-KitLog "Preset '$($detection.Preset)' not applied: $($_.Exception.Message)" -Level Warn
        }
    }
    [pscustomobject]@{
        Detection = $detection
        Applied   = $true
        Mode      = (Get-KitSetupMode)
    }
}