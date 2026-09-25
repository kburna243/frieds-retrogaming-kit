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
}
