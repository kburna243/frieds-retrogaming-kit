# Transaction.ps1 -- Saga pattern for multi-step cabinet operations.
# Every successful step registers its own undo action on a LIFO stack.
# If any step fails, the stack unwinds in reverse order, restoring the exact pre-transaction state.
#
# Pattern:
#   Invoke-KitTransaction -TransactionName "Setup Lightgun" -Action {
#       Register-RollbackStep -Description "Restore INI" -RollbackAction { Restore-File ... }
#       Set-EmulatorsIniValue -Path $ini -Section "input" -Values @{ lightgun = 1 }
#       Register-RollbackStep -Description "Restore Registry" -RollbackAction { Set-ItemProperty ... }
#       Set-ItemProperty -Path $reg -Name "GunMode" -Value 1
#       # If anything throws here, both rollback steps execute in reverse order
#   }
#
# Keeps the cabinet consistent: either all steps succeed, or NONE are applied.

# Active transaction rollback stack (null when no transaction is running).
$script:CurrentRollbackStack = $null

# Wrap a multi-step operation in a transaction. All steps execute inside a try/catch.
# On failure, the rollback stack unwinds LIFO — every registered undo action runs.
function Invoke-KitTransaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $TransactionName,
        [Parameter(Mandatory)] [scriptblock] $Action
    )
    # Initialize a fresh LIFO stack for this transaction
    $stack = [Collections.Generic.Stack[object]]::new()
    $script:CurrentRollbackStack = $stack

    Write-KitLog "Transaction started: $TransactionName" -Level Info

    try {
        & $Action
        Write-KitLog "Transaction completed: $TransactionName" -Level Info
    } catch {
        $errorMsg = $_.Exception.Message
        Write-KitLog "Transaction FAILED: $TransactionName -- $errorMsg" -Level Error
        Write-KitLog "Initiating rollback for '$TransactionName' ($($stack.Count) step(s) to undo)..." -Level Warn

        $rolledBack = 0; $rollbackErrors = @()
        while ($stack.Count -gt 0) {
            $entry = $stack.Pop()
            try {
                & $entry.RollbackAction
                $rolledBack++
            } catch {
                $rollbackErrors += [pscustomobject]@{
                    Step        = $entry.Description
                    Error       = $_.Exception.Message
                }
                Write-KitLog "CRITICAL: Rollback step failed: $($entry.Description) -- $($_.Exception.Message)" -Level Error
            }
        }

        $result = [pscustomobject]@{
            Transaction    = $TransactionName
            Success        = $false
            Error          = $errorMsg
            RolledBack     = $rolledBack
            RollbackErrors = $rollbackErrors
        }

        if ($rollbackErrors.Count) {
            Write-KitLog "Rollback incomplete: $($rollbackErrors.Count) step(s) failed. Cabinet may be in an inconsistent state." -Level Error
        } else {
            Write-KitLog "Rollback complete: $rolledBack step(s) undone. Cabinet restored to pre-transaction state." -Level Info
        }

        throw "Transaction '$TransactionName' was rolled back due to: $errorMsg"
    } finally {
        $script:CurrentRollbackStack = $null
    }
}

# Register a rollback (undo) action for the current step.
# Must be called INSIDE an active Invoke-KitTransaction block.
function Register-RollbackStep {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [scriptblock] $RollbackAction,
        [string] $Description = 'Unnamed rollback step'
    )
    if ($null -eq $script:CurrentRollbackStack) {
        Write-KitLog "Cannot register rollback step '$Description': no active transaction. Wrap the operation in Invoke-KitTransaction." -Level Warn
        return
    }
    $script:CurrentRollbackStack.Push([pscustomobject]@{
        Description    = $Description
        RollbackAction = $RollbackAction
    })
    Write-KitLog "Rollback step registered: $Description (stack depth: $($script:CurrentRollbackStack.Count))" -Level Info
}

# Check whether a transaction is currently active.
function Test-KitTransactionActive {
    [CmdletBinding()]
    param()
    $null -ne $script:CurrentRollbackStack
}

# Get the current transaction stack depth.
function Get-KitTransactionDepth {
    [CmdletBinding()]
    param()
    if ($script:CurrentRollbackStack) { $script:CurrentRollbackStack.Count } else { 0 }
}