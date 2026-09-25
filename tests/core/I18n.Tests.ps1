$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force

Describe 'I18n with the real text files' {
    It 'returns German text with correct umlauts' {
        Set-KitCulture -Culture 'de-DE'
        Get-KitText 'Process.PleaseClose' -f 'VPinballX' | Should BeExactly 'Bitte schließe diese Programme: VPinballX. Das Kit beendet nie selbst Programme.'
    }

    It 'returns English text' {
        Set-KitCulture -Culture 'en-US'
        Get-KitText 'Culture.Current' 'en-US' | Should BeExactly 'Language: en-US'
    }

    It 'falls back to en-US for a culture without a file' {
        Set-KitCulture -Culture 'fr-FR'
        Get-KitText 'Admin.Yes' | Should BeExactly 'Running with administrator rights.'
    }

    It 'shows a visible placeholder for a missing key' {
        Set-KitCulture -Culture 'de-DE'
        Get-KitText 'No.Such.Key' | Should BeExactly '[[No.Such.Key]]'
    }

    It 'has the same keys in de-DE and en-US' {
        $de = Import-PowerShellDataFile (Join-Path $kitRoot 'i18n\de-DE.psd1')
        $en = Import-PowerShellDataFile (Join-Path $kitRoot 'i18n\en-US.psd1')
        (@($de.Keys | Sort-Object) -join ',') | Should Be (@($en.Keys | Sort-Object) -join ',')
    }

    It 'stores every PowerShell file of the kit as UTF-8 with BOM' {
        $files = Get-ChildItem -LiteralPath (Join-Path $kitRoot 'core'), (Join-Path $kitRoot 'i18n'), (Join-Path $kitRoot 'tests') -Recurse -File |
            Where-Object { $_.Extension -in '.ps1', '.psm1', '.psd1' -and $_.FullName -notlike '*\fixtures-local\*' }
        $withoutBom = $files | Where-Object {
            $b = [IO.File]::ReadAllBytes($_.FullName)
            -not ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
        }
        @($withoutBom | ForEach-Object { $_.Name }) -join ', ' | Should BeNullOrEmpty
    }
}

Describe 'I18n fallback per key' {
    $dir = Join-Path $TestDrive 'i18n'
    New-Item -ItemType Directory -Path $dir | Out-Null
    [IO.File]::WriteAllText((Join-Path $dir 'de-DE.psd1'), "@{ 'Only.Both' = 'übersetzt' }", (New-Object Text.UTF8Encoding $true))
    [IO.File]::WriteAllText((Join-Path $dir 'en-US.psd1'), "@{ 'Only.Both' = 'translated'; 'Only.English' = 'english {0}' }", (New-Object Text.UTF8Encoding $true))

    InModuleScope 'RetroCabinetKit.Core' {
        $saved = $script:KitI18nDir
        $script:KitI18nDir = Join-Path $TestDrive 'i18n'
        $script:KitTextCache = @{}
        try {
            Set-KitCulture -Culture 'de-DE'
            It 'uses the selected culture when the key exists' {
                Get-KitText 'Only.Both' | Should BeExactly 'übersetzt'
            }
            It 'falls back to en-US for a key missing in the culture' {
                Get-KitText 'Only.English' -f 1 | Should BeExactly 'english 1'
            }
            It 'shows the placeholder when no culture has the key' {
                Get-KitText 'Nowhere' | Should BeExactly '[[Nowhere]]'
            }
        } finally {
            $script:KitI18nDir = $saved
            $script:KitTextCache = @{}
        }
    }
}
