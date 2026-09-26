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

    It 'does not write Skipped or NeedsUser into the state under -WhatIf' {
        $state = New-Marker 'whatif-state2.json'
        $verified = New-KitStep -Name 'verified' -Invoke { } -Verify { $true }
        (Invoke-KitStep -Step $verified -StatePath $state -WhatIf).Status | Should Be 'Skipped'
        $blocked = New-KitStep -Name 'blocked' -Test { $false } -Invoke { } -Verify { $false }
        (Invoke-KitStep -Step $blocked -StatePath $state -WhatIf).Status | Should Be 'NeedsUser'
        $state | Should Not Exist
        # An existing state stays byte for byte the same.
        $null = Invoke-KitStep -Step $blocked -StatePath $state
        $before = [IO.File]::ReadAllText($state)
        $null = Invoke-KitStep -Step $verified -StatePath $state -WhatIf
        [IO.File]::ReadAllText($state) | Should BeExactly $before
    }

    It 'records the status in the state file' {
        $m = New-Marker 'stated.txt'
        $state = New-Marker 'state.json'
        $step = New-KitStep -Name 'record' -Invoke { Set-Content -LiteralPath $m -Value 1 } -Verify { Test-Path -LiteralPath $m }
        $null = Invoke-KitStep -Step $step -StatePath $state
        Get-KitStepStatus -Path $state -Name 'record' | Should Be 'Done'
    }
}

# Structured result: what a front end shows without parsing any output.
Describe 'Step result details' {
    Set-KitCulture -Culture 'en-US'

    It 'collects changes, backups, warnings and errors reported while the step runs, plus the duration' {
        $step = New-KitStep -Name 'detailed' -Invoke {
            Add-KitStepChange -Kind File -Target 'a.ini' -Detail '2 replacement(s)'
            Add-KitStepChange -Kind Registry -Target 'HKCU:\Software\x\y'
            Add-KitStepBackup -Path 'a.ini.bak_test_20260101-000000'
            Add-KitStepBackup -Path 'a.ini.bak_test_20260101-000000' # reported twice, listed once
            Write-KitLog 'careful' -Level Warn
        } -Verify { $script:detailedDone = -not $script:detailedDone; -not $script:detailedDone }
        $script:detailedDone = $false
        $r = Invoke-KitStep -Step $step
        $r.Status | Should Be 'Done'
        $r.Changed | Should Be $true
        ($r.Changes | ForEach-Object { '{0}:{1}' -f $_.Kind, $_.Target }) -join ' ' | Should BeExactly 'File:a.ini Registry:HKCU:\Software\x\y'
        @($r.Backups).Count | Should Be 1
        ($r.Warnings -join '|') | Should BeExactly 'careful'
        @($r.Errors).Count | Should Be 0
        $r.Duration | Should BeOfType [TimeSpan]
        @($r.Log | Where-Object { $_.Message -match 'done and verified' }).Count | Should Be 1
    }

    It 'a skipped, a blocked and a dry-run step change nothing and report nothing' {
        foreach ($s in @(
            (New-KitStep -Name 'skip' -Invoke { Add-KitStepChange -Kind File -Target 'x' } -Verify { $true })
            (New-KitStep -Name 'block' -Test { $false } -Invoke { Add-KitStepChange -Kind File -Target 'x' } -Verify { $false })
        )) {
            $r = Invoke-KitStep -Step $s
            $r.Changed | Should Be $false
            @($r.Changes).Count | Should Be 0
        }
        $dry = New-KitStep -Name 'dry' -Invoke { Add-KitStepChange -Kind File -Target 'x' } -Verify { $false }
        (Invoke-KitStep -Step $dry -WhatIf).Changed | Should Be $false
    }

    It 'a failing step lists the error; reporting outside a step does nothing' {
        $r = Invoke-KitStep -Step (New-KitStep -Name 'boom' -Invoke { throw 'kaputt' } -Verify { $false })
        $r.Status | Should Be 'Failed'
        ($r.Errors -join ' ') | Should Match 'kaputt'
        { Add-KitStepChange -Kind File -Target 'outside'; Add-KitStepBackup -Path 'outside' } | Should Not Throw
    }

    It 'the core writers report on their own (text rewrite)' {
        $file = Join-Path $TestDrive 'self.ini'
        [IO.File]::WriteAllText($file, 'path=OLD')
        $step = New-KitStep -Name 'writers' -Invoke {
            $null = Edit-KitTextFile -Path $file -Replace @{ 'OLD' = 'NEW' }
        } -Verify { [IO.File]::ReadAllText($file) -eq 'path=NEW' }
        $r = Invoke-KitStep -Step $step
        $r.Status | Should Be 'Done'
        $r.Changes[0].Kind | Should Be 'File'
        $r.Changes[0].Target | Should BeExactly (Resolve-Path -LiteralPath $file).Path
    }

    It 'a step inside a step keeps its own details; the outer one continues afterwards' {
        $inner = New-KitStep -Name 'inner' -Invoke { Add-KitStepChange -Kind Setting -Target 'inner' } -Verify { $script:innerDone = -not $script:innerDone; -not $script:innerDone }
        $outer = New-KitStep -Name 'outer' -Invoke {
            $script:innerResult = Invoke-KitStep -Step $inner
            Add-KitStepChange -Kind Setting -Target 'outer'
        } -Verify { $script:outerDone = -not $script:outerDone; -not $script:outerDone }
        $script:innerDone = $false; $script:outerDone = $false
        $r = Invoke-KitStep -Step $outer
        ($script:innerResult.Changes | ForEach-Object { $_.Target }) -join ',' | Should BeExactly 'inner'
        ($r.Changes | ForEach-Object { $_.Target }) -join ',' | Should BeExactly 'outer'
    }
}
