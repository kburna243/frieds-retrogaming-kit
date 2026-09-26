#Requires -Version 5.1
# Kit API v1 (see API.md): one facade for every client. Operations return RetroCabinetKit.OperationResult;
# change operations run as dry run unless -Apply; approvals are declined unless -Approved; only plain parameters
# are accepted. No kit logic lives here: every handler calls the engine modules.

Set-StrictMode -Version 2.0

$script:ApiVersion = '1.0'
$script:ApiDir     = $PSScriptRoot
$script:KitRoot    = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $script:KitRoot 'core\RetroCabinetKit.Core.psd1')
Import-Module (Join-Path $script:KitRoot 'pinball\RetroCabinetKit.Pinball.psd1')
Import-Module (Join-Path $script:KitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1')

# Parameters a client may never set (security bindings, test injection, values the API controls itself).
$script:ApiDeniedParameters = @('StatePath', 'Culture', 'KitUserSid', 'TrustedOwner', 'TaskPrefix', 'AutomationDir',
    'LayersKey', 'RegistryRoots', 'AppCompatRoots', 'AnswerFile', 'WhatIf', 'Confirm')
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

function New-KitOperationResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Operation,
        [ValidateSet('Read', 'Change')] [string] $Kind = 'Read',
        [Parameter(Mandatory)] [ValidateSet('Ok', 'Done', 'Skipped', 'WhatIf', 'NeedsUser', 'Failed', 'NotAvailable')] [string] $Status,
        [string] $Message = '',
        [bool] $Applied = $false,
        [string[]] $Warnings = @(),
        [string[]] $Errors = @(),
        [object[]] $Changes = @(),
        [string[]] $Backups = @(),
        [string[]] $Approvals = @(),
        [double] $Duration = 0,
        [datetime] $StartedAt = (Get-Date),
        [object] $Data = $null
    )
    [pscustomobject]@{
        PSTypeName = 'RetroCabinetKit.OperationResult'
        ApiVersion = $script:ApiVersion
        Operation  = $Operation
        Kind       = $Kind
        Success    = $Status -in 'Ok', 'Done', 'Skipped', 'WhatIf'
        Status     = $Status
        Applied    = $Applied
        Message    = $Message
        Warnings   = @($Warnings | Where-Object { $_ })
        Errors     = @($Errors | Where-Object { $_ })
        Changes    = @($Changes | Where-Object { $_ })
        Backups    = @($Backups | Where-Object { $_ })
        Approvals  = @($Approvals | Where-Object { $_ })
        Duration   = [math]::Round($Duration, 3)
        StartedAt  = $StartedAt.ToString('o')
        Data       = $Data
    }
}

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
        @{ Name = 'operations'; Kind = 'Read'; Description = 'This catalog.'; Parameters = @() }
        @{ Name = 'status'; Kind = 'Read'; Description = 'Health check of system, pinball, lightgun and security (doctor).'; Parameters = @() }
        @{ Name = 'components'; Kind = 'Read'; Description = 'Detected components: Windows, RetroBat, Gunmote, ViGEmBus, DolphinBar, Steam, pinball build.'; Parameters = @() }
        @{ Name = 'backups.list'; Kind = 'Read'; Description = 'The kit''s backups, newest first.'; Parameters = @([pscustomobject]@{ Name = 'Root'; Type = 'String[]'; Mandatory = $false }) }
        @{ Name = 'backup.check'; Kind = 'Read'; Description = 'Checks a backup against its checksums (zip) or its original (file copy).'; Parameters = @([pscustomobject]@{ Name = 'Path'; Type = 'String'; Mandatory = $true }) }
        @{ Name = 'backup.restore'; Kind = 'Change'; Description = 'Restores a backup; the current file is saved first. Zip backups need AllowedRoot.'; Parameters = @([pscustomobject]@{ Name = 'Path'; Type = 'String'; Mandatory = $true }, [pscustomobject]@{ Name = 'AllowedRoot'; Type = 'String[]'; Mandatory = $false }) }
        @{ Name = 'backup.remove'; Kind = 'Change'; Description = 'Deletes one backup of the kit (nothing else can be deleted).'; Parameters = @([pscustomobject]@{ Name = 'Path'; Type = 'String'; Mandatory = $true }) }
        @{ Name = 'backup.export'; Kind = 'Change'; Description = 'Copies a backup to a folder and records its SHA-256.'; Parameters = @([pscustomobject]@{ Name = 'Path'; Type = 'String'; Mandatory = $true }, [pscustomobject]@{ Name = 'Destination'; Type = 'String'; Mandatory = $true }) }
        @{ Name = 'support.bundle'; Kind = 'Change'; Description = 'Writes an anonymized support bundle (doctor, environment, step states, logs).'; Parameters = @([pscustomobject]@{ Name = 'Destination'; Type = 'String'; Mandatory = $false }) }
    )
    foreach ($o in $fixed) {
        [pscustomobject]@{ Name = $o.Name; Kind = $o.Kind; Suite = ''; Interactive = $false; Available = $true; Description = $o.Description; Parameters = $o.Parameters }
    }
    foreach ($s in Get-KitApiStep) {
        [pscustomobject]@{ Name = $s.Name; Kind = 'Change'; Suite = $s.Suite; Interactive = $s.Interactive; Available = -not $s.Interactive; Description = $s.Description; Parameters = $s.Parameters }
    }
    foreach ($p in @(@{ Name = 'profile.export'; Command = 'Export-KitCabinetProfile' }, @{ Name = 'profile.import'; Command = 'Import-KitCabinetProfile' })) {
        $cmd = Get-Command -Name $p.Command -ErrorAction SilentlyContinue
        [pscustomobject]@{
            Name = $p.Name; Kind = 'Change'; Suite = ''; Interactive = $false; Available = [bool]$cmd
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
    try {
        $root = if (Test-Path -LiteralPath $PinballStatePath) { [string](Get-KitStateValue -Path $PinballStatePath -Key 'TargetRoot') } else { '' }
        $problem = if ($root) { Get-PinballRootProblem -Root $root } else { '' }
        Add-Row 'PinballBuild' ($root -and -not $problem) '' $root $problem
    } catch { Add-Row 'PinballBuild' $false '' '' $_.Exception.Message }
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
        $key = if ($op.Interactive) { 'Api.Interactive' } else { 'Api.NotAvailable' }
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
            'components' { $data = [pscustomobject]@{ Components = @(Get-KitApiComponent -PinballStatePath $PinballStatePath -LightgunStatePath $LightgunStatePath) }; $status = 'Ok'; $msg = '' }
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
                if ($apply) { Assert-PinballProcessesClosed; Assert-LightgunProcessesClosed }
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
                $call = @{} + $p
                if ((Get-Command -Name $cmd).Parameters.ContainsKey('WhatIf') -and -not $apply) { $call.WhatIf = $true }
                $out = @(& $cmd @call 6>$null)
                $stepResults = @($out | Where-Object { $_ -and $_.PSObject.TypeNames -contains 'RetroCabinetKit.StepResult' })
                $st = if ($stepResults.Count) { Get-WorstStatus @($stepResults | ForEach-Object { if ($_.WhatIf) { 'WhatIf' } else { $_.Status } }) } elseif ($apply -or $Name -eq 'profile.export') { 'Done' } else { 'WhatIf' }
                return New-KitOperationResult -Operation $Name -Kind Change -Status $st -Applied $apply -Message '' `
                    -Changes @($stepResults | ForEach-Object { $_.Changes }) -Backups @($stepResults | ForEach-Object { $_.Backups }) `
                    -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data ([pscustomobject]@{ Result = $out })
            }
        }
        New-KitOperationResult -Operation $Name -Kind $kind -Status $status -Message $msg -Duration $clock.Elapsed.TotalSeconds -StartedAt $started -Data $data
    } catch {
        New-KitOperationResult -Operation $Name -Kind $kind -Status Failed -Message $_.Exception.Message -Errors @($_.Exception.Message) -Applied $apply -Duration $clock.Elapsed.TotalSeconds -StartedAt $started
    }
}

