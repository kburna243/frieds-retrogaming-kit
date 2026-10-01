$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'output\RetroCabinetKit.Output.psd1') -Force
$newRetroBat = Join-Path $kitRoot 'tests\lightgun\New-LightgunTestRetroBat.ps1'
$steps = Join-Path $kitRoot 'output\steps'

# Output middleware adapters. Detection reads an injected snapshot only (no live processes, no live
# ports); configuration writes exist in synthetic RetroBat folders with mocked process guards.
Describe 'Output adapter catalog and multi detection' {
    Set-KitCulture -Culture 'en-US'

    It 'ships six complete adapters; the underscore template is never listed' {
        $cat = @(Get-OutputAdapterCatalog)
        ($cat | ForEach-Object Name) -join ',' | Should Be 'DirectOutputFramework,FFBBlaster,GunmoteOutput,HookOfTheReaper,MameHooker,QMamehook'
        foreach ($a in $cat) {
            $a.HasParseErrors | Should Be $false
            $a.HasTest | Should Be $true
            $a.HasInfo | Should Be $true
            $a.HasInstall | Should Be $true
            $a.HasConfigure | Should Be $true
            $a.HasShield | Should Be $true
        }
    }

    It 'detects nothing in an empty world without raising errors' {
        $r = Get-OutputDetectedMiddleware -Snapshot @{ Processes = @(); Ports = @(); Devices = @() } -Quiet
        $r.Success | Should Be $false
        @($r.DetectedOutputs).Count | Should Be 0
        @($r.Conflicts).Count | Should Be 0
        @($r.Errors).Count | Should Be 0
        $r.ScannedAdapters | Should Be 'DirectOutputFramework,FFBBlaster,GunmoteOutput,HookOfTheReaper,MameHooker,QMamehook'
    }

    It 'detects each middleware by process, port and tools folder' {
        $r = Get-OutputDetectedMiddleware -Snapshot @{ Processes = @('mamehooker'); Ports = @(); Devices = @() } -Quiet
        $r.DetectedOutputs -join ',' | Should Be 'MameHooker'
        $r.OutputMode | Should Be 'windows'
        $r = Get-OutputDetectedMiddleware -Snapshot @{ Processes = @(); Ports = @(9735); Devices = @() } -Quiet
        $r.DetectedOutputs -join ',' | Should Be 'QMamehook'
        $r.OutputMode | Should Be 'network'
        $rb = Join-Path $TestDrive 'ToolsBat'
        New-Item -ItemType Directory -Path (Join-Path $rb 'tools\HookOfTheReaper') -Force | Out-Null
        $r = Get-OutputDetectedMiddleware -RetroBatRoot $rb -Snapshot @{ Processes = @(); Ports = @(); Devices = @() } -Quiet
        $r.DetectedOutputs -join ',' | Should Be 'HookOfTheReaper'
        $r.OutputMode | Should Be 'windows'
    }

    It 'detects DirectOutputFramework by process and keeps its hands off the boards' {
        $r = Get-OutputDetectedMiddleware -Snapshot @{ Processes = @('DirectOutput'); Ports = @(); Devices = @() } -Quiet
        ($r.DetectedOutputs -join ',') | Should Be 'DirectOutputFramework'
        $r.OutputMode | Should Be 'windows'
        @($r.Conflicts).Count | Should Be 0
        # DOF claims no BoardMatchIds: a lone LED-Wiz board stays MameHooker's evidence, never DOF's.
        $r = Get-OutputDetectedMiddleware -Snapshot @{ Processes = @(); Ports = @(); Devices = @('USB\VID_0DFA&PID_0001&0') } -Quiet
        ($r.DetectedOutputs -join ',') | Should Be 'MameHooker'
    }

    It 'two windows consumers (DOF + MameHooker) coexist; only windows-vs-network conflicts' {
        $r = Get-OutputDetectedMiddleware -Snapshot @{ Processes = @('DirectOutput', 'mamehooker'); Ports = @(); Devices = @() } -Quiet
        ($r.DetectedOutputs -join '+') | Should Be 'DirectOutputFramework+MameHooker'
        $r.OutputMode | Should Be 'windows'
        @($r.Conflicts).Count | Should Be 0
        $r = Get-OutputDetectedMiddleware -Snapshot @{ Processes = @('DirectOutput', 'qmamehook'); Ports = @(); Devices = @() } -Quiet
        @($r.Conflicts).Count | Should Be 1
        $r.Conflicts[0].Kind | Should Be 'OutputModeConflict'
    }

    It 'reports OutputModeConflict instead of picking a winner when windows and network tools run at once' {
        $r = Get-OutputDetectedMiddleware -Snapshot @{ Processes = @('mamehooker', 'qmamehook'); Ports = @(); Devices = @() } -Quiet
        ($r.DetectedOutputs -join '+') | Should Be 'MameHooker+QMamehook'
        $r.OutputMode | Should BeNullOrEmpty
        @($r.Conflicts).Count | Should Be 1
        $r.Conflicts[0].Kind | Should Be 'OutputModeConflict'
        $r.Conflicts[0].Detail | Should Match 'windows'
    }

    It 'flags broken adapter files as errors and keeps scanning' {
        $dir = Join-Path $TestDrive 'brokendir'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $dir 'NoInfo.ps1'), 'function Test-NoInfoHardware { param($RetroBatRoot,$Snapshot) $true }')
        [IO.File]::WriteAllText((Join-Path $dir 'Kaboom.ps1'), "function Test-KaboomHardware { param(`$RetroBatRoot,`$Snapshot) throw 'port scanner died' }`nfunction Get-KaboomAdapterInfo { @{} }")
        $r = Get-OutputDetectedMiddleware -Snapshot @{ Processes = @(); Ports = @(); Devices = @() } -Dir $dir -Quiet
        @($r.Errors).Count | Should Be 2
        $r.ScannedAdapters | Should Be 'Kaboom'
    }
}

