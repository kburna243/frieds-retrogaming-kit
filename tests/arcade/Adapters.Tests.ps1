$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'arcade\RetroCabinetKit.Arcade.psd1') -Force
$newRetroBat = Join-Path $kitRoot 'tests\lightgun\New-LightgunTestRetroBat.ps1'
$steps = Join-Path $kitRoot 'arcade\steps'

# Arcade adapters (fightsticks, encoders, wheels). Everything is injected or synthetic: no real
# detection, no downloads, no process kills, and every Steam touch points at a fake folder.
Describe 'Arcade adapter catalog and class coexistence' {
    Set-KitCulture -Culture 'en-US'
    $ipac       = [pscustomobject]@{ InstanceId = 'USB\VID_D209&PID_0301\6&1' }
    $g29        = [pscustomobject]@{ InstanceId = 'USB\VID_046D&PID_C299\7&2' }
    $t300       = [pscustomobject]@{ InstanceId = 'USB\VID_044F&PID_B66E\8&3' }
    $zeroDelay  = [pscustomobject]@{ InstanceId = 'USB\VID_0079&PID_0006\9&4' }
    $hori       = [pscustomobject]@{ InstanceId = 'USB\VID_0F0D&PID_0016\1&5' }
    $madcatz    = [pscustomobject]@{ InstanceId = 'USB\VID_0738&PID_4718\2&6'; ConfigManagerErrorCode = 43 }
    $multi      = [pscustomobject]@{ InstanceId = 'USB\VID_1532&PID_0A00\3&7' }
    $ps2        = [pscustomobject]@{ InstanceId = 'USB\VID_0810&PID_0001\4&8' }
    $brook      = [pscustomobject]@{ InstanceId = 'USB\VID_0C12&PID_0E10\5&9' }
    $gp2040     = [pscustomobject]@{ InstanceId = 'USB\VID_2E8A&PID_0000\6&10'; FriendlyName = 'GP2040-CE USB Arcade Stick' }
    $x360wheel  = [pscustomobject]@{ InstanceId = 'USB\VID_045E&PID_0719\7&11' }
    $diy        = [pscustomobject]@{ InstanceId = 'USB\VID_1209&PID_FFB0\8&12' }
    # gun devices that must NEVER be re-claimed by arcade
    $gun4ir     = [pscustomobject]@{ InstanceId = 'USB\VID_2341&PID_8036\9&13' }
    $aimtrak    = [pscustomobject]@{ InstanceId = 'USB\VID_D209&PID_1602\1&14' }
    $openfire   = [pscustomobject]@{ InstanceId = 'USB\VID_2E8A&PID_000A\2&15' }
    $retroshoot = [pscustomobject]@{ InstanceId = 'USB\VID_16C0&PID_05E1\3&16' }
    $dolphin    = [pscustomobject]@{ InstanceId = 'HID\VID_0079&PID_1802&MI_00\4&17' }
    $xboxpad    = [pscustomobject]@{ InstanceId = 'USB\VID_045E&PID_028E\5&18' }
    $horiBare   = [pscustomobject]@{ InstanceId = 'USB\VID_0F0D\6&19' }

    It 'ships twelve complete adapters; the underscore template is never listed' {
        $cat = @(Get-ArcadeAdapterCatalog)
        ($cat | ForEach-Object Name) -join ',' | Should Be 'BrookUFB,DIYArcadeWheel,GP2040CE,HoriArcade,IPAC,LogitechWheel,MadCatzArcade,MultiConsoleArcade,PS2ToUSBAdapter,ThrustmasterFanatecWheel,Xbox360Wheel,ZeroDelay'
        foreach ($a in $cat) {
            $a.HasParseErrors | Should Be $false
            $a.HasTest | Should Be $true
            $a.HasInfo | Should Be $true
            $a.HasInstall | Should Be $true
            $a.HasConfigure | Should Be $true
            $a.HasShield | Should Be $true
        }
    }

    It 'detects every adapter by its tight signature and reports the class' {
        $cases = @(
            @{ D = $ipac;      Name = 'IPAC';                     Class = 'ArcadeStick' },
            @{ D = $g29;       Name = 'LogitechWheel';            Class = 'Wheel' },
            @{ D = $t300;      Name = 'ThrustmasterFanatecWheel'; Class = 'Wheel' },
            @{ D = $zeroDelay; Name = 'ZeroDelay';                Class = 'ArcadeStick' },
            @{ D = $hori;      Name = 'HoriArcade';               Class = 'ArcadeStick' },
            @{ D = $madcatz;   Name = 'MadCatzArcade';            Class = 'ArcadeStick' },
            @{ D = $multi;     Name = 'MultiConsoleArcade';       Class = 'ArcadeStick' },
            @{ D = $ps2;       Name = 'PS2ToUSBAdapter';          Class = 'ArcadeStick' },
            @{ D = $brook;     Name = 'BrookUFB';                 Class = 'ArcadeStick' },
            @{ D = $gp2040;    Name = 'GP2040CE';                 Class = 'ArcadeStick' },
            @{ D = $x360wheel; Name = 'Xbox360Wheel';             Class = 'Wheel' },
            @{ D = $diy;       Name = 'DIYArcadeWheel';           Class = 'Wheel' }
        )
        foreach ($c in $cases) {
            $r = Get-ArcadeDetectedAdapter -Devices @($c.D) -Quiet
            $r.DetectedAdapter | Should Be $c.Name
            $r.DetectedClass | Should Be $c.Class
            $r.NextStep | Should Be ("Install-{0}Software" -f $c.Name)
        }
    }

    It 'never claims a lightgun device: lightgun wins the shared USB ids' {
        foreach ($gun in @($gun4ir, $aimtrak, $openfire, $retroshoot)) {
            (Get-ArcadeDetectedAdapter -Devices @($gun) -Quiet).DetectedAdapter | Should BeNullOrEmpty
        }
    }

    It 'rejects ambiguous signatures: bare VIDs, DolphinBar, a normal Xbox pad and name traps' {
        (Get-ArcadeDetectedAdapter -Devices @($dolphin) -Quiet).DetectedAdapter | Should BeNullOrEmpty
        (Get-ArcadeDetectedAdapter -Devices @($xboxpad) -Quiet).DetectedAdapter | Should BeNullOrEmpty
        (Get-ArcadeDetectedAdapter -Devices @($horiBare) -Quiet).DetectedAdapter | Should BeNullOrEmpty
        # 'USB Composite Device' contains 'te' — name hints must never claim a device with foreign VID/PID
        $trap = [pscustomobject]@{ InstanceId = 'USB\VID_9999&PID_1111\1&2'; FriendlyName = 'USB Composite Device' }
        (Get-ArcadeDetectedAdapter -Devices @($trap) -Quiet).DetectedAdapter | Should BeNullOrEmpty
    }

    It 'carries the Code-43 quirk for Mad Catz without reading localized strings' {
        $r = Get-ArcadeDetectedAdapter -Devices @($madcatz) -Quiet
        $r.Quirks | Should Match 'usb-descriptor-failed'
        $ok = [pscustomobject]@{ InstanceId = 'USB\VID_0738&PID_4718\2&6'; ConfigManagerErrorCode = 0 }
        (Get-ArcadeDetectedAdapter -Devices @($ok) -Quiet).DetectedAdapter | Should Be 'MadCatzArcade'
    }

    It 'skips broken and incomplete adapter files with error entries instead of failing' {
        $dir = Join-Path $TestDrive 'broken'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $dir 'NoTest.ps1'), 'function Get-NoTestAdapterInfo { @{} }')
        [IO.File]::WriteAllText((Join-Path $dir 'Boom.ps1'), "function Test-BoomHardware { param(`$RetroBatRoot,`$Devices) throw 'usb stack exploded' }`nfunction Get-BoomAdapterInfo { @{} }")
        $r = Get-ArcadeDetectedAdapter -Devices @($ipac) -Dir $dir -Quiet
        $r.DetectedAdapter | Should BeNullOrEmpty
        $r.Errors.Count | Should Be 2
        $r.ScannedAdapters | Should Be 'Boom'
    }
}