# Runs one operation in its own PowerShell instance without a console host: "What if:" lines and host output of
# the engine go nowhere, only the result object comes back (same process, live objects). For every client that
# owns standard output (the JSON command, the MCP server).
function Invoke-KitOperationIsolated {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [hashtable] $Parameters = @{},
        [switch] $Apply,
        [switch] $Approved,
        [string] $Culture = (Get-KitCulture)
    )
    $ps = [PowerShell]::Create()
    try {
        $null = $ps.AddScript({
            param($KitRoot, $Culture, $Name, $Parameters, $Apply, $Approved)
            Import-Module (Join-Path $KitRoot 'core\RetroCabinetKit.Core.psd1')
            Import-Module (Join-Path $KitRoot 'api\RetroCabinetKit.Api.psd1')
            Set-KitCulture -Culture $Culture
            Invoke-KitOperation -Name $Name -Parameters $Parameters -Apply:$Apply -Approved:$Approved
        }).AddArgument($script:KitRoot).AddArgument($Culture).AddArgument($Name).AddArgument($Parameters).AddArgument([bool]$Apply).AddArgument([bool]$Approved)
        $result = @($ps.Invoke() | Where-Object { $_ -and $_.PSObject.TypeNames -contains 'RetroCabinetKit.OperationResult' }) | Select-Object -Last 1
        if (-not $result) {
            $why = @($ps.Streams.Error | ForEach-Object { $_.Exception.Message }) -join ' '
            $result = New-KitOperationResult -Operation $Name -Status Failed -Message "No result. $why" -Errors @($why)
        }
        $result
    } finally { $ps.Dispose() }
}