Describe 'Output middleware configuration' {
    Set-KitCulture -Culture 'en-US'
    Mock -ModuleName 'RetroCabinetKit.Lightgun' Test-KitProcessesClosed { }
    $rb = Join-Path $TestDrive 'RetroBat'
    & $newRetroBat -Root $rb
    $mameDir = Join-Path $rb 'emulators\mame'
    $hotrDir = Join-Path $rb 'tools\HookOfTheReaper'
    $qmDir   = Join-Path $rb 'tools\QMamehook'
    New-Item -ItemType Directory -Path $mameDir, $hotrDir, $qmDir -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $mameDir 'mame.ini'), ('output                      none' + "`r`n"), (New-Object Text.UTF8Encoding $false))
    [IO.File]::WriteAllText((Join-Path $hotrDir 'settings.ini'), "[Reaper]`r`nDefaultLGPath=old`r`n", (New-Object Text.UTF8Encoding $false))
    [IO.File]::WriteAllText((Join-Path $qmDir 'qmhook.ini'), 'Other = keepme' + "`r`n", (New-Object Text.UTF8Encoding $false))

    It 'writes output windows plus the enforced solenoid safety values' {
        Set-OutputMiddlewareConfiguration -Names @('MameHooker', 'HookOfTheReaper') -RetroBatRoot $rb -Confirm:$false | Should BeGreaterThan 0
        [IO.File]::ReadAllText((Join-Path $mameDir 'mame.ini')) | Should Match 'output\s+windows'
        $ini = [IO.File]::ReadAllText((Join-Path $hotrDir 'settings.ini'))
        $ini | Should Match 'SolenoidMaxOpenTime\s*=\s*200'
        $ini | Should Match 'SolenoidProtection\s*=\s*1'
        $ini | Should Match 'TcpServerPort\s*=\s*8000'
        $ini | Should Match 'DefaultLGPath\s*=\s*old'  # untouched user values survive
        Test-OutputMiddlewareConfiguration -Names @('MameHooker', 'HookOfTheReaper') -RetroBatRoot $rb | Should Be $true
        Set-OutputMiddlewareConfiguration -Names @('MameHooker', 'HookOfTheReaper') -RetroBatRoot $rb -Confirm:$false | Should Be 0
    }

    It 'a missing settings file is skipped with a warning, not created' {
        $ghost = Join-Path $TestDrive 'Ghost'
        New-Item -ItemType Directory -Path $ghost -Force | Out-Null
        $null = Set-OutputMiddlewareConfiguration -Names @('HookOfTheReaper') -RetroBatRoot $ghost -Confirm:$false
        Test-Path (Join-Path $ghost 'tools\HookOfTheReaper\settings.ini') | Should Be $false
    }

    It 'a missing settings file keeps verification red' {
        Test-OutputMiddlewareConfiguration -Names @('HookOfTheReaper') -RetroBatRoot (Join-Path $TestDrive 'Ghost') | Should Be $false
    }

    It 'a windows-vs-network conflict refuses to touch the mame output key' {
        $before = [IO.File]::ReadAllText((Join-Path $mameDir 'mame.ini'))
        $null = Set-OutputMiddlewareConfiguration -Names @('MameHooker', 'QMamehook') -RetroBatRoot $rb -Confirm:$false
        [IO.File]::ReadAllText((Join-Path $mameDir 'mame.ini')) | Should BeExactly $before
        Test-OutputMiddlewareConfiguration -Names @('MameHooker', 'QMamehook') -RetroBatRoot $rb | Should Be $false
    }

    It 'qMamehook alone switches the key to network and fills qmhook.ini' {
        # first reset windows back to none (conflict test above deliberately did not change it)
        Set-OutputMiddlewareConfiguration -Names @('QMamehook') -RetroBatRoot $rb -Confirm:$false | Should BeGreaterThan 0
        [IO.File]::ReadAllText((Join-Path $mameDir 'mame.ini')) | Should Match 'output\s+network'
        [IO.File]::ReadAllText((Join-Path $qmDir 'qmhook.ini')) | Should Match 'Port\s*=\s*9735'
        [IO.File]::ReadAllText((Join-Path $qmDir 'qmhook.ini')) | Should Match 'Other\s*=\s*keepme'
        Set-OutputMiddlewareConfiguration -Names @('QMamehook') -RetroBatRoot $rb -Confirm:$false | Should Be 0
    }

    It 'DOF and MameHooker agree on windows: Set writes the key, safety files stay untouched' {
        $hotrBefore = [IO.File]::ReadAllText((Join-Path $hotrDir 'settings.ini'))
        Set-OutputMiddlewareConfiguration -Names @('DirectOutputFramework', 'MameHooker') -RetroBatRoot $rb -Confirm:$false | Should BeGreaterThan 0
        [IO.File]::ReadAllText((Join-Path $mameDir 'mame.ini')) | Should Match 'output\s+windows'
        # neither new adapter has SettingsTargets/Safety - the HoTR safety file must survive byte-identical
        [IO.File]::ReadAllText((Join-Path $hotrDir 'settings.ini')) | Should BeExactly $hotrBefore
        Test-OutputMiddlewareConfiguration -Names @('DirectOutputFramework', 'MameHooker') -RetroBatRoot $rb | Should Be $true
        Set-OutputMiddlewareConfiguration -Names @('DirectOutputFramework', 'MameHooker') -RetroBatRoot $rb -Confirm:$false | Should Be 0
    }

    It 'DOF plus QMamehook is a mode conflict too: Set refuses the mame key' {
        $before = [IO.File]::ReadAllText((Join-Path $mameDir 'mame.ini'))
        $null = Set-OutputMiddlewareConfiguration -Names @('DirectOutputFramework', 'QMamehook') -RetroBatRoot $rb -Confirm:$false
        [IO.File]::ReadAllText((Join-Path $mameDir 'mame.ini')) | Should BeExactly $before
        Test-OutputMiddlewareConfiguration -Names @('DirectOutputFramework', 'QMamehook') -RetroBatRoot $rb | Should Be $false
    }

}

