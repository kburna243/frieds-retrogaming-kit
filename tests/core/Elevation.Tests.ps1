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

    It 'locks registry steps for another user, or when elevated and nobody can tell who is logged on' {
        Get-KitRegistryUserLock -OriginalSid '' -IsAdmin $false | Should BeNullOrEmpty
        Get-KitRegistryUserLock -OriginalSid '' -IsAdmin $true -InteractiveSid '' | Should Not BeNullOrEmpty
        Get-KitRegistryUserLock -OriginalSid (Get-KitUserSid) -IsAdmin $true | Should BeNullOrEmpty
        Get-KitRegistryUserLock -OriginalSid 'S-1-5-18' -IsAdmin $true | Should Not BeNullOrEmpty
    }

    It 'started directly as administrator: the interactively logged-on user decides' {
        $me = Get-KitUserSid
        Get-KitRegistryUserLock -OriginalSid '' -IsAdmin $true -InteractiveSid $me | Should BeNullOrEmpty
        Get-KitRegistryUserLock -OriginalSid '' -IsAdmin $true -InteractiveSid 'S-1-5-21-1-2-3-1001' | Should Be (Get-KitText 'Elevation.DifferentUser')
        Get-KitStartUserSid -OriginalSid '' -IsAdmin $true -InteractiveSid $me | Should Be $me
        Get-KitStartUserSid -OriginalSid '' -IsAdmin $true -InteractiveSid 'S-1-5-21-1-2-3-1001' | Should BeNullOrEmpty
        Get-KitStartUserSid -OriginalSid '' -IsAdmin $false | Should Be $me
        Get-KitStartUserSid -OriginalSid 'S-1-5-18' -IsAdmin $true | Should Be 'S-1-5-18'
    }

    It 'finds the interactively logged-on user of this session (the test runs in a desktop session)' {
        Get-KitInteractiveUserSid | Should Be (Get-KitUserSid)
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
