$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1') -Force
$newBuild = Join-Path $PSScriptRoot 'New-PinballTestBuild.ps1'
$steps = Join-Path $kitRoot 'pinball\steps'

# Test keys only: settings roots and AppCompat Layers of the whole flow.
$testKey = 'HKCU:\Software\retro-cabinet-kit-test-pinball-steps'

Describe 'Pinball steps 1-7 as stand-alone scripts' {
    Set-KitCulture -Culture 'en-US'
    $src = Join-Path $TestDrive 'Src'
    $dst = Join-Path $TestDrive 'Dst'
    $state = Join-Path $TestDrive 'install-state.json'
    & $newBuild -Root $src -OldRoot 'D:\Old Build'
    $common = @{ StatePath = $state; Culture = 'en-US' }

    BeforeAll {
        if (Test-Path -LiteralPath $testKey) { Remove-Item -LiteralPath $testKey -Recurse -Force }
        Set-KitRegistryValue -Path "$testKey\FP" -Name 'TablesDir' -Value 'D:\Old Build\vPinball\FuturePinball\Tables'
    }
    AfterAll { if (Test-Path -LiteralPath $testKey) { Remove-Item -LiteralPath $testKey -Recurse -Force } }

    It '1 detect: dry run writes no state, real run records the build' {
        (& "$steps\01-Detect.ps1" -Source $src @common -WhatIf).Status | Should Be 'Skipped'
        $state | Should Not Exist
        (& "$steps\01-Detect.ps1" -Source $src @common).Status | Should Be 'Done'
        Get-KitStateValue -Path $state -Key 'OldRoot' | Should BeExactly 'D:\Old Build'
        @(Get-KitStateValue -Path $state -Key 'Siblings') -join ',' | Should Be 'DOFLinx'
        (& "$steps\01-Detect.ps1" -Source $src @common).Status | Should Be 'Skipped'
    }

    It '2 target: records the validated target' {
        (& "$steps\02-Target.ps1" -TargetRoot $dst @common).Status | Should Be 'Done'
        Get-KitStateValue -Path $state -Key 'TargetRoot' | Should BeExactly $dst
    }

    It '3 dependencies: dry run only (detection is read-only)' {
        (& "$steps\03-Dependencies.ps1" @common -WhatIf).Status | Should Not Be 'Failed'
    }

    It '4 copy: -WhatIf copies nothing, then copies and verifies' {
        (& "$steps\04-Copy.ps1" @common -WhatIf).Status | Should Be 'Skipped'
        Join-Path $dst 'vPinball' | Should Not Exist
        (& "$steps\04-Copy.ps1" @common).Status | Should Be 'Done'
        Join-Path $dst 'DOFLinx\DOFLinx.INI' | Should Exist
    }

    It '5 relocate: dry run changes nothing, then rewrites and verifies; second run is skipped' {
        $opt = @{ RegistryRoots = @("$testKey\FP"); AppCompatRoots = @("$testKey\Layers") }
        $db = Get-PinballDatabasePath -Root $dst
        $hash = (Get-FileHash -LiteralPath $db).Hash
        (& "$steps\05-Relocate.ps1" @common @opt -WhatIf).Status | Should Be 'Skipped'
        (Get-FileHash -LiteralPath $db).Hash | Should Be $hash
        (& "$steps\05-Relocate.ps1" @common @opt).Status | Should Be 'Done'
        Get-KitRegistryValue -Path "$testKey\FP" -Name 'TablesDir' | Should BeExactly "$dst\vPinball\FuturePinball\Tables"
        Get-KitStateValue -Path $state -Key 'RelocateDone' | Should Be $true
        @(Get-KitStateValue -Path $state -Key 'RelocatedFiles') -contains $db | Should Be $true
        (& "$steps\05-Relocate.ps1" @common @opt).Status | Should Be 'Skipped'
    }

    It '4 copy is locked after relocation' {
        (& "$steps\04-Copy.ps1" @common).Status | Should Be 'NeedsUser'
    }

    It '6 register: dry run only (needs administrator rights, never registers in tests)' {
        @('Skipped', 'NeedsUser') -contains (& "$steps\06-Register.ps1" @common -WhatIf).Status | Should Be $true
    }

    It '7 FP/BAM: sets the flags in the test key, runs the batch file, waits for the admin confirmation' {
        $results = @(& "$steps\07-FpBamSetup.ps1" @common -LayersKey "$testKey\Layers")
        ($results | ForEach-Object { "$($_.Name)=$($_.Status)" }) -join ',' | Should Be 'pinball-7-fpbam=Done,pinball-7-fploader-admin=NeedsUser'
        Get-KitRegistryValue -Path "$testKey\Layers" -Name "$dst\vPinball\FuturePinball\BAM\FPLoader.exe" | Should BeExactly '~ DISABLEDXMAXIMIZEDWINDOWEDMODE'
        $results = @(& "$steps\07-FpBamSetup.ps1" @common -LayersKey "$testKey\Layers" -ConfirmFpLoaderAdminRun)
        ($results | ForEach-Object { "$($_.Name)=$($_.Status)" }) -join ',' | Should Be 'pinball-7-fpbam=Skipped,pinball-7-fploader-admin=Done'
    }
}
