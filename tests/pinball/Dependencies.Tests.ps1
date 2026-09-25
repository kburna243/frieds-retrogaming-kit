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

    It 'never runs DISM without confirmation and downloads nothing under -WhatIf' {
        Mock -ModuleName 'RetroCabinetKit.Pinball' Start-Process { throw 'must not start a process' }
        Mock -ModuleName 'RetroCabinetKit.Pinball' Save-KitDownload { throw 'must not download' }
        $rows = @(Invoke-PinballDependencyPlan -Plan $plan -WhatIf)
        ($rows | Where-Object { $_.Id -eq 'NetFx35' }).Result | Should Be 'NeedsUser'
        ($rows | Where-Object { $_.Id -eq 'Windows' }).Result | Should Be 'NeedsUser'
        ($rows | Where-Object { $_.Id -eq 'VC2015-2022-x64' }).Result | Should Be 'Skipped'
        Assert-MockCalled -ModuleName 'RetroCabinetKit.Pinball' Start-Process -Times 0
        Assert-MockCalled -ModuleName 'RetroCabinetKit.Pinball' Save-KitDownload -Times 0
    }

    It 'deletes a download without a valid Microsoft signature (NeedsUser, nothing started)' {
        $dl = Join-Path $TestDrive 'dl'
        New-Item -ItemType Directory -Path $dl -Force | Out-Null
        Mock -ModuleName 'RetroCabinetKit.Pinball' Save-KitDownload { Set-Content -LiteralPath $Destination -Value 'x'; Get-Item -LiteralPath $Destination }
        Mock -ModuleName 'RetroCabinetKit.Pinball' Start-Process { throw 'must not start an unsigned file' }
        $item = $plan | Where-Object { $_.Id -eq 'VC2015-2022-x64' }
        $row = Invoke-PinballDependencyPlan -Plan @($item) -DownloadDir $dl -Approve { throw 'no plan for untrusted files' }
        $row.Result | Should Be 'NeedsUser'
        $row.Message | Should Match 'no valid signature'
        @(Get-ChildItem -LiteralPath $dl).Count | Should Be 0
        Assert-MockCalled -ModuleName 'RetroCabinetKit.Pinball' Start-Process -Times 0
    }

    It 'does not run an unsigned installer from the build (placeholder file of the test build)' {
        Mock -ModuleName 'RetroCabinetKit.Pinball' Start-Process { throw 'must not start an unsigned file' }
        $item = $plan | Where-Object { $_.Id -eq 'VC2008-x86' }
        $row = Invoke-PinballDependencyPlan -Plan @($item) -Approve { throw 'no plan for untrusted files' }
        $row.Result | Should Be 'NeedsUser'
        "$root\vPinball\2-Programs\All In One Runtimes\vcredist2008_x86.exe" | Should Exist # the build is never changed
        Assert-MockCalled -ModuleName 'RetroCabinetKit.Pinball' Start-Process -Times 0
    }

    It 'never takes installers from a network path' {
        $unc = @(Get-PinballDependencyPlan -Root '\\nas\share' -Status $missing)
        @($unc | Where-Object { $_.Source -eq 'Build' }).Count | Should Be 0
        ($unc | Where-Object { $_.Id -eq 'DirectX9' }).Source | Should Be 'Download'
        Mock -ModuleName 'RetroCabinetKit.Pinball' Start-Process { throw 'must not start' }
        $item = [pscustomobject]@{ Id = 'X'; Name = 'X'; Source = 'Build'; FilePath = '\\nas\share\vPinball\x.exe'; Arguments = ''; Url = $null; Publisher = 'Microsoft Corporation' }
        (Invoke-PinballDependencyPlan -Plan @($item) -Approve { $true }).Result | Should Be 'NeedsUser'
    }

    Context 'a trusted file (a Windows system file stands in for an installer)' {
        $notepad = Join-Path $env:SystemRoot 'System32\notepad.exe'
        $item = [pscustomobject]@{ Id = 'T'; Name = 'Test'; Source = 'Build'; FilePath = $notepad; Arguments = '/x'; Url = $null; Publisher = 'Microsoft Windows' }

        It 'runs nothing when the plan is declined, and shows file and SHA256 first' {
            Mock -ModuleName 'RetroCabinetKit.Pinball' Start-Process { throw 'must not start' }
            $script:shown = $null
            $row = Invoke-PinballDependencyPlan -Plan @($item) -Approve { param($t) $script:shown = $t; $false }
            $row.Result | Should Be 'NeedsUser'
            $script:shown | Should Match ([regex]::Escape($notepad))
            $script:shown | Should Match (Get-FileHash -LiteralPath $notepad -Algorithm SHA256).Hash
            $script:shown | Should Match 'Valid'
            Assert-MockCalled -ModuleName 'RetroCabinetKit.Pinball' Start-Process -Times 0
        }

        It 'runs it after confirmation' {
            Mock -ModuleName 'RetroCabinetKit.Pinball' Start-Process { [pscustomobject]@{ ExitCode = 3010 } }
            $row = Invoke-PinballDependencyPlan -Plan @($item) -Approve { $true }
            $row.Result | Should Be 'RebootRequired'
            Assert-MockCalled -ModuleName 'RetroCabinetKit.Pinball' Start-Process -Times 1 -ParameterFilter { $FilePath -eq $notepad }
        }

        It 'refuses the same file under an expected publisher it does not have' {
            Mock -ModuleName 'RetroCabinetKit.Pinball' Start-Process { throw 'must not start' }
            $other = $item.PSObject.Copy(); $other.Publisher = 'Microsoft Corporation'
            (Invoke-PinballDependencyPlan -Plan @($other) -Approve { $true }).Result | Should Be 'NeedsUser'
        }
    }
}
