$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1') -Force

# Only the command plan and the verification are tested; nothing is registered.
$testKey = 'HKCU:\Software\retro-cabinet-kit-test-pinball-com'
$classes = "$testKey\Classes"
# Default values (empty name) are set with Set-Item; New-ItemProperty refuses an empty name.
function Set-Default([string] $Path, [string] $Value) { if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }; Set-Item -LiteralPath $Path -Value $Value }

Describe 'Register plan (step 6)' {
    $plan = @(Get-PinballRegisterPlan -Root 'E:\Games' -WindowsDir 'C:\Windows')

    It 'keeps the proven order' {
        ($plan | ForEach-Object { $_.Title }) -join ' | ' | Should BeExactly (
            'VPinMAME 64-bit | VPinMAME 32-bit | B2S Server 32-bit | B2S Server 64-bit | FlexDMD 32-bit | FlexDMD 64-bit | ' +
            'FlexUDMD 32-bit | FlexUDMD 64-bit | PUPDMDControl | PuP DllSurrogate | ForegroundLockTimeout 0 | ' +
            'PinUpDOF.exe | PuPServer.exe | PinUpPlayer.exe | PinUpMenuSetup -setfolders')
    }

    It 'uses regsvr32 64/32 and RegAsm /codebase instead of the RegisterApp GUI' {
        $plan[0].FilePath | Should BeExactly 'C:\Windows\System32\regsvr32.exe'
        $plan[0].Arguments | Should BeExactly '/s "E:\Games\vPinball\VisualPinball\VPinMAME\VPinMAME64.dll"'
        $plan[1].FilePath | Should BeExactly 'C:\Windows\SysWOW64\regsvr32.exe'
        $plan[2].FilePath | Should BeExactly 'C:\Windows\Microsoft.NET\Framework\v4.0.30319\RegAsm.exe'
        $plan[2].Arguments | Should BeExactly '"E:\Games\vPinball\VisualPinball\Tables\B2SBackglassServer.dll" /codebase /silent'
        $plan[3].FilePath | Should BeExactly 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\RegAsm.exe'
        @($plan | Where-Object { $_.FilePath -like '*RegisterApp*' -or $_.FilePath -like '*FlexDMDUI*' }).Count | Should Be 0
        ($plan | Where-Object { $_.Title -like 'FlexUDMD*' } | ForEach-Object { $_.Optional }) -join ',' | Should Be 'True,True'
    }

    It 'registers the Popper servers in their own folder' {
        $p = $plan | Where-Object { $_.Title -eq 'PinUpPlayer.exe' }
        $p.Arguments | Should BeExactly '/regserver'
        $p.WorkingDirectory | Should BeExactly 'E:\Games\vPinball\PinUPSystem'
        ($plan | Where-Object { $_.Title -eq 'PUPDMDControl' }).WorkingDirectory | Should BeExactly 'E:\Games\vPinball\VisualPinball\VPinMAME'
        $plan[-1].Arguments | Should BeExactly '-setfolders'
    }

    It 'sets the DllSurrogate as an empty string through the registry cmdlet' {
        $s = $plan | Where-Object { $_.Title -eq 'PuP DllSurrogate' }
        $s.Kind | Should Be 'Registry'
        $v = $s.Values | Where-Object { $_.Name -eq 'DllSurrogate' }
        $v.Value | Should BeExactly ''
        $v.Path | Should BeExactly 'Registry::HKEY_CLASSES_ROOT\WOW6432Node\AppID\{88919FAC-00B2-4AA8-B1C7-52AD65C476D3}'
    }

    It 'runs batch files with stdin from nul in their own folder' {
        $c = Get-PinballBatCommand -Path 'E:\Games\vPinball\Installer\Pu P Register.bat'
        $c.FilePath | Should BeExactly (Join-Path $env:SystemRoot 'System32\cmd.exe')
        $c.Arguments | Should BeExactly '/c ""E:\Games\vPinball\Installer\Pu P Register.bat" < nul"'
        $c.WorkingDirectory | Should BeExactly 'E:\Games\vPinball\Installer'
    }

    It 'reports missing files and registers nothing under -WhatIf' {
        Mock -ModuleName 'RetroCabinetKit.Pinball' Start-Process { throw 'must not start' }
        Mock -ModuleName 'RetroCabinetKit.Pinball' Set-KitRegistryValue { throw 'must not write' }
        $rows = @(Invoke-PinballRegisterPlan -Root $TestDrive -Plan (Get-PinballRegisterPlan -Root $TestDrive) -WhatIf)
        ($rows | Where-Object { $_.Title -eq 'VPinMAME 64-bit' }).Result | Should Be 'Missing'
        ($rows | Where-Object { $_.Title -eq 'FlexUDMD 32-bit' }).Result | Should Be 'NotPresent'
        ($rows | Where-Object { $_.Title -eq 'PuP DllSurrogate' }).Result | Should Be 'Skipped'
        Assert-MockCalled -ModuleName 'RetroCabinetKit.Pinball' Start-Process -Times 0
    }
}

