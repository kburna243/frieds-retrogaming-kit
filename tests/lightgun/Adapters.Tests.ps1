$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1') -Force
$newRetroBat = Join-Path $PSScriptRoot 'New-LightgunTestRetroBat.ps1'
$steps = Join-Path $kitRoot 'lightgun\steps'

# Step 15: USB lightgun adapters. Devices and files are injected or synthetic; nothing real is detected,
# downloaded or killed.
Describe 'Adapter catalog and discovery' {
    Set-KitCulture -Culture 'en-US'
    $dolphin  = [pscustomobject]@{ InstanceId = 'HID\VID_0079&PID_1802&MI_00\8&1' }
    $bar      = [pscustomobject]@{ InstanceId = 'USB\VID_057E&PID_0306\5&2&0&3' }
    $leonardo = [pscustomobject]@{ InstanceId = 'USB\VID_2341&PID_8036\7&3&0&2' }
    $bootloader = [pscustomobject]@{ InstanceId = 'USB\VID_1B4F&PID_9206\4&1' }
    $openfire = [pscustomobject]@{ InstanceId = 'HID\VID_303A&PID_1001&MI_02\x' }
    $aimtrak  = [pscustomobject]@{ InstanceId = 'USB\VID_D209&PID_1602\6&1&0&4' }
    $rsHub    = [pscustomobject]@{ InstanceId = 'USB\VID_0079&PID_187C\9&1' }
    $rsAlt    = [pscustomobject]@{ InstanceId = 'USB\VID_16C0&PID_05E1\3&1' }
    $sinden   = [pscustomobject]@{ InstanceId = 'HID\VID_16C0&PID_0F38&REV_0100\7&1' }
    $sindenP2 = [pscustomobject]@{ InstanceId = 'USB\VID_16C0&PID_0F02\4&2&0&1' }
    $sindenCam = [pscustomobject]@{ InstanceId = 'USB\VID_16C0&PID_0F37&MI_00\6&3' }
    $sindenName = [pscustomobject]@{ InstanceId = 'HID\VID_16C0&PID_0F99\5&1'; FriendlyName = 'Sinden Lightgun' }

    It 'ships the five adapters completely; the underscore template is never listed' {
        $cat = @(Get-LightgunAdapterCatalog)
        ($cat | ForEach-Object Name) -join ',' | Should Be 'AimTrak,Gun4IR,OpenFIRE,RetroShooter,Sinden'
        foreach ($a in $cat) {
            $a.HasParseErrors | Should Be $false
            $a.HasTest | Should Be $true
            $a.HasInfo | Should Be $true
            $a.HasInstall | Should Be $true
            $a.HasConfigure | Should Be $true
            $a.HasShield | Should Be $true
        }
    }

    It 'detects each system by its VID/PID and hands back device id and next step' {
        (Get-LightgunDetectedAdapter -Devices @($dolphin, $bar) -Quiet).DetectedAdapter | Should BeNullOrEmpty
        $r = Get-LightgunDetectedAdapter -Devices @($leonardo) -Quiet
        $r.Success | Should Be $true
        $r.DetectedAdapter | Should Be 'Gun4IR'
        $r.DetectedDeviceId | Should Be 'USB\VID_2341&PID_8036\7&3&0&2'
        $r.NextStep | Should Be 'Install-Gun4IRSoftware'
        (Get-LightgunDetectedAdapter -Devices @($bootloader) -Quiet).DetectedAdapter | Should Be 'Gun4IR'
        (Get-LightgunDetectedAdapter -Devices @($openfire) -Quiet).DetectedAdapter | Should Be 'OpenFIRE'
        (Get-LightgunDetectedAdapter -Devices @($aimtrak) -Quiet).DetectedAdapter | Should Be 'AimTrak'
        (Get-LightgunDetectedAdapter -Devices @($rsHub) -Quiet).DetectedAdapter | Should Be 'RetroShooter'
        (Get-LightgunDetectedAdapter -Devices @($rsAlt) -Quiet).DetectedAdapter | Should Be 'RetroShooter'
        $s = Get-LightgunDetectedAdapter -Devices @($sinden) -Quiet
        $s.DetectedAdapter | Should Be 'Sinden'
        $s.DetectedDeviceId | Should Be 'HID\VID_16C0&PID_0F38&REV_0100\7&1'
        (Get-LightgunDetectedAdapter -Devices @($sindenP2) -Quiet).DetectedAdapter | Should Be 'Sinden'
        (Get-LightgunDetectedAdapter -Devices @($sindenName) -Quiet).DetectedAdapter | Should Be 'Sinden'
    }

    It 'never mistakes the Retro Shooter hub for a Sinden and vice versa (both live on VID_16C0)' {
        (Get-LightgunDetectedAdapter -Devices @($rsAlt) -Quiet).DetectedAdapter | Should Not Be 'Sinden'
        (Get-LightgunDetectedAdapter -Devices @($sinden) -Quiet).DetectedAdapter | Should Not Be 'RetroShooter'
        # The UVC camera alone identifies the gun but is no [Player1] Device candidate: id stays empty.
        $cam = Get-LightgunDetectedAdapter -Devices @($sindenCam) -Quiet
        $cam.DetectedAdapter | Should Be 'Sinden'
        $cam.DetectedDeviceId | Should BeNullOrEmpty
    }

    It 'never mistakes the DolphinBar for a Retro Shooter hub (both share VID_0079)' {
        (Get-LightgunDetectedAdapter -Devices @($dolphin) -Quiet).DetectedAdapter | Should BeNullOrEmpty
        (Get-LightgunDetectedAdapter -Devices @($bar) -Quiet).DetectedAdapter | Should BeNullOrEmpty
    }

    It 'scans all adapters and the first match wins' {
        $r = Get-LightgunDetectedAdapter -Devices @($rsHub, $leonardo) -Quiet
        $r.DetectedAdapter | Should Be 'Gun4IR'
        ($r.ScannedAdapters | Sort-Object) -join ',' | Should Be 'AimTrak,Gun4IR'
    }

    It 'skips incomplete and broken adapter files with an error entry instead of failing' {
        $dir = Join-Path $TestDrive 'brokenadapters'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $dir 'NoTest.ps1'), 'function Get-NoTestAdapterInfo { @{} }')
        [IO.File]::WriteAllText((Join-Path $dir 'Broken.ps1'), 'function Test-BrokenHardware { param($RetroBatRoot,$Devices) throw ''usb stack exploded'' }')
        $r = Get-LightgunDetectedAdapter -Devices @($leonardo) -Dir $dir -Quiet
        $r.DetectedAdapter | Should BeNullOrEmpty
        $r.Errors.Count | Should Be 2
        $r.ScannedAdapters | Should Be 'Broken'
    }
}

