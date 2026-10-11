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

Describe 'API 1.6 -- Wiimote player order' {
    It 'API: the order is read with a known state; binding without -Apply writes nothing' {
        $r = Invoke-KitOperation -Name 'controllers.wiimote_order'
        $r.Status | Should Be 'Ok'
        @('Ok', 'Swapped', 'Unbound', 'Unclear', 'NoGunmote', 'NoWiimote') -contains $r.Data.State | Should Be $true
        $ledger = Join-Path $env:USERPROFILE 'RetroCabinet\wiimotes.json'
        $before = if (Test-Path $ledger) { (Get-Item $ledger).LastWriteTimeUtc } else { $null }
        $plan = Invoke-KitOperation -Name 'controllers.wiimote_bind'
        @('WhatIf', 'Failed') -contains $plan.Status | Should Be $true   # Failed: no Wiimote on this machine
        $plan.Applied | Should Be $false
        $after = if (Test-Path $ledger) { (Get-Item $ledger).LastWriteTimeUtc } else { $null }
        $after | Should Be $before
    }
}

# API 1.8: the binding by Bluetooth address, bound to its plan. The ledger is pointed into TestDrive; the connected
# Wiimotes are injected, so no real wiimotes.json is read or written.
Describe 'API 1.8 -- Wiimote binding by Bluetooth address' {
    Set-KitCulture -Culture 'en-US'
    $ledger = Join-Path $TestDrive 'home\RetroCabinet\wiimotes.json'
    foreach ($m in @(Get-Module -All 'RetroCabinetKit.Arcade')) { & $m { $script:WiimoteLedgerPath = $args[0] } $ledger }
    Mock -ModuleName RetroCabinetKit.Arcade Get-ArcadeWiimoteDevice { [pscustomobject]@{ Mac = '34AF2CD5795B'; Model = 'RVL-CNT-01-TR'; Arrived = Get-Date } }

    It 'offers Binding and PlanId; the plan names the chosen players and writes nothing' {
        $op = @(Get-KitOperation | Where-Object Name -eq 'controllers.wiimote_bind')[0]
        @($op.Parameters | ForEach-Object Name) -join ',' | Should Be 'Binding,PlanId'
        $plan = Invoke-KitOperation -Name 'controllers.wiimote_bind' -Parameters @{ Binding = '34:af:2c:d5:79:5b=1, 0017AB2CD0A0=2' }
        $plan.Status | Should Be 'WhatIf'
        $plan.Data.Source | Should Be 'Binding'
        ($plan.Data.Wiimotes | ForEach-Object { "$($_.Player)=$($_.Mac)/$($_.Model)" }) -join ' ' | Should Be '1=34AF2CD5795B/RVL-CNT-01-TR 2=0017AB2CD0A0/'
        $plan.Data.PlanId | Should Match '^[0-9a-f]{64}$'
        $plan.Changes[0].Kind | Should Be 'File'
        $plan.Changes[0].Detail | Should Be 'player 1 = 34AF2CD5795B'
        Test-Path $ledger | Should Be $false
    }

    It 'applies with the PlanId of the plan, refuses a stale one and writes nothing then' {
        $binding = @{ Binding = '34AF2CD5795B=1,0017AB2CD0A0=2' }
        $plan = Invoke-KitOperation -Name 'controllers.wiimote_bind' -Parameters $binding
        $done = Invoke-KitOperation -Name 'controllers.wiimote_bind' -Parameters @{ Binding = $binding.Binding; PlanId = $plan.Data.PlanId } -Apply
        $done.Status | Should Be 'Done'
        (Get-Content $ledger -Raw | ConvertFrom-Json).Wiimotes[1].Mac | Should Be '0017AB2CD0A0'
        $before = Get-Content $ledger -Raw
        # The same PlanId again: the file is now different, so it is a plan for a state that is gone.
        $stale = Invoke-KitOperation -Name 'controllers.wiimote_bind' -Parameters @{ Binding = '34AF2CD5795B=2,0017AB2CD0A0=1'; PlanId = $plan.Data.PlanId } -Apply
        $stale.Status | Should Be 'Failed'
        $stale.Message | Should Match 'changed since this plan'
        Get-Content $ledger -Raw | Should Be $before
    }

    It 'refuses a malformed binding, a player twice or a MAC twice' {
        foreach ($bad in 'nonsense', '34AF2CD5795B=5', '34AF2CD5795B=1,0017AB2CD0A0=1', '34AF2CD5795B=1,34af2cd5795b=2') {
            $r = Invoke-KitOperation -Name 'controllers.wiimote_bind' -Parameters @{ Binding = $bad }
            $r.Status | Should Be 'Failed'
        }
    }
}