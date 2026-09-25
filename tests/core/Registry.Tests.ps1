$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force

# The ONLY registry location the tests touch; created and removed here.
$testKey = 'HKCU:\Software\retro-cabinet-kit-test'

Describe 'Registry' {
    BeforeAll {
        if (Test-Path -LiteralPath $testKey) { Remove-Item -LiteralPath $testKey -Recurse -Force }
        New-Item -Path "$testKey\Sub\Deeper" -Force | Out-Null
        Set-KitRegistryValue -Path $testKey -Name 'TablesDir' -Value 'C:\Games\vPinball\Tables'
        Set-KitRegistryValue -Path "$testKey\Sub\Deeper" -Name 'Rom' -Value 'C:\Games\vPinball\VPinMAME\roms'
        Set-KitRegistryValue -Path "$testKey\Sub" -Name 'C:\Games\vPinball\FPLoader.exe' -Value '~ RUNASADMIN DISABLEDXMAXIMIZEDWINDOWEDMODE'
        Set-KitRegistryValue -Path "$testKey\Sub" -Name 'List' -Value @('a', 'C:\GAMES\VPINBALL\x') -Type MultiString
    }
    AfterAll {
        if (Test-Path -LiteralPath $testKey) { Remove-Item -LiteralPath $testKey -Recurse -Force }
    }

    It 'sets an empty string value (not swallowed like reg.exe /d "")' {
        Set-KitRegistryValue -Path $testKey -Name 'DllSurrogate' -Value ''
        $key = Get-Item -LiteralPath $testKey
        $key.GetValueKind('DllSurrogate') | Should Be 'String'
        Get-KitRegistryValue -Path $testKey -Name 'DllSurrogate' | Should BeExactly ''
    }

    It 'creates missing keys when setting a value' {
        Set-KitRegistryValue -Path "$testKey\New\Key" -Name 'n' -Value 5 -Type DWord
        Get-KitRegistryValue -Path "$testKey\New\Key" -Name 'n' | Should Be 5
    }

    It 'honours -WhatIf' {
        Set-KitRegistryValue -Path $testKey -Name 'WhatIfValue' -Value 'x' -WhatIf
        Get-KitRegistryValue -Path $testKey -Name 'WhatIfValue' | Should BeNullOrEmpty
    }

    It 'finds matches in value data recursively (case-insensitive, multi-string)' {
        $hits = @(Find-KitRegistryValue -Path $testKey -Pattern 'c:\games\vpinball\' -Recurse | Where-Object { $_.MatchIn -eq 'Data' })
        ($hits | ForEach-Object { $_.Name } | Sort-Object) -join ',' | Should Be 'List,Rom,TablesDir'
    }

    It 'finds matches in value names' {
        $hits = @(Find-KitRegistryValue -Path $testKey -Pattern 'FPLoader.exe' -Recurse)
        $hits.Count | Should Be 1
        $hits[0].MatchIn | Should Be 'Name'
        $hits[0].Name | Should Be 'C:\Games\vPinball\FPLoader.exe'
        $hits[0].Key | Should Be 'HKEY_CURRENT_USER\Software\retro-cabinet-kit-test\Sub'
    }

    It 'does not descend without -Recurse' {
        @(Find-KitRegistryValue -Path $testKey -Pattern 'roms').Count | Should Be 0
    }

    It 'exports the key as a .reg file' {
        $file = Join-Path $TestDrive 'export (1).reg'
        $null = Export-KitRegistryKey -Path $testKey -Destination $file
        $text = [IO.File]::ReadAllText($file)
        $text | Should Match ([regex]::Escape('[HKEY_CURRENT_USER\Software\retro-cabinet-kit-test\Sub\Deeper]'))
        $text | Should Match ([regex]::Escape('"TablesDir"="C:\\Games\\vPinball\\Tables"'))
    }

    It 'fails the export for a missing key' {
        { Export-KitRegistryKey -Path "$testKey\DoesNotExist" -Destination (Join-Path $TestDrive 'x.reg') } | Should Throw
    }

    It 'imports its own export (UTF-16LE with BOM) through the check, only below the allowed key' {
        $file = Join-Path $TestDrive 'roundtrip.reg'
        $null = Export-KitRegistryKey -Path "$testKey\Sub\Deeper" -Destination $file
        ([IO.File]::ReadAllBytes($file))[0..1] -join ',' | Should Be '255,254'
        Remove-ItemProperty -LiteralPath "$testKey\Sub\Deeper" -Name 'Rom'
        Import-KitRegistryFile -Path $file -AllowedRoots "$testKey\Sub" -Confirm:$false
        Get-KitRegistryValue -Path "$testKey\Sub\Deeper" -Name 'Rom' | Should BeExactly 'C:\Games\vPinball\VPinMAME\roms'
        { Import-KitRegistryFile -Path $file -AllowedRoots "$testKey\Other" -Confirm:$false } | Should Throw
    }
}

Describe 'Assert-KitRegText' {
    Set-KitCulture -Culture 'en-US'
    $root = 'HKCU:\Software\Future Pinball'
    $head = "Windows Registry Editor Version 5.00`r`n`r`n"

    It 'accepts merges below the allowed roots (short and long form, BOM, hex continuation)' {
        $ok = [char]0xFEFF + $head + "[HKEY_CURRENT_USER\Software\Future Pinball\GamePlayer]`r`n" + '"Width"=dword:00000780' + "`r`n" +
              '@="x"' + "`r`n" + '"Bin"=hex:01,02,\' + "`r`n" + '  03,04' + "`r`n; comment`r`n"
        Assert-KitRegText -Text $ok -AllowedRoots $root
        Assert-KitRegText -Text ($head + "[HKEY_CURRENT_USER\Software\B2S]`r`n") -AllowedRoots 'Registry::HKEY_CURRENT_USER\Software\B2S'
        Assert-KitRegText -Text ("REGEDIT4`r`n`r`n[HKEY_CURRENT_USER\Software\Future Pinball]`r`n") -AllowedRoots $root
    }

    It 'refuses key deletion, value deletion and keys outside the roots' {
        { Assert-KitRegText -Text ($head + "[-HKEY_CURRENT_USER\Software\Future Pinball]`r`n") -AllowedRoots $root } | Should Throw 'line 3'
        { Assert-KitRegText -Text ($head + "[HKEY_CURRENT_USER\Software\Future Pinball]`r`n" + '"Width"=-') -AllowedRoots $root } | Should Throw 'line 4'
        { Assert-KitRegText -Text ($head + "[HKEY_CURRENT_USER\Software\Future Pinball]`r`n@=-") -AllowedRoots $root } | Should Throw
        { Assert-KitRegText -Text ($head + "[HKEY_CURRENT_USER\Software\Future Pinball Evil]`r`n") -AllowedRoots $root } | Should Throw
        { Assert-KitRegText -Text ($head + "[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run]`r`n" + '"x"="evil.exe"') -AllowedRoots $root } | Should Throw
        { Assert-KitRegText -Text ($head + "[HKEY_LOCAL_MACHINE\Software\Future Pinball]`r`n") -AllowedRoots $root } | Should Throw
        { Assert-KitRegText -Text ($head + "[HKEY_CURRENT_USER\Software\Future Pinball]`r`n") -AllowedRoots @() } | Should Throw
    }

    It 'refuses every value whose data starts with -, not only a bare -' {
        foreach ($v in '"Width"=-', '"Width"= -', '"Width"=-dword:1', '@=-"x"', '@=--') {
            { Assert-KitRegText -Text ($head + "[HKEY_CURRENT_USER\Software\Future Pinball]`r`n" + $v) -AllowedRoots $root } | Should Throw 'line 4'
        }
    }

    It 'refuses control characters that reg.exe could read as a line break (CR, NUL, NEL, U+2028/9, ...)' {
        $key = "[HKEY_CURRENT_USER\Software\Future Pinball]"
        foreach ($c in 0x0D, 0x00, 0x0B, 0x0C, 0x1A, 0x7F, 0x85, 0x2028, 0x2029) {
            # "Harmless" value + hidden separator + a key outside the roots in the same checked line.
            $text = $head + $key + "`r`n" + '"x"="a"' + [char]$c + "[HKEY_CURRENT_USER\Software\Microsoft\Windows\CurrentVersion\Run]`r`n"
            { Assert-KitRegText -Text $text -AllowedRoots $root } | Should Throw 'line 4'
        }
        # A tab and CRLF / LF line ends stay allowed.
        $null = Assert-KitRegText -Text ($head + $key + "`n" + "`"x`"=`t`"a`"`r`n") -AllowedRoots $root
    }

    It 'returns the checked lines joined with CRLF (no BOM), the only text that is imported' {
        $text = [char]0xFEFF + "Windows Registry Editor Version 5.00`n`n[HKEY_CURRENT_USER\Software\Future Pinball]`n" + '"x"="a"' + "`n"
        Assert-KitRegText -Text $text -AllowedRoots $root |
            Should BeExactly ("Windows Registry Editor Version 5.00`r`n`r`n[HKEY_CURRENT_USER\Software\Future Pinball]`r`n" + '"x"="a"' + "`r`n")
    }

    It 'imports only the rebuilt text from a TEMP copy held read-only while reg.exe runs (reg.exe mocked)' {
        $file = Join-Path $TestDrive 'held.reg'
        [IO.File]::WriteAllText($file, $head + "[HKEY_CURRENT_USER\Software\Future Pinball]`n" + '"x"="a"', [Text.Encoding]::Unicode)
        $global:RckProbe = $null
        Mock -ModuleName 'RetroCabinetKit.Core' reg.exe {
            $probe = @{ Path = $args[1]; Text = [IO.File]::ReadAllText($args[1]); Writable = $true }
            try { [IO.File]::Open($args[1], 'Open', 'ReadWrite', 'ReadWrite').Dispose() } catch { $probe.Writable = $false }
            $global:RckProbe = $probe
            $global:LASTEXITCODE = 0
        }
        Import-KitRegistryFile -Path $file -AllowedRoots $root -Confirm:$false
        $global:RckProbe.Path | Should Not Be $file
        $global:RckProbe.Writable | Should Be $false
        $global:RckProbe.Text | Should BeExactly ($head + "[HKEY_CURRENT_USER\Software\Future Pinball]`r`n" + '"x"="a"')
        $global:RckProbe.Path | Should Not Exist
        Remove-Variable -Name RckProbe -Scope Global
    }

    It 'refuses files without header, values before a key and unknown lines' {
        { Assert-KitRegText -Text "[HKEY_CURRENT_USER\Software\Future Pinball]`r`n" -AllowedRoots $root } | Should Throw
        { Assert-KitRegText -Text '' -AllowedRoots $root } | Should Throw
        { Assert-KitRegText -Text ($head + '"x"="y"') -AllowedRoots $root } | Should Throw
        { Assert-KitRegText -Text ($head + "[HKEY_CURRENT_USER\Software\Future Pinball]`r`nrm -rf") -AllowedRoots $root } | Should Throw
        { Assert-KitRegText -Text ($head + "[HKEY_CURRENT_USER\Software\Future Pinball]`r`n" + '"Bin"=hex:01,\' + "`r`n[-HKEY_CURRENT_USER\Software]") -AllowedRoots $root } | Should Throw
    }
}