Describe 'Output step 01 as stand-alone script' {
    Set-KitCulture -Culture 'en-US'
    Mock -ModuleName 'RetroCabinetKit.Lightgun' Test-KitProcessesClosed { }
    $rb = Join-Path $TestDrive 'RetroBat'
    & $newRetroBat -Root $rb
    $mameDir = Join-Path $rb 'emulators\mame'
    New-Item -ItemType Directory -Path $mameDir -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $mameDir 'mame.ini'), ('output                      none' + "`r`n"), (New-Object Text.UTF8Encoding $false))
    $state = Join-Path $TestDrive 'install-state.json'
    $common = @{ StatePath = $state; Culture = 'en-US' }
    Set-KitStateValue -Path $state -Key 'RetroBatRoot' -Value $rb
    $solo = @{ Processes = @('mamehooker'); Ports = @(); Devices = @() }
    $both = @{ Processes = @('mamehooker', 'qmamehook'); Ports = @(); Devices = @() }

    It 'dry run: nothing persisted, nothing changed' {
        $before = [IO.File]::ReadAllText((Join-Path $mameDir 'mame.ini'))
        $r = @(& "$steps\01-Middleware.ps1" @common -Snapshot $solo -WhatIf)
        ($r | ForEach-Object { $_.Status }) -join ',' | Should Be 'Skipped,Skipped'
        Get-KitStateValue -Path $state -Key 'OutputMiddleware' | Should BeNullOrEmpty
        [IO.File]::ReadAllText((Join-Path $mameDir 'mame.ini')) | Should BeExactly $before
    }

    It 'detects, configures, second run skips' {
        $r = @(& "$steps\01-Middleware.ps1" @common -Snapshot $solo)
        ($r | ForEach-Object { "$($_.Name)=$($_.Status)" }) -join ',' | Should Be 'output-1-middleware-detect=Done,output-1-middleware-configure=Done'
        Get-KitStateValue -Path $state -Key 'OutputMiddleware' | Should Be 'MameHooker'
        [IO.File]::ReadAllText((Join-Path $mameDir 'mame.ini')) | Should Match 'output\s+windows'
        $r = @(& "$steps\01-Middleware.ps1" @common -Snapshot $solo)
        ($r | ForEach-Object { $_.Status }) -join ',' | Should Be 'Skipped,Skipped'
    }

    It 'two disagreeing modes stay NeedsUser with the conflict in state' {
        $r = @(& "$steps\01-Middleware.ps1" @common -Snapshot $both)
        (@($r | Where-Object { $_.Name -like '*configure' } | ForEach-Object { $_.Status }) -join '') | Should Be 'NeedsUser'
        Get-KitStateValue -Path $state -Key 'OutputMiddleware' | Should Be 'MameHooker+QMamehook'
        # mame.ini stays 'windows' from the previous solo run: the conflict refuses to rewrite it
        [IO.File]::ReadAllText((Join-Path $mameDir 'mame.ini')) | Should Match 'output\s+windows'
    }

    It 'an empty world writes None and asks nothing' {
        $r = @(& "$steps\01-Middleware.ps1" @common -Snapshot @{ Processes = @(); Ports = @(); Devices = @() })
        ($r | ForEach-Object { "$($_.Name)=$($_.Status)" }) -join ',' | Should Be 'output-1-middleware-detect=Done,output-1-middleware-configure=NeedsUser'
        Get-KitStateValue -Path $state -Key 'OutputMiddleware' | Should Be 'None'
    }
}
