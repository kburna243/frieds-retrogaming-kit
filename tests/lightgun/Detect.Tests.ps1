$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1') -Force
$newRetroBat = Join-Path $PSScriptRoot 'New-LightgunTestRetroBat.ps1'

# Detection, hardware, ViGEmBus and Gunmote with injected devices, services, entries and tasks.
# Nothing is installed, downloaded or registered.
Describe 'RetroBat detection' {
    Set-KitCulture -Culture 'en-US'

    It 'recognizes a build, a never started RetroBat and a folder without RetroBat' {
        $root = Join-Path $TestDrive 'RB'
        & $newRetroBat -Root $root
        $info = Get-LightgunRetroBatInfo -Root $root
        $info.Kind | Should Be 'Build'
        $info.Version | Should Be '9.9.9-test'
        Get-LightgunRetroBatProblem -Root $root | Should BeNullOrEmpty

        $fresh = Join-Path $TestDrive 'Fresh'
        New-Item -ItemType Directory -Path "$fresh\emulationstation" -Force | Out-Null
        [IO.File]::WriteAllBytes("$fresh\emulationstation\emulationstation.exe", [byte[]]@())
        (Get-LightgunRetroBatInfo -Root $fresh).Kind | Should Be 'Fresh'
        Get-LightgunRetroBatProblem -Root $fresh | Should Match 'never started'

        (Get-LightgunRetroBatInfo -Root (Join-Path $TestDrive 'Nothing')).Kind | Should Be 'None'
        Get-LightgunRetroBatProblem -Root '\\nas\share\RetroBat' | Should Match 'local drive'
        Get-LightgunRetroBatProblem -Root '' | Should Match 'step 1'
    }

    It 'links the official RetroBat releases' {
        Get-LightgunRetroBatReleaseUrl | Should Be 'https://github.com/RetroBat-Official/retrobat-setup/releases'
    }
}

Describe 'Hardware checks (read-only)' {
    Set-KitCulture -Culture 'en-US'
    $m60 = [pscustomobject]@{ DeviceName = '\\.\DISPLAY1'; Width = 1920; Height = 1080; RefreshRate = 60 }
    $m30 = [pscustomobject]@{ DeviceName = '\\.\DISPLAY2'; Width = 1920; Height = 1080; RefreshRate = 30 }
    $m144 = [pscustomobject]@{ DeviceName = '\\.\DISPLAY3'; Width = 2560; Height = 1440; RefreshRate = 144 }
    $bar4 = [pscustomobject]@{ InstanceId = 'USB\VID_057E&PID_0306\5&1&0&1' }

    It 'finds the DolphinBar in Mode 4 and explains the other modes' {
        (Get-LightgunDolphinBarState -Devices @($bar4)).Mode4 | Should Be $true
        $wrong = Get-LightgunDolphinBarState -Devices @([pscustomobject]@{ InstanceId = 'HID\VID_0079&PID_1802&MI_00\x' }, [pscustomobject]@{ InstanceId = 'USB\VID_0079&PID_1803\y' })
        $wrong.Mode4 | Should Be $false
        ($wrong.WrongMode | Sort-Object) -join ',' | Should Be 'Gamepad,Mode12'
        (Get-LightgunDolphinBarState -Devices @()).Mode4 | Should Be $false
    }

    It 'rates the real refresh rate: 60 ok, 30 warning, 144 info' {
        $r = @(Get-LightgunRefreshReport -Monitors @($m60, $m30, $m144))
        ($r | ForEach-Object { $_.Level }) -join ',' | Should Be 'Ok,Warn,Info'
    }

    It 'reports the Bluetooth service' {
        (Get-LightgunBluetoothState -Service ([pscustomobject]@{ Status = 'Running'; StartType = 'Manual' })).Running | Should Be $true
        (Get-LightgunBluetoothState -Service $null).Present | Should Be $false
    }

    It 'is green only with Mode 4 and no monitor below 50 Hz' {
        Test-LightgunHardware -Devices @($bar4) -Service $null -Monitors @($m60, $m144) -Quiet | Should Be $true
        Test-LightgunHardware -Devices @($bar4) -Service $null -Monitors @($m30) -Quiet | Should Be $false
        Test-LightgunHardware -Devices @() -Service $null -Monitors @($m60) -Quiet | Should Be $false
    }
}

