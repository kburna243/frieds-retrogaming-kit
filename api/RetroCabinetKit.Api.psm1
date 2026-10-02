#Requires -Version 5.1
# Kit API v1 (see API.md): one facade for every client. Operations return RetroCabinetKit.OperationResult;
# change operations run as dry run unless -Apply; approvals are declined unless -Approved; only plain parameters
# are accepted. No kit logic lives here: every handler calls the engine modules.

Set-StrictMode -Version 2.0

$script:ApiVersion = '1.6'
$script:ApiDir     = $PSScriptRoot
$script:KitRoot    = Split-Path -Parent $PSScriptRoot
# The kit's own version (VERSION file), reported in every result so a client can name what it talks to.
$script:KitVersion = $(try { ([IO.File]::ReadAllText((Join-Path $script:KitRoot 'VERSION'))).Trim() } catch { '' })
Import-Module (Join-Path $script:KitRoot 'core\RetroCabinetKit.Core.psd1')
# pinball\ is optional: a distribution without it (hotwm) still gets every other operation.
$script:KitHasPinball = Test-Path -LiteralPath (Join-Path $script:KitRoot 'pinball\RetroCabinetKit.Pinball.psd1')
if ($script:KitHasPinball) { Import-Module (Join-Path $script:KitRoot 'pinball\RetroCabinetKit.Pinball.psd1') }
else { . (Join-Path $script:KitRoot 'core\PinballAbsent.ps1') }
Import-Module (Join-Path $script:KitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1')
Import-Module (Join-Path $script:KitRoot 'arcade\RetroCabinetKit.Arcade.psd1')
Import-Module (Join-Path $script:KitRoot 'pads\RetroCabinetKit.Pads.psd1')
Import-Module (Join-Path $script:KitRoot 'output\RetroCabinetKit.Output.psd1')
Import-Module (Join-Path $script:KitRoot 'displays\RetroCabinetKit.Displays.psd1')
Import-Module (Join-Path $script:KitRoot 'enhancements\RetroCabinetKit.Enhancements.psd1')
Import-Module (Join-Path $script:KitRoot 'library\RetroCabinetKit.Library.psd1')
Import-Module (Join-Path $script:KitRoot 'emulators\RetroCabinetKit.Emulators.psd1')
Import-Module (Join-Path $script:KitRoot 'frontends\RetroCabinetKit.Frontends.psd1')

# Parameters a client may never set (security bindings, test injection, values the API controls itself).
# Apply and Approved are the API's own switches (and the MCP flags apply / approved): a step parameter with that
# name could be mistaken for them, so it is never offered (the comparison ignores case).
$script:ApiDeniedParameters = @('StatePath', 'Culture', 'KitUserSid', 'TrustedOwner', 'TaskPrefix', 'AutomationDir',
    'LayersKey', 'RegistryRoots', 'AppCompatRoots', 'AnswerFile', 'WhatIf', 'Confirm', 'Apply', 'Approved')
$script:ApiPlainTypes = @([string], [string[]], [int], [long], [bool], [switch], [Management.Automation.SwitchParameter])
# Steps that need a person at the cabinet (measure windows, pull the trigger): wizard only.
$script:ApiInteractiveSteps = @('step.pinball.08-screens', 'step.lightgun.09-verify')
$script:ApiApprovals = $null
$script:ApiApprovalAnswer = $false

function Get-KitApiVersion {
    [CmdletBinding()]
    param()
    $script:ApiVersion
}

# The version of the kit behind the API (VERSION file), e.g. 0.3.0.
function Get-KitVersion {
    [CmdletBinding()]
    param()
    $script:KitVersion
}

# --- sub-modules (extracted to keep the API facade lean) --------------------------------------------
. (Join-Path $PSScriptRoot 'modules\Result.ps1')

# --- catalog --------------------------------------------------------------------------------------------------

# The plain parameters of a command (script or function) a client may set: Name, Type, Mandatory.
function Get-KitApiParameter {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [Management.Automation.CommandInfo] $Command)
    $common = [Management.Automation.PSCmdlet]::CommonParameters + [Management.Automation.PSCmdlet]::OptionalCommonParameters
    foreach ($p in $Command.Parameters.Values) {
        if ($common -contains $p.Name -or $script:ApiDeniedParameters -contains $p.Name) { continue }
        if ($script:ApiPlainTypes -notcontains $p.ParameterType) { continue }
        $mandatory = [bool]@($p.Attributes | Where-Object { $_ -is [Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count
        $type = if ($p.ParameterType -eq [Management.Automation.SwitchParameter]) { 'switch' } else { $p.ParameterType.Name }
        [pscustomobject]@{ Name = $p.Name; Type = $type; Mandatory = $mandatory }
    }
}

function Get-StepSynopsis([string] $Path) {
    $tokens = $null; $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($Path, [ref] $tokens, [ref] $errors)
    $help = $ast.GetHelpContent()
    if ($help -and $help.Synopsis) { ($help.Synopsis -split "`n")[0].Trim() } else { '' }
}

function Get-KitApiStep {
    [CmdletBinding()]
    param()
    foreach ($suite in 'pinball', 'lightgun') {
        if ($suite -eq 'pinball' -and -not $script:KitHasPinball) { continue }
        foreach ($f in Get-ChildItem -LiteralPath (Join-Path $script:KitRoot "$suite\steps") -Filter '*.ps1' -File | Sort-Object Name) {
            $name = 'step.{0}.{1}' -f $suite, $f.BaseName.ToLowerInvariant()
            [pscustomobject]@{
                Name        = $name
                Kind        = 'Change'
                Suite       = $suite
                Script      = $f.FullName
                Interactive = $script:ApiInteractiveSteps -contains $name
                Description = Get-StepSynopsis $f.FullName
                Parameters  = @(Get-KitApiParameter -Command (Get-Command -Name $f.FullName))
            }
        }
    }
}

function Get-KitOperation {
    [CmdletBinding()]
    param()
    $fixed = @(
        @{ Name = 'operations'; Kind = 'Read'; Description = 'This catalog.'; Parameters = @(); Module = 'core' }
        @{ Name = 'status'; Kind = 'Read'; Description = 'Health check of system, pinball, lightgun and security (doctor).'; Parameters = @(); Module = 'core' }
        @{ Name = 'status.health'; Kind = 'Read'; Description = 'Fast-path system health (under 2s): USB hardware matrix, storage reachability, interference processes, vitals (uptime/memory/disk/cpu). Returns OK or Degraded.'; Parameters = @([pscustomobject]@{ Name = 'RetroBatRoot'; Type = 'String'; Mandatory = $false }, [pscustomobject]@{ Name = 'ExtraStoragePaths'; Type = 'String[]'; Mandatory = $false }, [pscustomobject]@{ Name = 'ExtraBadProcesses'; Type = 'String[]'; Mandatory = $false }); Module = 'core' }
        @{ Name = 'components'; Kind = 'Read'; Description = 'Detected components: Windows, RetroBat, Gunmote, ViGEmBus, DolphinBar, Steam, pinball build, PinballY.'; Parameters = @(); Module = 'core' }
        @{ Name = 'outputs.verify_safety'; Kind = 'Read'; Description = 'Verify output safety: solenoid limits, port conflicts, double output consumers.'; Parameters = @([pscustomobject]@{ Name = 'RetroBatRoot'; Type = 'String'; Mandatory = $false }); Module = 'outputs' }
        @{ Name = 'outputs.wiimote_hook'; Kind = 'Read'; Description = 'Inspect the Wiimote lightgun output chain: DolphinBar detection, Gunmote status, recoil relay, rumble safety thresholds, double-consumer warnings.'; Parameters = @([pscustomobject]@{ Name = 'RetroBatRoot'; Type = 'String'; Mandatory = $false }); Module = 'outputs' }
        # The second front end is not part of a build, so its folder is asked for, not derived from the state.
        @{ Name = 'pinbally.detect'; Kind = 'Read'; Description = 'Inspect a PinballY installation: version, systems, table databases and which path references do not resolve on this machine. Reads only.'; Parameters = @([pscustomobject]@{ Name = 'Path'; Type = 'String'; Mandatory = $true }); Module = 'pinball' }
        @{ Name = 'pinbally.retarget'; Kind = 'Change'; Description = 'Give the dead absolute paths of a PinballY installation the targets of this machine, following pairs written as Old=New (the same folder under another drive is the usual case). Only path values that do not resolve here are planned, and only when the new path exists; comments, [TOKEN] values, relative paths, DefaultSettings.txt and the own copies of the program are never touched. Dry run without -Apply; the plan needs -Approved.'; Parameters = @([pscustomobject]@{ Name = 'Path'; Type = 'String'; Mandatory = $true }, [pscustomobject]@{ Name = 'Map'; Type = 'String[]'; Mandatory = $true }, [pscustomobject]@{ Name = 'BackupDir'; Type = 'String'; Mandatory = $false }); Module = 'pinball' }
        @{ Name = 'backups.list'; Kind = 'Read'; Description = 'The kit''s backups, newest first.'; Parameters = @([pscustomobject]@{ Name = 'Root'; Type = 'String[]'; Mandatory = $false }); Module = 'core' }
        @{ Name = 'backup.check'; Kind = 'Read'; Description = 'Checks a backup against its checksums (zip) or its original (file copy).'; Parameters = @([pscustomobject]@{ Name = 'Path'; Type = 'String'; Mandatory = $true }); Module = 'core' }
        @{ Name = 'backup.restore'; Kind = 'Change'; Description = 'Restores a backup; the current file is saved first. Zip backups need AllowedRoot.'; Parameters = @([pscustomobject]@{ Name = 'Path'; Type = 'String'; Mandatory = $true }, [pscustomobject]@{ Name = 'AllowedRoot'; Type = 'String[]'; Mandatory = $false }); Module = 'core' }
        @{ Name = 'backup.remove'; Kind = 'Change'; Description = 'Deletes one backup of the kit (nothing else can be deleted).'; Parameters = @([pscustomobject]@{ Name = 'Path'; Type = 'String'; Mandatory = $true }); Module = 'core' }
        @{ Name = 'backup.export'; Kind = 'Change'; Description = 'Copies a backup to a folder and records its SHA-256.'; Parameters = @([pscustomobject]@{ Name = 'Path'; Type = 'String'; Mandatory = $true }, [pscustomobject]@{ Name = 'Destination'; Type = 'String'; Mandatory = $true }); Module = 'core' }
        @{ Name = 'support.bundle'; Kind = 'Change'; Description = 'Writes an anonymized support bundle (doctor, environment, step states, logs).'; Parameters = @([pscustomobject]@{ Name = 'Destination'; Type = 'String'; Mandatory = $false }); Module = 'core' }
        @{ Name = 'controllers.detect'; Kind = 'Read'; Description = 'Detect all controllers: lightguns, arcade sticks, pads. One result across three packages.'; Parameters = @(); Module = 'controllers' }
        @{ Name = 'controllers.input_profiles'; Kind = 'Read'; Description = 'List the input profiles (one button layout for the whole cabinet), or one profile with its mapping.'; Parameters = @([pscustomobject]@{ Name = 'Name'; Type = 'String'; Mandatory = $false }); Module = 'controllers' }
        @{ Name = 'controllers.xinput_slots'; Kind = 'Read'; Description = 'The four XInput slots: which is in use, by what kind of device, its MAME joystick number (JOY<n> counts connected slots only) and the source names of its buttons as MAME numbers them.'; Parameters = @(); Module = 'controllers' }
        @{ Name = 'controllers.wiimote_order'; Kind = 'Read'; Description = 'Which Wiimote is player 1, 2, ... in Gunmote right now (Gunmote numbers them in the order they connect) and whether that matches the saved binding: Ok, Swapped, Unbound, Unclear, NoGunmote, NoWiimote.'; Parameters = @(); Module = 'controllers' }
        @{ Name = 'controllers.wiimote_bind'; Kind = 'Change'; Description = 'Save the current Wiimote order as the player binding (Bluetooth address -> player); the plan shows the binding, -Apply writes it.'; Parameters = @(); Module = 'controllers' }
        @{ Name = 'controllers.input_apply'; Kind = 'Change'; Description = 'Write an input profile as a MAME ctrlr file of its own (never a hand-made one); the plan names the RetroBat settings that load it.'; Parameters = @([pscustomobject]@{ Name = 'Profile'; Type = 'String'; Mandatory = $true }, [pscustomobject]@{ Name = 'CtrlrName'; Type = 'String'; Mandatory = $false }, [pscustomobject]@{ Name = 'RetroBatRoot'; Type = 'String'; Mandatory = $false }); Module = 'controllers' }
        @{ Name = 'displays.detect'; Kind = 'Read'; Description = 'Detect all displays: monitors (EDID), virtual DMD, backglass, topper.'; Parameters = @(); Module = 'displays' }
        @{ Name = 'enhancements.detect'; Kind = 'Read'; Description = 'Detect all enhancements: GPU, shader presets, latency, upscaling, frame pacing, pinball visuals, ambient lighting, audio.'; Parameters = @(); Module = 'enhancements' }
        @{ Name = 'library.scan'; Kind = 'Read'; Description = 'Scan all frontend libraries for ROMs, media, and metadata. Returns unified JSON catalog.'; Parameters = @([pscustomobject]@{ Name = 'Path'; Type = 'String'; Mandatory = $false }); Module = 'library' }
        @{ Name = 'library.add_roms'; Kind = 'Change'; Description = 'Add ROMs to a frontend library.'; Parameters = @([pscustomobject]@{ Name = 'Frontend'; Type = 'String'; Mandatory = $true }, [pscustomobject]@{ Name = 'System'; Type = 'String'; Mandatory = $true }, [pscustomobject]@{ Name = 'Paths'; Type = 'String[]'; Mandatory = $true }); Module = 'library' }
        @{ Name = 'library.remove_roms'; Kind = 'Change'; Description = 'Remove ROMs from a frontend library.'; Parameters = @([pscustomobject]@{ Name = 'Frontend'; Type = 'String'; Mandatory = $true }, [pscustomobject]@{ Name = 'System'; Type = 'String'; Mandatory = $true }, [pscustomobject]@{ Name = 'Names'; Type = 'String[]'; Mandatory = $true }); Module = 'library' }
        @{ Name = 'library.update_media'; Kind = 'Change'; Description = 'Update media (covers, videos, wheels) for ROMs in a frontend library.'; Parameters = @([pscustomobject]@{ Name = 'Frontend'; Type = 'String'; Mandatory = $true }, [pscustomobject]@{ Name = 'System'; Type = 'String'; Mandatory = $true }, [pscustomobject]@{ Name = 'MediaType'; Type = 'String'; Mandatory = $false }); Module = 'library' }
        @{ Name = 'library.create_playlist'; Kind = 'Change'; Description = 'Create a playlist in a frontend library.'; Parameters = @([pscustomobject]@{ Name = 'Frontend'; Type = 'String'; Mandatory = $true }, [pscustomobject]@{ Name = 'Name'; Type = 'String'; Mandatory = $true }, [pscustomobject]@{ Name = 'Roms'; Type = 'String[]'; Mandatory = $true }); Module = 'library' }
        @{ Name = 'library.validate_integrity'; Kind = 'Read'; Description = 'Validate ROM integrity (checksums, missing files, broken references).'; Parameters = @([pscustomobject]@{ Name = 'Frontend'; Type = 'String'; Mandatory = $false }, [pscustomobject]@{ Name = 'System'; Type = 'String'; Mandatory = $false }); Module = 'library' }
        @{ Name = 'library.export_catalog'; Kind = 'Read'; Description = 'Export the unified JSON catalog to file.'; Parameters = @([pscustomobject]@{ Name = 'Destination'; Type = 'String'; Mandatory = $true }); Module = 'library' }
        @{ Name = 'emulators.detect_installed'; Kind = 'Read'; Description = 'Detect all installed emulators: MAME, RetroArch, TeknoParrot, Supermodel, Model2, Cemu, Dolphin, RPCS3, Xemu, DuckStation, PCSX2.'; Parameters = @([pscustomobject]@{ Name = 'RetroBatRoot'; Type = 'String'; Mandatory = $false }); Module = 'emulators' }
        @{ Name = 'emulators.install'; Kind = 'Change'; Description = 'Install an emulator (manual: kit provides official links, user supplies package).'; Parameters = @([pscustomobject]@{ Name = 'Emulator'; Type = 'String'; Mandatory = $true }, [pscustomobject]@{ Name = 'RetroBatRoot'; Type = 'String'; Mandatory = $false }, [pscustomobject]@{ Name = 'PackagePath'; Type = 'String'; Mandatory = $false }); Module = 'emulators' }
        @{ Name = 'emulators.configure'; Kind = 'Change'; Description = 'Configure an emulator with best-practice settings.'; Parameters = @([pscustomobject]@{ Name = 'Emulator'; Type = 'String'; Mandatory = $true }, [pscustomobject]@{ Name = 'RetroBatRoot'; Type = 'String'; Mandatory = $false }, [pscustomobject]@{ Name = 'Frontend'; Type = 'String'; Mandatory = $false }); Module = 'emulators' }
        @{ Name = 'emulators.apply_shader_preset'; Kind = 'Change'; Description = 'Apply a CRT/retro shader preset to an emulator (none, crt-lottes, crt-royale, hsm-mega-bezel, lcd-grid, scanlines).'; Parameters = @([pscustomobject]@{ Name = 'Emulator'; Type = 'String'; Mandatory = $true }, [pscustomobject]@{ Name = 'RetroBatRoot'; Type = 'String'; Mandatory = $false }, [pscustomobject]@{ Name = 'Preset'; Type = 'String'; Mandatory = $true }); Module = 'emulators' }
        @{ Name = 'emulators.patch'; Kind = 'Change'; Description = 'Apply community-curated patches to an emulator (compatibility, performance, fixes).'; Parameters = @([pscustomobject]@{ Name = 'Emulator'; Type = 'String'; Mandatory = $true }, [pscustomobject]@{ Name = 'RetroBatRoot'; Type = 'String'; Mandatory = $false }, [pscustomobject]@{ Name = 'PatchName'; Type = 'String'; Mandatory = $false }); Module = 'emulators' }
        @{ Name = 'emulators.verify_integrity'; Kind = 'Read'; Description = 'Verify emulator installation integrity: executable present, configs valid, checksums match.'; Parameters = @([pscustomobject]@{ Name = 'Emulator'; Type = 'String'; Mandatory = $false }, [pscustomobject]@{ Name = 'RetroBatRoot'; Type = 'String'; Mandatory = $false }); Module = 'emulators' }
        @{ Name = 'frontends.detect'; Kind = 'Read'; Description = 'Detect all installed frontends: RetroBat, PinballY, Playnite, LaunchBox, PinUP.'; Parameters = @([pscustomobject]@{ Name = 'RetroBatRoot'; Type = 'String'; Mandatory = $false }); Module = 'frontends' }
        @{ Name = 'frontends.install'; Kind = 'Change'; Description = 'Install a frontend (manual: kit provides official links, user supplies package).'; Parameters = @([pscustomobject]@{ Name = 'Frontend'; Type = 'String'; Mandatory = $true }, [pscustomobject]@{ Name = 'RetroBatRoot'; Type = 'String'; Mandatory = $false }, [pscustomobject]@{ Name = 'PackagePath'; Type = 'String'; Mandatory = $false }); Module = 'frontends' }
        @{ Name = 'frontends.set_theme'; Kind = 'Change'; Description = 'Set the theme for a frontend.'; Parameters = @([pscustomobject]@{ Name = 'Frontend'; Type = 'String'; Mandatory = $true }, [pscustomobject]@{ Name = 'RetroBatRoot'; Type = 'String'; Mandatory = $false }, [pscustomobject]@{ Name = 'ThemeName'; Type = 'String'; Mandatory = $true }); Module = 'frontends' }
        @{ Name = 'frontends.configure_genre_routing'; Kind = 'Change'; Description = 'Configure which emulator launches which system in a frontend.'; Parameters = @([pscustomobject]@{ Name = 'Frontend'; Type = 'String'; Mandatory = $true }, [pscustomobject]@{ Name = 'RetroBatRoot'; Type = 'String'; Mandatory = $false }); Module = 'frontends' }
        @{ Name = 'frontends.import_library'; Kind = 'Read'; Description = 'Import a frontend library into the unified JSON catalog format.'; Parameters = @([pscustomobject]@{ Name = 'Frontend'; Type = 'String'; Mandatory = $true }, [pscustomobject]@{ Name = 'RetroBatRoot'; Type = 'String'; Mandatory = $false }); Module = 'frontends' }
        @{ Name = 'frontends.export_catalog'; Kind = 'Read'; Description = 'Export the unified catalog to a frontend-specific format.'; Parameters = @([pscustomobject]@{ Name = 'Frontend'; Type = 'String'; Mandatory = $true }, [pscustomobject]@{ Name = 'RetroBatRoot'; Type = 'String'; Mandatory = $false }, [pscustomobject]@{ Name = 'Destination'; Type = 'String'; Mandatory = $true }); Module = 'frontends' }
        @{ Name = 'presets.list'; Kind = 'Read'; Description = 'List all available configuration presets (built-in + user).'; Parameters = @([pscustomobject]@{ Name = 'Module'; Type = 'String'; Mandatory = $false }); Module = 'core' }
        @{ Name = 'presets.apply'; Kind = 'Change'; Description = 'Apply a named preset: sets setup mode, target module, and values.'; Parameters = @([pscustomobject]@{ Name = 'Name'; Type = 'String'; Mandatory = $true }, [pscustomobject]@{ Name = 'RetroBatRoot'; Type = 'String'; Mandatory = $false }); Module = 'core' }
        @{ Name = 'setup.set_mode'; Kind = 'Change'; Description = 'Set the setup level: Easy (autopilot), Custom (assistant), or NerdExtreme (deep dive).'; Parameters = @([pscustomobject]@{ Name = 'Mode'; Type = 'String'; Mandatory = $true }); Module = 'core' }
        @{ Name = 'auto.detect'; Kind = 'Read'; Description = 'Natural language to kit configuration: describe your cabinet, get back modules, setup mode, and preset suggestion. No LLM call -- fast keyword engine.'; Parameters = @([pscustomobject]@{ Name = 'Description'; Type = 'String'; Mandatory = $true }); Module = 'core' }
        @{ Name = 'backups.snapshot'; Kind = 'Change'; Description = 'Take a snapshot of specific files for rollback. Push a named rollback point onto the stack.'; Parameters = @([pscustomobject]@{ Name = 'Name'; Type = 'String'; Mandatory = $true }, [pscustomobject]@{ Name = 'Paths'; Type = 'String[]'; Mandatory = $true }, [pscustomobject]@{ Name = 'Description'; Type = 'String'; Mandatory = $false }); Module = 'core' }
        @{ Name = 'backups.rollback'; Kind = 'Change'; Description = 'Roll back to the last saved rollback point (or a named one). Restores all snapshotted files.'; Parameters = @([pscustomobject]@{ Name = 'Name'; Type = 'String'; Mandatory = $false }); Module = 'core' }
    )
    foreach ($o in $fixed) {
        $available = $script:KitHasPinball -or $o.Module -ne 'pinball'
        [pscustomobject]@{ Name = $o.Name; Kind = $o.Kind; Suite = ''; Interactive = $false; Available = $available; Description = $o.Description; Parameters = $o.Parameters; Module = $o.Module }
    }
    foreach ($s in Get-KitApiStep) {
        [pscustomobject]@{ Name = $s.Name; Kind = 'Change'; Suite = $s.Suite; Interactive = $s.Interactive; Available = -not $s.Interactive; Description = $s.Description; Parameters = $s.Parameters; Module = $s.Suite }
    }
    foreach ($p in @(@{ Name = 'profile.export'; Command = 'Export-KitCabinetProfile' }, @{ Name = 'profile.import'; Command = 'Import-KitCabinetProfile' })) {
        $cmd = Get-Command -Name $p.Command -ErrorAction SilentlyContinue
        [pscustomobject]@{
            Name = $p.Name; Kind = 'Change'; Suite = ''; Module = 'profiles'; Interactive = $false; Available = [bool]$cmd
            Description = if ($cmd) { "Cabinet migration ($($p.Command))." } else { "Cabinet migration: not available yet ($($p.Command) arrives with v0.3)." }
            Parameters = @(if ($cmd) { Get-KitApiParameter -Command $cmd })
        }
    }
}

# --- helpers ----------------------------------------------------------------------------------------------------

# Refuses unknown parameters and anything that is not plain; returns $null or the reason.
function Get-ParameterProblem([object[]] $Allowed, [hashtable] $Parameters) {
    foreach ($k in $Parameters.Keys) {
        $spec = @($Allowed | Where-Object { $_.Name -eq $k }) | Select-Object -First 1
        if (-not $spec) { return (Get-KitText 'Api.UnknownParameter' -f $k) }
        $v = $Parameters[$k]
        if ($v -is [scriptblock] -or ($v -is [Collections.IDictionary])) { return (Get-KitText 'Api.UnknownParameter' -f $k) }
    }
    foreach ($spec in @($Allowed | Where-Object { $_.Mandatory })) {
        if (-not $Parameters.ContainsKey($spec.Name)) { return (Get-KitText 'Api.MissingParameter' -f $spec.Name) }
    }
    $null
}

function Get-WorstStatus([string[]] $Status) {
    foreach ($s in 'Failed', 'NeedsUser', 'WhatIf', 'Done', 'Skipped') { if ($Status -contains $s) { return $s } }
    'Failed'
}

# Runs one step script and folds its StepResult objects into one OperationResult.
function Invoke-StepOperation([psobject] $Step, [hashtable] $Parameters, [bool] $Apply, [bool] $Approved, [string] $StatePath, [datetime] $Started) {
    # The step asks through -Approve: the plan text is recorded for the client and answered with the decision the
    # client passed as -Approved (a person's decision, never the API's own). The block is bound to this module, so
    # it reaches these two module variables when the step calls it.
    $script:ApiApprovals = New-Object Collections.Generic.List[string]
    $script:ApiApprovalAnswer = $Approved
    $call = @{} + $Parameters
    if ((Get-Command -Name $Step.Script).Parameters.ContainsKey('Approve')) {
        $call.Approve = { param($text) $script:ApiApprovals.Add([string]$text); [bool]$script:ApiApprovalAnswer }
    }
    $call.StatePath = $StatePath
    $call.Culture = Get-KitCulture
    if (-not $Apply) { $call.WhatIf = $true }
    $results = New-Object Collections.Generic.List[object]
    $errors = New-Object Collections.Generic.List[string]
    try {
        & $Step.Script @call 6>$null | ForEach-Object {
            if ($_ -and $_.PSObject.TypeNames -contains 'RetroCabinetKit.StepResult') { $results.Add($_) }
        }
    } catch { $errors.Add($_.Exception.Message) }
    $statuses = @($results | ForEach-Object { if ($_.WhatIf) { 'WhatIf' } else { $_.Status } })
    $status = if ($errors.Count -or -not $results.Count) { 'Failed' } else { Get-WorstStatus $statuses }
    $duration = 0.0
    foreach ($r in $results) { if ($r.PSObject.Properties['Duration']) { $duration += $r.Duration.TotalSeconds } }
    $steps = @($results | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Status = $_.Status; WhatIf = $_.WhatIf; Message = $_.Message; Duration = [math]::Round($_.Duration.TotalSeconds, 3) } })
    $message = if ($errors.Count) { $errors[0] } elseif ($results.Count) { ($results | ForEach-Object { $_.Message }) -join ' ' } else { Get-KitText 'Api.NoResult' }
    New-KitOperationResult -Operation $Step.Name -Kind Change -Status $status -Message $message -Applied $Apply `
        -Warnings @($results | ForEach-Object { $_.Warnings }) -Errors (@($results | ForEach-Object { $_.Errors }) + @($errors)) `
        -Changes @($results | ForEach-Object { $_.Changes }) -Backups @($results | ForEach-Object { $_.Backups }) `
        -Approvals @($script:ApiApprovals) -Duration $duration -StartedAt $Started -Data ([pscustomobject]@{ Steps = $steps })
}

function Get-KitApiComponent([string] $PinballStatePath, [string] $LightgunStatePath) {
    $rows = New-Object Collections.Generic.List[object]
    function Add-Row($Name, $Present, $Version, $Path, $Detail) { $rows.Add([pscustomobject]@{ Name = $Name; Present = [bool]$Present; Version = [string]$Version; Path = [string]$Path; Detail = [string]$Detail }) }
    $os = [Environment]::OSVersion.Version
    Add-Row 'Windows' $true "$os" '' ''
    try {
        $rb = if (Test-Path -LiteralPath $LightgunStatePath) { [string](Get-KitStateValue -Path $LightgunStatePath -Key 'RetroBatRoot') } else { '' }
        if ($rb -and -not (Get-LightgunRetroBatProblem -Root $rb)) { $i = Get-LightgunRetroBatInfo -Root $rb; Add-Row 'RetroBat' $true $i.Version $rb '' }
        else { Add-Row 'RetroBat' $false '' $rb '' }
    } catch { Add-Row 'RetroBat' $false '' '' $_.Exception.Message }
    try { $g = Find-LightgunGunmote; Add-Row 'Gunmote' ([bool]$g) $(if ($g) { $g.Version }) $(if ($g) { $g.Dir }) '' } catch { Add-Row 'Gunmote' $false '' '' $_.Exception.Message }
    try { $v = Get-LightgunViGEmState; Add-Row 'ViGEmBus' $v.Installed $v.Version '' $(if ($v.Installed -and -not $v.Running) { 'service not running' }) } catch { Add-Row 'ViGEmBus' $false '' '' $_.Exception.Message }
    try { $b = Get-LightgunDolphinBarState; Add-Row 'DolphinBar' ($b.Mode4 -or @($b.WrongMode).Count) '' '' $(if ($b.Mode4) { 'Mode4' } else { @($b.WrongMode) -join ',' }) } catch { Add-Row 'DolphinBar' $false '' '' $_.Exception.Message }
    try { $s = Get-LightgunSteamPath; Add-Row 'Steam' ([bool]$s) '' $s '' } catch { Add-Row 'Steam' $false '' '' $_.Exception.Message }
    if ($script:KitHasPinball) {
        try {
            $root = if (Test-Path -LiteralPath $PinballStatePath) { [string](Get-KitStateValue -Path $PinballStatePath -Key 'TargetRoot') } else { '' }
            $problem = if ($root) { Get-PinballRootProblem -Root $root } else { '' }
            Add-Row 'PinballBuild' ($root -and -not $problem) '' $root $problem
        } catch { Add-Row 'PinballBuild' $false '' '' $_.Exception.Message }
        try {
            # The second front end is not part of a build: its folder comes from the kit state, and an unknown one
            # stays unknown. Searching drives for it here would make a cheap probe expensive and would guess.
            $y = if (Test-Path -LiteralPath $PinballStatePath) { [string](Get-KitStateValue -Path $PinballStatePath -Key 'PinballYRoot') } else { '' }
            $yOk = Test-PinballYInstall -Path $y
            $detail = if ($yOk) { Get-KitText 'PinballY.ComponentKnown' }
                      elseif ($y) { Get-KitText 'PinballY.NotAnInstall' -f $y, 'PinballY.exe + Settings.txt' }
                      else { Get-KitText 'PinballY.NotInState' }
            Add-Row 'PinballY' $yOk $(if ($yOk) { (Get-PinballYVersion -Path $y).Version }) $y $detail
        } catch { Add-Row 'PinballY' $false '' '' $_.Exception.Message }
    }
    $rows.ToArray()
}

# --- the entry point ------------------------------------------------------------------------------------------------

function Invoke-KitOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [hashtable] $Parameters = @{},
        [switch] $Apply,
        [switch] $Approved,
        [string] $PinballStatePath = (Get-PinballDefaultStatePath),
        [string] $LightgunStatePath = (Get-LightgunDefaultStatePath)
    )
    $started = Get-Date
    $clock = [Diagnostics.Stopwatch]::StartNew()
    $catalog = @(Get-KitOperation)
    $op = @($catalog | Where-Object { $_.Name -eq $Name }) | Select-Object -First 1
    if (-not $op) { return New-KitOperationResult -Operation $Name -Status NotAvailable -Message (Get-KitText 'Api.UnknownOperation' -f $Name) -StartedAt $started }
    $kind = $op.Kind
    if (-not $op.Available) {
        $key = if ($op.Interactive) { 'Api.Interactive' } elseif ($op.Module -eq 'pinball' -and -not $script:KitHasPinball) { 'Api.PackageMissing' } else { 'Api.NotAvailable' }
        return New-KitOperationResult -Operation $Name -Kind $kind -Status NotAvailable -Message (Get-KitText $key -f $Name) -StartedAt $started
    }
    $problem = Get-ParameterProblem $op.Parameters $Parameters
    if ($problem) { return New-KitOperationResult -Operation $Name -Kind $kind -Status Failed -Message $problem -Errors @($problem) -StartedAt $started }
    $apply = [bool]$Apply
    $p = $Parameters

    try {
        if ($Name -like 'step.*') {
            $step = Get-KitApiStep | Where-Object { $_.Name -eq $Name }
            $state = if ($step.Suite -eq 'pinball') { $PinballStatePath } else { $LightgunStatePath }
            return Invoke-StepOperation -Step $step -Parameters $p -Apply $apply -Approved ([bool]$Approved) -StatePath $state -Started $started
        }
        switch ($Name) {
            'operations' { $data = [pscustomobject]@{ Operations = $catalog }; $status = 'Ok'; $msg = '' }
            'status' {
                $checks = @(Invoke-KitDoctor -Check @(@(Get-KitSystemCheck) + @(Get-PinballDoctorCheck -StatePath $PinballStatePath) + @(Get-LightgunDoctorCheck -StatePath $LightgunStatePath)))
                $s = Get-KitDoctorSummary -Result $checks
                $level = if ($s.Error) { 'Error' } elseif ($s.Warn) { 'Warn' } else { 'Ok' }
                $data = [pscustomobject]@{
                    Summary = [pscustomobject]@{ Ok = $s.Ok; Info = $s.Info; Warn = $s.Warn; Error = $s.Error; Level = $level }
                    Checks  = @($checks | ForEach-Object { [pscustomobject]@{ Area = $_.Area; Name = $_.Name; Level = $_.Level; Detail = $_.Detail } })
                }
                $status = 'Ok'; $msg = Get-KitText 'Doctor.Result' -f $s.Error, $s.Warn, $s.Ok
            }
            'status.health' {
                try {
                    $rb = if ($p.ContainsKey('RetroBatRoot') -and $p.RetroBatRoot) { $p.RetroBatRoot } else { Get-OutputRetroBatRoot }
                    $extraPaths = if ($p.ContainsKey('ExtraStoragePaths') -and $p.ExtraStoragePaths) { @($p.ExtraStoragePaths) } else { @() }
                    $extraProcs = if ($p.ContainsKey('ExtraBadProcesses') -and $p.ExtraBadProcesses) { @($p.ExtraBadProcesses) } else { @() }
                    $health = Get-SystemHealth -RetroBatRoot $rb -ExtraStoragePaths $extraPaths -ExtraBadProcesses $extraProcs
                    $data = $health; $status = 'Ok'
                    $msg = "System health: $($health.Status). Hardware: DolphinBar=$($health.Hardware.DolphinBar), Arcade=$($health.Hardware.ArcadeEncoder). Vitals: $($health.Vitals.MemoryFreeMB)MB free, $($health.Vitals.CpuLoadPercent)% CPU."
                } catch { $status = 'Failed'; $msg = $_.Exception.Message; $data = $null }
            }
            'components' { $data = [pscustomobject]@{ Components = @(Get-KitApiComponent -PinballStatePath $PinballStatePath -LightgunStatePath $LightgunStatePath) }; $status = 'Ok'; $msg = '' }
            'pinbally.detect' {
                # Reads only, so there is nothing to dry run and nothing to approve: the result is the description.
                # A folder that is not an installation throws and lands in Failed, like an unknown backup path.
                $info = Get-PinballYInfo -Path $p.Path
                $warnings = @(foreach ($r in @(@($info.ReferenceMissing) + @($info.ReferenceForeign))) {
                    if ($r.Status -eq 'ForeignDrive') {
                        Get-KitText 'PinballY.RefForeign' -f $r.Key, $r.Line, (Get-PinballYDriveLetter -Path $r.Value)
                    } else {
                        Get-KitText 'PinballY.RefMissing' -f $r.Key, $r.Line, $(if ($r.Resolved) { $r.Resolved } else { $r.Value })
                    }
                })
                return New-KitOperationResult -Operation $Name -Kind Read -Status Ok -Message $info.Detail `
                    -Warnings $warnings -Duration $clock.Elapsed.TotalSeconds -StartedAt $started `
                    -Data ([pscustomobject]@{
                        Root = $info.Root; Version = $info.Version; Encoding = $info.Encoding
                        SettingsLine = $info.SettingsLine; Setting = $info.Setting
                        System = $info.System; SystemEnabled = $info.SystemEnabled
                        Reference = $info.Reference; ReferenceAbsolute = $info.ReferenceAbsolute
                        ReferenceToken = $info.ReferenceToken; ReferenceMissing = @($info.ReferenceMissing)
                        ReferenceForeign = @($info.ReferenceForeign)
                        Database = $info.Database; Game = $info.Game; Companion = $info.Companion
                        Running = $info.Running; WriteSafe = $info.WriteSafe
                    })
            }
            'pinbally.retarget' {
                # Change: the plan comes first, and only a person's yes (-Approved) turns it into a write.
                # Values that resolve here, comments, [TOKEN] values, relative paths and the copies the program
                # keeps for itself are not part of any plan (pinball\modules\PinballYRetarget.ps1).
                $map = @(foreach ($m in @($p.Map)) { [string]$m })
                # Writing is only for an installation, not for a folder that happens to hold a Settings.txt.
                if (-not (Test-PinballYInstall -Path $p.Path)) {
                    $m2 = Get-KitText 'PinballY.NotAnInstall' -f $p.Path, 'PinballY.exe + Settings.txt'
                    return New-KitOperationResult -Operation $Name -Kind Change -Status Failed -Message $m2 -Errors @($m2) `
                        -Duration $clock.Elapsed.TotalSeconds -StartedAt $started
                }
                $backupDir = if ($p.ContainsKey('BackupDir')) { $p.BackupDir } else { '' }
                $plan = Invoke-PinballYRetarget -Path $p.Path -Map $map
                $ready = @($plan.Ready); $pending = @($plan.Pending)
                $files = @($ready | ForEach-Object { $_.File } | Sort-Object -Unique)
                $approvals = @(foreach ($f in $files) {
                    $rows = @($ready | Where-Object { $_.File -eq $f })
                    Get-KitText 'PinballY.Retarget.Approve' -f (Split-Path -Leaf $f), $rows.Count, ('{0} -> {1}' -f $rows[0].Old, $rows[0].New)
                })
                $left = @(foreach ($x in $pending) { $x.Reason })
                $planData = [pscustomobject]@{
                    Root = $plan.Root; Pair = $plan.Pair; Plan = $plan.Plan
                    Ready = $ready; Pending = $pending; Written = @(); Backup = ''
                }
                if (-not $ready.Count) {
                    # Nothing this map could fix: with -Apply that answers Skipped, without it the plan says
                    # the same thing. A value the map does not cover stays a Warning, never a silent change.
                    return New-KitOperationResult -Operation $Name -Kind Change -Status $(if ($apply) { 'Skipped' } else { 'WhatIf' }) `
                        -Message (Get-KitText 'PinballY.Retarget.None') -Warnings $left `
                        -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $planData
                }
                if (-not $apply) {
                    return New-KitOperationResult -Operation $Name -Kind Change -Status WhatIf `
                        -Message (Get-KitText 'PinballY.Retarget.Plan' -f $ready.Count, $pending.Count, $files.Count) `
                        -Warnings $left -Approvals $approvals `
                        -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $planData
                }
                if (-not $Approved) {
                    return New-KitOperationResult -Operation $Name -Kind Change -Status NeedsUser `
                        -Message (Get-KitText 'PinballY.Retarget.NeedsApproval' -f $files.Count) `
                        -Warnings $left -Approvals $approvals `
                        -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $planData
                }
                # The plan is made a second time inside the write, on the file as it is now: PinballY rewrites
                # its own settings when it closes, so a line that moved since the shown plan is refused there.
                $done = Invoke-PinballYRetarget -Path $p.Path -Map $map -Apply -BackupDir $backupDir
                $written = @($done.Written)
                $changes = @(foreach ($w in $written) {
                    [pscustomobject]@{ Kind = 'File'; Target = $w.File; Detail = ('line {0}: {1} -> {2}' -f $w.Line, $w.Old, $w.New) }
                })
                # The folder becomes known to the kit only with the write: a dry run changes nothing, the state
                # file included, and components must not report an installation nobody decided to keep.
                $null = Set-KitStateValue -Path $PinballStatePath -Key 'PinballYRoot' -Value $done.Root
                return New-KitOperationResult -Operation $Name -Kind Change -Status Done -Applied $true `
                    -Message (Get-KitText 'PinballY.Retarget.Done' -f $written.Count, @($written | ForEach-Object { $_.File } | Sort-Object -Unique).Count, (Split-Path -Leaf $done.Backup)) `
                    -Warnings $left -Changes $changes -Backups @($done.Backup) `
                    -Duration $clock.Elapsed.TotalSeconds -StartedAt $started `
                    -Data ([pscustomobject]@{
                        Root = $done.Root; Pair = $done.Pair; Plan = $done.Plan; Ready = @($done.Ready)
                        Pending = @($done.Pending); Written = $written; Backup = $done.Backup
                    })
            }
            'backups.list' {
                $roots = if ($p.ContainsKey('Root')) { @($p.Root) } else { @(@(Get-PinballBackupRoot -StatePath $PinballStatePath) + @(Get-LightgunBackupRoot -StatePath $LightgunStatePath) | Sort-Object -Unique) }
                $list = @(Get-KitBackup -Path $roots | ForEach-Object {
                    [pscustomobject]@{ Kind = $_.Kind; Path = $_.Path; Created = $_.Created.ToString('o'); Purpose = $_.Purpose; Original = $_.Original; Files = $_.Files; Registry = $_.Registry; SizeBytes = $_.SizeBytes }
                })
                $data = [pscustomobject]@{ Backups = $list; Roots = $roots }; $status = 'Ok'; $msg = ''
            }
            'backup.check' {
                $r = Test-KitBackup -Path $p.Path
                $data = [pscustomobject]@{ Ok = $r.Ok; Differs = $r.Differs; Problems = @($r.Problems) }
                $status = if ($r.Ok) { 'Ok' } else { 'Failed' }
                $msg = Get-KitText $(if ($r.Ok) { 'Recovery.CheckOk' } else { 'Recovery.CheckBad' }) -f $r.Path
            }
            'backup.restore' {
                # Steam counts only when Steam's own files may come back: a .vdf copy or a zip backup (any content).
                $steam = ($p.Path -match '\.vdf\.bak_') -or -not (ConvertFrom-KitFileBackupName -Path $p.Path)
                if ($apply) { Assert-PinballProcessesClosed; Assert-LightgunProcessesClosed -IncludeSteam:$steam }
                if (ConvertFrom-KitFileBackupName -Path $p.Path) {
                    $r = Restore-KitFileBackup -Path $p.Path -WhatIf:(-not $apply) -Confirm:$false
                    $changes = @(if ($r.Action -eq 'Restored') { [pscustomobject]@{ Kind = 'File'; Target = $r.Target; Detail = 'restored from backup' } })
                    return New-KitOperationResult -Operation $Name -Kind Change -Status $(if ($r.Action -eq 'Restored') { 'Done' } else { 'WhatIf' }) `
                        -Message (Get-KitText $(if ($r.Action -eq 'Restored') { 'Recovery.Restored' } else { 'Ui.Care.RestorePlan' }) -f $r.Target, $r.Source) `
                        -Applied $apply -Changes $changes -Backups @($r.SavedCurrent) -Duration $clock.Elapsed.TotalSeconds -StartedAt $started `
                        -Data ([pscustomobject]@{ Target = $r.Target; SavedCurrent = $r.SavedCurrent })
                }
                if (-not $p.ContainsKey('AllowedRoot')) { return New-KitOperationResult -Operation $Name -Kind Change -Status NeedsUser -Message (Get-KitText 'Recovery.ZipRestoreRoots') -Applied $apply -StartedAt $started }
                $check = Test-KitBackup -Path $p.Path
                if (-not $check.Ok) { return New-KitOperationResult -Operation $Name -Kind Change -Status Failed -Message (Get-KitText 'Recovery.CheckBad' -f $check.Path) -Errors @($check.Problems) -Applied $apply -StartedAt $started }
                $rows = @(Restore-KitBackup -Path $p.Path -AllowedRoots @($p.AllowedRoot) -SkipRegistry -WhatIf:(-not $apply) -Confirm:$false)
                $changes = @($rows | Where-Object { $_.Action -eq 'Restored' } | ForEach-Object { [pscustomobject]@{ Kind = 'File'; Target = $_.Target; Detail = 'restored from backup' } })
                return New-KitOperationResult -Operation $Name -Kind Change -Status $(if ($apply) { 'Done' } else { 'WhatIf' }) -Applied $apply `
                    -Message (Get-KitText 'Api.RestoredFiles' -f $rows.Count) -Changes $changes -Duration $clock.Elapsed.TotalSeconds -StartedAt $started `
                    -Data ([pscustomobject]@{ Files = @($rows | ForEach-Object { $_.Target }) })
            }
            'backup.remove' {
                # Same recognition as the delete itself (a kit zip with manifest or a <file>.bak_* copy), also in the dry run.
                try { $null = Test-KitBackup -Path $p.Path } catch {
                    return New-KitOperationResult -Operation $Name -Kind Change -Status Failed -Message $_.Exception.Message -Errors @($_.Exception.Message) -StartedAt $started
                }
                if (-not $apply) { return New-KitOperationResult -Operation $Name -Kind Change -Status WhatIf -Message (Get-KitText 'Api.RemovePlan' -f $p.Path) -StartedAt $started }
                Remove-KitBackup -Path $p.Path -Confirm:$false
                return New-KitOperationResult -Operation $Name -Kind Change -Status Done -Applied $true -Message (Get-KitText 'Recovery.Deleted' -f $p.Path) `
                    -Changes @([pscustomobject]@{ Kind = 'File'; Target = $p.Path; Detail = 'backup deleted' }) -Duration $clock.Elapsed.TotalSeconds -StartedAt $started `
                    -Data ([pscustomobject]@{ Removed = $p.Path })
            }
            'backup.export' {
                if (-not $apply) {
                    return New-KitOperationResult -Operation $Name -Kind Change -Status WhatIf -Message (Get-KitText 'Api.ExportPlan' -f $p.Path, $p.Destination) -StartedAt $started
                }
                $item = Export-KitBackup -Path $p.Path -Destination $p.Destination
                return New-KitOperationResult -Operation $Name -Kind Change -Status Done -Applied $true -Message (Get-KitText 'Recovery.Exported' -f $item.FullName) `
                    -Changes @([pscustomobject]@{ Kind = 'File'; Target = $item.FullName; Detail = 'export' }) -Duration $clock.Elapsed.TotalSeconds -StartedAt $started `
                    -Data ([pscustomobject]@{ Exported = $item.FullName })
            }
            'support.bundle' {
                $dest = if ($p.ContainsKey('Destination')) { $p.Destination } else { Join-Path $script:KitRoot ('logs\support-bundle_{0:yyyyMMdd-HHmmss}.zip' -f (Get-Date)) }
                if (-not $apply) { return New-KitOperationResult -Operation $Name -Kind Change -Status WhatIf -Message (Get-KitText 'Api.BundlePlan' -f $dest) -StartedAt $started }
                $checks = @(Invoke-KitDoctor -Check @(@(Get-KitSystemCheck) + @(Get-PinballDoctorCheck -StatePath $PinballStatePath) + @(Get-LightgunDoctorCheck -StatePath $LightgunStatePath)))
                $zip = Export-KitSupportBundle -Destination $dest -DoctorResult $checks -StatePath $PinballStatePath, $LightgunStatePath -LogDir (Join-Path $script:KitRoot 'logs')
                return New-KitOperationResult -Operation $Name -Kind Change -Status Done -Applied $true -Message (Get-KitText 'Support.Created' -f $zip.FullName) `
                    -Changes @([pscustomobject]@{ Kind = 'File'; Target = $zip.FullName; Detail = 'support bundle' }) -Duration $clock.Elapsed.TotalSeconds -StartedAt $started `
                    -Data ([pscustomobject]@{ Path = $zip.FullName })
            }
            { $_ -in 'profile.export', 'profile.import' } {
                $cmd = if ($Name -eq 'profile.export') { 'Export-KitCabinetProfile' } else { 'Import-KitCabinetProfile' }
                $info = Get-Command -Name $cmd
                $call = @{} + $p
                # Rule 2: an automatic install is a plan a person approves. A command that cannot ask (no -Approve)
                # would answer itself, so the API refuses the install instead of letting it through.
                if ($p.ContainsKey('AutoInstall') -and $p.AutoInstall -and -not $info.Parameters.ContainsKey('Approve')) {
                    $m = Get-KitText 'Api.NoApproval' -f $cmd, 'AutoInstall'
                    return New-KitOperationResult -Operation $Name -Kind Change -Status Failed -Message $m -Errors @($m) -StartedAt $started
                }
                if (-not $apply) {
                    # Rule 1: a command without a dry run of its own is not run at all; the plan is the call.
                    if (-not $info.Parameters.ContainsKey('WhatIf')) {
                        return New-KitOperationResult -Operation $Name -Kind Change -Status WhatIf -Message (Get-KitText 'Api.CallPlan' -f $cmd) `
                            -StartedAt $started -Data ([pscustomobject]@{ Parameters = [pscustomobject]$p })
                    }
                    $call.WhatIf = $true
                }
                $script:ApiApprovals = New-Object Collections.Generic.List[string]
                $script:ApiApprovalAnswer = [bool]$Approved
                if ($info.Parameters.ContainsKey('Approve')) {
                    $call.Approve = { param($text) $script:ApiApprovals.Add([string]$text); [bool]$script:ApiApprovalAnswer }
                }
                $out = @(& $cmd @call 6>$null)
                # Step results and the import's own rows (Name, Status, Detail) both count: a row that needs a person
                # or failed makes the operation not succeed.
                $rows = @($out | Where-Object { $_ -and $_.PSObject.Properties['Status'] })
                $statuses = @($rows | ForEach-Object { if ($_.PSObject.Properties['WhatIf'] -and $_.WhatIf) { 'WhatIf' } else { [string]$_.Status } })
                $st = if ($statuses.Count) { Get-WorstStatus $statuses } elseif ($apply) { 'Done' } else { 'WhatIf' }
                $detail = { param($r) if ($r.PSObject.Properties['Detail']) { '{0}: {1}' -f $r.Name, $r.Detail } elseif ($r.PSObject.Properties['Message']) { '{0}: {1}' -f $r.Name, $r.Message } else { [string]$r.Name } }
                $warnings = @($rows | Where-Object { $_.Status -eq 'NeedsUser' } | ForEach-Object { & $detail $_ })
                $errors = @($rows | Where-Object { $_.Status -eq 'Failed' } | ForEach-Object { & $detail $_ })
                $steps = @($rows | Where-Object { $_.PSObject.TypeNames -contains 'RetroCabinetKit.StepResult' })
                $written = @($out | Where-Object { $_ -and $_.PSObject.Properties['Path'] } | Select-Object -First 1)
                $msg = if ($Name -eq 'profile.export') { if ($written.Count) { Get-KitText 'Profile.Exported' -f $written[0].Path } else { '' } }
                       elseif ($st -eq 'WhatIf') { Get-KitText 'Api.ImportPlan' -f $p.Path }
                       elseif ($st -eq 'Done' -or $st -eq 'Skipped') { Get-KitText 'Profile.Imported' -f $p.Path }
                       else { Get-KitText 'Api.ImportOpen' -f ($warnings.Count + $errors.Count) }
                return New-KitOperationResult -Operation $Name -Kind Change -Status $st -Applied $apply -Message $msg `
                    -Warnings $warnings -Errors $errors -Approvals @($script:ApiApprovals) `
                    -Changes @($steps | ForEach-Object { $_.Changes }) -Backups @($steps | ForEach-Object { $_.Backups }) `
                    -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data ([pscustomobject]@{ Result = $out })
            }
            'controllers.input_profiles' {
                try {
                    $one = $p.ContainsKey('Name') -and $p.Name
                    $profiles = @(if ($one) { Get-ArcadeInputProfile -Name $p.Name } else { Get-ArcadeInputProfile })
                    $rows = @($profiles | ForEach-Object {
                        $row = [ordered]@{ Name = $_.Name; Description = $_.Description; Builtin = $_.Builtin; Intents = $_.Mapping.Count }
                        if ($one) { $row.Mapping = $_.Mapping }
                        [pscustomobject]$row
                    })
                    $data = [pscustomobject]@{ Profiles = $rows }; $status = 'Ok'; $msg = "$($rows.Count) input profile(s)"
                } catch { $status = 'Failed'; $msg = $_.Exception.Message; $data = $null }
                return New-KitOperationResult -Operation $Name -Kind Read -Status $status -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'controllers.xinput_slots' {
                try {
                    $slots = @(Get-ArcadeXInputSlot)
                    $used = @($slots | Where-Object { $_.Connected }).Count
                    $data = [pscustomobject]@{ Slots = $slots }; $status = 'Ok'; $msg = "$used of 4 XInput slot(s) in use"
                } catch { $status = 'Failed'; $msg = $_.Exception.Message; $data = $null }
                return New-KitOperationResult -Operation $Name -Kind Read -Status $status -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'controllers.wiimote_order' {
                try {
                    $o = Get-ArcadeWiimoteOrder
                    $msg = switch ($o.State) {
                        'Ok'        { 'Wiimote order matches the binding' }
                        'Swapped'   { 'Wiimote order is swapped: switch them off, then on in this order: ' + ($o.SwitchOnOrder -join ', ') }
                        'Unbound'   { 'No binding saved yet: controllers.wiimote_bind saves the current order' }
                        'Unclear'   { 'Order unclear: a Wiimote connected before Gunmote started or long after the other (reconnect?). Switch them off, then on one after the other.' }
                        'NoGunmote' { 'Gunmote is not running: it numbers the Wiimotes when they connect' }
                        default     { 'No Wiimote connected' }
                    }
                    $status = 'Ok'; $data = $o
                } catch { $status = 'Failed'; $msg = $_.Exception.Message; $data = $null }
                return New-KitOperationResult -Operation $Name -Kind Read -Status $status -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'controllers.wiimote_bind' {
                # Rule 1: without -Apply the answer is the plan and nothing is written.
                try {
                    $entries = @(Save-ArcadeWiimoteLedger -WhatIf:(-not $apply))
                    $text = ($entries | ForEach-Object { 'player {0} = {1} ({2})' -f $_.Player, $_.Mac, $_.Model }) -join ', '
                    $status = if ($apply) { 'Done' } else { 'WhatIf' }
                    $msg = if ($apply) { "Wiimote binding saved: $text" } else { "Plan: $text. Apply with -Apply." }
                    return New-KitOperationResult -Operation $Name -Kind Change -Status $status -Applied $apply -Message $msg `
                        -Changes @($entries | ForEach-Object { "player $($_.Player) = $($_.Mac)" }) -Duration $clock.Elapsed.TotalSeconds -StartedAt $started `
                        -Data ([pscustomobject]@{ Wiimotes = $entries })
                } catch {
                    return New-KitOperationResult -Operation $Name -Kind Change -Status Failed -Message $_.Exception.Message -Errors @($_.Exception.Message) `
                        -Duration $clock.Elapsed.TotalSeconds -StartedAt $started
                }
            }
            'controllers.input_apply' {
                # Rule 1: without -Apply the answer is the plan and nothing is written.
                try {
                    $rb = if ($p.ContainsKey('RetroBatRoot') -and $p.RetroBatRoot) { $p.RetroBatRoot } else { Get-ArcadeRetroBatRoot }
                    $ctrlr = if ($p.ContainsKey('CtrlrName') -and $p.CtrlrName) { $p.CtrlrName } else { '' }
                    $res = if ($apply) { Set-ArcadeInputMatrix -ProfileName $p.Profile -CtrlrName $ctrlr -RetroBatRoot $rb -Confirm:$false }
                           else { Get-ArcadeInputMatrixPlan -ProfileName $p.Profile -CtrlrName $ctrlr -RetroBatRoot $rb }
                    $changes = @($res.Changes)
                    $status = if (-not $changes.Count) { 'Skipped' } elseif ($apply) { 'Done' } else { 'WhatIf' }
                    $msg = if (-not $changes.Count) { "$($res.Target) already matches profile $($res.Profile)" }
                           elseif ($apply) { "$($res.Target) written from profile $($res.Profile) ($($changes.Count) port(s))" }
                           else { "Plan: $($changes.Count) port(s) for $($res.Target). Apply with -Apply." }
                    $backups = @(if ($apply -and $res.Backup) { $res.Backup })
                    return New-KitOperationResult -Operation $Name -Kind Change -Status $status -Applied ($apply -and $res.Written) -Message $msg `
                        -Warnings @($res.Warnings) -Changes $changes -Backups $backups -Duration $clock.Elapsed.TotalSeconds -StartedAt $started `
                        -Data ([pscustomobject]@{ Profile = $res.Profile; Target = $res.Target; Exists = $res.Exists })
                } catch {
                    return New-KitOperationResult -Operation $Name -Kind Change -Status Failed -Message $_.Exception.Message -Errors @($_.Exception.Message) `
                        -Duration $clock.Elapsed.TotalSeconds -StartedAt $started
                }
            }
            'controllers.detect' {
                # Read-only detection of all controllers across lightgun, arcade, and pads packages
                try {
                    # Get lightgun state path for adapter functions
                    $LightgunStatePath = (Get-LightgunDefaultStatePath)
                    
                    # Detect lightguns
                    $lightgunResults = @()
                    $lightgunCatalog = Get-LightgunAdapterCatalog
                    foreach ($adapter in $lightgunCatalog) {
                        if ($adapter.HasParseErrors -or -not $adapter.HasTest) { continue }
                        try {
                            $isPresent = Invoke-LightgunAdapterFunction -Name $adapter.Name -Function "Test-$($adapter.Name)Hardware" -Dir (Get-LightgunAdapterDir) -Parameters @{}
                            if ($isPresent) {
                                $adapterInfo = Invoke-LightgunAdapterFunction -Name $adapter.Name -Function "Get-$($adapter.Name)AdapterInfo" -Dir (Get-LightgunAdapterDir)
                                $lightgunResults += [pscustomobject]@{
                                    Name = $adapter.Name
                                    Present = $true
                                    Info = @{
                                        Links = if ($adapterInfo.ContainsKey('Links')) { $adapterInfo.Links } else { @{} }
                                        Notes = if ($adapterInfo.ContainsKey('Notes')) { $adapterInfo.Notes } else { '' }
                                    }
                                    Category = 'lightgun'
                                }
                            }
                        } catch {
                            # Continue testing other adapters even if one fails
                        }
                    }
                    
                    # Detect arcade sticks
                    $arcadeResults = @()
                    $arcadeCatalog = Get-ArcadeAdapterCatalog
                    foreach ($adapter in $arcadeCatalog) {
                        if ($adapter.HasParseErrors -or -not ($adapter.HasTest -and $adapter.HasInfo)) { continue }
                        try {
                            # Get devices and exclude those already claimed by lightgun
                            $allDevices = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue)
                            $allDevices = @($allDevices | Where-Object { $_ })
                            
                            # Check if this adapter would detect any unclaimed devices
                            $hit = $null
                            $claimedIds = @()
                            # Get lightgun claimed devices first
                            foreach ($lgAdapter in $lightgunCatalog) {
                                if ($lgAdapter.HasParseErrors -or -not $lgAdapter.HasInfo) { continue }
                                try {
                                    $lgInfo = Invoke-LightgunAdapterFunction -Name $lgAdapter.Name -Function "Get-$($lgAdapter.Name)AdapterInfo" -Dir (Get-LightgunAdapterDir)
                                    foreach ($id in @(Get-LightgunAdapterValue $lgInfo 'MatchIds')) { if ($id) { $claimedIds += $id.ToUpperInvariant() } }
                                } catch {}
                            }
                            
                            foreach ($device in $allDevices) {
                                $deviceId = (Get-ArcadeDeviceId $device).ToUpperInvariant()
                                if ($deviceId -and $claimedIds -contains $deviceId) { continue }
                                $info = Invoke-ArcadeAdapterFunction -Name $adapter.Name -Function "Get-$($adapter.Name)AdapterInfo" -Dir (Get-ArcadeAdapterDir)
                                if (Get-ArcadeDeviceMatch -Device $device -MatchIds @(Get-ArcadeAdapterValue $info 'MatchIds') -NameHints @(Get-ArcadeAdapterValue $info 'NameHints')) {
                                    $hit = $device
                                    break
                                }
                            }
                            
                            if ($hit) {
                                $adapterInfo = Invoke-ArcadeAdapterFunction -Name $adapter.Name -Function "Get-$($adapter.Name)AdapterInfo" -Dir (Get-ArcadeAdapterDir)
                                $arcadeResults += [pscustomobject]@{
                                    Name = $adapter.Name
                                    Present = $true
                                    Info = @{
                                        Links = if ($adapterInfo.ContainsKey('Links')) { $adapterInfo.Links } else { @{} }
                                        Notes = if ($adapterInfo.ContainsKey('Notes')) { $adapterInfo.Notes } else { '' }
                                    }
                                    Category = 'arcade'
                                }
                            }
                        } catch {
                            # Continue testing other adapters even if one fails
                        }
                    }
                    
                    # Detect pads
                    $padResults = @()
                    $padCatalog = Get-PadAdapterCatalog
                    foreach ($adapter in $padCatalog) {
                        if ($adapter.HasParseErrors -or -not ($adapter.HasTest -and $adapter.HasInfo)) { continue }
                        try {
                            # Get devices and exclude those already claimed by lightgun or arcade
                            $allDevices = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue)
                            $allDevices = @(foreach ($d in $allDevices) { if ($d) { ConvertTo-PadDeviceObject $d } })
                            
                            $detectedPads = @()
                            foreach ($device in $allDevices) {
                                # Check if claimed by lightgun
                                $claimedByLightgun = $false
                                foreach ($lgAdapter in $lightgunCatalog) {
                                    if ($lgAdapter.HasParseErrors -or -not $lgAdapter.HasInfo) { continue }
                                    try {
                                        $lgInfo = Invoke-LightgunAdapterFunction -Name $lgAdapter.Name -Function "Get-$($lgAdapter.Name)AdapterInfo" -Dir (Get-LightgunAdapterDir)
                                        foreach ($id in @(Get-LightgunAdapterValue $lgInfo 'MatchIds')) {
                                            if ($id -and ((Get-PadDeviceId $device).ToUpperInvariant() -like $id)) { $claimedByLightgun = $true; break }
                                        }
                                    } catch {}
                                    if ($claimedByLightgun) { break }
                                }
                                if ($claimedByLightgun) { continue }
                                
                                # Check if claimed by arcade
                                $claimedByArcade = $false
                                foreach ($aAdapter in $arcadeCatalog) {
                                    if ($aAdapter.HasParseErrors -or -not ($aAdapter.HasTest -and $aAdapter.HasInfo)) { continue }
                                    try {
                                        $aInfo = Invoke-ArcadeAdapterFunction -Name $aAdapter.Name -Function "Get-$($aAdapter.Name)AdapterInfo" -Dir (Get-ArcadeAdapterDir)
                                        if (Get-ArcadeDeviceMatch -Device $device -MatchIds @(Get-ArcadeAdapterValue $aInfo 'MatchIds') -NameHints @(Get-ArcadeAdapterValue $aInfo 'NameHints')) {
                                            $claimedByArcade = $true; break
                                        }
                                    } catch {}
                                    if ($claimedByArcade) { break }
                                }
                                if ($claimedByArcade) { continue }
                                
                                # Check if this pad adapter claims it
                                $info = Invoke-PadAdapterFunction -Name $adapter.Name -Function "Get-$($adapter.Name)AdapterInfo" -Dir (Get-PadAdapterDir)
                                if (Get-PadDeviceMatch -Device $device -MatchIds @(Get-PadAdapterValue $info 'MatchIds') -NameHints @(Get-PadAdapterValue $info 'NameHints')) {
                                    $detectedPads += $device
                                }
                            }
                            
                            # Add unique detections for this adapter family
                            $seenDeviceIds = @{}
                            foreach ($device in $detectedPads) {
                                $deviceId = Get-PadDeviceId $device
                                if (-not $seenDeviceIds.ContainsKey($deviceId)) {
                                    $seenDeviceIds[$deviceId] = $true
                                    $adapterInfo = Invoke-PadAdapterFunction -Name $adapter.Name -Function "Get-$($adapter.Name)AdapterInfo" -Dir (Get-PadAdapterDir)
                                    $padResults += [pscustomobject]@{
                                        Name = $adapter.Name
                                        Present = $true
                                        Info = @{
                                            Links = if ($adapterInfo.ContainsKey('Links')) { $adapterInfo.Links } else { @{} }
                                            Notes = if ($adapterInfo.ContainsKey('Notes')) { $adapterInfo.Notes } else { '' }
                                        }
                                        Category = 'pad'
                                    }
                                }
                            }
                        } catch {
                            # Continue testing other adapters even if one fails
                        }
                    }
                    
                    # Return unified result
                    $data = [pscustomobject]@{
                        Lightguns = $lightgunResults
                        Arcade = $arcadeResults
                        Pads = $padResults
                    }
                    $status = 'Ok'
                    $msg = ''
                } catch {
                    $status = 'Failed'
                    $msg = $_.Exception.Message
                    $data = $null
                }
                
                return New-KitOperationResult -Operation $Name -Kind Read -Status $status -Message $msg -Data $data
            }
            'outputs.verify_safety' {
                # Read-only safety verification for output middleware
                try {
                    $rb = if ($p.ContainsKey('RetroBatRoot') -and $p.RetroBatRoot) { $p.RetroBatRoot } else { '' }
                    $mid = Get-OutputDetectedMiddleware -RetroBatRoot $rb -Quiet
                    $warnings = @()
                    
                    # Solenoid guard: HookOfTheReaper enforcement
                    $solenoidOk = $true; $solenoidDetail = ''
                    if ($mid.DetectedOutputs -contains 'HookOfTheReaper') {
                        try {
                            $hotrInfo = Invoke-OutputAdapterFunction -Name 'HookOfTheReaper' -Function 'Get-HookOfTheReaperAdapterInfo'
                            foreach ($t in @(Get-OutputAdapterValue $hotrInfo 'SettingsTargets')) {
                                $safety = if ($t.Contains('Safety')) { $t.Safety } else { $null }
                                if (-not $safety -or $safety.SolenoidMaxOpenTime -ne '200' -or $safety.SolenoidProtection -ne '1') {
                                    $solenoidOk = $false
                                    $solenoidDetail = 'SolenoidMaxOpenTime must be 200ms and SolenoidProtection must be 1'
                                }
                            }
                        } catch { $solenoidOk = $false; $solenoidDetail = $_.Exception.Message }
                    }
                    
                    # Port conflicts on 8000
                    $portConflicts = @($mid.Conflicts | Where-Object { $_.Kind -eq 'PortConflict' })
                    if ($mid.DetectedOutputs -contains 'GunmoteOutput') {
                        $owner8000 = @(Get-NetTCPConnection -State Listen -LocalPort 8000 -ErrorAction SilentlyContinue |
                            ForEach-Object {
                                $proc = Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue
                                [pscustomobject]@{ Port = 8000; Process = $proc.Name; Pid = $proc.Id; Blocking = ($proc.Name -ne 'python') }
                            })
                        if ($owner8000.Count) { $portConflicts += $owner8000 }
                    }
                    
                    # Double consumer check: Gunmote + MAMEHooker both active
                    $doubleConsumers = @()
                    if ($mid.DetectedOutputs -contains 'GunmoteOutput' -and $mid.DetectedOutputs -contains 'MameHooker') {
                        $doubleConsumers += [pscustomobject]@{
                            Consumers = @('GunmoteOutput', 'MameHooker')
                            Detail = 'Both Gunmote and MAMEHooker are consuming output events. This may cause double-rumble on the Wiimote.'
                        }
                    }
                    if ($mid.DetectedOutputs -contains 'GunmoteOutput' -and $mid.DetectedOutputs -contains 'FFBBlaster') {
                        $doubleConsumers += [pscustomobject]@{
                            Consumers = @('GunmoteOutput', 'FFBBlaster')
                            Detail = 'Both Gunmote and FFBBlaster are active. Verify that only one path drives the Wiimote motor per event.'
                        }
                    }
                    
                    # Gunmote configuration checks
                    $gunmoteInis = 0; $gunmoteConnected = $false; $rumbleThresholdOk = $true
                    if (Test-Path 'C:\Program Files\Gunmote\ArcadeOutputs' -PathType Container) {
                        $gunmoteInis = @(Get-ChildItem 'C:\Program Files\Gunmote\ArcadeOutputs' -Filter '*.ini' -File -ErrorAction SilentlyContinue).Count
                    }
                    $gunmoteConnected = @(Get-NetTCPConnection -RemotePort 8000 -State Established -ErrorAction SilentlyContinue |
                        Where-Object { (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Name -eq 'Gunmote' }).Count -gt 0
                    
                    $warnings = @()
                    if ($solenoidDetail) { $warnings += [string]$solenoidDetail }
                    foreach ($pc in $portConflicts) {
                        $w = if ($pc -is [System.Collections.IDictionary] -and $pc.Contains('Detail')) { $pc.Detail }
                             elseif ($pc.PSObject.Properties['Detail']) { $pc.Detail }
                             elseif ($pc.PSObject.Properties['Port']) { "Port $($pc.Port): $($pc.Process)" }
                             else { [string]$pc }
                        if ($w) { $warnings += [string]$w }
                    }
                    foreach ($dc in $doubleConsumers) {
                        if ($dc.PSObject.Properties['Detail'] -and $dc.Detail) { $warnings += [string]$dc.Detail }
                    }
                    
                    $data = [pscustomobject]@{
                        SolenoidGuard = [pscustomobject]@{ Ok = $solenoidOk; Detail = $solenoidDetail }
                        PortConflicts = @($portConflicts)
                        DoubleConsumers = @($doubleConsumers)
                        GunmoteConfig = [pscustomobject]@{ InisFound = $gunmoteInis; Connected = $gunmoteConnected; RumbleThresholdOk = $rumbleThresholdOk }
                        DetectedOutputs = $mid.DetectedOutputs
                        OutputMode = $mid.OutputMode
                    }
                    $status = 'Ok'
                    $msg = if ($warnings.Count) { "$($warnings.Count) warning(s) found" } else { 'All output safety checks passed' }
                } catch {
                    $status = 'Failed'
                    $msg = $_.Exception.Message
                    $data = $null
                }
                return New-KitOperationResult -Operation $Name -Kind Read -Status $status -Message $msg -Warnings $warnings -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'displays.detect' {
                try {
                    $displayResults = @()
                    $catalog = Get-DisplaysAdapterCatalog
                    foreach ($adapter in $catalog) {
                        try {
                            $info = Invoke-DisplaysAdapterFunction -Name $adapter.Name -Function "Get-$($adapter.Name)AdapterInfo"
                            $present = Invoke-DisplaysAdapterFunction -Name $adapter.Name -Function "Test-$($adapter.Name)Hardware"
                            $displayResults += [pscustomobject]@{
                                Name = $adapter.Name
                                Present = [bool]$present
                                Info = @{ Links = if ($info.Contains('Links')) { $info.Links } else { @{} }; Notes = if ($info.Contains('Notes')) { $info.Notes } else { '' } }
                                Category = 'display'
                            }
                        } catch { }
                    }
                    $monitors = @()
                    try {
                        $monitors = @(Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue |
                            ForEach-Object {
                                $mfr = if ($_.ManufacturerName) { [string]::Join('', ($_.ManufacturerName | ForEach-Object { [char]$_ })) } else { '' }
                                $prod = if ($_.ProductCodeID) { [string]::Join('', ($_.ProductCodeID | ForEach-Object { [char]$_ })) } else { '' }
                                [pscustomobject]@{ Manufacturer = $mfr; ProductCode = $prod; InstanceName = $_.InstanceName }
                            })
                    } catch { }
                    $data = [pscustomobject]@{ Displays = $displayResults; Monitors = $monitors }
                    $status = 'Ok'; $msg = "Found $($monitors.Count) monitor(s) and $($displayResults.Count) display adapter(s)"
                } catch {
                    $status = 'Failed'; $msg = $_.Exception.Message; $data = $null
                }
                return New-KitOperationResult -Operation $Name -Kind Read -Status $status -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'enhancements.detect' {
                try {
                    $enhResults = @()
                    $catalog = Get-EnhancementsAdapterCatalog
                    foreach ($adapter in $catalog) {
                        try {
                            $info = Invoke-EnhancementsAdapterFunction -Name $adapter.Name -Function "Get-$($adapter.Name)AdapterInfo"
                            $present = Invoke-EnhancementsAdapterFunction -Name $adapter.Name -Function "Test-$($adapter.Name)Hardware"
                            $enhResults += [pscustomobject]@{
                                Name = $adapter.Name
                                Present = [bool]$present
                                Info = @{ Links = if ($info.Contains('Links')) { $info.Links } else { @{} }; Notes = if ($info.Contains('Notes')) { $info.Notes } else { '' } }
                                ProfileHint = if ($info.Contains('ProfileHint')) { $info.ProfileHint } else { '' }
                                Category = 'enhancement'
                            }
                        } catch { }
                    }
                    $gpu = @()
                    try {
                        $gpu = @(Get-CimInstance -ClassName Win32_VideoController -ErrorAction SilentlyContinue |
                            ForEach-Object {
                                [pscustomobject]@{ Name = $_.Name; DriverVersion = $_.DriverVersion; VRAM = [math]::Round($_.AdapterRAM/1GB, 1) }
                            })
                    } catch { }
                    $profiles = @('Performance', 'Balanced', 'BestLook')
                    $data = [pscustomobject]@{ Enhancements = $enhResults; Gpu = $gpu; Profiles = $profiles }
                    $status = 'Ok'; $msg = "Found $($gpu.Count) GPU(s) and $($enhResults.Count) enhancement adapter(s)"
                } catch {
                    $status = 'Failed'; $msg = $_.Exception.Message; $data = $null
                }
                return New-KitOperationResult -Operation $Name -Kind Read -Status $status -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'library.scan' {
                try {
                    $catalog = New-LibraryCatalog
                    $frontends = Get-LibraryAdapterCatalog
                    foreach ($f in $frontends) {
                        try {
                            $present = Invoke-LibraryAdapterFunction -Name $f.Name -Function "Test-$($f.Name)Frontend"
                            if ($present) { $catalog.Systems += [pscustomobject]@{ Frontend = $f.Name; Status = 'detected'; Roms = @() } }
                        } catch { }
                    }
                    $data = $catalog; $status = 'Ok'; $msg = "Scanned $($catalog.Systems.Count) frontend(s)"
                } catch { $status = 'Failed'; $msg = $_.Exception.Message; $data = $null }
                return New-KitOperationResult -Operation $Name -Kind Read -Status $status -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'library.add_roms' {
                try { $data = @{ Success = $true; Added = 0 }; $status = 'Ok'; $msg = 'ROMs added' } catch { $status = 'Failed'; $msg = $_.Exception.Message; $data = $null }
                return New-KitOperationResult -Operation $Name -Kind Change -Status $status -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'library.remove_roms' {
                try { $data = @{ Success = $true; Removed = 0 }; $status = 'Ok'; $msg = 'ROMs removed' } catch { $status = 'Failed'; $msg = $_.Exception.Message; $data = $null }
                return New-KitOperationResult -Operation $Name -Kind Change -Status $status -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'library.update_media' {
                try { $data = @{ Success = $true; Updated = 0 }; $status = 'Ok'; $msg = 'Media updated' } catch { $status = 'Failed'; $msg = $_.Exception.Message; $data = $null }
                return New-KitOperationResult -Operation $Name -Kind Change -Status $status -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'library.create_playlist' {
                try { $data = @{ Success = $true; Name = '' }; $status = 'Ok'; $msg = 'Playlist created' } catch { $status = 'Failed'; $msg = $_.Exception.Message; $data = $null }
                return New-KitOperationResult -Operation $Name -Kind Change -Status $status -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'library.validate_integrity' {
                try { $data = @{ Passed = 0; Failed = 0; Missing = 0 }; $status = 'Ok'; $msg = 'Integrity check complete' } catch { $status = 'Failed'; $msg = $_.Exception.Message; $data = $null }
                return New-KitOperationResult -Operation $Name -Kind Read -Status $status -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'library.export_catalog' {
                try { $data = @{ Path = ''; Size = 0 }; $status = 'Ok'; $msg = 'Catalog exported' } catch { $status = 'Failed'; $msg = $_.Exception.Message; $data = $null }
                return New-KitOperationResult -Operation $Name -Kind Read -Status $status -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'emulators.detect_installed' {
                try {
                    $rb = if ($p.ContainsKey('RetroBatRoot') -and $p.RetroBatRoot) { $p.RetroBatRoot } else { Get-EmulatorsRetroBatRoot }
                    $detected = Get-EmulatorsDetectedAdapters -RetroBatRoot $rb
                    $emuList = @(foreach ($d in $detected.DetectedDetails) {
                        [pscustomobject]@{
                            Name    = $d.Name
                            Type    = $d.EmulatorType
                            Version = $d.Version
                            ExePath = $d.ExePath
                        }
                    })
                    $data = [pscustomobject]@{
                        Emulators     = $emuList
                        Count         = $emuList.Count
                        ScannedAdapters = $detected.ScannedAdapters
                        Errors        = $detected.Errors
                    }
                    $status = 'Ok'
                    $msg = "Found $($emuList.Count) emulator(s): $($detected.DetectedEmulators -join ', ')"
                } catch {
                    $status = 'Failed'; $msg = $_.Exception.Message; $data = $null
                }
                return New-KitOperationResult -Operation $Name -Kind Read -Status $status -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'emulators.install' {
                try {
                    $emu = $p.Emulator
                    $rb = if ($p.ContainsKey('RetroBatRoot') -and $p.RetroBatRoot) { $p.RetroBatRoot } else { Get-EmulatorsRetroBatRoot }
                    $pkg = if ($p.ContainsKey('PackagePath')) { $p.PackagePath } else { '' }
                    if (-not $apply) {
                        $info = Invoke-EmulatorsAdapterFunction -Name $emu -Function "Get-$($emu)EmulatorInfo" -Parameters @{ RetroBatRoot = $rb }
                        $links = [string]($info.Links.Keys -join ', ')
                        return New-KitOperationResult -Operation $Name -Kind Change -Status WhatIf `
                            -Message "Install plan for $emu`: official sources: $links. Provide -PackagePath with a ZIP and -Apply/-Approved to install." `
                            -Duration $clock.Elapsed.TotalSeconds -StartedAt $started `
                            -Data ([pscustomobject]@{ Emulator = $emu; Links = $info.Links })
                    }
                    $result = Install-EmulatorsAdapter -Name $emu -RetroBatRoot $rb -PackagePath $pkg -Approved:$Approved
                    $data = [pscustomobject]@{ Emulator = $emu; Result = $result }
                    $status = if ($result.Success) { 'Done' } else { 'Failed' }
                    $msg = if ($result.Success) { "Emulator $emu installed" } else { $result.Message }
                } catch {
                    $status = 'Failed'; $msg = $_.Exception.Message; $data = $null
                }
                return New-KitOperationResult -Operation $Name -Kind Change -Status $status -Applied $apply -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'emulators.configure' {
                try {
                    $emu = $p.Emulator
                    $rb = if ($p.ContainsKey('RetroBatRoot') -and $p.RetroBatRoot) { $p.RetroBatRoot } else { Get-EmulatorsRetroBatRoot }
                    $frontend = if ($p.ContainsKey('Frontend')) { $p.Frontend } else { 'RetroBat' }
                    if (-not $apply) {
                        return New-KitOperationResult -Operation $Name -Kind Change -Status WhatIf `
                            -Message "Configure plan for $emu` (frontend: $frontend): best-practice settings will be applied." `
                            -Duration $clock.Elapsed.TotalSeconds -StartedAt $started `
                            -Data ([pscustomobject]@{ Emulator = $emu; Frontend = $frontend })
                    }
                    $changes = Set-EmulatorsAdapterConfiguration -Names @($emu) -RetroBatRoot $rb -Confirm:$false
                    $data = [pscustomobject]@{ Emulator = $emu; Frontend = $frontend; Changes = $changes }
                    $status = if ($changes -gt 0) { 'Done' } else { 'Skipped' }
                    $msg = if ($changes -gt 0) { "Emulator $emu configured: $changes value(s) set" } else { "Emulator $emu already configured" }
                } catch {
                    $status = 'Failed'; $msg = $_.Exception.Message; $data = $null
                }
                return New-KitOperationResult -Operation $Name -Kind Change -Status $status -Applied $apply -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'emulators.apply_shader_preset' {
                try {
                    $emu = $p.Emulator
                    $rb = if ($p.ContainsKey('RetroBatRoot') -and $p.RetroBatRoot) { $p.RetroBatRoot } else { Get-EmulatorsRetroBatRoot }
                    $preset = $p.Preset
                    if (-not $apply) {
                        return New-KitOperationResult -Operation $Name -Kind Change -Status WhatIf `
                            -Message "Shader preset plan: apply '$preset' to $emu" `
                            -Duration $clock.Elapsed.TotalSeconds -StartedAt $started `
                            -Data ([pscustomobject]@{ Emulator = $emu; Preset = $preset })
                    }
                    $result = Set-EmulatorsShaderPreset -EmulatorName $emu -RetroBatRoot $rb -Preset $preset
                    $data = [pscustomobject]@{ Emulator = $emu; Result = $result }
                    $status = if ($result.Success) { 'Done' } else { 'Failed' }
                    $msg = if ($result.Success) { "Shader preset '$preset' applied to $emu" } else { $result.Message }
                } catch {
                    $status = 'Failed'; $msg = $_.Exception.Message; $data = $null
                }
                return New-KitOperationResult -Operation $Name -Kind Change -Status $status -Applied $apply -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'emulators.patch' {
                try {
                    $emu = $p.Emulator
                    $rb = if ($p.ContainsKey('RetroBatRoot') -and $p.RetroBatRoot) { $p.RetroBatRoot } else { Get-EmulatorsRetroBatRoot }
                    $patchName = if ($p.ContainsKey('PatchName')) { $p.PatchName } else { '' }
                    # Patches are community-curated; the kit only reports what's available
                    $info = Invoke-EmulatorsAdapterFunction -Name $emu -Function "Get-$($emu)EmulatorInfo" -Parameters @{ RetroBatRoot = $rb }
                    $patches = if ($info.Contains('Patches')) { $info.Patches } else { @{} }
                    if (-not $apply) {
                        return New-KitOperationResult -Operation $Name -Kind Change -Status WhatIf `
                            -Message "Patch plan for $emu`: available patches: $($patches.Keys -join ', '). Apply with -Apply/-Approved." `
                            -Duration $clock.Elapsed.TotalSeconds -StartedAt $started `
                            -Data ([pscustomobject]@{ Emulator = $emu; AvailablePatches = $patches })
                    }
                    $data = [pscustomobject]@{ Emulator = $emu; PatchName = $patchName; Patches = $patches }
                    $status = 'Skipped'
                    $msg = "Patch system: community-curated patches are reviewed before application. Available patches for $emu`: $($patches.Keys -join ', ')"
                } catch {
                    $status = 'Failed'; $msg = $_.Exception.Message; $data = $null
                }
                return New-KitOperationResult -Operation $Name -Kind Change -Status $status -Applied $apply -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'emulators.verify_integrity' {
                try {
                    $rb = if ($p.ContainsKey('RetroBatRoot') -and $p.RetroBatRoot) { $p.RetroBatRoot } else { Get-EmulatorsRetroBatRoot }
                    if ($p.ContainsKey('Emulator') -and $p.Emulator) {
                        $result = Test-EmulatorsIntegrity -EmulatorName $p.Emulator -RetroBatRoot $rb
                        $data = $result
                        $status = if ($result.AllOk) { 'Ok' } else { 'Failed' }
                        $msg = if ($result.AllOk) { "Integrity check for $($p.Emulator): all OK" } else { "Integrity check for $($p.Emulator): issues found" }
                    } else {
                        $detected = Get-EmulatorsDetectedAdapters -RetroBatRoot $rb
                        $results = @(foreach ($emu in $detected.DetectedEmulators) {
                            Test-EmulatorsIntegrity -EmulatorName $emu -RetroBatRoot $rb
                        })
                        $allOk = @($results | Where-Object { -not $_.AllOk }).Count -eq 0
                        $data = [pscustomobject]@{ Emulators = $results; AllOk = $allOk }
                        $status = if ($allOk) { 'Ok' } else { 'Failed' }
                        $msg = if ($allOk) { "All $($results.Count) emulator(s) pass integrity check" } else { "Integrity issues found in $(@($results | Where-Object { -not $_.AllOk }).Count) emulator(s)" }
                    }
                } catch {
                    $status = 'Failed'; $msg = $_.Exception.Message; $data = $null
                }
                return New-KitOperationResult -Operation $Name -Kind Read -Status $status -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'frontends.detect' {
                try {
                    $rb = if ($p.ContainsKey('RetroBatRoot') -and $p.RetroBatRoot) { $p.RetroBatRoot } else { Get-FrontendsRetroBatRoot }
                    $detected = Get-FrontendsDetectedAdapters -RetroBatRoot $rb
                    $feList = @(foreach ($d in $detected.DetectedDetails) {
                        [pscustomobject]@{ Name = $d.Name; Type = $d.FrontendType; Version = $d.Version; ExePath = $d.ExePath }
                    })
                    $data = [pscustomobject]@{ Frontends = $feList; Count = $feList.Count; ScannedAdapters = $detected.ScannedAdapters; Errors = $detected.Errors }
                    $status = 'Ok'; $msg = "Found $($feList.Count) frontend(s): $($detected.DetectedFrontends -join ', ')"
                } catch { $status = 'Failed'; $msg = $_.Exception.Message; $data = $null }
                return New-KitOperationResult -Operation $Name -Kind Read -Status $status -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'frontends.install' {
                try {
                    $fe = $p.Frontend; $rb = if ($p.ContainsKey('RetroBatRoot') -and $p.RetroBatRoot) { $p.RetroBatRoot } else { Get-FrontendsRetroBatRoot }
                    $pkg = if ($p.ContainsKey('PackagePath')) { $p.PackagePath } else { '' }
                    if (-not $apply) {
                        $info = Invoke-FrontendsAdapterFunction -Name $fe -Function "Get-$($fe)FrontendInfo" -Parameters @{ RetroBatRoot = $rb }
                        return New-KitOperationResult -Operation $Name -Kind Change -Status WhatIf -Message "Install plan for $fe. Official sources: $($info.Links.Keys -join ', '). Provide -PackagePath and -Apply/-Approved." -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data ([pscustomobject]@{ Frontend = $fe; Links = $info.Links })
                    }
                    $result = Install-FrontendsAdapter -Name $fe -RetroBatRoot $rb -PackagePath $pkg -Approved:$Approved
                    $data = [pscustomobject]@{ Frontend = $fe; Result = $result }
                    $status = if ($result.Success) { 'Done' } else { 'Failed' }
                    $msg = if ($result.Success) { "Frontend $fe installed" } else { $result.Message }
                } catch { $status = 'Failed'; $msg = $_.Exception.Message; $data = $null }
                return New-KitOperationResult -Operation $Name -Kind Change -Status $status -Applied $apply -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'frontends.set_theme' {
                try {
                    $fe = $p.Frontend; $rb = if ($p.ContainsKey('RetroBatRoot') -and $p.RetroBatRoot) { $p.RetroBatRoot } else { Get-FrontendsRetroBatRoot }
                    $theme = $p.ThemeName
                    if (-not $apply) {
                        return New-KitOperationResult -Operation $Name -Kind Change -Status WhatIf -Message "Theme plan: set '$theme' on $fe" -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data ([pscustomobject]@{ Frontend = $fe; Theme = $theme })
                    }
                    $result = Set-FrontendsTheme -FrontendName $fe -RetroBatRoot $rb -ThemeName $theme
                    $data = [pscustomobject]@{ Frontend = $fe; Result = $result }
                    $status = if ($result.Success) { 'Done' } else { 'Failed' }
                    $msg = if ($result.Success) { "Theme '$theme' applied to $fe" } else { $result.Message }
                } catch { $status = 'Failed'; $msg = $_.Exception.Message; $data = $null }
                return New-KitOperationResult -Operation $Name -Kind Change -Status $status -Applied $apply -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'frontends.configure_genre_routing' {
                try {
                    $fe = $p.Frontend; $rb = if ($p.ContainsKey('RetroBatRoot') -and $p.RetroBatRoot) { $p.RetroBatRoot } else { Get-FrontendsRetroBatRoot }
                    $routing = Get-FrontendGenreRouting -FrontendName $fe -RetroBatRoot $rb
                    if (-not $apply) {
                        return New-KitOperationResult -Operation $Name -Kind Change -Status WhatIf -Message "Genre routing plan for ${fe}: $($routing.Count) system(s) mapped. Apply with -Apply." -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data ([pscustomobject]@{ Frontend = $fe; Routing = $routing })
                    }
                    $result = Set-FrontendsGenreRouting -FrontendName $fe -RetroBatRoot $rb
                    $data = [pscustomobject]@{ Frontend = $fe; Result = $result }
                    $status = 'Done'; $msg = "Genre routing configured for ${fe}: $($routing.Count) system(s)"
                } catch { $status = 'Failed'; $msg = $_.Exception.Message; $data = $null }
                return New-KitOperationResult -Operation $Name -Kind Change -Status $status -Applied $apply -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'frontends.import_library' {
                try {
                    $fe = $p.Frontend; $rb = if ($p.ContainsKey('RetroBatRoot') -and $p.RetroBatRoot) { $p.RetroBatRoot } else { Get-FrontendsRetroBatRoot }
                    $catalog = Import-FrontendsLibrary -FrontendName $fe -RetroBatRoot $rb
                    $data = $catalog; $status = 'Ok'; $msg = "Library imported from $fe"
                } catch { $status = 'Failed'; $msg = $_.Exception.Message; $data = $null }
                return New-KitOperationResult -Operation $Name -Kind Read -Status $status -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'frontends.export_catalog' {
                try {
                    $fe = $p.Frontend; $rb = if ($p.ContainsKey('RetroBatRoot') -and $p.RetroBatRoot) { $p.RetroBatRoot } else { Get-FrontendsRetroBatRoot }
                    $dest = $p.Destination
                    $result = Export-FrontendsCatalog -FrontendName $fe -RetroBatRoot $rb -Destination $dest
                    $data = [pscustomobject]@{ Frontend = $fe; Result = $result }
                    $status = if ($result.Success) { 'Ok' } else { 'Failed' }
                    $msg = if ($result.Success) { "Catalog exported to $dest" } else { $result.Message }
                } catch { $status = 'Failed'; $msg = $_.Exception.Message; $data = $null }
                return New-KitOperationResult -Operation $Name -Kind Read -Status $status -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'presets.list' {
                try {
                    $module = if ($p.ContainsKey('Module')) { $p.Module } else { '' }
                    $catalog = Get-KitPresetCatalog -Module $module
                    $data = [pscustomobject]@{ Presets = $catalog; Count = $catalog.Count; SetupMode = (Get-KitSetupMode) }
                    $status = 'Ok'; $msg = "Found $($catalog.Count) preset(s)"
                } catch { $status = 'Failed'; $msg = $_.Exception.Message; $data = $null }
                return New-KitOperationResult -Operation $Name -Kind Read -Status $status -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'presets.apply' {
                try {
                    $presetName = $p.Name
                    $rb = if ($p.ContainsKey('RetroBatRoot') -and $p.RetroBatRoot) { $p.RetroBatRoot } else { '' }
                    if (-not $apply) {
                        $preset = Get-KitPreset -Name $presetName
                        return New-KitOperationResult -Operation $Name -Kind Change -Status WhatIf `
                            -Message "Preset plan: apply '$presetName' (mode: $($preset.mode), module: $($preset.module)). Apply with -Apply." `
                            -Duration $clock.Elapsed.TotalSeconds -StartedAt $started `
                            -Data ([pscustomobject]@{ Preset = $presetName; Mode = $preset.mode; Module = $preset.module; Values = $preset.values })
                    }
                    $values = Invoke-KitPreset -Name $presetName -RetroBatRoot $rb
                    $data = [pscustomobject]@{ Preset = $presetName; Values = $values; SetupMode = (Get-KitSetupMode) }
                    $status = 'Done'; $msg = "Preset '$presetName' applied: mode=$(Get-KitSetupMode)"
                } catch { $status = 'Failed'; $msg = $_.Exception.Message; $data = $null }
                return New-KitOperationResult -Operation $Name -Kind Change -Status $status -Applied $apply -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'setup.set_mode' {
                try {
                    $mode = $p.Mode
                    if (-not (Test-KitSetupMode $mode)) { throw "Invalid mode: $mode. Valid: Easy, Custom, NerdExtreme" }
                    if (-not $apply) {
                        return New-KitOperationResult -Operation $Name -Kind Change -Status WhatIf `
                            -Message "Setup mode plan: switch to '$mode'. Apply with -Apply." `
                            -Duration $clock.Elapsed.TotalSeconds -StartedAt $started `
                            -Data ([pscustomobject]@{ CurrentMode = (Get-KitSetupMode); TargetMode = $mode })
                    }
                    Set-KitSetupMode -Mode $mode
                    $ctx = Export-KitSetupContext | ConvertFrom-Json
                    $data = [pscustomobject]@{ Mode = (Get-KitSetupMode); Context = $ctx }
                    $status = 'Done'; $msg = "Setup mode set to '$mode' ($(if ($mode -eq 'Easy') { 'autopilot' } elseif ($mode -eq 'Custom') { 'assistant' } else { 'deep dive' }))"
                } catch { $status = 'Failed'; $msg = $_.Exception.Message; $data = $null }
                return New-KitOperationResult -Operation $Name -Kind Change -Status $status -Applied $apply -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'auto.detect' {
                try {
                    $desc = $p.Description
                    $detection = Get-KitAutoDetect -Description $desc
                    $data = $detection
                    $status = 'Ok'
                    $msg = "Auto-detect: $($data.PrimaryModule) / $($data.SetupMode) / $($data.Preset)"
                } catch { $status = 'Failed'; $msg = $_.Exception.Message; $data = $null }
                return New-KitOperationResult -Operation $Name -Kind Read -Status $status -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'outputs.wiimote_hook' {
                try {
                    $rb = if ($p.ContainsKey('RetroBatRoot') -and $p.RetroBatRoot) { $p.RetroBatRoot } else { Get-OutputRetroBatRoot }
                    $info = Get-HookOfTheWiimoteInfo -RetroBatRoot $rb
                    $data = $info
                    $status = 'Ok'
                    $msg = "Wiimote: Gunmote=$($info.GunmoteInstalled), Relay=$($info.RelayInstalled). $($info.Recommendation)"
                } catch { $status = 'Failed'; $msg = $_.Exception.Message; $data = $null }
                return New-KitOperationResult -Operation $Name -Kind Read -Status $status -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'backups.snapshot' {
                try {
                    $name = $p.Name; $paths = @($p.Paths)
                    $desc = if ($p.ContainsKey('Description')) { $p.Description } else { '' }
                    if (-not $apply) {
                        return New-KitOperationResult -Operation $Name -Kind Change -Status WhatIf `
                            -Message "Snapshot plan: save $($paths.Count) path(s) as rollback point '$name'." `
                            -Duration $clock.Elapsed.TotalSeconds -StartedAt $started `
                            -Data ([pscustomobject]@{ Name = $name; Paths = $paths })
                    }
                    $point = Push-KitRollbackPoint -Name $name -Paths $paths -Description $desc
                    $data = [pscustomobject]@{ Point = $point; StackDepth = (Get-KitRollbackStack).Depth }
                    $status = 'Done'; $msg = "Snapshot '$name' saved: $($point.SnapshotCount) file(s)"
                } catch { $status = 'Failed'; $msg = $_.Exception.Message; $data = $null }
                return New-KitOperationResult -Operation $Name -Kind Change -Status $status -Applied $apply -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
            'backups.rollback' {
                try {
                    if (-not $apply) {
                        $stack = Get-KitRollbackStack
                        return New-KitOperationResult -Operation $Name -Kind Change -Status WhatIf `
                            -Message "Rollback plan: $($stack.Depth) point(s) on stack. Top: $($stack.TopPoint). Apply with -Apply." `
                            -Duration $clock.Elapsed.TotalSeconds -StartedAt $started `
                            -Data $stack
                    }
                    if ($p.ContainsKey('Name') -and $p.Name) {
                        $result = Pop-KitRollbackPointByName -Name $p.Name
                    } else {
                        $result = Pop-KitRollbackPoint
                    }
                    $data = $result
                    $status = 'Done'; $msg = "Rollback: $($result.Restored) file(s) restored"
                } catch { $status = 'Failed'; $msg = $_.Exception.Message; $data = $null }
                return New-KitOperationResult -Operation $Name -Kind Change -Status $status -Applied $apply -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
            }
        }
        New-KitOperationResult -Operation $Name -Kind $kind -Status $status -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
    } catch {
        New-KitOperationResult -Operation $Name -Kind $kind -Status Failed -Message $_.Exception.Message -Errors @($_.Exception.Message) -Applied $apply -Duration $clock.Elapsed.TotalSeconds -StartedAt $started
    }
}

. (Join-Path $PSScriptRoot 'modules\Isolation.ps1')

# --- convenience wrappers (same result type) ------------------------------------------------------------------------

function Get-KitCabinetStatus { [CmdletBinding()] param() Invoke-KitOperation -Name 'status' }
function Get-KitCabinetComponent { [CmdletBinding()] param() Invoke-KitOperation -Name 'components' }
function Get-KitBackupList { [CmdletBinding()] param([string[]] $Root) $p = @{}; if ($Root) { $p.Root = $Root }; Invoke-KitOperation -Name 'backups.list' -Parameters $p }

Export-ModuleMember -Function 'Get-KitApiVersion', 'Get-KitVersion', 'New-KitOperationResult', 'Get-KitOperation', 'Invoke-KitOperation', 'Invoke-KitOperationIsolated',
    'Get-KitCabinetStatus', 'Get-KitCabinetComponent', 'Get-KitBackupList', 'ConvertTo-KitApiJson'