Describe 'mame.ini writer (space-separated values)' {
    Set-KitCulture -Culture 'en-US'
    $ini = Join-Path $TestDrive 'mame.ini'
    function Get-Hash([string] $Path) { (Get-FileHash -LiteralPath $Path).Hash }
    [IO.File]::WriteAllText($ini, @(
        '# Input Configuration'
        'lightgun                  0'
        'lightgun_device           dinput'
        '#pragma comment sample'
        ''
    ) -join "`r`n")
    $hashBefore = Get-Hash $ini

    It 'plans changes without touching the file' {
        $probe = [ordered]@{ lightgun = '1'; brand_new_option = 'x' }
        @(Get-LightgunMameIniPlan -Path $ini -Values $probe).Count | Should Be 2
        (Get-Hash $ini) | Should Be $hashBefore
    }

    It 'changes values in place, appends missing keys and keeps the second run at zero changes' {
        Mock -ModuleName 'RetroCabinetKit.Lightgun' Test-KitProcessesClosed { }
        $want = [ordered]@{ lightgun = '1'; lightgun_device = 'rawinput'; offscreen_reload = '1' }
        @(Get-LightgunMameIniPlan -Path $ini -Values $want).Count | Should Be 3
        Set-LightgunMameIniValue -Path $ini -Values $want -Confirm:$false | Should Be 3
        $lines = [IO.File]::ReadAllLines($ini)
        ($lines | Where-Object { $_ -match '^lightgun\s+' }) | Should Match '\b1\b'
        ($lines | Where-Object { $_ -match '^lightgun_device\s+' }) | Should Match 'rawinput'
        ($lines | Where-Object { $_ -match '^offscreen_reload\s+1' }).Count | Should Be 1
        ($lines -join "`n") | Should Match '#pragma comment sample'
        [IO.File]::ReadAllText($ini) | Should Match "`r`n"
        Set-LightgunMameIniValue -Path $ini -Values $want -Confirm:$false | Should Be 0
    }

    It 'does nothing under -WhatIf' {
        $before = [IO.File]::ReadAllBytes($ini)
        $probe = [ordered]@{ lightgun = '0' }
        $null = Set-LightgunMameIniValue -Path $ini -Values $probe -WhatIf -Confirm:$false
        $after = [IO.File]::ReadAllBytes($ini)
        (Compare-Object $before $after) | Should BeNullOrEmpty
    }
}

