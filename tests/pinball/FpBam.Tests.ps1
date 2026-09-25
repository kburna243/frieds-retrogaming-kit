$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1') -Force
$newBuild = Join-Path $PSScriptRoot 'New-PinballTestBuild.ps1'

# A test key stands in for ...\AppCompatFlags\Layers; the real key is never touched.
$testKey = 'HKCU:\Software\retro-cabinet-kit-test-pinball-layers'

Describe 'FP/BAM setup (step 7)' {
    $root = Join-Path $TestDrive 'Cab'
    & $newBuild -Root $root -OldRoot 'D:\Old'
    $exes = @(Get-PinballFpExecutable -Root $root)

    BeforeAll { if (Test-Path -LiteralPath $testKey) { Remove-Item -LiteralPath $testKey -Recurse -Force } }
    AfterAll { if (Test-Path -LiteralPath $testKey) { Remove-Item -LiteralPath $testKey -Recurse -Force } }

    It 'merges the flag into existing AppCompat data' {
        Add-PinballLayerFlag -Data '' -Flag 'DISABLEDXMAXIMIZEDWINDOWEDMODE' | Should BeExactly '~ DISABLEDXMAXIMIZEDWINDOWEDMODE'
        Add-PinballLayerFlag -Data '~ RUNASADMIN' -Flag 'DISABLEDXMAXIMIZEDWINDOWEDMODE' | Should BeExactly '~ RUNASADMIN DISABLEDXMAXIMIZEDWINDOWEDMODE'
        Add-PinballLayerFlag -Data '~ DISABLEDXMAXIMIZEDWINDOWEDMODE RUNASADMIN' -Flag 'DISABLEDXMAXIMIZEDWINDOWEDMODE' | Should BeExactly '~ DISABLEDXMAXIMIZEDWINDOWEDMODE RUNASADMIN'
    }

    It 'sets the flag for FPLoader.exe and Future Pinball.exe below the new root, once' {
        $exes | Should Be @("$root\vPinball\FuturePinball\BAM\FPLoader.exe", "$root\vPinball\FuturePinball\Future Pinball.exe")
        Set-KitRegistryValue -Path $testKey -Name $exes[1] -Value '~ RUNASADMIN'
        Test-PinballFullscreenOptimizationOff -Executable $exes -LayersKey $testKey | Should Be $false
        @(Set-PinballFullscreenOptimizationOff -Executable $exes -LayersKey $testKey).Count | Should Be 2
        Get-KitRegistryValue -Path $testKey -Name $exes[0] | Should BeExactly '~ DISABLEDXMAXIMIZEDWINDOWEDMODE'
        Get-KitRegistryValue -Path $testKey -Name $exes[1] | Should BeExactly '~ RUNASADMIN DISABLEDXMAXIMIZEDWINDOWEDMODE'
        Test-PinballFullscreenOptimizationOff -Executable $exes -LayersKey $testKey | Should Be $true
        @(Set-PinballFullscreenOptimizationOff -Executable $exes -LayersKey $testKey).Count | Should Be 0
    }

    It 'reports entries of the old root as outdated and leaves them' {
        Set-KitRegistryValue -Path $testKey -Name 'D:\Old\vPinball\FuturePinball\BAM\FPLoader.exe' -Value '~ DISABLEDXMAXIMIZEDWINDOWEDMODE'
        $legacy = @(Get-PinballLegacyAppCompat -Roots $testKey -Relocator (New-PinballRelocator -OldRoot 'D:\Old' -NewRoot $root))
        $legacy.Count | Should Be 1
        $legacy[0].Name | Should BeExactly 'D:\Old\vPinball\FuturePinball\BAM\FPLoader.exe'
    }

    It 'finds the BAM batch file and the install guide' {
        Find-PinballBamBat -Root $root | Should BeExactly "$root\vPinball\FuturePinball\BAM\BAM settings - Cabinet - Reset and Install.bat"
        Find-PinballInstallGuide -Root $root | Should BeExactly "$root\vPinball\FuturePinball\BAM\BAM Install Guide.pdf"
    }

    It 'runs nothing when the plan of the batch file is declined' {
        $bat = Find-PinballBamBat -Root $root
        $script:shown = $null
        { Invoke-PinballBat -Path $bat -Approve { param($t) $script:shown = $t; $false } } | Should Throw
        $script:shown | Should Match ([regex]::Escape($bat))
        $script:shown | Should Match (Get-FileHash -LiteralPath $bat -Algorithm SHA256).Hash
        Join-Path $root 'vPinball\FuturePinball\BAM\bam_ran.txt' | Should Not Exist
    }

    It 'runs the batch file with stdin from nul after confirmation (a prompt returns at once)' {
        Invoke-PinballBat -Path (Find-PinballBamBat -Root $root) -Approve { $true } | Should Be 0
        Join-Path $root 'vPinball\FuturePinball\BAM\bam_ran.txt' | Should Exist
    }

    It 'finds nothing through a junction in the build' {
        $outside = Join-Path $TestDrive 'OutsideFp'
        New-Item -ItemType Directory -Path $outside -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $outside 'Install Guide.pdf'), 'x')
        $root2 = Join-Path $TestDrive 'Cab2'
        New-Item -ItemType Directory -Path "$root2\vPinball\FuturePinball" -Force | Out-Null
        $null = cmd /c mklink /J "$root2\vPinball\FuturePinball\Docs" "$outside"
        try { Find-PinballInstallGuide -Root $root2 | Should BeNullOrEmpty }
        finally { cmd /c rmdir "$root2\vPinball\FuturePinball\Docs" }
    }
}
