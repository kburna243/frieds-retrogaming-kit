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

    It 'deletes a download without a valid Microsoft signature' {
        $dl = Join-Path $TestDrive 'dl'
        Mock -ModuleName 'RetroCabinetKit.Pinball' Save-KitDownload { Set-Content -LiteralPath $Destination -Value 'x'; Get-Item -LiteralPath $Destination }
        Mock -ModuleName 'RetroCabinetKit.Pinball' Start-Process { throw 'must not start an unsigned file' }
        $item = $plan | Where-Object { $_.Id -eq 'VC2015-2022-x64' }
        $row = Invoke-PinballDependencyPlan -Plan @($item) -DownloadDir $dl -Confirm:$false
        $row.Result | Should Be 'Failed'
        @(Get-ChildItem -LiteralPath $dl).Count | Should Be 0
    }
}
