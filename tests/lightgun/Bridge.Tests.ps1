$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1') -Force
$newRetroBat = Join-Path $PSScriptRoot 'New-LightgunTestRetroBat.ps1'
$newGunmote = Join-Path $PSScriptRoot 'New-LightgunTestGunmote.ps1'

# The two Wiimote connections (DolphinBar, Bluetooth) and the game helper that replaced the cabinet's hand-made
# bridge. Devices are injected, the hooks run with their program replaced by echo, no DemulShooter is started and
# nothing talks to a real relay.
$bar4 = [pscustomobject]@{ InstanceId = 'USB\VID_057E&PID_0306\5&1' }
$btWii = [pscustomobject]@{ InstanceId = 'HID\{00001124-0000-1000-8000-00805F9B34FB}_VID&0002057E_PID&0330\B&365BF8AA&4&0000' }
$m60 = [pscustomobject]@{ DeviceName = 'D1'; Width = 1920; Height = 1080; RefreshRate = 60 }

Describe 'Wiimote connection' {
    It 'tells the DolphinBar from Bluetooth Wiimotes; a bar in Mode 4 wins' {
        Get-LightgunConnection -Devices @($bar4) | Should Be 'DolphinBar'
        Get-LightgunConnection -Devices @($btWii) | Should Be 'Bluetooth'
        Get-LightgunConnection -Devices @($bar4, $btWii) | Should Be 'DolphinBar'
        Get-LightgunConnection -Devices @() | Should Be ''
        Get-LightgunBluetoothWiimoteCount -Devices @($btWii, $btWii, $bar4) | Should Be 2
    }

    It 'with nothing connected takes the connection used last' {
        $old = Get-Date '2026-09-20'; $new = Get-Date '2026-10-01'
        Get-LightgunLastConnection -Devices @(
            [pscustomobject]@{ InstanceId = $bar4.InstanceId; Arrived = $old }, [pscustomobject]@{ InstanceId = $btWii.InstanceId; Arrived = $new }) | Should Be 'Bluetooth'
        Get-LightgunLastConnection -Devices @(
            [pscustomobject]@{ InstanceId = $bar4.InstanceId; Arrived = $new }, [pscustomobject]@{ InstanceId = $btWii.InstanceId; Arrived = $old }) | Should Be 'DolphinBar'
        Get-LightgunLastConnection -Devices @() | Should Be ''
    }

    It 'resolves parameter, then state, then now, then last, then DolphinBar' {
        $state = Join-Path $TestDrive 'conn-state.json'
        Resolve-LightgunConnection -Connection 'Bluetooth' -StatePath $state -Devices @($bar4) | Should Be 'Bluetooth'
        Resolve-LightgunConnection -StatePath $state -Devices @($btWii) | Should Be 'Bluetooth'
        Resolve-LightgunConnection -StatePath $state -Devices @() -History @([pscustomobject]@{ InstanceId = $btWii.InstanceId; Arrived = (Get-Date) }) | Should Be 'Bluetooth'
        Resolve-LightgunConnection -StatePath $state -Devices @() -History @() | Should Be 'DolphinBar'
        Set-KitStateValue -Path $state -Key 'WiimoteConnection' -Value 'Bluetooth'
        Resolve-LightgunConnection -StatePath $state -Devices @($bar4) | Should Be 'Bluetooth'
    }

    It 'step 2 accepts Bluetooth Wiimotes without a DolphinBar' {
        Test-LightgunHardware -Devices @($btWii) -Service $null -Monitors @($m60) -Quiet | Should Be $true
        Test-LightgunHardware -Devices @() -Service $null -Monitors @($m60) -Quiet | Should Be $false
    }
}

