$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'api\RetroCabinetKit.Api.psd1') -Force

# Contract of the two input-matrix operations (API 1.5): dry run, -Apply, refusal, listing. Fake RetroBat in TestDrive;
# the user profile folder of the arcade module is pointed into TestDrive, so no real profile is read.
Describe 'API 1.5 -- input matrix' {
    Set-KitCulture -Culture 'en-US'
    foreach ($m in @(Get-Module -All 'RetroCabinetKit.Arcade')) { & $m { $script:InputUserDir = $args[0] } (Join-Path $TestDrive 'home\InputProfiles') }
    $rb = Join-Path $TestDrive 'RetroBat'
    $ctrlrDir = Join-Path $rb 'saves\mame\ctrlr'
    $null = New-Item -ItemType Directory -Path $ctrlrDir, (Join-Path $rb 'emulationstation\.emulationstation') -Force
    [IO.File]::WriteAllText((Join-Path $ctrlrDir 'custom1.cfg'), '<mameconfig version="10" />')

    It 'API: the dry run writes nothing, -Apply writes, a refused file is Failed' {
        $target = Join-Path $ctrlrDir 'api.cfg'
        $dry = Invoke-KitOperation -Name 'controllers.input_apply' -Parameters @{ Profile = 'ipac2-default'; CtrlrName = 'api'; RetroBatRoot = $rb }
        $dry.Status | Should Be 'WhatIf'
        @($dry.Changes).Count | Should Be 26
        Test-Path $target | Should Be $false
        $done = Invoke-KitOperation -Name 'controllers.input_apply' -Parameters @{ Profile = 'ipac2-default'; CtrlrName = 'api'; RetroBatRoot = $rb } -Apply
        $done.Status | Should Be 'Done'
        $done.Applied | Should Be $true
        Test-Path $target | Should Be $true
        $refused = Invoke-KitOperation -Name 'controllers.input_apply' -Parameters @{ Profile = 'ipac2-default'; CtrlrName = 'custom1'; RetroBatRoot = $rb } -Apply
        $refused.Status | Should Be 'Failed'
        $list = Invoke-KitOperation -Name 'controllers.input_profiles'
        $list.Status | Should Be 'Ok'
        @($list.Data.Profiles | Where-Object { $_.Name -eq 'ipac2-default' }).Count | Should Be 1
    }
}

Describe 'API 1.6 -- XInput slots' {
    It 'API: reads the four slots and says how many are in use' {
        $r = Invoke-KitOperation -Name 'controllers.xinput_slots'
        $r.Status | Should Be 'Ok'
        $r.Kind | Should Be 'Read'
        @($r.Data.Slots).Count | Should Be 4
        (@($r.Data.Slots) | ForEach-Object { $_.Slot }) -join ',' | Should Be '0,1,2,3'
        $r.Message | Should Match '^\d of 4 XInput slot'
    }
}
