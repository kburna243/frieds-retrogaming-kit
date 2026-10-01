$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1') -Force
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1') -Force
Import-Module (Join-Path $kitRoot 'output\RetroCabinetKit.Output.psd1') -Force
Import-Module (Join-Path $kitRoot 'displays\RetroCabinetKit.Displays.psd1') -Force
Import-Module (Join-Path $kitRoot 'enhancements\RetroCabinetKit.Enhancements.psd1') -Force
Import-Module (Join-Path $kitRoot 'library\RetroCabinetKit.Library.psd1') -Force
Import-Module (Join-Path $kitRoot 'emulators\RetroCabinetKit.Emulators.psd1') -Force
Import-Module (Join-Path $kitRoot 'api\RetroCabinetKit.Api.psd1') -Force

Describe 'v0.9.0 API — Module field' {
    Set-KitCulture -Culture 'en-US'

    It 'every catalog entry carries a Module property including emulators' {
        foreach ($op in Get-KitOperation) {
            $op.PSObject.Properties['Module'] | Should Not Be $null
            $op.Module | Should Match '^(core|pinball|lightgun|controllers|outputs|profiles|library|emulators|frontends|displays|enhancements)$'
        }
    }

    It 'fixed operations have correct Module assignments for v0.9.0' {
        $ops = @{}
        foreach ($o in Get-KitOperation) { $ops[$o.Name] = $o.Module }
        $ops['emulators.detect_installed'] | Should Be 'emulators'
        $ops['emulators.install'] | Should Be 'emulators'
        $ops['emulators.configure'] | Should Be 'emulators'
        $ops['emulators.apply_shader_preset'] | Should Be 'emulators'
        $ops['emulators.patch'] | Should Be 'emulators'
        $ops['emulators.verify_integrity'] | Should Be 'emulators'
    }
}

Describe 'v0.9.0 API — emulators.* catalog entries' {
    Set-KitCulture -Culture 'en-US'

    It 'emulators.detect_installed is listed in the catalog' {
        $names = @(Get-KitOperation | ForEach-Object { $_.Name })
        $names -contains 'emulators.detect_installed' | Should Be $true
    }

    It 'emulators.install is a Change operation with Emulator parameter' {
        $op = @(Get-KitOperation | Where-Object { $_.Name -eq 'emulators.install' })[0]
        $op.Kind | Should Be 'Change'
        $op.Module | Should Be 'emulators'
        (@($op.Parameters | Where-Object { $_.Name -eq 'Emulator' })).Count | Should Be 1
    }

    It 'emulators.configure has Emulator, RetroBatRoot, and Frontend parameters' {
        $op = @(Get-KitOperation | Where-Object { $_.Name -eq 'emulators.configure' })[0]
        $op.Kind | Should Be 'Change'
        $paramNames = @($op.Parameters | ForEach-Object { $_.Name })
        $paramNames -contains 'Emulator' | Should Be $true
        $paramNames -contains 'Frontend' | Should Be $true
    }

    It 'emulators.apply_shader_preset has Preset parameter' {
        $op = @(Get-KitOperation | Where-Object { $_.Name -eq 'emulators.apply_shader_preset' })[0]
        $op.Kind | Should Be 'Change'
        (@($op.Parameters | Where-Object { $_.Name -eq 'Preset' -and $_.Mandatory })).Count | Should Be 1
    }

    It 'emulators.patch is listed in the catalog' {
        $names = @(Get-KitOperation | ForEach-Object { $_.Name })
        $names -contains 'emulators.patch' | Should Be $true
    }

    It 'emulators.verify_integrity is a Read operation' {
        $op = @(Get-KitOperation | Where-Object { $_.Name -eq 'emulators.verify_integrity' })[0]
        $op.Kind | Should Be 'Read'
        $op.Module | Should Be 'emulators'
    }
}

Describe 'v0.9.0 API — emulators.detect_installed' {
    Set-KitCulture -Culture 'en-US'

    It 'returns Ok with Emulators array' {
        $r = Invoke-KitOperation -Name 'emulators.detect_installed'
        $r.Status | Should Be 'Ok'
        $r.Kind | Should Be 'Read'
        $r.Data | Should Not Be $null
        $r.Data.PSObject.Properties['Emulators'] | Should Not Be $null
        $r.Data.PSObject.Properties['Count'] | Should Not Be $null
    }
}

Describe 'v0.9.0 API — emulators.verify_integrity' {
    Set-KitCulture -Culture 'en-US'

    It 'returns Ok with Emulators or AllOk when no specific emulator given' {
        $r = Invoke-KitOperation -Name 'emulators.verify_integrity'
        $r.Status | Should Be 'Ok'
        $r.Kind | Should Be 'Read'
        $r.Data | Should Not Be $null
    }
}

Describe 'v0.9.0 API — emulators adapter catalog' {
    Set-KitCulture -Culture 'en-US'

    It 'emulators adapter catalog is non-empty and each has required functions' {
        $catalog = Get-EmulatorsAdapterCatalog
        $catalog.Count | Should BeGreaterThan 0
        foreach ($a in $catalog) {
            $a.HasParseErrors | Should Be $false
            $a.HasTest | Should Be $true
            $a.HasInfo | Should Be $true
            $a.HasInstall | Should Be $true
            $a.HasConfigure | Should Be $true
            $a.HasShield | Should Be $true
        }
    }

    It 'expected emulators are in the catalog' {
        $names = @(Get-EmulatorsAdapterCatalog | ForEach-Object { $_.Name })
        $expected = @('MAME', 'RetroArch', 'TeknoParrot', 'Supermodel', 'Model2', 'Cemu', 'Dolphin', 'RPCS3', 'Xemu', 'DuckStation', 'PCSX2', 'FuturePinball', 'VisualPinball', 'PinballArcade', 'PinballFX3')
        foreach ($e in $expected) {
            $names -contains $e | Should Be $true
        }
    }
}