Describe 'Adapter configuration end to end' {
    Set-KitCulture -Culture 'en-US'
    Mock -ModuleName 'RetroCabinetKit.Lightgun' Test-KitProcessesClosed { }
    $rb = Join-Path $TestDrive 'RetroBat'
    & $newRetroBat -Root $rb
    $mameDir = Join-Path $rb 'emulators\mame'
    New-Item -ItemType Directory -Path $mameDir -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $mameDir 'mame.ini'), ('lightgun                  0' + "`r`n" + 'output                    none' + "`r`n"), (New-Object Text.UTF8Encoding $false))
    $guns = "[Guns]`r`nEnableLightguns=0`r`n"
    [IO.File]::WriteAllText((Join-Path $rb 'retrobat.ini'), $guns, (New-Object Text.UTF8Encoding $false))

    It 'writes mame.ini, [Guns] and DemulShooter device, then verifies green' {
        $ds = Join-Path $rb 'system\demulshooter'
        New-Item -ItemType Directory -Path $ds -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $ds 'DemulShooter.ini'), "[Global]`r`nUseStaticCrosshair=0`r`n", (New-Object Text.UTF8Encoding $false))
        $id = 'USB\VID_2341&PID_8036\7&3'
        Test-LightgunAdapterConfiguration -Name 'Gun4IR' -RetroBatRoot $rb -DetectedDeviceId $id -SteamConfigVdf '' | Should Be $false
        $n = Set-LightgunAdapterConfiguration -Name 'Gun4IR' -RetroBatRoot $rb -DetectedDeviceId $id -SteamConfigVdf '' -Confirm:$false
        $n | Should BeGreaterThan 0
        Test-LightgunAdapterConfiguration -Name 'Gun4IR' -RetroBatRoot $rb -DetectedDeviceId $id -SteamConfigVdf '' | Should Be $true
        [IO.File]::ReadAllText((Join-Path $mameDir 'mame.ini')) | Should Match 'rawinput'
        [IO.File]::ReadAllText((Join-Path $rb 'retrobat.ini')) | Should Match 'Gun1Device\s*=\s*Gun4IR'
        [IO.File]::ReadAllText((Join-Path $ds 'DemulShooter.ini')) | Should Match ([regex]::Escape("Device = $id"))
    }

    It 'is idempotent: a second apply changes nothing' {
        Set-LightgunAdapterConfiguration -Name 'Gun4IR' -RetroBatRoot $rb -DetectedDeviceId 'USB\VID_2341&PID_8036\7&3' -SteamConfigVdf '' -Confirm:$false | Should Be 0
    }

    It 'install without a package only names the official source; with -Approved it unpacks' {
        Install-LightgunAdapter -Name 'Gun4IR' -RetroBatRoot $rb -Confirm:$false | Should Be $false
        Test-Path (Join-Path $rb 'tools\Gun4IR') | Should Be $false
        $src = Join-Path $TestDrive 'payload'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $src 'Gun4IR-Calibration.exe'), 'fake')
        $zip = Join-Path $TestDrive 'Gun4IR.zip'
        Compress-Archive -Path (Join-Path $src 'Gun4IR-Calibration.exe') -DestinationPath $zip -Force
        Install-LightgunAdapter -Name 'Gun4IR' -RetroBatRoot $rb -PackagePath $zip -Confirm:$false | Should Be $false # without -Approved: nothing
        Test-Path (Join-Path $rb 'tools\Gun4IR') | Should Be $false
        Install-LightgunAdapter -Name 'Gun4IR' -RetroBatRoot $rb -PackagePath $zip -Approved -Confirm:$false | Should Be $true
        Join-Path $rb 'tools\Gun4IR\Gun4IR-Calibration.exe' | Should Exist
    }

    It 'switches the same cabinet to Sinden: border keys in [Guns], gun (not camera) into DemulShooter' {
        $id = 'HID\VID_16C0&PID_0F38&REV_0100\7&1'
        $n = Set-LightgunAdapterConfiguration -Name 'Sinden' -RetroBatRoot $rb -DetectedDeviceId $id -SteamConfigVdf '' -Confirm:$false
        $n | Should BeGreaterThan 0
        $rbIni = [IO.File]::ReadAllText((Join-Path $rb 'retrobat.ini'))
        $rbIni | Should Match 'Gun1Device\s*=\s*Sinden'
        $rbIni | Should Match 'SindenBorder\s*=\s*1'
        [IO.File]::ReadAllText((Join-Path $rb 'system\demulshooter\DemulShooter.ini')) | Should Match ([regex]::Escape("Device = $id"))
        Set-LightgunAdapterConfiguration -Name 'Sinden' -RetroBatRoot $rb -DetectedDeviceId $id -SteamConfigVdf '' -Confirm:$false | Should Be 0
        Test-LightgunAdapterConfiguration -Name 'Sinden' -RetroBatRoot $rb -DetectedDeviceId $id -SteamConfigVdf '' | Should Be $true
    }
}

