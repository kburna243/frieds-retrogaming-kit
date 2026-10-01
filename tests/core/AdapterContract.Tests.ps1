$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'emulators\RetroCabinetKit.Emulators.psd1') -Force
Import-Module (Join-Path $kitRoot 'frontends\RetroCabinetKit.Frontends.psd1') -Force
. (Join-Path $kitRoot 'core\modules\AdapterContract.ps1')

Describe 'P2 -- Multi-Section INI Parser' {
    $testIni = Join-Path $TestDrive 'test.ini'

    BeforeEach {
        @'
[video]
fullscreen = 0
resolution = 1920x1080

[input]
fullscreen = 1
deadzone = 15

[audio]
volume = 80
'@ | Set-Content -LiteralPath $testIni -Encoding UTF8
    }

    It 'Get-EmulatorsIniPlan matches only keys in the specified section' {
        # Section='video': should find fullscreen=0, NOT fullscreen=1 from [input]
        $plan = Get-EmulatorsIniPlan -Path $testIni -Section 'video' -Values @{ fullscreen = '1' }
        $plan.Count | Should Be 1
        $plan[0].Key | Should Be 'fullscreen'
        $plan[0].Old | Should Be '0'
        $plan[0].Section | Should Be 'video'
    }

    It 'Get-EmulatorsIniPlan does NOT match keys from wrong section' {
        $plan = Get-EmulatorsIniPlan -Path $testIni -Section 'audio' -Values @{ fullscreen = '1' }
        # fullscreen exists in [video] and [input], but NOT in [audio] -- should not find it
        $plan.Count | Should Be 0
    }

    It 'Get-EmulatorsIniPlan with Section="input" finds input-specific keys' {
        $plan = Get-EmulatorsIniPlan -Path $testIni -Section 'input' -Values @{ deadzone = '10' }
        $plan.Count | Should Be 1
        $plan[0].Key | Should Be 'deadzone'
        $plan[0].Old | Should Be '15'
    }

    It 'Get-EmulatorsIniPlan with Section="" matches global section (no header)' {
        @'
global_setting = on

[video]
fullscreen = 0
'@ | Set-Content -LiteralPath $testIni -Encoding UTF8
        $plan = Get-EmulatorsIniPlan -Path $testIni -Section '' -Values @{ global_setting = 'off' }
        $plan.Count | Should Be 1
        $plan[0].Old | Should Be 'on'
    }

    It 'Set-EmulatorsIniValue writes new key under correct section' {
        Set-EmulatorsIniValue -Path $testIni -Section 'audio' -Values @{ bassboost = '1' }
        $content = Get-Content -LiteralPath $testIni -Raw
        # bassboost should appear after [audio], not before it
        $audioIdx = $content.IndexOf('[audio]')
        $bassIdx = $content.IndexOf('bassboost')
        $bassIdx | Should BeGreaterThan $audioIdx
    }

    It 'Get-FrontendsIniPlan also respects sections (cross-check)' {
        $plan = Get-FrontendsIniPlan -Path $testIni -Section 'video' -Values @{ fullscreen = '1'; resolution = '1280x720' }
        $plan.Count | Should Be 2
        $plan[0].Section | Should Be 'video'
        $plan[1].Section | Should Be 'video'
    }
}

Describe 'P2 -- Adapter Contract Compliance' {
    It 'all emulator adapters pass Test-AdapterContract' {
        $dir = Join-Path $kitRoot 'emulators\adapters'
        $results = Test-AdapterContractBatch -AdapterDir $dir -AdapterKind 'Emulator'
        foreach ($r in $results) {
            $r.Valid | Should Be $true -Because "$($r.Name) should be valid: $($r.Warnings -join ', ')"
            $r.ParseErrors.Count | Should Be 0 -Because "$($r.Name) should have 0 parse errors"
            $r.MissingFuncs.Count | Should Be 0 -Because "$($r.Name) should export all 5 functions"
        }
    }

    It 'all frontend adapters pass Test-AdapterContract' {
        $dir = Join-Path $kitRoot 'frontends\adapters'
        $results = Test-AdapterContractBatch -AdapterDir $dir -AdapterKind 'Frontend'
        foreach ($r in $results) {
            $r.Valid | Should Be $true -Because "$($r.Name) should be valid: $($r.Warnings -join ', ')"
            $r.ParseErrors.Count | Should Be 0
            $r.MissingFuncs.Count | Should Be 0
        }
    }

    It 'emulator adapter count matches expected (15)' {
        $dir = Join-Path $kitRoot 'emulators\adapters'
        $results = Test-AdapterContractBatch -AdapterDir $dir -AdapterKind 'Emulator'
        $results.Count | Should Be 15
    }

    It 'frontend adapter count matches expected (5)' {
        $dir = Join-Path $kitRoot 'frontends\adapters'
        $results = Test-AdapterContractBatch -AdapterDir $dir -AdapterKind 'Frontend'
        $results.Count | Should Be 5
    }
}

Describe 'P2 -- Idempotency (Verify-before-Invoke)' {
    $testIni = Join-Path $TestDrive 'idem.ini'

    BeforeEach {
        @'
[video]
fullscreen = 0
vsync = 1
'@ | Set-Content -LiteralPath $testIni -Encoding UTF8
    }

    It 'Set-EmulatorsIniValue returns 0 when values already match (idempotent)' {
        # First apply
        $first = Set-EmulatorsIniValue -Path $testIni -Section 'video' -Values @{ fullscreen = '1'; vsync = '1' }
        $first | Should Be 1  # Only fullscreen changed

        # Second apply with same values -- should be idempotent
        $second = Set-EmulatorsIniValue -Path $testIni -Section 'video' -Values @{ fullscreen = '1'; vsync = '1' }
        $second | Should Be 0  # Nothing changed
    }

    It 'Get-EmulatorsIniPlan returns empty when values already match' {
        Set-EmulatorsIniValue -Path $testIni -Section 'video' -Values @{ fullscreen = '1' }
        $plan = Get-EmulatorsIniPlan -Path $testIni -Section 'video' -Values @{ fullscreen = '1' }
        $plan.Count | Should Be 0
    }

    It 'backup is created before modification' {
        $beforeCount = @(Get-ChildItem -LiteralPath $TestDrive -Filter '*.bak_*').Count
        Set-EmulatorsIniValue -Path $testIni -Section 'video' -Values @{ fullscreen = '2' }
        $afterCount = @(Get-ChildItem -LiteralPath $TestDrive -Filter '*.bak_*').Count
        $afterCount | Should Be ($beforeCount + 1)
    }
}