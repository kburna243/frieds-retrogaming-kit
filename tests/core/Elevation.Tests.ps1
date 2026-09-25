$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force

Describe 'Elevation' {
    It 'Test-KitAdmin returns a boolean' {
        (Test-KitAdmin) -is [bool] | Should Be $true
    }

    It 'Test-KitSameUser accepts the current SID and rejects another' {
        Test-KitSameUser -OriginalSid (Get-KitUserSid) | Should Be $true
        Test-KitSameUser -OriginalSid 'S-1-5-18' | Should Be $false
    }

    Context 'Convert-KitMappedDriveToUnc' {
        Mock -ModuleName 'RetroCabinetKit.Core' Get-CimInstance {
            [pscustomobject]@{ DeviceID = 'Z:'; ProviderName = '\\fileserver\share' }
        } -ParameterFilter { $ClassName -eq 'Win32_MappedLogicalDisk' -and $Filter -eq "DeviceID='Z:'" }
        Mock -ModuleName 'RetroCabinetKit.Core' Get-CimInstance { $null } -ParameterFilter { $Filter -notmatch "'Z:'" }

        It 'converts a mapped drive path to UNC' {
            Convert-KitMappedDriveToUnc 'z:\Games\a b\run.ps1' | Should Be '\\fileserver\share\Games\a b\run.ps1'
        }
        It 'converts the bare drive' {
            Convert-KitMappedDriveToUnc 'Z:' | Should Be '\\fileserver\share'
        }
        It 'leaves local drives unchanged' {
            Convert-KitMappedDriveToUnc 'C:\Windows' | Should Be 'C:\Windows'
        }
        It 'leaves UNC paths unchanged' {
            Convert-KitMappedDriveToUnc '\\host\share\x' | Should Be '\\host\share\x'
        }
    }

    Context 'Get-KitElevationCommandLine' {
        It 'uses Bypass and -File with a quoted script path' {
            $cmd = Get-KitElevationCommandLine -ScriptPath 'C:\Kit Folder\step.ps1'
            $cmd | Should BeExactly '-NoProfile -ExecutionPolicy Bypass -File "C:\Kit Folder\step.ps1"'
        }
        It 'quotes arguments with spaces, quotes and trailing backslashes' {
            $cmd = Get-KitElevationCommandLine -ScriptPath 'C:\k\s.ps1' -ArgumentList 'plain', 'with space', 'say "hi"', 'C:\dir with space\', ''
            $cmd | Should BeExactly '-NoProfile -ExecutionPolicy Bypass -File C:\k\s.ps1 plain "with space" "say \"hi\"" "C:\dir with space\\" ""'
        }
        It 'passes the current user SID on request' {
            $cmd = Get-KitElevationCommandLine -ScriptPath 'C:\k\s.ps1' -PassUserSid
            $cmd | Should Match ([regex]::Escape('-KitUserSid ' + (Get-KitUserSid)) + '$')
        }
    }
}
