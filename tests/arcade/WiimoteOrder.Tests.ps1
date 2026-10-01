$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'arcade\RetroCabinetKit.Arcade.psd1') -Force

# Wiimote player order: Gunmote numbers the Wiimotes in the order they connect, Windows keeps that order as
# LastArrivalDate. Devices, Gunmote start and binding are injected; the addresses are the two measured Wiimotes.
Describe 'Wiimote player order' {
    $start = [datetime]'2026-10-02 00:04:34'
    $plain = [pscustomobject]@{ Mac = '0017AB2CD0A0'; Model = 'RVL-CNT-01';    Arrived = $start.AddSeconds(7) }
    $tr    = [pscustomobject]@{ Mac = '34AF2CD5795B'; Model = 'RVL-CNT-01-TR'; Arrived = $start.AddSeconds(9) }
    $bind  = @([pscustomobject]@{ Player = 1; Mac = '0017AB2CD0A0' }, [pscustomobject]@{ Player = 2; Mac = '34AF2CD5795B' })

    It 'numbers the players by arrival and finds the binding kept' {
        $o = Get-ArcadeWiimoteOrder -Device @($tr, $plain) -GunmoteStart $start -Ledger $bind
        ($o.Wiimotes | ForEach-Object { "$($_.Player)=$($_.Mac)" }) -join ' ' | Should Be '1=0017AB2CD0A0 2=34AF2CD5795B'
        $o.State | Should Be 'Ok'
    }

    It 'reports swapped players and the order to switch them on in' {
        $late = [pscustomobject]@{ Mac = $plain.Mac; Model = $plain.Model; Arrived = $start.AddSeconds(12) }
        $o = Get-ArcadeWiimoteOrder -Device @($late, $tr) -GunmoteStart $start -Ledger $bind
        $o.State | Should Be 'Swapped'
        $o.SwitchOnOrder -join ', ' | Should Be '0017AB2CD0A0 (RVL-CNT-01), 34AF2CD5795B (RVL-CNT-01-TR)'
    }

    It 'says unclear instead of guessing: a Wiimote before Gunmote, or arrivals far apart (reconnect?)' {
        $early = [pscustomobject]@{ Mac = $plain.Mac; Model = $plain.Model; Arrived = $start.AddSeconds(-30) }
        (Get-ArcadeWiimoteOrder -Device @($early, $tr) -GunmoteStart $start -Ledger $bind).State | Should Be 'Unclear'
        $back = [pscustomobject]@{ Mac = $tr.Mac; Model = $tr.Model; Arrived = $start.AddMinutes(20) }
        (Get-ArcadeWiimoteOrder -Device @($plain, $back) -GunmoteStart $start -Ledger $bind).State | Should Be 'Unclear'
    }

    It 'without Gunmote, without Wiimotes, without a binding' {
        (Get-ArcadeWiimoteOrder -Device @($plain, $tr) -GunmoteStart $null -Ledger $bind).State | Should Be 'NoGunmote'
        (Get-ArcadeWiimoteOrder -Device @() -GunmoteStart $start -Ledger $bind).State | Should Be 'NoWiimote'
        (Get-ArcadeWiimoteOrder -Device @($plain, $tr) -GunmoteStart $start -Ledger @()).State | Should Be 'Unbound'
    }

    It 'saves the current order as the binding, -WhatIf writes nothing, an old file is kept as backup' {
        $path = Join-Path $TestDrive 'RetroCabinet\wiimotes.json'
        $rows = (Get-ArcadeWiimoteOrder -Device @($tr, $plain) -GunmoteStart $start -Ledger @()).Wiimotes
        $null = Save-ArcadeWiimoteLedger -Wiimotes $rows -Path $path -WhatIf
        Test-Path $path | Should Be $false
        $null = Save-ArcadeWiimoteLedger -Wiimotes $rows -Path $path -Confirm:$false
        $saved = @(Get-ArcadeWiimoteLedger -Path $path)
        ($saved | ForEach-Object { "$($_.Player)=$($_.Mac)" }) -join ' ' | Should Be '1=0017AB2CD0A0 2=34AF2CD5795B'
        $null = Save-ArcadeWiimoteLedger -Wiimotes $rows -Path $path -Confirm:$false
        @(Get-ChildItem (Split-Path $path) -Filter 'wiimotes.json.bak_*').Count | Should Be 1
    }
}