Describe 'Profiles and layouts per connection' {
    It 'over Bluetooth gives the RawInput emulators the pad and DuckStation the mouse' {
        foreach ($s in 'model2', 'model3', 'singe', 'daphne', 'mame') { Get-LightgunProfileFor $s -Connection Bluetooth | Should Be 'Pad43' }
        Get-LightgunProfileFor 'psx' -Connection Bluetooth | Should Be 'Mouse43'
        Get-LightgunProfileFor 'naomi' -Connection Bluetooth | Should Be 'Naomi'
        Get-LightgunProfileFor 'teknoparrot' -Connection Bluetooth | Should Be 'TP'
        # DolphinBar keeps the measured mouse route (27.09.)
        Get-LightgunProfileFor 'model3' -Connection DolphinBar | Should Be 'Mouse43'
        Get-LightgunProfileFor 'psx' -Connection DolphinBar | Should Be 'Pad43'
    }

    It 'the Naomi task aims with the pad over Bluetooth and with the mouse over the DolphinBar' {
        $titles = [pscustomobject]@{ Menu = 'M'; Pad43 = 'P43'; TP = 'T'; Mouse = 'Mo'; Mouse43 = 'M43' }
        (@(Get-LightgunProfileTaskPlan -Titles $titles -AutomationDir 'C:\x' -Connection Bluetooth) | Where-Object Name -eq 'Naomi').Argument | Should Match '-Layout "P43"$'
        (@(Get-LightgunProfileTaskPlan -Titles $titles -AutomationDir 'C:\x' -Connection DolphinBar) | Where-Object Name -eq 'Naomi').Argument | Should Match '-Layout "M43"$'
    }

    It 'the Bluetooth hook selects the pad for Model 3 and the mouse for PSX (schtasks replaced by echo)' {
        $bat = Join-Path $TestDrive 'bt-start.bat'
        [IO.File]::WriteAllText($bat, ((New-LightgunHookText -Kind 'Start' -TaskPrefix 'T' -Connection Bluetooth) -replace 'schtasks /run /tn ("[^"]+") >nul 2>&1', 'echo TASK=$1'), [Text.Encoding]::ASCII)
        (& cmd.exe /d /c "`"$bat`" `"X:\RetroBat\roms\model3\lostwsga.zip`"" 2>&1 | Out-String).Trim() | Should BeExactly 'TASK="T Pad43"'
        (& cmd.exe /d /c "`"$bat`" `"X:\RetroBat\roms\psx\A & B.chd`"" 2>&1 | Out-String).Trim() | Should BeExactly 'TASK="T Mouse43"'
    }

    It 'step 6 over Bluetooth puts Supermodel, Model 2, Demul and Hypseus on the pad layout and DuckStation on mouse 4:3' {
        $g = Join-Path $TestDrive 'GBT'
        & $newGunmote -Gunmote $g
        $plan = Get-LightgunLayoutPlan -KeymapsDir "$g\Keymaps" -RetroBatRoot 'X:\RetroBat' -Connection Bluetooth
        $apps = $plan.Keymaps.Applications
        foreach ($exe in 'supermodel\supermodel.exe', 'm2emulator\emulator_multicpu.exe', 'demul\demul.exe', 'hypseus\hypseus.exe') {
            ($apps | Where-Object { $_.Search -eq "X:\RetroBat\emulators\$exe" }).Keymap | Should Be 'rck_pad43.json'
        }
        ($apps | Where-Object { $_.Search -eq 'X:\RetroBat\emulators\duckstation\duckstation-qt-x64-ReleaseLTCG.exe' }).Keymap | Should Be 'rck_mouse43.json'
        $db = Get-LightgunLayoutPlan -KeymapsDir "$g\Keymaps" -RetroBatRoot 'X:\RetroBat' -Connection DolphinBar
        ($db.Keymaps.Applications | Where-Object { $_.Search -eq 'X:\RetroBat\emulators\supermodel\supermodel.exe' }).Keymap | Should Be 'rck_mouse43.json'
        @($db.Keymaps.Applications | Where-Object { $_.Search -like '*duckstation*' }).Count | Should Be 0
    }

    It 'keeps a menu layout with Home on the Xbox Guide button (Keep), not on any other layout' {
        $g = Join-Path $TestDrive 'GH'
        & $newGunmote -Gunmote $g
        $menu = [ordered]@{ All = [ordered]@{ OnScreen = [ordered]@{ Pointer = 'disable'; B = '360.a'; Home = '360.guide' }; OffScreen = [ordered]@{ Pointer = 'disable'; B = '360.a' } } }
        [IO.File]::WriteAllText("$g\Keymaps\my_menu.json", (ConvertTo-Json $menu -Depth 5))
        (Get-LightgunLayoutInfo -KeymapsDir "$g\Keymaps" -File 'my_menu.json').Correct | Should Be $true
        $menu.All.OnScreen.Pointer = '360.stickl-light-4:3'; $menu.All.OffScreen.Pointer = '360.stickl-light-4:3'
        $menu.All.OnScreen.B = '360.b'; $menu.All.OffScreen.B = '360.b'
        [IO.File]::WriteAllText("$g\Keymaps\my_pad.json", (ConvertTo-Json $menu -Depth 5))
        (Get-LightgunLayoutInfo -KeymapsDir "$g\Keymaps" -File 'my_pad.json').Correct | Should Be $false
    }
}

Describe 'Game helper hook' {
    It 'starts only the kit''s GameHelper.ps1 with the connection, quoted ROM path, no task, no elevation' {
        $text = New-LightgunGameHelperHookText -Kind Start -Connection Bluetooth -HelperPath 'C:\Kit\lightgun\tools\GameHelper.ps1'
        $lines = @($text -split "`r`n" | Where-Object { $_ -and $_ -notmatch '^rem ' })
        $lines.Count | Should Be 2
        $lines[1] | Should BeExactly 'start "" /b "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "C:\Kit\lightgun\tools\GameHelper.ps1" -Phase Start -Connection Bluetooth -Rom "%~1"'
        $text | Should Not Match '(?i)schtasks|runas|-Verb'
        { New-LightgunGameHelperHookText -Kind End -HelperPath 'C:\100%\x.ps1' } | Should Throw
    }

    It 'passes ROM paths with & ^ % and spaces through unchanged (powershell replaced by echo)' {
        $bat = Join-Path $TestDrive 'helper-start.bat'
        $text = (New-LightgunGameHelperHookText -Kind Start -HelperPath 'C:\Kit\h.ps1') -replace 'start "" /b "[^"]+" ', 'echo '
        [IO.File]::WriteAllText($bat, $text, [Text.Encoding]::ASCII)
        $out = (& cmd.exe /d /c "`"$bat`" `"X:\RetroBat\roms\naomi\A & B ^C 100%.zip`"" 2>&1 | Out-String).Trim()
        $out | Should BeExactly '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "C:\Kit\h.ps1" -Phase Start -Connection DolphinBar -Rom "X:\RetroBat\roms\naomi\A & B ^C 100%.zip"'
    }

    It 'step 8 writes both hook pairs once and checks them' {
        $rb = Join-Path $TestDrive 'RBH'
        & $newRetroBat -Root $rb
        $p = Get-LightgunRetroBatPath -Root $rb
        Test-LightgunHook -RetroBatRoot $rb -TaskPrefix 'T' -Connection Bluetooth | Should Be $false
        Install-LightgunHook -RetroBatRoot $rb -TaskPrefix 'T' -Connection Bluetooth -Confirm:$false
        foreach ($d in $p.HookStart, $p.HookEnd) { foreach ($n in 'rck-gunmote-profile.bat', 'rck-game-helper.bat') { Join-Path $d $n | Should Exist } }
        Test-LightgunHook -RetroBatRoot $rb -TaskPrefix 'T' -Connection Bluetooth | Should Be $true
        Test-LightgunHook -RetroBatRoot $rb -TaskPrefix 'T' -Connection DolphinBar | Should Be $false
    }
}

Describe 'Game helper plan' {
    It 'starts DemulShooter only for a known gun ROM, with the target of its system' {
        $p = Get-LightgunGameHelperPlan -Phase Start -Rom 'F:\RetroBat\roms\naomi\hotd2.zip'
        $p.DemulShooter.Target | Should Be 'demul07a'; $p.DemulShooter.Rom | Should Be 'hotd2'
        (Get-LightgunGameHelperPlan -Phase Start -Rom 'F:\RetroBat\roms\atomiswave\sprtshot.zip').DemulShooter.Target | Should Be 'demul07a'
        (Get-LightgunGameHelperPlan -Phase Start -Rom 'F:\RetroBat\roms\model2\vcop.zip').DemulShooter.Target | Should Be 'model2m'
        (Get-LightgunGameHelperPlan -Phase Start -Rom 'F:\RetroBat\roms\naomi\unknown.zip').DemulShooter | Should BeNullOrEmpty
        (Get-LightgunGameHelperPlan -Phase Start -Rom 'F:\RetroBat\roms\naomi\a & calc.zip').DemulShooter | Should BeNullOrEmpty
        (Get-LightgunGameHelperPlan -Phase Start -Rom 'F:\RetroBat\roms\mame\hotd2.zip').DemulShooter | Should BeNullOrEmpty
    }

    It 'ends DemulShooter at game end of its systems only' {
        (Get-LightgunGameHelperPlan -Phase End -Rom 'F:\RetroBat\roms\model2\vcop.zip').StopDemulShooter | Should Be $true
        (Get-LightgunGameHelperPlan -Phase End -Rom 'F:\RetroBat\roms\mame\alien3.zip').StopDemulShooter | Should Be $false
        (Get-LightgunGameHelperPlan -Phase End -Rom 'F:\RetroBat\roms\naomi\hotd2.zip').DemulShooter | Should BeNullOrEmpty
    }

    It 'sets FFBBlaster network outputs for TeknoParrot at start and end, with the RetroBat folder from the ROM path' {
        $p = Get-LightgunGameHelperPlan -Phase End -Rom 'F:\RetroBat\roms\teknoparrot\Rambo\x.parrot'
        $p.FfbNetOutputs | Should Be $true; $p.RetroBatRoot | Should Be 'F:\RetroBat'
        (Get-LightgunGameHelperPlan -Phase Start -Rom 'F:\RetroBat\roms\mame\alien3.zip').FfbNetOutputs | Should Be $false
        (Get-LightgunGameHelperPlan -Phase Start -Rom '').FfbNetOutputs | Should Be $false
    }

    It 'checks the player order only over Bluetooth, at game start, for light gun systems' {
        (Get-LightgunGameHelperPlan -Phase Start -Rom 'F:\RetroBat\roms\mame\alien3.zip' -Connection Bluetooth).OrderCheck | Should Be $true
        (Get-LightgunGameHelperPlan -Phase Start -Rom 'F:\RetroBat\roms\mame\alien3.zip' -Connection DolphinBar).OrderCheck | Should Be $false
        (Get-LightgunGameHelperPlan -Phase End -Rom 'F:\RetroBat\roms\mame\alien3.zip' -Connection Bluetooth).OrderCheck | Should Be $false
        (Get-LightgunGameHelperPlan -Phase Start -Rom 'F:\RetroBat\roms\n64\x.z64' -Connection Bluetooth).OrderCheck | Should Be $false
    }

    It 'asks the relay to show the players only when the order is swapped' {
        $w = @([pscustomobject]@{ Player = 1; Expected = 2 }, [pscustomobject]@{ Player = 2; Expected = 1 })
        Get-LightgunShowPlayersCommand -Order ([pscustomobject]@{ State = 'Swapped'; Wiimotes = $w }) | Should BeExactly 'SHOW_PLAYERS 1=2 2=1'
        foreach ($s in 'Ok', 'Unclear', 'Unbound', 'NoGunmote', 'NoWiimote') {
            Get-LightgunShowPlayersCommand -Order ([pscustomobject]@{ State = $s; Wiimotes = $w }) | Should BeNullOrEmpty
        }
    }

    It 'reports an unreachable relay instead of failing' {
        Send-LightgunRelayCommand -Command 'PING' -Port 1 -TimeoutMs 300 | Should Be $false
    }
}

Describe 'FFBBlaster network outputs' {
    function New-TpGame([string] $Root, [string] $Name, [string] $Enable) {
        $profiles = Join-Path $Root 'emulators\teknoparrot\UserProfiles'
        $game = Join-Path $Root "roms\teknoparrot\$Name"
        New-Item -ItemType Directory -Path $profiles, $game -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $profiles "$Name.xml"), @"
<?xml version="1.0" encoding="utf-8"?>
<GameProfile><GamePath>$game\game.exe</GamePath><ConfigValues>
<FieldInformation><CategoryName>FFB Blaster</CategoryName><FieldName>Enable</FieldName><FieldValue>$Enable</FieldValue></FieldInformation>
</ConfigValues></GameProfile>
"@)
        [IO.File]::WriteAllText((Join-Path $game 'FFBBlaster.ini'), "[Settings]`r`nOutputsSystem=0`r`nNetOutputsTCPPort=8000`r`nOther=1`r`n")
        Join-Path $game 'FFBBlaster.ini'
    }

    It 'switches the games with FFB Blaster on to port 8002, once, with a backup; others stay' {
        $rb = Join-Path $TestDrive 'RBT'
        $on = New-TpGame $rb 'Rambo' '1'
        $off = New-TpGame $rb 'Other' '0'
        @(Set-LightgunTpNetOutput -RetroBatRoot $rb -Confirm:$false) | Should Be @($on)
        [IO.File]::ReadAllLines($on) | Should Be @('[Settings]', 'OutputsSystem=1', 'NetOutputsTCPPort=8002', 'Other=1')
        "$on.bak_netoutputs" | Should Exist
        [IO.File]::ReadAllText($off) | Should Match 'OutputsSystem=0'
        @(Set-LightgunTpNetOutput -RetroBatRoot $rb -Confirm:$false).Count | Should Be 0
    }
}