Describe 'Steam blacklist with adapter entries' {
    Set-KitCulture -Culture 'en-US'
    Mock -ModuleName 'RetroCabinetKit.Lightgun' Test-KitProcessesClosed { }
    $steam = Join-Path $TestDrive 'Steam'
    & (Join-Path $PSScriptRoot 'New-LightgunTestGunmote.ps1') -Gunmote (Join-Path $TestDrive 'Gunmote') -Steam $steam
    $vdf = Join-Path $steam 'config\config.vdf'

    It 'extra entries are written, verified and survive the default check' {
        $extra = @('0x2341/0x8036')
        Set-LightgunSteamBlacklist -ConfigVdf $vdf -Confirm:$false | Should Be 1
        Test-LightgunSteamBlacklist -ConfigVdf $vdf -ExtraEntries $extra | Should Be $false
        Set-LightgunSteamBlacklist -ConfigVdf $vdf -ExtraEntries $extra -Confirm:$false | Should Be 1
        Test-LightgunSteamBlacklist -ConfigVdf $vdf -ExtraEntries $extra | Should Be $true
        Test-LightgunSteamBlacklist -ConfigVdf $vdf | Should Be $true # step 5 rerun does not strip the gun VID
        Set-LightgunSteamBlacklist -ConfigVdf $vdf -ExtraEntries $extra -Confirm:$false | Should Be 0
        [IO.File]::ReadAllText($vdf) | Should Match '0x2341/0x8036'
    }
}

