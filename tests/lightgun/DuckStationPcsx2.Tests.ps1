$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1') -Force
$newRetroBat = Join-Path $PSScriptRoot 'New-LightgunTestRetroBat.ps1'

Describe 'DuckStation & PCSX2 Guided Audit (Step 14)' {
    Set-KitCulture -Culture 'en-US'
    Mock -ModuleName 'RetroCabinetKit.Lightgun' Test-KitProcessesClosed { }

    $rb = Join-Path $TestDrive 'RB_DuckStation'
    & $newRetroBat -Root $rb
    $paths = Get-LightgunDuckStationPath -RetroBatRoot $rb

    It 'resolves DuckStation and PCSX2 paths' {
        $paths.DuckStationDir | Should Match 'emulators\\duckstation$'
        $paths.DuckStationSettings | Should Match 'emulators\\duckstation\\settings\.ini$'
        $paths.Pcsx2Dir | Should Match 'emulators\\pcsx2$'
    }

    It 'audits missing DuckStation and PCSX2 without errors' {
        $ds = Get-LightgunDuckStationAudit -RetroBatRoot $rb
        $ds.DuckStationFound | Should Be $false
        $ds.HasSettings | Should Be $false
        $ds.KonamiAudit.Count | Should Be 2
        $ds.KonamiAudit[0].Valid | Should Be $false

        $p2 = Get-LightgunPcsx2Audit -RetroBatRoot $rb
        $p2.Pcsx2Found | Should Be $false
        $p2.HasIni | Should Be $false
    }

    It 'audits DuckStation settings and Konami Justifier game settings' {
        New-Item -ItemType Directory -Path $paths.DuckStationGameSettings -Force | Out-Null
        $dsIni = @(
            '[InputSources]',
            'RawInput = true',
            '[Pad1]',
            'Type = GunCon',
            'Trigger = XInput-0/B'
        ) -join "`r`n"
        [IO.File]::WriteAllText($paths.DuckStationSettings, $dsIni)

        # Die Hard Trilogy configured with Justifier
        $dieHardIni = @(
            '[ControllerPorts]',
            'UseGameSettingsForController = true',
            '[Pad1]',
            'Type = Justifier'
        ) -join "`r`n"
        [IO.File]::WriteAllText((Join-Path $paths.DuckStationGameSettings 'SLUS-00119.ini'), $dieHardIni)

        # Crypt Killer missing Justifier (configured as GunCon instead)
        $cryptKillerIni = @(
            '[ControllerPorts]',
            'UseGameSettingsForController = true',
            '[Pad1]',
            'Type = GunCon'
        ) -join "`r`n"
        [IO.File]::WriteAllText((Join-Path $paths.DuckStationGameSettings 'SLUS-00335.ini'), $cryptKillerIni)

        $ds = Get-LightgunDuckStationAudit -RetroBatRoot $rb
        $ds.DuckStationFound | Should Be $true
        $ds.HasSettings | Should Be $true
        $ds.RawInput | Should Be 'true'
        $ds.Pad1Type | Should Be 'GunCon'

        $dh = $ds.KonamiAudit | Where-Object { $_.Serial -eq 'SLUS-00119' }
        $dh.HasGameSettings | Should Be $true
        $dh.UsesJustifier | Should Be $true
        $dh.Valid | Should Be $true

        $ck = $ds.KonamiAudit | Where-Object { $_.Serial -eq 'SLUS-00335' }
        $ck.HasGameSettings | Should Be $true
        $ck.UsesJustifier | Should Be $false
        $ck.Valid | Should Be $false
    }

    It 'audits PCSX2 configuration' {
        New-Item -ItemType Directory -Path (Split-Path $paths.Pcsx2Ini) -Force | Out-Null
        [IO.File]::WriteAllText($paths.Pcsx2Ini, "[USB1]`r`nType = GunCon2`r`n[USB2]`r`nType = None`r`n")

        $p2 = Get-LightgunPcsx2Audit -RetroBatRoot $rb
        $p2.Pcsx2Found | Should Be $true
        $p2.HasIni | Should Be $true
        $p2.HasGunCon2 | Should Be $true
    }

    It 'executes step 14 as stand-alone script with -WhatIf and real execution' {
        $state = Join-Path $TestDrive 'state-duckstation.json'
        $stepScript = Join-Path $kitRoot 'lightgun\steps\14-DuckStationPcsx2.ps1'

        # Dry run with -WhatIf
        $resWhatIf = @(& $stepScript -RetroBatRoot $rb -StatePath $state -WhatIf)
        $resWhatIf.Count | Should Be 1
        $resWhatIf[0].WhatIf | Should Be $true
        $resWhatIf[0].Status | Should Be 'Skipped'
        $state | Should Not Exist

        # Real execution
        $resReal = @(& $stepScript -RetroBatRoot $rb -StatePath $state)
        $resReal.Count | Should Be 1
        $resReal[0].Status | Should Be 'Done'

        # Verify state written
        $auditTime = Get-KitStateValue -Path $state -Key 'DuckStationAuditCompleted'
        [string]::IsNullOrEmpty($auditTime) | Should Be $false
    }
}
