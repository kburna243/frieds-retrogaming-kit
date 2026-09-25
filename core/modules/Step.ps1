# Step: every installer step is Test (precondition) -> Invoke (supports -WhatIf) -> Verify (mandatory).
# A step is only green ("Done") when Verify returns exactly $true after Invoke.
#   Verify already $true before Invoke -> Skipped (resume without redoing work)
#   Test not $true                      -> NeedsUser (Invoke is not run)
#   -WhatIf                             -> Skipped with WhatIf = $true, nothing persisted

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

function Invoke-KitStep {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [psobject] $Step,
        [string] $StatePath
    )
    process {
        $ErrorActionPreference = 'Stop'
        $status = $null; $whatIf = $false; $errorText = ''
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
        Write-KitLog $message -Level $level

        if ($StatePath -and -not $whatIf) {
            Set-KitStepStatus -Path $StatePath -Name $Step.Name -Status $status -Message $message
        }
        [pscustomobject]@{
            PSTypeName = 'RetroCabinetKit.StepResult'
            Name       = $Step.Name
            Status     = $status
            WhatIf     = $whatIf
            Message    = $message
            Error      = $errorText
        }
    }
}