Describe 'Arcade configuration end to end' {
    Set-KitCulture -Culture 'en-US'
    Mock -ModuleName 'RetroCabinetKit.Lightgun' Test-KitProcessesClosed { }
    $rb = Join-Path $TestDrive 'RetroBat'
    & $newRetroBat -Root $rb
    $mameDir = Join-Path $rb 'emulators\mame'
    New-Item -ItemType Directory -Path $mameDir, (Join-Path $rb 'emulators\m2emulator'), (Join-Path $rb 'emulators\supermodel\Config') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $mameDir 'mame.ini'), ('joystick                    0' + "`r`n" + 'output                      none' + "`r`n"), (New-Object Text.UTF8Encoding $false))
    [IO.File]::WriteAllText((Join-Path $rb 'retrobat.ini'), "[Guns]`r`nEnableLightguns=1`r`n", (New-Object Text.UTF8Encoding $false))
    [IO.File]::WriteAllText((Join-Path $rb 'emulators\m2emulator\Emulator.ini'), "UseFeedback = 0`r`n", (New-Object Text.UTF8Encoding $false))
    [IO.File]::WriteAllText((Join-Path $rb 'emulators\supermodel\Config\Supermodel.ini'), "[Global]`r`nForceFeedback = 0`r`n", (New-Object Text.UTF8Encoding $false))

    It 'the stick route writes mame.ini and the [Controllers] section' {
        $n = Set-ArcadeAdapterConfiguration -Name 'IPAC' -RetroBatRoot $rb -SteamConfigVdf '' -Confirm:$false
        $n | Should BeGreaterThan 0
        [IO.File]::ReadAllText((Join-Path $mameDir 'mame.ini')) | Should Match 'keyboard\s+1'
        Test-ArcadeAdapterConfiguration -Name 'IPAC' -RetroBatRoot $rb -SteamConfigVdf '' | Should Be $true
        Set-ArcadeAdapterConfiguration -Name 'IPAC' -RetroBatRoot $rb -SteamConfigVdf '' -Confirm:$false | Should Be 0
    }

    It 'the wheel route covers [Controllers], Model 2 and Supermodel files too' {
        $n = Set-ArcadeAdapterConfiguration -Name 'LogitechWheel' -RetroBatRoot $rb -SteamConfigVdf '' -Confirm:$false
        $n | Should BeGreaterThan 3
        [IO.File]::ReadAllText((Join-Path $mameDir 'mame.ini')) | Should Match 'paddle_device\s+joystick'
        [IO.File]::ReadAllText((Join-Path $rb 'retrobat.ini')) | Should Match 'WheelRotation\s*=\s*900'
        [IO.File]::ReadAllText((Join-Path $rb 'retrobat.ini')) | Should Match 'Autocontrollers\s*=\s*1'
        [IO.File]::ReadAllText((Join-Path $rb 'emulators\m2emulator\Emulator.ini')) | Should Match 'UseFeedback\s*=\s*1'
        [IO.File]::ReadAllText((Join-Path $rb 'emulators\supermodel\Config\Supermodel.ini')) | Should Match 'ForceFeedback\s*=\s*1'
        Test-ArcadeAdapterConfiguration -Name 'LogitechWheel' -RetroBatRoot $rb -SteamConfigVdf '' | Should Be $true
        Set-ArcadeAdapterConfiguration -Name 'LogitechWheel' -RetroBatRoot $rb -SteamConfigVdf '' -Confirm:$false | Should Be 0
    }

    It 'a wheel adapter skips emulators whose files are absent' {
        $bare = Join-Path $TestDrive 'BareRetroBat'
        & $newRetroBat -Root $bare
        $bareMame = Join-Path $bare 'emulators\mame'
        New-Item -ItemType Directory -Path $bareMame -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $bareMame 'mame.ini'), 'joystick                    0' + "`r`n", (New-Object Text.UTF8Encoding $false))
        $n = Set-ArcadeAdapterConfiguration -Name 'Xbox360Wheel' -RetroBatRoot $bare -SteamConfigVdf '' -Confirm:$false
        [IO.File]::ReadAllText((Join-Path $bareMame 'mame.ini')) | Should Match 'paddle_device\s+joystick'
        Test-Path (Join-Path $bare 'emulators\m2emulator\Emulator.ini') | Should Be $false
        $n | Should BeGreaterThan 0
    }

    It 'installs nothing without -Approved and unpacks an explicitly approved local ZIP' {
        Install-ArcadeAdapter -Name 'LogitechWheel' -RetroBatRoot $rb -Confirm:$false | Should Be $false
        Test-Path (Join-Path $rb 'tools\LogitechWheel') | Should Be $false
        $src = Join-Path $TestDrive 'payload'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $src 'profile.ini'), 'fake')
        $zip = Join-Path $TestDrive 'wheel.zip'
        Compress-Archive -Path (Join-Path $src 'profile.ini') -DestinationPath $zip -Force
        Install-ArcadeAdapter -Name 'LogitechWheel' -RetroBatRoot $rb -PackagePath $zip -Confirm:$false | Should Be $false
        Install-ArcadeAdapter -Name 'LogitechWheel' -RetroBatRoot $rb -PackagePath $zip -Approved -Confirm:$false | Should Be $true
        Join-Path $rb 'tools\LogitechWheel\profile.ini' | Should Exist
    }

    It 'extends the Steam controller_blacklist with wheel VIDs and verifies idempotently' {
        $steam = Join-Path $TestDrive 'Steam'
        & (Join-Path $kitRoot 'tests\lightgun\New-LightgunTestGunmote.ps1') -Gunmote (Join-Path $TestDrive 'Gunmote') -Steam $steam
        $vdf = Join-Path $steam 'config\config.vdf'
        Test-ArcadeAdapterConfiguration -Name 'LogitechWheel' -RetroBatRoot $rb -SteamConfigVdf $vdf | Should Be $false
        Set-ArcadeAdapterConfiguration -Name 'LogitechWheel' -RetroBatRoot $rb -SteamConfigVdf $vdf -Confirm:$false | Should Be 1
        [IO.File]::ReadAllText($vdf) | Should Match '0x046d/0xc299'
        Test-ArcadeAdapterConfiguration -Name 'LogitechWheel' -RetroBatRoot $rb -SteamConfigVdf $vdf | Should Be $true
        Set-ArcadeAdapterConfiguration -Name 'LogitechWheel' -RetroBatRoot $rb -SteamConfigVdf $vdf -Confirm:$false | Should Be 0
    }
}

