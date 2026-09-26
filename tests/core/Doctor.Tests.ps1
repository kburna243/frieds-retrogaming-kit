$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force

Describe 'Doctor framework' {
    Set-KitCulture -Culture 'en-US'

    It 'fills area and name, keeps an own row name and turns a bad level into an error' {
        $checks = @(
            New-KitCheck -Area 'A' -Name 'one' -Script { @{ Level = 'Ok'; Detail = 'fine' } }
            New-KitCheck -Area 'A' -Name 'two' -Script { @{ Level = 'Warn'; Detail = 'w' }; @{ Name = 'two-b'; Level = 'Info' } }
            New-KitCheck -Area 'B' -Name 'bad' -Script { @{ Level = 'Maybe' } }
        )
        $r = @(Invoke-KitDoctor -Check $checks)
        $r.Count | Should Be 4
        ($r | ForEach-Object { '{0}/{1}/{2}' -f $_.Area, $_.Name, $_.Level }) -join ' ' | Should BeExactly 'A/one/Ok A/two/Warn A/two-b/Info B/bad/Error'
    }

    It 'hands -Data to the check and reports an exception as one error row' {
        $checks = @(
            New-KitCheck -Area 'A' -Name 'data' -Data @{ Value = 42 } -Script { param($d) @{ Level = 'Info'; Detail = "$($d.Value)" } }
            New-KitCheck -Area 'A' -Name 'boom' -Script { throw 'kaputt' }
        )
        $r = @(Invoke-KitDoctor -Check $checks)
        $r[0].Detail | Should BeExactly '42'
        $r[1].Level | Should Be 'Error'
        $r[1].Detail | Should Match 'could not run: kaputt'
    }

    It 'counts the levels and writes a report grouped by area with the result line' {
        $r = @(
            New-KitCheckResult -Area 'System' -Name 'Windows' -Level Ok -Detail 'Windows 11'
            New-KitCheckResult -Area 'Lightgun' -Name 'ViGEmBus' -Level Error -Detail 'Not installed'
            New-KitCheckResult -Area 'System' -Name 'Admin' -Level Warn
        )
        $s = Get-KitDoctorSummary -Result $r
        '{0}{1}{2}{3}' -f $s.Ok, $s.Info, $s.Warn, $s.Error | Should BeExactly '1011'
        $text = (Format-KitDoctorReport -Result $r) -join "`n"
        $text | Should Match '(?s)System\n\[OK\]\s+Windows: Windows 11\n\[WARN\]\s+Admin\n\nLightgun\n\[ERROR\] ViGEmBus: Not installed'
        $text | Should Match 'Result: 1 error\(s\), 1 warning\(s\), 1 OK'
    }
}

Describe 'Doctor system checks (injected values, nothing is read from this machine)' {
    Set-KitCulture -Culture 'en-US'
    $good = @{
        KitRoot = $kitRoot; OsVersion = [version]'10.0.22631'; OnWindows = $true; PSVersion = [version]'5.1.22621'
        PSEdition = 'Desktop'; Is64Bit = $true; IsAdmin = $false; FileSystem = 'NTFS'; BlockedFiles = @()
    }
    function Get-Levels([hashtable] $Values) { @(Invoke-KitDoctor -Check @(Get-KitSystemCheck @Values)) | ForEach-Object { '{0}={1}' -f $_.Name, $_.Level } }

    It 'a supported cabinet is green (not elevated = information only)' {
        (Get-Levels $good) -join '; ' | Should BeExactly 'Kit version=Info; Windows=Ok; PowerShell=Ok; 64-bit Windows=Ok; Administrator=Info; File system of the kit folder=Ok; Download mark=Ok'
    }

    It 'reads the kit version from VERSION' {
        $v = ([IO.File]::ReadAllText((Join-Path $kitRoot 'VERSION'))).Trim()
        (@(Invoke-KitDoctor -Check @(Get-KitSystemCheck @good))[0]).Detail | Should BeExactly $v
    }

    It 'warns for an old Windows 10 build, FAT32 and blocked files; errors for 32-bit and PowerShell 4' {
        $bad = $good.Clone()
        $bad.OsVersion = [version]'10.0.17763'; $bad.FileSystem = 'FAT32'; $bad.BlockedFiles = @('a', 'b')
        $bad.Is64Bit = $false; $bad.PSVersion = [version]'4.0'
        $levels = (Get-Levels $bad) -join '; '
        $levels | Should Match 'Windows=Warn'
        $levels | Should Match 'PowerShell=Error'
        $levels | Should Match '64-bit Windows=Error'
        $levels | Should Match 'File system of the kit folder=Warn'
        $levels | Should Match 'Download mark=Info'
    }

    It 'PowerShell 7 is information (the launchers use Windows PowerShell 5.1)' {
        $ps7 = $good.Clone(); $ps7.PSVersion = [version]'7.4.0'; $ps7.PSEdition = 'Core'
        (Get-Levels $ps7) -join '; ' | Should Match 'PowerShell=Info'
    }
}

Describe 'Doctor step states' {
    Set-KitCulture -Culture 'en-US'

    It 'no state file is information' {
        $r = @(Invoke-KitDoctor -Check @(Get-KitStateCheck -Area 'Pinball' -StatePath (Join-Path $TestDrive 'none.json')))
        $r.Count | Should Be 1
        $r[0].Level | Should Be 'Info'
    }

    It 'failed = error, needs user = warning, the rest one OK row' {
        $state = Join-Path $TestDrive 'install-state.json'
        Set-KitStepStatus -Path $state -Name 's-1' -Status Done -Message 'ok'
        Set-KitStepStatus -Path $state -Name 's-2' -Status Skipped -Message 'already'
        Set-KitStepStatus -Path $state -Name 's-3' -Status Failed -Message 'broken'
        Set-KitStepStatus -Path $state -Name 's-4' -Status NeedsUser -Message 'plug it in'
        $r = @(Invoke-KitDoctor -Check @(Get-KitStateCheck -Area 'Pinball' -StatePath $state))
        ($r | ForEach-Object { $_.Level }) -join ',' | Should BeExactly 'Error,Warn,Ok'
        $r[0].Detail | Should BeExactly 'Step s-3 failed: broken'
        $r[1].Detail | Should BeExactly 'Step s-4 needs you: plug it in'
        $r[2].Detail | Should BeExactly '2 step(s) done or already in place.'
    }
}
