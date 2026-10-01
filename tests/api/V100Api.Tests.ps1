$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1') -Force
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1') -Force
Import-Module (Join-Path $kitRoot 'output\RetroCabinetKit.Output.psd1') -Force
Import-Module (Join-Path $kitRoot 'displays\RetroCabinetKit.Displays.psd1') -Force
Import-Module (Join-Path $kitRoot 'enhancements\RetroCabinetKit.Enhancements.psd1') -Force
Import-Module (Join-Path $kitRoot 'library\RetroCabinetKit.Library.psd1') -Force
Import-Module (Join-Path $kitRoot 'emulators\RetroCabinetKit.Emulators.psd1') -Force
Import-Module (Join-Path $kitRoot 'frontends\RetroCabinetKit.Frontends.psd1') -Force
Import-Module (Join-Path $kitRoot 'api\RetroCabinetKit.Api.psd1') -Force

Describe 'v1.0.0 API -- Module field' {
    Set-KitCulture -Culture 'en-US'

    It 'frontends module is accepted in Module regex' {
        foreach ($op in Get-KitOperation) {
            $op.PSObject.Properties['Module'] | Should Not Be $null
            $op.Module | Should Match '^(core|pinball|lightgun|controllers|outputs|profiles|library|emulators|frontends|displays|enhancements)$'
        }
    }

    It 'frontends operations have correct Module assignments' {
        $ops = @{}
        foreach ($o in Get-KitOperation) { $ops[$o.Name] = $o.Module }
        $ops['frontends.detect'] | Should Be 'frontends'
        $ops['frontends.install'] | Should Be 'frontends'
        $ops['frontends.set_theme'] | Should Be 'frontends'
        $ops['frontends.configure_genre_routing'] | Should Be 'frontends'
        $ops['frontends.import_library'] | Should Be 'frontends'
        $ops['frontends.export_catalog'] | Should Be 'frontends'
    }
}

Describe 'v1.0.0 API -- frontends.* catalog entries' {
    Set-KitCulture -Culture 'en-US'

    It 'frontends.detect is listed' {
        $names = @(Get-KitOperation | ForEach-Object { $_.Name })
        $names -contains 'frontends.detect' | Should Be $true
    }

    It 'frontends.install has Frontend and PackagePath parameters' {
        $op = @(Get-KitOperation | Where-Object { $_.Name -eq 'frontends.install' })[0]
        $op.Kind | Should Be 'Change'
        (@($op.Parameters | Where-Object { $_.Name -eq 'Frontend' })).Count | Should Be 1
    }

    It 'frontends.set_theme has mandatory ThemeName' {
        $op = @(Get-KitOperation | Where-Object { $_.Name -eq 'frontends.set_theme' })[0]
        $op.Kind | Should Be 'Change'
        (@($op.Parameters | Where-Object { $_.Name -eq 'ThemeName' -and $_.Mandatory })).Count | Should Be 1
    }

    It 'frontends.configure_genre_routing is a Change operation' {
        $op = @(Get-KitOperation | Where-Object { $_.Name -eq 'frontends.configure_genre_routing' })[0]
        $op.Kind | Should Be 'Change'
    }

    It 'frontends.import_library is a Read operation' {
        $op = @(Get-KitOperation | Where-Object { $_.Name -eq 'frontends.import_library' })[0]
        $op.Kind | Should Be 'Read'
    }

    It 'frontends.export_catalog has mandatory Destination' {
        $op = @(Get-KitOperation | Where-Object { $_.Name -eq 'frontends.export_catalog' })[0]
        $op.Kind | Should Be 'Read'
        (@($op.Parameters | Where-Object { $_.Name -eq 'Destination' -and $_.Mandatory })).Count | Should Be 1
    }
}

Describe 'v1.0.0 API -- frontends.detect' {
    Set-KitCulture -Culture 'en-US'

    It 'returns Ok with Frontends array' {
        $r = Invoke-KitOperation -Name 'frontends.detect'
        $r.Status | Should Be 'Ok'
        $r.Kind | Should Be 'Read'
        $r.Data | Should Not Be $null
        $r.Data.PSObject.Properties['Frontends'] | Should Not Be $null
    }
}

Describe 'v1.0.0 API -- frontends adapter catalog (extensibility)' {
    Set-KitCulture -Culture 'en-US'

    It 'frontends adapter catalog is non-empty and each has required functions' {
        $catalog = Get-FrontendsAdapterCatalog
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

    It 'expected frontends are in the catalog' {
        $names = @(Get-FrontendsAdapterCatalog | ForEach-Object { $_.Name })
        $expected = @('RetroBat', 'PinballY', 'Playnite', 'LaunchBox', 'PinUP')
        foreach ($e in $expected) {
            $names -contains $e | Should Be $true
        }
    }
}