Describe 'Step arcade-1-adapter as stand-alone script' {
    Set-KitCulture -Culture 'en-US'
    Mock -ModuleName 'RetroCabinetKit.Lightgun' Test-KitProcessesClosed { }
    $rb = Join-Path $TestDrive 'RetroBat'
    & $newRetroBat -Root $rb
    $mameDir = Join-Path $rb 'emulators\mame'
    New-Item -ItemType Directory -Path $mameDir -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $mameDir 'mame.ini'), ('joystick                    0' + "`r`n"), (New-Object Text.UTF8Encoding $false))
    [IO.File]::WriteAllText((Join-Path $rb 'retrobat.ini'), "[Guns]`r`nEnableLightguns=1`r`n", (New-Object Text.UTF8Encoding $false))
    $state = Join-Path $TestDrive 'install-state.json'
    $common = @{ StatePath = $state; Culture = 'en-US' }
    Set-KitStateValue -Path $state -Key 'RetroBatRoot' -Value $rb
    $g29 = [pscustomobject]@{ InstanceId = 'USB\VID_046D&PID_C299\7&2' }
    $openfire = [pscustomobject]@{ InstanceId = 'USB\VID_2E8A&PID_000A\2&15' }

    It 'dry run: nothing persisted, nothing changed' {
        $iniBefore = [IO.File]::ReadAllText((Join-Path $mameDir 'mame.ini'))
        $r = @(& "$steps\01-Adapter.ps1" @common -Devices @($g29) -SteamConfigVdf '' -WhatIf)
        ($r | ForEach-Object { $_.Status }) -join ',' | Should Be 'Skipped,Skipped'
        Get-KitStateValue -Path $state -Key 'ArcadeAdapter' | Should BeNullOrEmpty
        [IO.File]::ReadAllText((Join-Path $mameDir 'mame.ini')) | Should BeExactly $iniBefore
    }

    It 'detects the wheel, configures, second run skips; a gun device only writes None' {
        $r = @(& "$steps\01-Adapter.ps1" @common -Devices @($openfire) -SteamConfigVdf '')
        ($r | ForEach-Object { "$($_.Name)=$($_.Status)" }) -join ',' | Should Be 'arcade-1-adapter-detect=Done,arcade-1-adapter-configure=NeedsUser'
        Get-KitStateValue -Path $state -Key 'ArcadeAdapter' | Should Be 'None'
        $r = @(& "$steps\01-Adapter.ps1" @common -Devices @($g29) -SteamConfigVdf '')
        ($r | ForEach-Object { "$($_.Name)=$($_.Status)" }) -join ',' | Should Be 'arcade-1-adapter-detect=Done,arcade-1-adapter-configure=Done'
        Get-KitStateValue -Path $state -Key 'ArcadeAdapter' | Should Be 'LogitechWheel'
        Get-KitStateValue -Path $state -Key 'ArcadeAdapterClass' | Should Be 'Wheel'
        [IO.File]::ReadAllText((Join-Path $mameDir 'mame.ini')) | Should Match 'paddle_device\s+joystick'
        $r = @(& "$steps\01-Adapter.ps1" @common -Devices @($g29) -SteamConfigVdf '')
        ($r | ForEach-Object { $_.Status }) -join ',' | Should Be 'Skipped,Skipped'
    }

    It 'a bound empty -SteamConfigVdf keeps the step away from the found Steam folder' {
        $fakeSteam = Join-Path $TestDrive 'FakeSteam'
        New-Item -ItemType Directory -Path (Join-Path $fakeSteam 'config') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $fakeSteam 'config\config.vdf'), "`"InstallConfigStore`"`n{`n`"Software`"`n{`n`"Valve`"`n{`n`"Steam`"`n{`n}`n}`n}`n}`n", (New-Object Text.UTF8Encoding $false))
        # The Steam fallback resolves INSIDE the Arcade module session (not only inside Lightgun) —
        # Pester patches per session, so both must be mocked or the test would hit the real registry.
        $steamMock = ({ $fakeSteam }.GetNewClosure())
        Mock -ModuleName 'RetroCabinetKit.Lightgun' Get-LightgunSteamPath $steamMock
        Mock -ModuleName 'RetroCabinetKit.Arcade' Get-LightgunSteamPath $steamMock
        # dirty mame again; the explicit '' must keep the step away from even the mocked Steam
        [IO.File]::WriteAllText((Join-Path $mameDir 'mame.ini'), ('joystick                    0' + "`r`n"), (New-Object Text.UTF8Encoding $false))
        $r = @(& "$steps\01-Adapter.ps1" @common -Devices @($g29) -SteamConfigVdf '')
        (@($r | Where-Object { $_.Name -like '*configure' } | ForEach-Object { $_.Status }) -join '') | Should Be 'Done'
        @(Get-ChildItem (Join-Path $fakeSteam 'config') -Filter '*.bak_lightgun*').Count | Should Be 0
        [IO.File]::ReadAllText((Join-Path $fakeSteam 'config\config.vdf')) | Should Not Match '0x046d/0xc299'
        # unbound again: now the found (fake) Steam gets the wheel VIDs plus exactly one backup
        [IO.File]::WriteAllText((Join-Path $mameDir 'mame.ini'), ('joystick                    0' + "`r`n"), (New-Object Text.UTF8Encoding $false))
        $r = @(& "$steps\01-Adapter.ps1" @common -Devices @($g29))
        (@($r | Where-Object { $_.Name -like '*configure' } | ForEach-Object { $_.Status }) -join '') | Should Be 'Done'
        [IO.File]::ReadAllText((Join-Path $fakeSteam 'config\config.vdf')) | Should Match '0x046d/0xc299'
        @(Get-ChildItem (Join-Path $fakeSteam 'config') -Filter '*.bak_lightgun*').Count | Should Be 1
    }
}
