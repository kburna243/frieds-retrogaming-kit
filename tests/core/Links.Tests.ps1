$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force

Describe 'Links' {
    $notepad = Join-Path $env:SystemRoot 'System32\notepad.exe'
    $lnk = Join-Path $TestDrive 'Pinball [test] (1).lnk'

    It 'creates and reads a shortcut' {
        $s = Set-KitShortcut -Path $lnk -TargetPath $notepad -Arguments '/a "b c"' -WorkingDirectory $env:SystemRoot -Description 'Test ä'
        $s.TargetPath | Should Be $notepad
        $r = Get-KitShortcut -Path $lnk
        $r.Arguments | Should BeExactly '/a "b c"'
        $r.Description | Should BeExactly 'Test ä'
    }

    It 'reports an existing target' {
        Test-KitShortcutTarget -Path $lnk | Should Be $true
    }

    It 'reports a dead target' {
        $dead = Join-Path $TestDrive 'NoSuchFolder\missing.exe'
        $null = Set-KitShortcut -Path $lnk -TargetPath $dead
        Test-KitShortcutTarget -Path $lnk | Should Be $false
    }

    It 'does not write under -WhatIf' {
        $other = Join-Path $TestDrive 'whatif.lnk'
        Set-KitShortcut -Path $other -TargetPath $notepad -WhatIf
        $other | Should Not Exist
    }

    It 'throws for a missing shortcut' {
        { Get-KitShortcut -Path (Join-Path $TestDrive 'none.lnk') } | Should Throw
    }
}

Describe 'Open-KitWebLink (Start-Process mocked, no browser opens)' {
    It 'hands web links to explorer.exe (never a browser started with the wizard''s rights)' {
        Mock -ModuleName 'RetroCabinetKit.Core' Start-Process { }
        Open-KitWebLink -Url 'https://github.com/nefarius/ViGEmBus/releases' | Should Be $true
        Assert-MockCalled -ModuleName 'RetroCabinetKit.Core' Start-Process -Times 1 -Exactly -ParameterFilter {
            $FilePath -eq (Join-Path $env:SystemRoot 'explorer.exe') -and $ArgumentList -eq '"https://github.com/nefarius/ViGEmBus/releases"'
        }
    }

    It 'ignores everything that is not a plain http(s) URL' {
        Mock -ModuleName 'RetroCabinetKit.Core' Start-Process { throw 'must not start' }
        foreach ($u in 'file:///C:/Windows/System32/calc.exe', 'C:\Windows\System32\calc.exe', 'https://x.example/a" /c calc', 'javascript:alert(1)', '') {
            Open-KitWebLink -Url $u | Should Be $false
        }
        Open-KitWebLink -Url 'http://example.com/' -HttpsOnly | Should Be $false
    }
}
