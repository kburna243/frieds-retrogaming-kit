$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force

Describe 'Step' {
    Set-KitCulture -Culture 'en-US'

    # File markers instead of variables: the script blocks run from inside the module.
    function New-Marker([string] $Name) { Join-Path $TestDrive $Name }

    It 'is Done when Verify is true after Invoke' {
        $m = New-Marker 'done.txt'
        $step = New-KitStep -Name 'make' -Invoke { Set-Content -LiteralPath $m -Value 1 } -Verify { Test-Path -LiteralPath $m }
        $r = Invoke-KitStep -Step $step
        $r.Status | Should Be 'Done'
        $r.WhatIf | Should Be $false
    }

    It 'is Failed when Verify stays false' {
        $step = New-KitStep -Name 'noop' -Invoke { } -Verify { $false }
        (Invoke-KitStep -Step $step).Status | Should Be 'Failed'
    }

    It 'is Failed with the error text when Invoke throws' {
        $step = New-KitStep -Name 'boom' -Invoke { throw 'disk on fire' } -Verify { $false }
        $r = Invoke-KitStep -Step $step
        $r.Status | Should Be 'Failed'
        $r.Error | Should Be 'disk on fire'
        $r.Message | Should Match 'disk on fire'
    }

    It 'is only green for a real $true from Verify' {
        $step = New-KitStep -Name 'truthy' -Invoke { } -Verify { 'yes' }
        (Invoke-KitStep -Step $step).Status | Should Be 'Failed'
    }

    It 'is NeedsUser and does not invoke when Test is false' {
        $m = New-Marker 'needsuser.txt'
        $step = New-KitStep -Name 'pre' -Test { $false } -Invoke { Set-Content -LiteralPath $m -Value 1 } -Verify { Test-Path -LiteralPath $m }
        (Invoke-KitStep -Step $step).Status | Should Be 'NeedsUser'
        $m | Should Not Exist
    }

    It 'is Skipped without invoking when already verified' {
        $m = New-Marker 'already.txt'
        Set-Content -LiteralPath $m -Value 1
        $step = New-KitStep -Name 'again' -Invoke { throw 'must not run' } -Verify { Test-Path -LiteralPath $m }
        (Invoke-KitStep -Step $step).Status | Should Be 'Skipped'
    }

    It 'does nothing and persists nothing under -WhatIf' {
        $m = New-Marker 'whatif.txt'
        $state = New-Marker 'whatif-state.json'
        $step = New-KitStep -Name 'dry' -Invoke { Set-Content -LiteralPath $m -Value 1 } -Verify { Test-Path -LiteralPath $m }
        $r = Invoke-KitStep -Step $step -StatePath $state -WhatIf
        $r.Status | Should Be 'Skipped'
        $r.WhatIf | Should Be $true
        $m | Should Not Exist
        $state | Should Not Exist
    }

    It 'records the status in the state file' {
        $m = New-Marker 'stated.txt'
        $state = New-Marker 'state.json'
        $step = New-KitStep -Name 'record' -Invoke { Set-Content -LiteralPath $m -Value 1 } -Verify { Test-Path -LiteralPath $m }
        $null = Invoke-KitStep -Step $step -StatePath $state
        Get-KitStepStatus -Path $state -Name 'record' | Should Be 'Done'
    }
}
