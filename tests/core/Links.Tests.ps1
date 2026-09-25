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
