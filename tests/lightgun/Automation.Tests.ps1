$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1') -Force
$newRetroBat = Join-Path $PSScriptRoot 'New-LightgunTestRetroBat.ps1'

# Profile automation and measurement. The admin-only folder is simulated in TEMP, tasks are mocked or injected
# (no real task is created), the hook runs with "schtasks" replaced by "echo", profile.ps1 is never executed
# (it would talk to a real Gunmote).
$me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value

# A folder "a user created beforehand": owned by the current user. An elevated run (CI) would otherwise create it
# owned by the Administrators group, which the kit rightly trusts. Only the owner section is written.
function Set-TestOwner([string] $Path) {
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier $me))
    [IO.Directory]::SetAccessControl($Path, $acl)
}

# Own TEMP test folder: give the rights back top-down (as owner) so it can be removed.
function Reset-TestAcl([string] $Path) {
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule ((New-Object Security.Principal.SecurityIdentifier $me), 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow')))
    [IO.Directory]::SetAccessControl($Path, $acl)
    foreach ($d in [IO.Directory]::GetDirectories($Path)) { Reset-TestAcl $d }
}

Describe 'System to profile' {
    It 'maps the systems as specified' {
        Get-LightgunProfileFor 'teknoparrot' | Should Be 'TP'
        foreach ($s in 'mame', 'psx', 'model2', 'model3') { Get-LightgunProfileFor $s | Should Be 'Pad43' }
        foreach ($s in 'naomi', 'atomiswave') { Get-LightgunProfileFor $s | Should Be 'Naomi' }
        foreach ($s in 'nes', 'snes', 'megadrive', 'mastersystem', 'ps2') { Get-LightgunProfileFor $s | Should Be 'Mouse' }
        Get-LightgunProfileFor 'MAME' | Should Be 'Pad43'
        Get-LightgunProfileFor 'wii' | Should BeNullOrEmpty
    }
}

Describe 'RetroBat hooks' {
    $prefix = 'RCK-TEST Profile'

    It 'contain nothing but schtasks /run (no script, no PowerShell, no other program)' {
        foreach ($kind in 'Start', 'End') {
            $lines = (New-LightgunHookText -Kind $kind -TaskPrefix $prefix) -split "`r`n" | Where-Object { $_ -and $_ -notmatch '^rem ' }
            $lines | Should Not Match '(?i)powershell|\.ps1|\bstart\b|\bcall\b|\bcmd\b'
            foreach ($l in $lines) {
                $l | Should Match '^(@echo off|setlocal DisableDelayedExpansion|endlocal|set "ROM=%~1"|set "PROFILE="|if not defined ROM goto :eof|if not defined PROFILE if not "%ROM:\\roms\\[a-z0-9]+\\=%"=="%ROM%" set "PROFILE=[A-Za-z0-9]+"|(if defined PROFILE )?schtasks /run /tn "RCK-TEST Profile (%PROFILE%|Menu)" >nul 2>&1)$'
            }
        }
        (New-LightgunHookText -Kind 'Start') | Should Match 'schtasks /run /tn "RetroCabinetKit Gunmote Profile %PROFILE%"'
    }

    It 'select the right task, also for ROM names with & ^ % and spaces (run with schtasks replaced by echo)' {
        $bat = Join-Path $TestDrive 'hook-start.bat'
        [IO.File]::WriteAllText($bat, ((New-LightgunHookText -Kind 'Start' -TaskPrefix $prefix) -replace 'schtasks /run /tn ("[^"]+") >nul 2>&1', 'echo TASK=$1'), [Text.Encoding]::ASCII)
        $cases = [ordered]@{
            'X:\RetroBat\roms\teknoparrot\Game.teknoparrot'        = 'TASK="RCK-TEST Profile TP"'
            'X:\RetroBat\roms\mame\alien3.zip'                     = 'TASK="RCK-TEST Profile Pad43"'
            'X:\RetroBat\ROMS\PSX\A & B ^C 100% (USA).chd'         = 'TASK="RCK-TEST Profile Pad43"'
            'X:\RetroBat\roms\atomiswave\x.zip'                    = 'TASK="RCK-TEST Profile Naomi"'
            'X:\RetroBat\roms\nes\duck hunt & calc.nes'            = 'TASK="RCK-TEST Profile Mouse"'
            'X:\RetroBat\roms\snes\game.sfc'                       = 'TASK="RCK-TEST Profile Mouse"'
            'X:\RetroBat\roms\n64\game.z64'                        = ''
        }
        foreach ($rom in $cases.Keys) {
            $out = (& cmd.exe /d /c "`"$bat`" `"$rom`" name title" 2>&1 | Out-String).Trim()
            $out | Should BeExactly $cases[$rom]
        }
        (& cmd.exe /d /c "`"$bat`"" 2>&1 | Out-String).Trim() | Should BeExactly ''
    }

    It 'are written into RetroBat once (idempotent) and other hooks are only reported' {
        $rb = Join-Path $TestDrive 'RB'
        & $newRetroBat -Root $rb
        $p = Get-LightgunRetroBatPath -Root $rb
        New-Item -ItemType Directory -Path $p.HookStart -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $p.HookStart 'old-profile.bat'), '@echo off')
        Test-LightgunHook -RetroBatRoot $rb -TaskPrefix $prefix | Should Be $false
        Install-LightgunHook -RetroBatRoot $rb -TaskPrefix $prefix -Confirm:$false
        Test-LightgunHook -RetroBatRoot $rb -TaskPrefix $prefix | Should Be $true
        Join-Path $p.HookStart 'old-profile.bat' | Should Exist
        $t = (Get-Item -LiteralPath (Join-Path $p.HookEnd 'rck-gunmote-profile.bat')).LastWriteTimeUtc
        Start-Sleep -Milliseconds 50
        Install-LightgunHook -RetroBatRoot $rb -TaskPrefix $prefix -Confirm:$false
        (Get-Item -LiteralPath (Join-Path $p.HookEnd 'rck-gunmote-profile.bat')).LastWriteTimeUtc | Should Be $t
    }
}

Describe 'Admin-only automation folder (simulated in TEMP)' {
    Set-KitCulture -Culture 'en-US'

    It 'installs profile.ps1 with Administrators/SYSTEM full control, Users read only, parent locked too' {
        $base = Join-Path $TestDrive 'ProgramDataSim'
        $dir = Join-Path $base 'lightgun'
        try {
            Install-LightgunAutomationFile -AutomationDir $dir -TrustedOwner @($me, 'S-1-5-32-544', 'S-1-5-18') -Confirm:$false
            $acl = [IO.Directory]::GetAccessControl($dir)
            $acl.AreAccessRulesProtected | Should Be $true
            $rules = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
            (@($rules | ForEach-Object { $_.IdentityReference.Value } | Sort-Object -Unique) -join ',') | Should Be 'S-1-5-18,S-1-5-32-544,S-1-5-32-545'
            ($rules | Where-Object { $_.IdentityReference.Value -eq 'S-1-5-32-545' }).FileSystemRights.ToString() | Should Match '^ReadAndExecute'
            $baseAcl = [IO.Directory]::GetAccessControl($base)
            # Administrators and SYSTEM, plus the trusted test owner (the real run trusts only those two).
            (@($baseAcl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) | ForEach-Object { $_.IdentityReference.Value } | Sort-Object -Unique) -join ',') |
                Should Be ((@('S-1-5-18', 'S-1-5-32-544', $me) | Sort-Object -Unique) -join ',')
            Test-LightgunAutomationFile -AutomationDir $dir -TrustedOwner @($me, 'S-1-5-32-544', 'S-1-5-18') | Should Be $true
            # The real check trusts only Administrators/SYSTEM as owner: a folder a user owns is not safe.
            Test-LightgunAutomationFile -AutomationDir $dir | Should Be $false
        } finally { Reset-TestAcl $base; Remove-Item -LiteralPath $base -Recurse -Force }
    }

    It 'notices a user write rule and a changed script' {
        $base = Join-Path $TestDrive 'Sim2'
        $dir = Join-Path $base 'lightgun'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $dir 'profile.ps1'), 'changed')
        Test-LightgunAutomationFile -AutomationDir $dir -TrustedOwner @($me) | Should Be $false
        Test-LightgunAdminOnlyAcl -Path $dir -TrustedOwner @($me) | Should Be $false
    }

    It 'refuses a junction as automation folder' {
        $base = Join-Path $TestDrive 'Sim3'
        $elsewhere = Join-Path $TestDrive 'elsewhere'
        New-Item -ItemType Directory -Path $base, $elsewhere -Force | Out-Null
        Set-TestOwner $base
        $null = cmd /c mklink /J "$base\lightgun" "$elsewhere"
        try { { Install-LightgunAutomationFile -AutomationDir "$base\lightgun" -TrustedOwner @($me) -Confirm:$false } | Should Throw 'link' }
        finally { cmd /c rmdir "$base\lightgun"; Reset-TestAcl $base }
        Join-Path $elsewhere 'profile.ps1' | Should Not Exist
    }

    It 'refuses a kit folder that a user created beforehand (owner is not Administrators or SYSTEM)' {
        $base = Join-Path $TestDrive 'Sim4'
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        Set-TestOwner $base
        { Install-LightgunAutomationFile -AutomationDir "$base\lightgun" -Confirm:$false } | Should Throw 'not owned by Administrators or SYSTEM'
        Join-Path $base 'lightgun' | Should Not Exist
        (Get-Acl -LiteralPath $base).AreAccessRulesProtected | Should Be $false
    }
}

Describe 'Profile tasks (mocked, no real task)' {
    Set-KitCulture -Culture 'en-US'
    $titles = [pscustomobject]@{ Menu = 'RCK Menu (no pointer)'; Pad43 = 'RCK Pad 4:3'; TP = 'RCK TeknoParrot'; Mouse = 'RCK Mouse' }
    $dir = 'C:\ProgramDataSim\RetroCabinetKit\lightgun'

    It 'plans five tasks that start the admin-only script with the recorded, quoted layout title' {
        $plan = @(Get-LightgunProfileTaskPlan -Titles $titles -AutomationDir $dir -TaskPrefix 'RCK-TEST Profile')
        ($plan | ForEach-Object { $_.TaskName }) -join '|' | Should Be 'RCK-TEST Profile Menu|RCK-TEST Profile TP|RCK-TEST Profile Pad43|RCK-TEST Profile Naomi|RCK-TEST Profile Mouse'
        $plan[0].Argument | Should BeExactly '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\ProgramDataSim\RetroCabinetKit\lightgun\profile.ps1" -Layout "RCK Menu (no pointer)" -Once'
        ($plan | Where-Object { $_.Name -eq 'Naomi' }).Argument | Should Match '-Layout "RCK Pad 4:3"$'
    }

    It 'refuses a layout title that could break out of the task arguments' {
        $bad = [pscustomobject]@{ Menu = 'x" -Command "calc'; Pad43 = 'a'; TP = 'b'; Mouse = 'c' }
        { Get-LightgunProfileTaskPlan -Titles $bad -AutomationDir $dir } | Should Throw
    }

    It 'registers every task with highest rights for the given user (Register-ScheduledTask mocked)' {
        Mock -ModuleName 'RetroCabinetKit.Lightgun' Register-ScheduledTask { }
        $plan = @(Get-LightgunProfileTaskPlan -Titles $titles -AutomationDir $dir -TaskPrefix 'RCK-TEST Profile')
        Register-LightgunProfileTask -Plan $plan -UserSid $me -Confirm:$false
        Assert-MockCalled -ModuleName 'RetroCabinetKit.Lightgun' Register-ScheduledTask -Times 5 -Exactly -ParameterFilter {
            $Principal.RunLevel -eq 'Highest' -and $Action[0].Execute -eq (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') -and $TaskName -like 'RCK-TEST Profile *'
        }
    }

    It 'checks existing tasks: program, arguments and run level must match exactly' {
        $plan = @(Get-LightgunProfileTaskPlan -Titles $titles -AutomationDir $dir -TaskPrefix 'RCK-TEST Profile')
        $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $tasks = @($plan | ForEach-Object { [pscustomobject]@{ TaskName = $_.TaskName; Principal = [pscustomobject]@{ RunLevel = 'Highest' }; Actions = @([pscustomobject]@{ Execute = $exe; Arguments = $_.Argument }) } })
        Test-LightgunProfileTask -Plan $plan -Tasks $tasks | Should Be $true
        $tasks[1].Actions[0].Arguments = $tasks[1].Actions[0].Arguments + ' -Evil'
        Test-LightgunProfileTask -Plan $plan -Tasks $tasks | Should Be $false
        Test-LightgunProfileTask -Plan $plan -Tasks @($tasks | Select-Object -First 4) | Should Be $false
    }
}

Describe 'profile.ps1 template (parsed, never run)' {
    $template = Get-LightgunTemplatePath

    It 'is valid PowerShell, uses only the Gunmote pipe and checks its layout argument' {
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($template, [ref]$null, [ref]$errors)
        @($errors).Count | Should Be 0
        $text = [IO.File]::ReadAllText($template)
        $text | Should Match "NamedPipeClientStream \('\.', 'Gunmote'"
        $text | Should Not Match 'Stop-Process|Start-Process|Invoke-Expression|iex '
        $pattern = ($ast.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Layout' }).Attributes |
            Where-Object { $_.TypeName.Name -eq 'ValidatePattern' } | ForEach-Object { $_.PositionalArguments[0].Value }
        'Gamepad (xinput) 4:3' -match $pattern | Should Be $true
        'x" ; calc' -match $pattern | Should Be $false
    }
}

Describe 'Measuring (XInput, profile log, emulatorLauncher.log)' {
    Set-KitCulture -Culture 'en-US'

    It 'loads the XInput wrapper and reports every pad slot (no pad = Connected false, no error)' {
        $s = @(0..3 | ForEach-Object { Get-LightgunXInputState -Pad $_ })
        $s.Count | Should Be 4
        foreach ($x in $s) { $x.Connected -is [bool] | Should Be $true }
    }

    It 'reports NoPad cleanly without any pad' {
        $none = { param($p) [pscustomobject]@{ Connected = $false; Buttons = @() } }
        @(Get-LightgunXInputPad -Reader $none).Count | Should Be 0
        (Wait-LightgunXInputPress -Pad 0 -TimeoutSeconds 0.2 -Reader $none).Status | Should Be 'NoPad'
    }

    It 'needs a fresh press: a button held from the start counts only after it was released' {
        $script:seq = @(@('A'), @('A'), @(), @('B'))
        $script:n = 0
        $reader = { param($p) $b = $script:seq[[math]::Min($script:n, $script:seq.Count - 1)]; $script:n++; [pscustomobject]@{ Connected = $true; Buttons = $b } }
        $r = Wait-LightgunXInputPress -Pad 1 -TimeoutSeconds 5 -Reader $reader
        $r.Status | Should Be 'Pressed'
        $r.Buttons -join '+' | Should Be 'B'
        (Wait-LightgunXInputPress -Pad 1 -TimeoutSeconds 0.2 -Reader { param($p) [pscustomobject]@{ Connected = $true; Buttons = @() } }).Status | Should Be 'Timeout'
    }

    It 'finds a profile switch in the log after the installation time' {
        $log = Join-Path $TestDrive 'profile.log'
        [IO.File]::WriteAllLines($log, @(
            "2026-01-01 10:00:00 START layout='RCK Menu (no pointer)' once=True"
            "2026-01-01 10:00:01 SENT layout='RCK Menu (no pointer)' (once)"
            "2026-01-01 10:05:00 START layout='RCK TeknoParrot' once=False"
            "2026-01-01 10:05:01 SENT layout='RCK TeknoParrot' (start)"
            "2026-01-01 10:05:09 END RetroBat in front again"
        ))
        @(Get-LightgunProfileEvent -LogPath $log).Count | Should Be 5
        Test-LightgunProfileSwitch -LogPath $log -MenuTitle 'RCK Menu (no pointer)' | Should Be $true
        Test-LightgunProfileSwitch -LogPath $log -MenuTitle 'RCK Menu (no pointer)' -Since ([datetime]'2026-01-01 11:00:00') | Should Be $false
        Test-LightgunProfileSwitch -LogPath (Join-Path $TestDrive 'none.log') -MenuTitle 'x' | Should Be $false
    }

    It 'reads the last start from emulatorLauncher.log, gun automation included' {
        $rb = Join-Path $TestDrive 'RBlog'
        & $newRetroBat -Root $rb
        $logPath = (Get-LightgunRetroBatPath -Root $rb).LauncherLog
        $r = Get-LightgunLauncherReport -Path $logPath
        $r.System | Should Be 'psx'
        $r.Emulator | Should Be 'duckstation'
        $r.Rom | Should Be 'X:\RetroBat\roms\psx\game (USA).chd'
        $r.GunAutomation | Should Be $false
        $r.Lightgun | Should Be $false
        $lines = [IO.File]::ReadAllLines($logPath)
        [IO.File]::WriteAllLines($logPath, $lines[0..2])
        $r = Get-LightgunLauncherReport -Path $logPath
        $r.System | Should Be 'mame'
        $r.Lightgun | Should Be $true
        $r.GunAutomation | Should Be $true
        $r.Running | Should Match 'retroarch\.exe'
    }
}
