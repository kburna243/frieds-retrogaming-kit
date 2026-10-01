# SetupContext.ps1 -- Three setup levels across all modules.
# Easy (Autopilot): minimal questions, best-practice presets, silent backups.
# Custom (Assistent): choice + sliders, 3-4 profiles, plain-text summary before execution.
# NerdExtreme (Deep Dive): raw INI keys, file paths, JSON diffs, low-level tools.
#
# The level only changes HOW MUCH is asked and shown. Safety rules apply equally:
# dry-run first, backup before every change, API changes only with -Approved.
#
# Context header (from agent):
# {
#   "tool": "setup.run",
#   "parameters": {
#     "mode": "easy",
#     "target_module": "controllers",
#     "hardware_detected": "LogitechG29",
#     "preset": "arcade_racer"
#   }
# }

$script:SetupMode = 'Custom'      # Default: middle ground
$script:SetupTargetModule = ''    # Which module is being set up
$script:SetupHardwareDetected = @()

# Valid mode identifiers
$script:ValidModes = @('Easy', 'Custom', 'NerdExtreme')

function Get-KitSetupMode {
    [CmdletBinding()]
    param()
    $script:SetupMode
}

function Set-KitSetupMode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Easy', 'Custom', 'NerdExtreme')]
        [string] $Mode
    )
    $script:SetupMode = $Mode
    if ($Mode -eq 'Easy') {
        $script:SetupVerbosity = 'Minimal'
        $script:SetupShowBackups = $false
        $script:SetupConfirmEach = $false
    } elseif ($Mode -eq 'Custom') {
        $script:SetupVerbosity = 'Normal'
        $script:SetupShowBackups = $true
        $script:SetupConfirmEach = $true
    } else {
        $script:SetupVerbosity = 'Full'
        $script:SetupShowBackups = $true
        $script:SetupConfirmEach = $false  # Nerd: no hand-holding, but dry-run still applies
    }
    Write-KitLog "Setup mode: $Mode ($($script:SetupVerbosity) verbosity)"
    $Mode
}

function Test-KitSetupMode {
    [CmdletBinding()]
    param([string] $Mode)
    $Mode -in $script:ValidModes
}

# Parse a context header (JSON from the agent) into the current setup state.
function Import-KitSetupContext {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Json)
    try {
        $ctx = ConvertFrom-Json $Json
        if ($ctx.mode) { Set-KitSetupMode -Mode $ctx.mode }
        if ($ctx.target_module) { $script:SetupTargetModule = $ctx.target_module }
        if ($ctx.hardware_detected) { $script:SetupHardwareDetected = @($ctx.hardware_detected) }
        if ($ctx.preset) { $script:SetupPreset = $ctx.preset }
        [pscustomobject]@{
            Mode             = $script:SetupMode
            TargetModule     = $script:SetupTargetModule
            HardwareDetected = $script:SetupHardwareDetected
            Preset           = $script:SetupPreset
        }
    } catch {
        Write-KitLog "Invalid setup context JSON: $($_.Exception.Message)" -Level Warn
        $null
    }
}

# Export current setup context as JSON (for the agent to inspect).
function Export-KitSetupContext {
    [CmdletBinding()]
    param()
    ConvertTo-Json ([ordered]@{
        tool       = 'setup.run'
        parameters = [ordered]@{
            mode              = $script:SetupMode
            target_module     = $script:SetupTargetModule
            hardware_detected = $script:SetupHardwareDetected
            preset            = $script:SetupPreset
        }
    }) -Compress
}

# Easy-mode: pick best-practice preset for a given module + hardware combination.
function Get-KitEasyPreset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $TargetModule,
        [string] $Hardware = ''
    )
    # Best-practice defaults per module (Easy mode uses these without asking)
    $easyPresets = @{
        'controllers' = @{ preset = 'gamepad_standard'; deadzone = '10'; mapping = 'auto' }
        'displays'    = @{ preset = 'single_monitor'; resolution = '1920x1080'; vsync = '1' }
        'enhancements'= @{ preset = 'Balanced'; shader = 'crt-lottes'; audio = 'stereo-upmix' }
        'emulators'   = @{ preset = 'retroarch_default'; shader = 'crt-lottes' }
        'frontends'   = @{ preset = 'retrobat_default'; theme = 'es-theme-carbon' }
        'library'     = @{ preset = 'scan_all'; media = 'boxart_only' }
        'outputs'     = @{ preset = 'rumble_basic'; solenoid = '200ms' }
    }
    $key = if ($easyPresets.ContainsKey($TargetModule)) { $TargetModule } else { 'emulators' }
    $easyPresets[$key]
}

# Mode-aware Write-KitLog wrapper: suppresses detail in Easy mode.
function Write-KitSetupLog {
    [CmdletBinding()]
    param([string] $Message, [string] $Level = 'Info')
    if ($script:SetupMode -eq 'Easy' -and $Level -eq 'Info') {
        # Easy mode: only show warnings and errors, skip info
        if ($Level -notin 'Warn', 'Error') { return }
    }
    Write-KitLog $Message -Level $Level
}

# Mode-aware approval prompt: skipped in NerdExtreme (trust the expert).
function Request-KitSetupApproval {
    [CmdletBinding()]
    param([string] $Action = 'apply changes')
    if ($script:SetupMode -eq 'NerdExtreme') {
        Write-KitLog "NerdExtreme mode: auto-approving '$Action' (safety rules still apply)" -Level Info
        return $true
    }
    if ($script:SetupMode -eq 'Easy') {
        Write-KitLog "Easy mode: auto-approving '$Action' with best-practice defaults" -Level Info
        return $true
    }
    # Custom mode: ask
    Write-KitLog "Custom mode: awaiting approval for '$Action'" -Level Info
    $false  # In Custom mode, the agent must explicitly approve
}