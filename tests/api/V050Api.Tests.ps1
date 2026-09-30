$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1') -Force
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1') -Force
Import-Module (Join-Path $kitRoot 'output\RetroCabinetKit.Output.psd1') -Force
Import-Module (Join-Path $kitRoot 'api\RetroCabinetKit.Api.psd1') -Force

Describe 'v0.5.0 API — Module field' {
    Set-KitCulture -Culture 'en-US'

    It 'every catalog entry carries a Module property' {
        foreach ($op in Get-KitOperation) {
            $op.PSObject.Properties['Module'] | Should Not Be $null
            $op.Module | Should Match '^(core|pinball|lightgun|controllers|outputs|profiles|library|emulators|frontends|displays|enhancements)$'
        }
    }

    It 'fixed operations have correct Module assignments' {
        $ops = @{}
        foreach ($o in Get-KitOperation) { $ops[$o.Name] = $o.Module }
        $ops['operations'] | Should Be 'core'
        $ops['status'] | Should Be 'core'
        $ops['components'] | Should Be 'core'
        $ops['pinbally.detect'] | Should Be 'pinball'
        $ops['pinbally.retarget'] | Should Be 'pinball'
        $ops['backups.list'] | Should Be 'core'
        $ops['backup.check'] | Should Be 'core'
        $ops['backup.restore'] | Should Be 'core'
        $ops['backup.remove'] | Should Be 'core'
        $ops['backup.export'] | Should Be 'core'
        $ops['support.bundle'] | Should Be 'core'
        $ops['controllers.detect'] | Should Be 'controllers'
        $ops['outputs.verify_safety'] | Should Be 'outputs'
        $ops['profile.export'] | Should Be 'profiles'
        $ops['profile.import'] | Should Be 'profiles'
    }

    It 'step operations derive Module from Suite' {
        foreach ($op in Get-KitOperation | Where-Object { $_.Name -like 'step.*' }) {
            if ($op.Suite -eq 'pinball') { $op.Module | Should Be 'pinball' }
            elseif ($op.Suite -eq 'lightgun') { $op.Module | Should Be 'lightgun' }
        }
    }
}

Describe 'v0.5.0 API — controllers.detect' {
    Set-KitCulture -Culture 'en-US'

    It 'is listed in the catalog' {
        $names = @(Get-KitOperation | ForEach-Object { $_.Name })
        $names -contains 'controllers.detect' | Should Be $true
    }

    It 'returns Ok with Lightguns, Arcade and Pads arrays' {
        $r = Invoke-KitOperation -Name 'controllers.detect'
        $r.Status | Should Be 'Ok'
        $r.Kind | Should Be 'Read'
        $r.Data | Should Not Be $null
        $r.Data.PSObject.Properties['Lightguns'] | Should Not Be $null
        $r.Data.PSObject.Properties['Arcade'] | Should Not Be $null
        $r.Data.PSObject.Properties['Pads'] | Should Not Be $null
    }

    It 'each detected entry has the required fields' {
        $r = Invoke-KitOperation -Name 'controllers.detect'
        foreach ($cat in @('Lightguns', 'Arcade', 'Pads')) {
            foreach ($d in @($r.Data.$cat)) {
                $d.PSObject.Properties['Name'] | Should Not Be $null
                $d.PSObject.Properties['Present'] | Should Not Be $null
                $d.PSObject.Properties['Info'] | Should Not Be $null
                $d.PSObject.Properties['Category'] | Should Not Be $null
                $d.Category | Should Match '^(lightgun|arcade|pad)$'
            }
        }
    }
}

Describe 'v0.5.0 API — outputs.verify_safety' {
    Set-KitCulture -Culture 'en-US'

    It 'is listed in the catalog' {
        $names = @(Get-KitOperation | ForEach-Object { $_.Name })
        $names -contains 'outputs.verify_safety' | Should Be $true
    }

    It 'returns Ok with the four safety sections' {
        $r = Invoke-KitOperation -Name 'outputs.verify_safety'
        $r.Status | Should Be 'Ok'
        $r.Kind | Should Be 'Read'
        $r.Data | Should Not Be $null
        $r.Data.PSObject.Properties['SolenoidGuard'] | Should Not Be $null
        $r.Data.PSObject.Properties['PortConflicts'] | Should Not Be $null
        $r.Data.PSObject.Properties['DoubleConsumers'] | Should Not Be $null
        $r.Data.PSObject.Properties['GunmoteConfig'] | Should Not Be $null
        $r.Data.PSObject.Properties['DetectedOutputs'] | Should Not Be $null
    }

    It 'SolenoidGuard has Ok and Detail fields' {
        $r = Invoke-KitOperation -Name 'outputs.verify_safety'
        $r.Data.SolenoidGuard.PSObject.Properties['Ok'] | Should Not Be $null
        $r.Data.SolenoidGuard.PSObject.Properties['Detail'] | Should Not Be $null
    }

    It 'GunmoteConfig has InisFound, Connected and RumbleThresholdOk' {
        $r = Invoke-KitOperation -Name 'outputs.verify_safety'
        $r.Data.GunmoteConfig.PSObject.Properties['InisFound'] | Should Not Be $null
        $r.Data.GunmoteConfig.PSObject.Properties['Connected'] | Should Not Be $null
        $r.Data.GunmoteConfig.PSObject.Properties['RumbleThresholdOk'] | Should Not Be $null
    }

    It 'accepts optional RetroBatRoot parameter' {
        $r = Invoke-KitOperation -Name 'outputs.verify_safety' -Parameters @{ RetroBatRoot = 'C:\RetroBat' }
        $r.Status | Should Be 'Ok'
    }
}