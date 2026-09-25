$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1') -Force
$newBuild = Join-Path $PSScriptRoot 'New-PinballTestBuild.ps1'

Describe 'Dependency detection on this computer (read-only)' {
    $status = @(Get-PinballDependencyStatus)

    It 'reports every dependency once' {
        ($status | ForEach-Object { $_.Id }) -join ',' |
            Should Be 'VC2005-x86,VC2005-x64,VC2008-x86,VC2008-x64,VC2010-x86,VC2010-x64,VC2012-x86,VC2012-x64,VC2013-x86,VC2013-x64,VC2015-2022-x86,VC2015-2022-x64,NetFx35,NetFx48,DirectX9,Windows'
        @($status | Where-Object { $_.Present -isnot [bool] }).Count | Should Be 0
    }

    It 'sees Windows 10/11 and .NET 4.8 on the test machine' {
        ($status | Where-Object { $_.Id -eq 'Windows' }).Present | Should Be $true
        ($status | Where-Object { $_.Id -eq 'NetFx48' }).Present | Should Be $true
    }

    It 'agrees with the v14 runtime key for VC++ 2015-2022 x64' {
        $vc = $status | Where-Object { $_.Id -eq 'VC2015-2022-x64' }
        if (Test-PinballVc14Runtime -Arch x64) { $vc.Present | Should Be $true }
        else { $vc.Present | Should Be ([bool]$vc.Detail) }
    }

    It 'maps uninstall names to year and architecture' {
        $key = 'HKCU:\Software\retro-cabinet-kit-test-pinball-deps'
        try {
            foreach ($n in 'Microsoft Visual C++ 2005 Redistributable', 'Microsoft Visual C++ 2010  x64 Redistributable - 10.0.40219',
                           'Microsoft Visual C++ 2015-2022 Redistributable (x86) - 14.38.33135', 'Microsoft Visual C++ 2022 X64 Minimum Runtime - 14.38') {
                Set-KitRegistryValue -Path "$key\WOW6432Node\$([guid]::NewGuid())" -Name 'DisplayName' -Value $n
            }
            $found = @(Get-PinballVcRedist -UninstallKeys "$key\WOW6432Node" | ForEach-Object { "$($_.Year)-$($_.Arch)" } | Sort-Object)
            $found -join ',' | Should Be '2005-x86,2010-x64,2015-2022-x86'
        } finally { Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'Dependency plan and install results (nothing is installed)' {
    Set-KitCulture -Culture 'en-US'
    $root = Join-Path $TestDrive 'Build'
    & $newBuild -Root $root -OldRoot 'D:\Old'
    $missing = @('VC2008-x86', 'VC2012-x64', 'VC2015-2022-x64', 'DirectX9', 'NetFx35', 'Windows') |
        ForEach-Object { [pscustomobject]@{ Id = $_; Name = $_; Present = $false; Detail = '' } }
    $plan = @(Get-PinballDependencyPlan -Root $root -Status $missing)

    It 'takes installers from the build first' {
        $vc = $plan | Where-Object { $_.Id -eq 'VC2008-x86' }
        $vc.Source | Should Be 'Build'
        $vc.FilePath | Should BeExactly "$root\vPinball\2-Programs\All In One Runtimes\vcredist2008_x86.exe"
        $vc.Arguments | Should BeExactly '/qb'
        $dx = $plan | Where-Object { $_.Id -eq 'DirectX9' }
        $dx.Source | Should Be 'Build'
        $dx.Arguments | Should BeExactly '/silent'
    }

    It 'falls back to allow-listed Microsoft downloads, or to the user' {
        ($plan | Where-Object { $_.Id -eq 'VC2015-2022-x64' }).Source | Should Be 'Download'
        ($plan | Where-Object { $_.Id -eq 'VC2012-x64' }).Source | Should Be 'User'
        ($plan | Where-Object { $_.Id -eq 'Windows' }).Source | Should Be 'User'
        ($plan | Where-Object { $_.Id -eq 'NetFx35' }).Arguments | Should BeExactly '/Online /Enable-Feature /FeatureName:NetFx3 /All /NoRestart'
        InModuleScope 'RetroCabinetKit.Pinball' {
            $urls = @($script:PinballVcPackages | Where-Object { $_.ContainsKey('Url') } | ForEach-Object { $_.Url }) + $script:PinballDirectXUrl
            @($urls | Where-Object { -not (Test-KitDownloadUrl -Uri $_) }) -join ', ' | Should BeNullOrEmpty
        }
    }

    It 'maps installer exit codes (0/1638 ok, 3010 restart, else failed)' {
        Get-PinballInstallerResult 0 | Should Be 'Ok'
        Get-PinballInstallerResult 1638 | Should Be 'Ok'
        Get-PinballInstallerResult 3010 | Should Be 'RebootRequired'
        Get-PinballInstallerResult 1603 | Should Be 'Failed'
    }

    # The kit data folder is simulated in TEMP (never ProgramData); the test user is a trusted owner there.
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $kd = @{ KitDataBase = (Join-Path $TestDrive 'KitData'); TrustedOwner = @('S-1-5-32-544', 'S-1-5-18', $me) }
    $work = Join-Path $TestDrive 'KitData\downloads'

    It 'never runs DISM without confirmation and downloads nothing under -WhatIf' {
        Mock -ModuleName 'RetroCabinetKit.Core' Start-Process { throw 'must not start a process' }
        Mock -ModuleName 'RetroCabinetKit.Pinball' Save-KitDownload { throw 'must not download' }
        $rows = @(Invoke-PinballDependencyPlan -Plan $plan -WhatIf @kd)
        ($rows | Where-Object { $_.Id -eq 'NetFx35' }).Result | Should Be 'NeedsUser'
        ($rows | Where-Object { $_.Id -eq 'Windows' }).Result | Should Be 'NeedsUser'
        ($rows | Where-Object { $_.Id -eq 'VC2015-2022-x64' }).Result | Should Be 'Skipped'
        Assert-MockCalled -ModuleName 'RetroCabinetKit.Core' Start-Process -Times 0
        Assert-MockCalled -ModuleName 'RetroCabinetKit.Pinball' Save-KitDownload -Times 0
    }

    It 'deletes a download without a valid Microsoft signature (NeedsUser, nothing started)' {
        Mock -ModuleName 'RetroCabinetKit.Pinball' Save-KitDownload { Set-Content -LiteralPath $Destination -Value 'x'; Get-Item -LiteralPath $Destination }
        Mock -ModuleName 'RetroCabinetKit.Core' Start-Process { throw 'must not start an unsigned file' }
        $item = $plan | Where-Object { $_.Id -eq 'VC2015-2022-x64' }
        $row = Invoke-PinballDependencyPlan -Plan @($item) @kd -Approve { throw 'no plan for untrusted files' }
        $row.Result | Should Be 'NeedsUser'
        $row.Message | Should Match 'no valid signature'
        @(Get-ChildItem -LiteralPath $work -Force).Count | Should Be 0 # download and work folder are gone
        Assert-MockCalled -ModuleName 'RetroCabinetKit.Core' Start-Process -Times 0
    }

    It 'does not run an unsigned installer from the build (placeholder file of the test build)' {
        Mock -ModuleName 'RetroCabinetKit.Core' Start-Process { throw 'must not start an unsigned file' }
        $item = $plan | Where-Object { $_.Id -eq 'VC2008-x86' }
        $row = Invoke-PinballDependencyPlan -Plan @($item) @kd -Approve { throw 'no plan for untrusted files' }
        $row.Result | Should Be 'NeedsUser'
        "$root\vPinball\2-Programs\All In One Runtimes\vcredist2008_x86.exe" | Should Exist # the build is never changed
        Assert-MockCalled -ModuleName 'RetroCabinetKit.Core' Start-Process -Times 0
    }

    It 'never takes installers from a network path' {
        $unc = @(Get-PinballDependencyPlan -Root '\\nas\share' -Status $missing)
        @($unc | Where-Object { $_.Source -eq 'Build' }).Count | Should Be 0
        ($unc | Where-Object { $_.Id -eq 'DirectX9' }).Source | Should Be 'Download'
        Mock -ModuleName 'RetroCabinetKit.Core' Start-Process { throw 'must not start' }
        $item = [pscustomobject]@{ Id = 'X'; Name = 'X'; Source = 'Build'; FilePath = '\\nas\share\vPinball\x.exe'; Arguments = ''; Url = $null; Publisher = 'Microsoft Corporation' }
        (Invoke-PinballDependencyPlan -Plan @($item) @kd -Approve { $true }).Result | Should Be 'NeedsUser'
    }

    Context 'a trusted file in the build (a copy of a signed Windows file stands in for an installer)' {
        $aio = "$root\vPinball\2-Programs\All In One Runtimes"
        Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\notepad.exe') -Destination "$aio\signed.exe"
        $item = [pscustomobject]@{ Id = 'T'; Name = 'Test'; Source = 'Build'; FilePath = "$aio\signed.exe"; Arguments = '/x'; Url = $null; Publisher = 'Microsoft Windows' }

        It 'runs nothing when the plan is declined, and shows the copy with SHA256 first' {
            Mock -ModuleName 'RetroCabinetKit.Core' Start-Process { throw 'must not start' }
            $script:shown = $null
            $row = Invoke-PinballDependencyPlan -Plan @($item) @kd -Approve { param($t) $script:shown = $t; $false }
            $row.Result | Should Be 'NeedsUser'
            $script:shown | Should Match ([regex]::Escape($work))
            $script:shown | Should Match (Get-FileHash -LiteralPath $item.FilePath -Algorithm SHA256).Hash
            $script:shown | Should Match 'Valid'
            Assert-MockCalled -ModuleName 'RetroCabinetKit.Core' Start-Process -Times 0
        }

        It 'runs the copy in the work folder after confirmation, never the file in the build' {
            Mock -ModuleName 'RetroCabinetKit.Core' Start-Process { [pscustomobject]@{ ExitCode = 3010 } }
            $row = Invoke-PinballDependencyPlan -Plan @($item) @kd -Approve { $true }
            $row.Result | Should Be 'RebootRequired'
            Assert-MockCalled -ModuleName 'RetroCabinetKit.Core' Start-Process -Times 1 -ParameterFilter {
                $FilePath -like "$work\*\signed.exe" -and $WorkingDirectory -eq (Split-Path -Parent $FilePath) -and $ArgumentList -eq '/x'
            }
            @(Get-ChildItem -LiteralPath $work -Force).Count | Should Be 0
        }

        It 'refuses the same file under an expected publisher it does not have' {
            Mock -ModuleName 'RetroCabinetKit.Core' Start-Process { throw 'must not start' }
            $other = $item.PSObject.Copy(); $other.Publisher = 'Microsoft Corporation'
            (Invoke-PinballDependencyPlan -Plan @($other) @kd -Approve { $true }).Result | Should Be 'NeedsUser'
        }

        It 'refuses DirectX when any DLL in its folder is not signed (DLL planting)' {
            $dx = "$root\vPinball\Installer\directx9"
            Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\notepad.exe') -Destination "$dx\DXSETUP.exe" -Force
            [IO.File]::WriteAllBytes("$dx\dsetup.dll", [byte[]](77, 90, 0, 0))
            Mock -ModuleName 'RetroCabinetKit.Core' Start-Process { throw 'must not start' }
            $dxItem = [pscustomobject]@{ Id = 'DirectX9'; Name = 'DirectX'; Source = 'Build'; FilePath = "$dx\DXSETUP.exe"; Arguments = '/silent'; Url = $null; Publisher = 'Microsoft Windows' }
            $row = Invoke-PinballDependencyPlan -Plan @($dxItem) @kd -Approve { throw 'no plan for untrusted files' }
            $row.Result | Should Be 'NeedsUser'
            $row.Message | Should Match 'dsetup\.dll'
            Remove-Item -LiteralPath "$dx\dsetup.dll"
        }
    }

    It 'runs DISM (below System32) in place' {
        Mock -ModuleName 'RetroCabinetKit.Core' Start-Process { [pscustomobject]@{ ExitCode = 0 } }
        $dism = $plan | Where-Object { $_.Id -eq 'NetFx35' }
        (Invoke-PinballDependencyPlan -Plan @($dism) -AllowDism @kd -Approve { $true }).Result | Should Be 'Ok'
        Assert-MockCalled -ModuleName 'RetroCabinetKit.Core' Start-Process -Times 1 -ParameterFilter { $FilePath -eq (Join-Path $env:SystemRoot 'System32\dism.exe') }
    }
}
