$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1') -Force
$newRetroBat = Join-Path $PSScriptRoot 'New-LightgunTestRetroBat.ps1'
$steps = Join-Path $kitRoot 'lightgun\steps'

# The step scripts as stand-alone scripts. Hardware, services, uninstall entries and tasks are injected;
# nothing is installed, downloaded or registered and no real task is created.
Describe 'Lightgun steps 1-4 as stand-alone scripts' {
    Set-KitCulture -Culture 'en-US'
    $rb = Join-Path $TestDrive 'RetroBat'
    & $newRetroBat -Root $rb
    $state = Join-Path $TestDrive 'install-state.json'
    $common = @{ StatePath = $state; Culture = 'en-US' }

    It '1 detect: dry run writes no state, real run records RetroBat, second run is skipped' {
        (& "$steps\01-Detect.ps1" -RetroBatRoot $rb @common -WhatIf).Status | Should Be 'Skipped'
        $state | Should Not Exist
        (& "$steps\01-Detect.ps1" -RetroBatRoot $rb @common).Status | Should Be 'Done'
        Get-KitStateValue -Path $state -Key 'RetroBatRoot' | Should BeExactly $rb
        (& "$steps\01-Detect.ps1" -RetroBatRoot $rb @common).Status | Should Be 'Skipped'
    }

    It '1 detect: a folder without RetroBat needs the user' {
        $s = Join-Path $TestDrive 'other-state.json'
        (& "$steps\01-Detect.ps1" -RetroBatRoot (Join-Path $TestDrive 'none') -StatePath $s -Culture 'en-US').Status | Should Be 'NeedsUser'
    }

    It '2 hardware: green with Mode 4 at 60 Hz, needs the user without DolphinBar or at 30 Hz' {
        $bar = [pscustomobject]@{ InstanceId = 'USB\VID_057E&PID_0306\1' }
        $m60 = [pscustomobject]@{ DeviceName = 'D1'; Width = 1920; Height = 1080; RefreshRate = 60 }
        $m30 = [pscustomobject]@{ DeviceName = 'D1'; Width = 1920; Height = 1080; RefreshRate = 30 }
        (& "$steps\02-Hardware.ps1" @common -Devices @($bar) -BluetoothService $null -Monitors @($m60)).Status | Should Be 'Skipped'
        (& "$steps\02-Hardware.ps1" @common -Devices @() -BluetoothService $null -Monitors @($m60)).Status | Should Be 'NeedsUser'
        (& "$steps\02-Hardware.ps1" @common -Devices @($bar) -BluetoothService $null -Monitors @($m30)).Status | Should Be 'NeedsUser'
    }

    It '3 ViGEmBus: present = green; missing without permission = needs the user, nothing is downloaded' {
        $entry = [pscustomobject]@{ DisplayName = 'ViGEm Bus Driver'; DisplayVersion = '1.22.0' }
        (& "$steps\03-ViGEmBus.ps1" @common -Service ([pscustomobject]@{ Status = 'Running' }) -Entries @($entry)).Status | Should Be 'Skipped'
        (& "$steps\03-ViGEmBus.ps1" @common -Service $null -Entries @() -Approve { throw 'must not ask' }).Status | Should Be 'NeedsUser'
    }

    It '4 Gunmote: missing = needs the user; found outside Program Files = no task with highest rights' {
        $none = Join-Path $TestDrive 'NoGunmote'
        (& "$steps\04-Gunmote.ps1" @common -GunmotePath $none -Tasks @()).Status | Should Be 'NeedsUser'
        $g = Join-Path $TestDrive 'Gunmote'
        New-Item -ItemType Directory -Path $g -Force | Out-Null
        [IO.File]::WriteAllBytes("$g\Gunmote.exe", [byte[]]@())
        (& "$steps\04-Gunmote.ps1" @common -GunmotePath $g -Tasks @()).Status | Should Be 'NeedsUser'
        Get-KitStateValue -Path $state -Key 'GunmoteDir' | Should Be $g
        $task = [pscustomobject]@{ TaskName = 'Gunmote'; TaskPath = '\'; State = 'Ready'; Actions = @([pscustomobject]@{ Execute = "$g\Gunmote.exe" }); Principal = [pscustomobject]@{ RunLevel = 'Highest' } }
        (& "$steps\04-Gunmote.ps1" @common -GunmotePath $g -Tasks @($task)).Status | Should Be 'Skipped'
    }
}