Describe 'COM verification against a test classes key' {
    BeforeAll {
        if (Test-Path -LiteralPath $testKey) { Remove-Item -LiteralPath $testKey -Recurse -Force }
        $ids = @{ 'VPinMAME.Controller' = '{00000000-0000-0000-0000-00000000000A}'; 'B2S.Server' = '{00000000-0000-0000-0000-00000000000B}'
                  'FlexDMD.FlexDMD' = '{00000000-0000-0000-0000-00000000000C}'; 'PinUpPlayer.PinUpPlayerX' = '{00000000-0000-0000-0000-00000000000D}' }
        foreach ($p in $ids.Keys) { Set-Default "$classes\$p\CLSID" $ids[$p] }
        Set-Default "$classes\CLSID\$($ids['VPinMAME.Controller'])\InprocServer32" 'E:\Games\vPinball\VisualPinball\VPinMAME\VPinMAME64.dll'
        Set-Default "$classes\WOW6432Node\CLSID\$($ids['B2S.Server'])\InprocServer32" 'mscoree.dll'
        Set-KitRegistryValue -Path "$classes\WOW6432Node\CLSID\$($ids['B2S.Server'])\InprocServer32" -Name 'CodeBase' -Value 'file:///E:/Games/vPinball/VisualPinball/Tables/B2SBackglassServer.dll'
        Set-KitRegistryValue -Path "$classes\CLSID\$($ids['FlexDMD.FlexDMD'])\InprocServer32" -Name 'CodeBase' -Value 'file:///D:/Old/vPinball/VisualPinball/VPinMAME/FlexDMD.dll'
        Set-Default "$classes\CLSID\$($ids['PinUpPlayer.PinUpPlayerX'])\LocalServer32" '"E:\Games\vPinball\PinUPSystem\PinUpPlayer.exe" /automation'
        Set-KitRegistryValue -Path "$classes\WOW6432Node\AppID\{88919FAC-00B2-4AA8-B1C7-52AD65C476D3}" -Name 'DllSurrogate' -Value ''
    }
    AfterAll { if (Test-Path -LiteralPath $testKey) { Remove-Item -LiteralPath $testKey -Recurse -Force } }

    It 'accepts servers below the new root and flags one still pointing to the old root' {
        $r = @(Test-PinballComRegistration -Root 'E:\Games' -ClassesRoot $classes)
        ($r | Where-Object { $_.Ok } | ForEach-Object { $_.Name }) -join ',' | Should Be 'VPinMAME.Controller,B2S.Server,PinUpPlayer.PinUpPlayerX,PuP DllSurrogate'
        $flex = $r | Where-Object { $_.Name -eq 'FlexDMD.FlexDMD' }
        $flex.Ok | Should Be $false
        $flex.Paths[0] | Should BeExactly 'D:\Old\vPinball\VisualPinball\VPinMAME\FlexDMD.dll'
        ($r | Where-Object { $_.Name -eq 'PinUpPlayer.PinUpPlayerX' }).Paths[0] | Should BeExactly 'E:\Games\vPinball\PinUPSystem\PinUpPlayer.exe'
    }
}
