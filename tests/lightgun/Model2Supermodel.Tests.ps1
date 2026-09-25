$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1') -Force
$newRetroBat = Join-Path $PSScriptRoot 'New-LightgunTestRetroBat.ps1'

Describe 'Model 2 & Supermodel (Step 13)' {
    Set-KitCulture -Culture 'en-US'
    Mock -ModuleName 'RetroCabinetKit.Lightgun' Test-KitProcessesClosed { }

    $rb = Join-Path $TestDrive 'RB_Model2'
    & $newRetroBat -Root $rb
    $paths = Get-LightgunModel2Path -RetroBatRoot $rb

    It 'detects missing Model 2 and detects EMULATOR.EXE / emulator_multicpu.exe' {
        (Test-LightgunModel2Installed -RetroBatRoot $rb).Installed | Should Be $false

        New-Item -ItemType Directory -Path $paths.Model2Dir -Force | Out-Null
        [IO.File]::WriteAllBytes($paths.Model2Exe, [byte[]]@(0x4D, 0x5A))
        [IO.File]::WriteAllText($paths.Model2Ini, "[Renderer]`r`nFullScreen=1`r`n")

        $m2 = Test-LightgunModel2Installed -RetroBatRoot $rb
        $m2.Installed | Should Be $true
        $m2.HasIni | Should Be $true
        $m2.ExePath | Should Be $paths.Model2Exe

        # Test multicpu exe precedence
        [IO.File]::WriteAllBytes($paths.Model2MultiCpu, [byte[]]@(0x4D, 0x5A))
        $m2Multi = Test-LightgunModel2Installed -RetroBatRoot $rb
        $m2Multi.Installed | Should Be $true
        $m2Multi.ExePath | Should Be $paths.Model2MultiCpu
    }

    It 'provides official Supermodel release URLs and known Model 2 ROMs' {
        Get-LightgunSupermodelReleaseUrl | Should Be 'https://github.com/trzy/Supermodel/releases'
        Get-LightgunSupermodelReleasePrefix | Should Match '^https://github.com/trzy/Supermodel/releases/download/'
        (@(Get-LightgunModel2KnownRoms) -contains 'hotd') | Should Be $true
        (@(Get-LightgunModel2KnownRoms) -contains 'vcop2') | Should Be $true
    }

    It 'detects missing Supermodel and detects installed exe and ini' {
        (Test-LightgunSupermodelInstalled -RetroBatRoot $rb).Installed | Should Be $false

        New-Item -ItemType Directory -Path $paths.SupermodelConfigDir -Force | Out-Null
        [IO.File]::WriteAllBytes($paths.SupermodelExe, [byte[]]@(0x4D, 0x5A))
        [IO.File]::WriteAllText($paths.SupermodelIni, "[ Global ]`r`nCrosshairs = 0`r`n")

        $sm = Test-LightgunSupermodelInstalled -RetroBatRoot $rb
        $sm.Installed | Should Be $true
        $sm.HasIni | Should Be $true
        $sm.ExePath | Should Be $paths.SupermodelExe
    }

    It 'validates Model 2 ROM names against allowlist and rejects injection attempts' {
        foreach ($rom in 'hotd', 'HOTD', 'vcop', 'VCOP2', 'bel', 'gunblade', 'rchase2') {
            Test-LightgunModel2RomName -Rom $rom | Should Be $true
            { Assert-LightgunModel2RomName -Rom $rom } | Should Not Throw
        }

        $badRoms = @(
            'hotd & calc.exe',
            'vcop | whoami',
            'bel; rm -rf',
            'hotd" -param',
            "hotd' or 1=1",
            '..\..\secret.rom',
            'unknown_m2_game',
            '',
            $null,
            ('x' * 65)
        )
        foreach ($bad in $badRoms) {
            Test-LightgunModel2RomName -Rom $bad | Should Be $false
            { Assert-LightgunModel2RomName -Rom $bad } | Should Throw
        }
    }

    It 'plans and configures Supermodel.ini with crosshairs and XInput bindings (idempotent, backup kept)' {
        $cfg = $paths.SupermodelIni
        [IO.File]::WriteAllText($cfg, "[ Global ]`r`nCrosshairs = 0`r`n[ Sound ]`r`nMusic = 100`r`n")

        $plan = @(Get-LightgunSupermodelConfigPlan -ConfigPath $cfg)
        $plan.Count | Should BeGreaterThan 5
        ($plan | Where-Object { $_.Key -eq 'Crosshairs' }).New | Should Be '1'
        ($plan | Where-Object { $_.Key -eq 'InputGunX' }).New | Should Be '"JOY1_XAXIS,MOUSE_XAXIS"'
        ($plan | Where-Object { $_.Key -eq 'InputTrigger' }).New | Should Be '"JOY1_BUTTON1,MOUSE_LEFT_BUTTON"'
        ($plan | Where-Object { $_.Key -eq 'InputOffscreen' }).New | Should Be '"JOY1_BUTTON5,MOUSE_RIGHT_BUTTON"'

        $count = Set-LightgunSupermodelConfig -ConfigPath $cfg -Plan $plan -Confirm:$false
        $count | Should Be $plan.Count
        @(Get-ChildItem -LiteralPath (Split-Path $cfg) -Filter 'Supermodel.ini.bak_lightgun_*').Count | Should Be 1

        # Second plan: 0 changes
        @(Get-LightgunSupermodelConfigPlan -ConfigPath $cfg).Count | Should Be 0
        Set-LightgunSupermodelConfig -ConfigPath $cfg -Plan @(Get-LightgunSupermodelConfigPlan -ConfigPath $cfg) -Confirm:$false | Should Be 0

        # Verify other sections preserved
        $content = [IO.File]::ReadAllText($cfg)
        $content | Should Match '\[ Sound \]'
        $content | Should Match 'Music = 100'
        $content | Should Match 'Crosshairs = 1'
    }

    It 'executes step 13 as stand-alone script with -WhatIf and real execution' {
        $state = Join-Path $TestDrive 'state-model2.json'
        $stepScript = Join-Path $kitRoot 'lightgun\steps\13-Model2Supermodel.ps1'

        # Dry run with -WhatIf
        $resWhatIf = @(& $stepScript -RetroBatRoot $rb -StatePath $state -WhatIf)
        $resWhatIf.Count | Should Be 3
        $settingsStep = $resWhatIf | Where-Object { $_.Name -eq 'lightgun-13-model-settings' }
        $settingsStep.WhatIf | Should Be $true
        $state | Should Not Exist

        # Real execution
        $resReal = @(& $stepScript -RetroBatRoot $rb -StatePath $state)
        $resReal.Count | Should Be 3
        foreach ($r in $resReal) {
            (@('Done', 'Skipped') -contains $r.Status) | Should Be $true
        }

        # Verify RetroBat es_settings.cfg settings applied
        $esCfg = (Get-LightgunRetroBatPath -Root $rb).EsSettings
        $esContent = [IO.File]::ReadAllText($esCfg)
        $esContent | Should Match '<string name="model2\.use_guns" value="0"'
        $esContent | Should Match '<string name="model2\.disableautocontrollers" value="1"'
        $esContent | Should Match '<string name="model3\.use_guns" value="0"'
        $esContent | Should Match '<string name="model3\.disableautocontrollers" value="1"'

        # Re-run: all skipped / verified
        $resSecond = @(& $stepScript -RetroBatRoot $rb -StatePath $state)
        foreach ($r in $resSecond) {
            $r.Status | Should Be 'Skipped'
        }
    }
}
