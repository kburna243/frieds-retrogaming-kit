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

Describe 'Lightgun steps 5-7 as stand-alone scripts' {
    Set-KitCulture -Culture 'en-US'
    Mock -ModuleName 'RetroCabinetKit.Lightgun' Test-KitProcessesClosed { }
    $rb = Join-Path $TestDrive 'RetroBat'
    & $newRetroBat -Root $rb
    $g = Join-Path $TestDrive 'Gunmote'
    $steam = Join-Path $TestDrive 'Steam'
    & (Join-Path $PSScriptRoot 'New-LightgunTestGunmote.ps1') -Gunmote $g -Steam $steam
    $state = Join-Path $TestDrive 'install-state.json'
    $common = @{ StatePath = $state; Culture = 'en-US' }
    Set-KitStateValue -Path $state -Key 'RetroBatRoot' -Value $rb
    Set-KitStateValue -Path $state -Key 'GunmoteDir' -Value $g
    function Get-Hash([string] $Path) { (Get-FileHash -LiteralPath $Path).Hash }

    It '5 interference: dry run changes nothing; then the blacklist is written and verified; guard needs permission' {
        $guard = [pscustomobject]@{ TaskName = 'Gunmote Vmulti Guard'; TaskPath = '\EmuMote\'; State = 'Ready' }
        $vdf = "$steam\config\config.vdf"
        $hash = Get-Hash $vdf
        $r = @(& "$steps\05-Interference.ps1" @common -SteamPath $steam -Tasks @($guard) -Approve { throw 'must not ask' } -WhatIf)
        $r[0].WhatIf | Should Be $true
        Get-Hash $vdf | Should Be $hash
        $r = @(& "$steps\05-Interference.ps1" @common -SteamPath $steam -Tasks @($guard) -Approve { throw 'must not ask' })
        ($r | ForEach-Object { "$($_.Name)=$($_.Status)" }) -join ',' | Should Be 'lightgun-5-steam-blacklist=Done,lightgun-5-vmulti-guard=NeedsUser'
        $r = @(& "$steps\05-Interference.ps1" @common -SteamPath $steam -Tasks @() -Approve { throw 'must not ask' })
        ($r | ForEach-Object { "$($_.Name)=$($_.Status)" }) -join ',' | Should Be 'lightgun-5-steam-blacklist=Skipped,lightgun-5-vmulti-guard=Skipped'
    }

    It '5 interference: without Steam there is nothing to do for Steam' {
        (@(& "$steps\05-Interference.ps1" @common -SteamPath (Join-Path $TestDrive 'NoSteam') -Tasks @())[0]).Status | Should Be 'Skipped'
    }

    It '6 layouts: preview in the dry run, then written; the titles for step 8 are recorded; second run skipped' {
        $hash = Get-Hash "$g\Keymaps\Keymaps.json"
        (@(& "$steps\06-GunmoteLayouts.ps1" @common -WhatIf)[0]).Status | Should Be 'Skipped'
        Get-Hash "$g\Keymaps\Keymaps.json" | Should Be $hash
        (@(& "$steps\06-GunmoteLayouts.ps1" @common)[0]).Status | Should Be 'Done'
        (Get-KitStateValue -Path $state -Key 'LayoutTitles').TP | Should Be 'RCK TeknoParrot'
        (@(& "$steps\06-GunmoteLayouts.ps1" @common)[0]).Status | Should Be 'Skipped'
        (@(& "$steps\06-GunmoteLayouts.ps1" @common -Mode Replace)[0]).Status | Should Be 'Skipped'
    }

    It '7 settings: dry run changes nothing, then written and verified, second run 0 changes (skipped)' {
        $p = Get-LightgunRetroBatPath -Root $rb
        $hash = Get-Hash $p.EsSettings
        (& "$steps\07-RetroBatSettings.ps1" @common -WhatIf).Status | Should Be 'Skipped'
        Get-Hash $p.EsSettings | Should Be $hash
        (& "$steps\07-RetroBatSettings.ps1" @common).Status | Should Be 'Done'
        $hash = Get-Hash $p.EsSettings
        (& "$steps\07-RetroBatSettings.ps1" @common).Status | Should Be 'Skipped'
        Get-Hash $p.EsSettings | Should Be $hash
    }

    It '6 and 7 need the user while a guarded program runs' {
        Mock -ModuleName 'RetroCabinetKit.Lightgun' Test-KitProcessesClosed { [pscustomobject]@{ Name = 'emulationstation'; Id = 1 } }
        $rb2 = Join-Path $TestDrive 'RetroBat2'
        & $newRetroBat -Root $rb2
        (& "$steps\07-RetroBatSettings.ps1" @common -RetroBatRoot $rb2).Status | Should Be 'NeedsUser'
        $g2 = Join-Path $TestDrive 'Gunmote2'
        & (Join-Path $PSScriptRoot 'New-LightgunTestGunmote.ps1') -Gunmote $g2
        (@(& "$steps\06-GunmoteLayouts.ps1" @common -GunmotePath $g2)[0]).Status | Should Be 'NeedsUser'
    }
}