# --- convenience wrappers (same result type) ------------------------------------------------------------------------

function Get-KitCabinetStatus { [CmdletBinding()] param() Invoke-KitOperation -Name 'status' }
function Get-KitCabinetComponent { [CmdletBinding()] param() Invoke-KitOperation -Name 'components' }
function Get-KitBackupList { [CmdletBinding()] param([string[]] $Root) $p = @{}; if ($Root) { $p.Root = $Root }; Invoke-KitOperation -Name 'backups.list' -Parameters $p }

# Every string inside a result, anonymized (same rules as the support bundle); names and structure stay.
function ConvertTo-AnonymousValue($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) { return (ConvertTo-KitSupportText -Text $Value) }
    if ($Value -is [ValueType]) { return $Value }
    if ($Value -is [Collections.IEnumerable] -and $Value -isnot [Collections.IDictionary]) { return ,@($Value | ForEach-Object { ConvertTo-AnonymousValue $_ }) }
    $copy = [ordered]@{}
    if ($Value -is [Collections.IDictionary]) { foreach ($k in $Value.Keys) { $copy[[string]$k] = ConvertTo-AnonymousValue $Value[$k] } }
    else { foreach ($prop in $Value.PSObject.Properties) { $copy[$prop.Name] = ConvertTo-AnonymousValue $prop.Value } }
    [pscustomobject]$copy
}

# JSON for other processes. -Anonymize for anything that leaves this PC (e.g. to a cloud model).
function ConvertTo-KitApiJson {
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)] [psobject] $Result, [switch] $Anonymize)
    process {
        # Through JSON once, so every value is plain data (no live .NET objects), then anonymized, then final JSON.
        $plain = ConvertTo-Json -InputObject $Result -Depth 10 | ConvertFrom-Json
        if ($Anonymize) { $plain = ConvertTo-AnonymousValue $plain }
        ConvertTo-Json -InputObject $plain -Depth 10 -Compress
    }
}

Export-ModuleMember -Function 'Get-KitApiVersion', 'New-KitOperationResult', 'Get-KitOperation', 'Invoke-KitOperation', 'Invoke-KitOperationIsolated',
    'Get-KitCabinetStatus', 'Get-KitCabinetComponent', 'Get-KitBackupList', 'ConvertTo-KitApiJson'
