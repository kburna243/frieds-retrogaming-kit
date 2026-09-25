$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1') -Force
$newRetroBat = Join-Path $PSScriptRoot 'New-LightgunTestRetroBat.ps1'

Describe 'Demul & DemulShooter (Naomi/Atomiswave)' {
    Set-KitCulture -Culture 'en-US'
    Mock -ModuleName 'RetroCabinetKit.Lightgun' Test-KitProcessesClosed { }

    $rb = Join-Path $TestDrive 'RB_Demul'
    & $newRetroBat -Root $rb
    $paths = Get-LightgunDemulPath -RetroBatRoot $rb

    It 'detects missing Demul and verifies when exe and nvram are supplied' {
        (Test-LightgunDemulInstalled -RetroBatRoot $rb).Installed | Should Be $false
        New-Item -ItemType Directory -Path $paths.NvramDir -Force | Out-Null
        [IO.File]::WriteAllBytes($paths.DemulExe, [byte[]]@(0x4D, 0x5A))
        $info = Test-LightgunDemulInstalled -RetroBatRoot $rb
        $info.Installed | Should Be $true
        $info.HasExe | Should Be $true
        $info.HasNvram | Should Be $true
    }

    It 'provides official DemulShooter release URL' {
        Get-LightgunDemulShooterReleaseUrl | Should Be 'https://github.com/argonlefou/DemulShooter/releases'
    }

    It 'detects DemulShooter and reads version' {
        (Test-LightgunDemulShooterInstalled -RetroBatRoot $rb).Installed | Should Be $false
        New-Item -ItemType Directory -Path $paths.DemulShooterDir -Force | Out-Null
        [IO.File]::WriteAllBytes($paths.DemulShooterExe, [byte[]]@(0x4D, 0x5A))
        [IO.File]::WriteAllText($paths.DemulShooterLog, "## [17.9.0] - 2026-09-22`r`n- Added test`r`n")
        $info = Test-LightgunDemulShooterInstalled -RetroBatRoot $rb
        $info.Installed | Should Be $true
        $info.Version | Should Be '17.9.0'
    }

    It 'plans and configures DemulShooter for HID raw input (idempotent, backup kept)' {
        $cfg = $paths.DemulShooterConfig
        [IO.File]::WriteAllText($cfg, "; initial config`r`nP1Mode = DINPUT`r`nP1HidAxisX = 0x01`r`n")
        $plan = @(Get-LightgunDemulShooterConfigPlan -ConfigPath $cfg)
        $plan.Count | Should BeGreaterThan 5
        ($plan | Where-Object { $_.Key -eq 'P1Mode' }).New | Should Be 'RAWINPUT'
        ($plan | Where-Object { $_.Key -eq 'P1HidAxisX' }).New | Should Be '0x30'
        ($plan | Where-Object { $_.Key -eq 'P1HidAxisY' }).New | Should Be '0x31'
        ($plan | Where-Object { $_.Key -eq 'P1HidBtnOnscreenTrigger' }).New | Should Be '2'
        ($plan | Where-Object { $_.Key -eq 'P1HidBtnOffscreenTrigger' }).New | Should Be '1'
        ($plan | Where-Object { $_.Key -eq 'P1HidBtnAction' }).New | Should Be '3'

        $count = Set-LightgunDemulShooterConfig -ConfigPath $cfg -Plan $plan -Confirm:$false
        $count | Should Be $plan.Count
        @(Get-ChildItem -LiteralPath (Split-Path $cfg) -Filter 'config.ini.bak_lightgun_*').Count | Should Be 1

        # Second run: 0 changes
        @(Get-LightgunDemulShooterConfigPlan -ConfigPath $cfg).Count | Should Be 0
        Set-LightgunDemulShooterConfig -ConfigPath $cfg -Plan @(Get-LightgunDemulShooterConfigPlan -ConfigPath $cfg) -Confirm:$false | Should Be 0
    }

    It 'validates ROM names: allowlist accepted, injection attempts strictly rejected' {
        # Valid ROMs
        foreach ($rom in 'confmiss', 'hotd2', 'HOTD2', 'ninjaslt', 'claychal', 'xtrmhunt', 'mok') {
            Test-LightgunDemulRomName -Rom $rom | Should Be $true
            { Assert-LightgunDemulRomName -Rom $rom } | Should Not Throw
        }

        # Injection attempts and malicious characters
        $badCases = @(
            'confmiss & calc.exe',
            'hotd2 | whoami',
            'confmiss; rm -rf',
            'confmiss" -evil',
            "hotd2' or 1=1",
            '..\..\windows\system32\cmd.exe',
            'confmiss/evil',
            'hotd2%test%',
            'confmiss$var',
            'confmiss^extra',
            'unknown_game_xyz',
            '',
            $null,
            ('a' * 65) # length > 64
        )
        foreach ($bad in $badCases) {
            Test-LightgunDemulRomName -Rom $bad | Should Be $false
            { Assert-LightgunDemulRomName -Rom $bad } | Should Throw
        }
    }

    It 'scans and removes hardwired emulator overrides in Naomi and Atomiswave gamelists' {
        $naomiDir = Join-Path $rb 'roms\naomi'
        $awDir = Join-Path $rb 'roms\atomiswave'
        New-Item -ItemType Directory -Path $naomiDir, $awDir -Force | Out-Null

        $naomiXml = @(
            '<?xml version="1.0"?>',
            '<gameList>',
            '  <game>',
            '    <path>./confmiss.zip</path>',
            '    <name>Confidential Mission</name>',
            '    <emulator>flycast</emulator>',
            '    <core>flycast</core>',
            '  </game>',
            '  <game>',
            '    <path>./hotd2.zip</path>',
            '    <name>House of the Dead 2</name>',
            '    <emulator>demul</emulator>',
            '    <core>naomi</core>',
            '  </game>',
            '</gameList>'
        ) -join "`r`n"
        [IO.File]::WriteAllText($paths.NaomiGamelist, $naomiXml)

        $awXml = @(
            '<?xml version="1.0"?>',
            '<gameList>',
            '  <game>',
            '    <path>./claychal.zip</path>',
            '    <name>Sega Clay Challenge</name>',
            '    <emulator>libretro</emulator>',
            '    <core>flycast</core>',
            '  </game>',
            '</gameList>'
        ) -join "`r`n"
        [IO.File]::WriteAllText($paths.AtomiswaveGamelist, $awXml)

        $overrides = @(Get-LightgunDemulGamelistOverride -RetroBatRoot $rb)
        $overrides.Count | Should Be 2
        ($overrides | Where-Object { $_.Game -eq 'confmiss' }).Emulator | Should Be 'flycast'
        ($overrides | Where-Object { $_.Game -eq 'claychal' }).Emulator | Should Be 'libretro'

        # Remove overrides
        $removed = Remove-LightgunDemulGamelistOverride -RetroBatRoot $rb -Overrides $overrides -Confirm:$false
        $removed | Should Be 2

        # Second check: 0 overrides
        @(Get-LightgunDemulGamelistOverride -RetroBatRoot $rb).Count | Should Be 0

        # Verify confmiss still exists in gamelist but without emulator tag
        $content = [IO.File]::ReadAllText($paths.NaomiGamelist)
        $content | Should Match '<name>Confidential Mission</name>'
        $content | Should Not Match '<emulator>flycast</emulator>'
        # hotd2 was already demul/naomi, kept intact
        $content | Should Match '<emulator>demul</emulator>'
    }

    It 'step 12 as stand-alone script: WhatIf dry run and full run' {
        $state = Join-Path $TestDrive 'state-demul.json'
        $stepScript = Join-Path $kitRoot 'lightgun\steps\12-Demul.ps1'

        # Dry run with -WhatIf
        $resWhatIf = @(& $stepScript -RetroBatRoot $rb -StatePath $state -WhatIf)
        $resWhatIf.Count | Should Be 4
        $settingsStep = $resWhatIf | Where-Object { $_.Name -eq 'lightgun-12-demul-settings' }
        $settingsStep.WhatIf | Should Be $true
        $state | Should Not Exist

        # Real run with -RemoveHardwired
        $resReal = @(& $stepScript -RetroBatRoot $rb -StatePath $state -RemoveHardwired)
        $resReal.Count | Should Be 4
        foreach ($r in $resReal) {
            (@('Done', 'Skipped') -contains $r.Status) | Should Be $true
        }

        # Second run: all skipped / verified
        $resSecond = @(& $stepScript -RetroBatRoot $rb -StatePath $state -RemoveHardwired)
        foreach ($r in $resSecond) {
            $r.Status | Should Be 'Skipped'
        }
    }
}
