# Step: every installer step is Test (precondition) -> Invoke (supports -WhatIf) -> Verify (mandatory).
# A step is only green ("Done") when Verify returns exactly $true after Invoke.
#   Verify already $true before Invoke -> Skipped (resume without redoing work)
#   Test not $true                      -> NeedsUser (Invoke is not run)
#   -WhatIf                             -> Skipped with WhatIf = $true; the state file is never written
#
# Structured result (for the wizards and any other front end, no output parsing): while a step runs, a context
# collects its log lines, the backups the core and the suites make (Add-KitStepBackup) and the changes they
# write (Add-KitStepChange). The result carries Duration, Changed, Changes, Backups, Warnings, Errors and Log.
# Outside a step both Add-* functions do nothing.

$script:KitStepContext = $null

function Test-IsTrue([scriptblock] $Block) {
    $last = & $Block | Select-Object -Last 1
    ($last -is [bool]) -and $last
}

function New-KitStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [scriptblock] $Test = { $true },
        [Parameter(Mandatory)] [scriptblock] $Invoke,
        [Parameter(Mandatory)] [scriptblock] $Verify
    )
    [pscustomobject]@{
        PSTypeName = 'RetroCabinetKit.Step'
        Name       = $Name
        Test       = $Test
        Invoke     = $Invoke
        Verify     = $Verify
    }
}

# Reported by the code that writes: File, Registry, Database, Task, Setting.
function Add-KitStepChange {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('File', 'Registry', 'Database', 'Task', 'Setting')] [string] $Kind,
        [Parameter(Mandatory)] [string] $Target,
        [string] $Detail = ''
    )
    if (-not $script:KitStepContext) { return }
    $script:KitStepContext.Changes.Add([pscustomobject]@{ Kind = $Kind; Target = $Target; Detail = $Detail })
}

# Reported right after a backup was written (zip of New-KitBackup or a <file>.bak_* copy).
function Add-KitStepBackup {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    if (-not $script:KitStepContext) { return }
    if (-not $script:KitStepContext.Backups.Contains($Path)) { $script:KitStepContext.Backups.Add($Path) }
}

# Log lines go into the running step's context too (called by Write-KitLog).
function Add-StepLogLine([string] $Level, [string] $Message) {
    if ($script:KitStepContext) { $script:KitStepContext.Log.Add([pscustomobject]@{ Level = $Level; Message = $Message }) }
}

function Invoke-KitStep {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [psobject] $Step,
        [string] $StatePath
    )
    process {
        $ErrorActionPreference = 'Stop'
        $status = $null; $whatIf = $false; $errorText = ''
        $outer = $script:KitStepContext
        $context = @{
            Log     = New-Object Collections.Generic.List[object]
            Changes = New-Object Collections.Generic.List[object]
            Backups = New-Object Collections.Generic.List[string]
        }
        $script:KitStepContext = $context
        $clock = [Diagnostics.Stopwatch]::StartNew()
        try {
            if (Test-IsTrue $Step.Verify) {
                $status = 'Skipped'
            } elseif (-not (Test-IsTrue $Step.Test)) {
                $status = 'NeedsUser'
            } elseif (-not $PSCmdlet.ShouldProcess($Step.Name, 'Invoke step')) {
                $status = 'Skipped'; $whatIf = $true
            } else {
                $null   = & $Step.Invoke
                $status = if (Test-IsTrue $Step.Verify) { 'Done' } else { 'Failed' }
            }
        } catch {
            $status = 'Failed'; $errorText = $_.Exception.Message
        }

        $key     = if ($whatIf) { 'Step.WhatIf' } else { "Step.$status" }
        $message = Get-KitText $key -f $Step.Name, $errorText
        $level   = @{ Skipped = 'Info'; Done = 'Info'; Failed = 'Error'; NeedsUser = 'Warn' }[$status]
        try { Write-KitLog $message -Level $level }
        finally {
            $clock.Stop()
            $script:KitStepContext = $outer # a step started inside a step gets its own context, then the outer one continues
        }

        # A dry run never changes the state, whatever the status (Skipped, NeedsUser) says.
        if ($StatePath -and -not $WhatIfPreference) {
            Set-KitStepStatus -Path $StatePath -Name $Step.Name -Status $status -Message $message
        }
        [pscustomobject]@{
            PSTypeName = 'RetroCabinetKit.StepResult'
            Name       = $Step.Name
            Status     = $status
            WhatIf     = $whatIf
            Message    = $message
            Error      = $errorText
            Duration   = $clock.Elapsed
            Changed    = [bool]($context.Changes.Count -or $context.Backups.Count)
            Changes    = $context.Changes.ToArray()
            Backups    = $context.Backups.ToArray()
            Warnings   = @($context.Log | Where-Object { $_.Level -eq 'Warn' } | ForEach-Object { $_.Message })
            Errors     = @($context.Log | Where-Object { $_.Level -eq 'Error' } | ForEach-Object { $_.Message })
            Log        = $context.Log.ToArray()
        }
    }
}
