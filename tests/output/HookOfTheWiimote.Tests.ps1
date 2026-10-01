$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'output\RetroCabinetKit.Output.psd1') -Force

# Detection of the Wiimote output chain (outputs.wiimote_hook): device ids and the MAME output mode, measured on a
# cabinet with two Bluetooth Wiimotes and RetroBat 7.
Describe 'Hook of the Wiimote detection' {
    It 'finds Bluetooth Wiimotes, which are not USB devices' {
        $bt = [pscustomobject]@{ Name = 'Bluetooth-HID-Gerät'; DeviceID = 'BTHENUM\{00001124-0000-1000-8000-00805F9B34FB}_VID&0002057E_PID&0330\A&295D669D&0&34AF2CD5795B_C00000000' }
        Test-HotwWiimoteDevice -Device @($bt) | Should Be $true
        Test-HotwWiimoteDevice -Device @([pscustomobject]@{ Name = 'Nintendo RVL-CNT-01'; DeviceID = 'BTHENUM\DEV_0017AB2CD0A0' }) | Should Be $true
    }

    It 'finds a DolphinBar and nothing in an unrelated device list' {
        Test-HotwWiimoteDevice -Device @([pscustomobject]@{ Name = 'HID'; DeviceID = 'USB\VID_0079&PID_1803\6&1' }) | Should Be $true
        Test-HotwWiimoteDevice -Device @([pscustomobject]@{ Name = 'Xbox 360 Controller'; DeviceID = 'USB\VID_045E&PID_028E\01' }) | Should Be $false
        Test-HotwWiimoteDevice -Device @() | Should Be $false
    }

    Context 'MAME output mode' {
        $rb = Join-Path $TestDrive 'RetroBat'
        $es = Join-Path $rb 'emulationstation\.emulationstation'
        $bios = Join-Path $rb 'bios\mame\ini'
        New-Item -ItemType Directory -Path $es, $bios -Force | Out-Null

        It 'takes RetroBat''s mame.mame_output over the ini RetroBat rewrites at every start' {
            Set-Content -LiteralPath (Join-Path $bios 'mame.ini') -Value "writeconfig 0`noutput auto" -Encoding Ascii
            Set-Content -LiteralPath (Join-Path $es 'es_settings.cfg') -Value '<?xml version="1.0"?><config><string name="mame.mame_output" value="windows" /></config>' -Encoding UTF8
            Test-HotwMameOutputWindows -RetroBatRoot $rb | Should Be $true
            Set-Content -LiteralPath (Join-Path $es 'es_settings.cfg') -Value '<?xml version="1.0"?><config><string name="mame.mame_output" value="network" /></config>' -Encoding UTF8
            Test-HotwMameOutputWindows -RetroBatRoot $rb | Should Be $false
        }

        It 'falls back to the ini when es_settings has no mame_output' {
            Set-Content -LiteralPath (Join-Path $es 'es_settings.cfg') -Value '<?xml version="1.0"?><config></config>' -Encoding UTF8
            Test-HotwMameOutputWindows -RetroBatRoot $rb | Should Be $false
            Set-Content -LiteralPath (Join-Path $bios 'mame.ini') -Value "writeconfig 0`noutput windows" -Encoding Ascii
            Test-HotwMameOutputWindows -RetroBatRoot $rb | Should Be $true
        }
    }
}