Describe 'Step 15 as stand-alone script' {
    Set-KitCulture -Culture 'en-US'
    Mock -ModuleName 'RetroCabinetKit.Lightgun' Test-KitProcessesClosed { }
    $rb = Join-Path $TestDrive 'RetroBat'
    & $newRetroBat -Root $rb
    $mameDir = Join-Path $rb 'emulators\mame'
    New-Item -ItemType Directory -Path $mameDir -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $mameDir 'mame.ini'), ('lightgun                  0' + "`r`n"), (New-Object Text.UTF8Encoding $false))
    [IO.File]::WriteAllText((Join-Path $rb 'retrobat.ini'), "[Guns]`r`nEnableLightguns=0`r`n", (New-Object Text.UTF8Encoding $false))
    $state = Join-Path $TestDrive 'install-state.json'
    $common = @{ StatePath = $state; Culture = 'en-US' }
    Set-KitStateValue -Path $state -Key 'RetroBatRoot' -Value $rb
    $leonardo = [pscustomobject]@{ InstanceId = 'USB\VID_2341&PID_8036\7&3&0&2' }
    $dolphin  = [pscustomobject]@{ InstanceId = 'HID\VID_0079&PID_1802&MI_00\8&1' }

    It 'dry run: nothing persisted, nothing changed' {
        $iniBefore = [IO.File]::ReadAllText((Join-Path $mameDir 'mame.ini'))
        $r = @(& "$steps\15-Adapter.ps1" @common -Devices @($leonardo) -SteamConfigVdf '' -WhatIf)
        ($r | ForEach-Object { $_.Status }) -join ',' | Should Be 'Skipped,Skipped'
        Get-KitStateValue -Path $state -Key 'LightgunAdapter' | Should BeNullOrEmpty
        [IO.File]::ReadAllText((Join-Path $mameDir 'mame.ini')) | Should BeExactly $iniBefore
    }

    It 'detects Gun4IR, configures both files, second run skips; Wiimote-only devices write None' {
        $r = @(& "$steps\15-Adapter.ps1" @common -Devices @($dolphin) -SteamConfigVdf '')
        ($r | ForEach-Object { "$($_.Name)=$($_.Status)" }) -join ',' | Should Be 'lightgun-15-adapter-detect=Done,lightgun-15-adapter-configure=NeedsUser'
        Get-KitStateValue -Path $state -Key 'LightgunAdapter' | Should Be 'None'
        $r = @(& "$steps\15-Adapter.ps1" @common -Devices @($leonardo) -SteamConfigVdf '')
        ($r | ForEach-Object { "$($_.Name)=$($_.Status)" }) -join ',' | Should Be 'lightgun-15-adapter-detect=Done,lightgun-15-adapter-configure=Done'
        Get-KitStateValue -Path $state -Key 'LightgunAdapter' | Should Be 'Gun4IR'
        [IO.File]::ReadAllText((Join-Path $mameDir 'mame.ini')) | Should Match 'rawinput'
        $r = @(& "$steps\15-Adapter.ps1" @common -Devices @($leonardo) -SteamConfigVdf '')
        ($r | ForEach-Object { "$($_.Name)=$($_.Status)" }) -join ',' | Should Be 'lightgun-15-adapter-detect=Skipped,lightgun-15-adapter-configure=Skipped'
    }

    It 'a bound empty -SteamConfigVdf keeps the step away from the found Steam folder' {
        $fakeSteam = Join-Path $TestDrive 'FakeSteam'
        New-Item -ItemType Directory -Path (Join-Path $fakeSteam 'config') -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $fakeSteam 'config\config.vdf'), "`"InstallConfigStore`"`n{`n`"Software`"`n{`n`"Valve`"`n{`n`"Steam`"`n{`n}`n}`n}`n}`n", (New-Object Text.UTF8Encoding $false))
        # GetNewClosure keeps the path bound to this scope (Pester 3 keeps closures out of the module session)
        Mock -ModuleName 'RetroCabinetKit.Lightgun' Get-LightgunSteamPath ({ $fakeSteam }.GetNewClosure())
        # everything is already configured (previous It): the step must not touch the found Steam either way
        $r = @(& "$steps\15-Adapter.ps1" @common -Devices @($leonardo) -SteamConfigVdf '')
        ($r | ForEach-Object { $_.Status }) -join ',' | Should Be 'Skipped,Skipped'
        @(Get-ChildItem (Join-Path $fakeSteam 'config') -Filter '*.bak_lightgun*').Count | Should Be 0
        # now make it dirty again: without a bound value the step uses the found Steam folder — with backup
        [IO.File]::WriteAllText((Join-Path $mameDir 'mame.ini'), ('lightgun                  0' + "`r`n"), (New-Object Text.UTF8Encoding $false))
        $r = @(& "$steps\15-Adapter.ps1" @common -Devices @($leonardo))
        (@($r | Where-Object { $_.Name -like '*configure' } | ForEach-Object { $_.Status }) -join '') | Should Be 'Done'
        @(Get-ChildItem (Join-Path $fakeSteam 'config') -Filter '*.bak_lightgun*').Count | Should Be 1
        [IO.File]::ReadAllText((Join-Path $fakeSteam 'config\config.vdf')) | Should Match '0x2341/0x8036'
    }
}