Describe 'ViGEmBus' {
    Set-KitCulture -Culture 'en-US'

    It 'detects the driver by service and uninstall entry' {
        $svc = [pscustomobject]@{ Status = 'Running' }
        $entry = [pscustomobject]@{ DisplayName = 'ViGEm Bus Driver'; DisplayVersion = '1.22.0' }
        $s = Get-LightgunViGEmState -Service $svc -Entries @($entry)
        $s.Installed | Should Be $true
        $s.Version | Should Be '1.22.0'
        (Get-LightgunViGEmState -Service $null -Entries @()).Installed | Should Be $false
    }

    It 'downloads only from the allow-listed official release folder' {
        $r = Get-LightgunViGEmRelease
        Test-KitDownloadUrl -Uri $r.Url | Should Be $true
        $r.Publisher | Should BeExactly 'Nefarius Software Solutions e.U.'
    }

    It 'refuses an installer that is not signed by Nefarius and never runs it' {
        $fake = Join-Path $TestDrive 'ViGEmBus_fake.exe'
        [IO.File]::WriteAllBytes($fake, [byte[]](77, 90, 0, 0))
        { Install-LightgunViGEm -InstallerPath $fake -Approve { throw 'must not ask' } -Confirm:$false } | Should Throw 'not signed by Nefarius'
    }

    It 'does nothing under -WhatIf (no download)' {
        Install-LightgunViGEm -WhatIf -Approve { throw 'must not ask' } | Should BeNullOrEmpty
    }
}

Describe 'Gunmote' {
    Set-KitCulture -Culture 'en-US'
    $dir = Join-Path $TestDrive 'Gunmote'
    New-Item -ItemType Directory -Path "$dir\Keymaps" -Force | Out-Null
    [IO.File]::WriteAllBytes("$dir\Gunmote.exe", [byte[]]@())

    It 'finds Gunmote in a given folder and knows it is not below Program Files' {
        $g = Find-LightgunGunmote -Path $dir
        $g.Exe | Should Be "$dir\Gunmote.exe"
        $g.KeymapsJson | Should Be "$dir\Keymaps\Keymaps.json"
        $g.InProgramFiles | Should Be $false
        Find-LightgunGunmote -Path (Join-Path $TestDrive 'none') | Should BeNullOrEmpty
    }

    It 'takes folder and version from the uninstall entry' {
        $g = Find-LightgunGunmote -Entries @([pscustomobject]@{ DisplayName = 'Gunmote Version 1.1.1.0'; DisplayVersion = '1.1.1.0'; InstallLocation = "$dir\" })
        $g.Dir | Should Be $dir
        $g.Version | Should Be '1.1.1.0'
    }

    It 'links the official Gunmote releases' {
        Get-LightgunGunmoteReleaseUrl | Should Be 'https://github.com/gunmotelabs/Gunmote/releases'
    }

    It 'accepts only a task with highest rights that starts this Gunmote.exe' {
        $action = [pscustomobject]@{ Execute = "`"$dir\Gunmote.exe`"" }
        $high = [pscustomobject]@{ TaskName = 'x'; TaskPath = '\'; State = 'Ready'; Actions = @($action); Principal = [pscustomobject]@{ RunLevel = 'Highest' } }
        $low = [pscustomobject]@{ TaskName = 'y'; TaskPath = '\'; State = 'Ready'; Actions = @($action); Principal = [pscustomobject]@{ RunLevel = 'Limited' } }
        $other = [pscustomobject]@{ TaskName = 'z'; TaskPath = '\'; State = 'Ready'; Actions = @([pscustomobject]@{ Execute = 'C:\other.exe' }); Principal = [pscustomobject]@{ RunLevel = 'Highest' } }
        Test-LightgunGunmoteTask -Exe "$dir\Gunmote.exe" -Tasks @($high) | Should Be $true
        Test-LightgunGunmoteTask -Exe "$dir\Gunmote.exe" -Tasks @($low, $other) | Should Be $false
    }

    It 'refuses a task with highest rights for a Gunmote outside Program Files' {
        $g = Find-LightgunGunmote -Path $dir
        { Register-LightgunGunmoteTask -Gunmote $g -UserSid (Get-KitUserSid) -Confirm:$false } | Should Throw 'outside Program Files'
    }

    It 'registers the logon task with highest rights for the starting user (Register-ScheduledTask mocked)' {
        Mock -ModuleName 'RetroCabinetKit.Lightgun' Register-ScheduledTask { }
        $g = [pscustomobject]@{ Dir = "$env:ProgramFiles\Gunmote"; Exe = "$env:ProgramFiles\Gunmote\Gunmote.exe"; InProgramFiles = $true }
        Register-LightgunGunmoteTask -Gunmote $g -UserSid (Get-KitUserSid) -Confirm:$false
        Assert-MockCalled -ModuleName 'RetroCabinetKit.Lightgun' Register-ScheduledTask -Times 1 -Exactly -ParameterFilter {
            $TaskName -eq 'RetroCabinetKit Gunmote' -and $Principal.RunLevel -eq 'Highest' -and $Action[0].Execute -eq "$env:ProgramFiles\Gunmote\Gunmote.exe" -and $Trigger
        }
    }
}
