$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force

$testKey = 'HKCU:\Software\retro-cabinet-kit-test'

Describe 'Backup' {
    AfterAll {
        if (Test-Path -LiteralPath $testKey) { Remove-Item -LiteralPath $testKey -Recurse -Force }
    }

    if (Test-Path -LiteralPath $testKey) { Remove-Item -LiteralPath $testKey -Recurse -Force }
    Set-KitRegistryValue -Path "$testKey\Backup" -Name 'Path' -Value 'C:\Games\Old\vPinball'

    $src = Join-Path $TestDrive 'src'
    New-Item -ItemType Directory -Path "$src\dir with space" -Force | Out-Null
    $bracket = Join-Path $src 'Table (1990) [v2].vpx'
    $spaced  = Join-Path $src 'dir with space\a b ä.txt'
    $locked  = Join-Path $src 'locked.db'
    [IO.File]::WriteAllText($bracket, 'binary-ish content')
    [IO.File]::WriteAllText($spaced, 'Grüße', (New-Object Text.UTF8Encoding $true))
    [IO.File]::WriteAllText($locked, 'locked')
    $zip = Join-Path $TestDrive 'out\backup.zip'

    $lock = [IO.File]::Open($locked, 'Open', 'ReadWrite', 'None')
    try {
        $result = New-KitBackup -Files $src -Registry "$testKey\Backup" -Destination $zip
    } finally { $lock.Dispose() }
    $manifest = Get-KitBackupManifest -Path $zip

    It 'creates the ZIP and reports the locked file instead of aborting' {
        $zip | Should Exist
        $result.Files | Should Be 2
        $result.Skipped -join ',' | Should Be $locked
        @($manifest.Skipped)[0].Path | Should Be $locked
    }

    It 'stores exact paths and matching SHA256 hashes in the manifest' {
        foreach ($f in @($bracket, $spaced)) {
            $entry = @($manifest.Files | Where-Object { $_.Path -ceq $f })
            $entry.Count | Should Be 1
            $entry[0].Sha256 | Should Be (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash
        }
    }

    It 'includes the registry export' {
        @($manifest.Registry).Count | Should Be 1
        @($manifest.Registry)[0].Key | Should Be "$testKey\Backup"
    }

    It 'refuses to overwrite an existing backup' {
        { New-KitBackup -Files $bracket -Destination $zip } | Should Throw
    }

    It 'changes nothing under -WhatIf' {
        $dest = Join-Path $TestDrive 'restore-whatif'
        $actions = @(Restore-KitBackup -Path $zip -WhatIf -PathFilter { param($p) $p.Replace($src, $dest) })
        @($actions | Where-Object { $_.Action -ne 'WhatIf' }).Count | Should Be 0
        $dest | Should Not Exist
    }

    It 'restores files through the path filter with identical hashes' {
        $dest = Join-Path $TestDrive 'restore'
        $actions = @(Restore-KitBackup -Path $zip -SkipRegistry -PathFilter { param($p) $p.Replace($src, $dest) })
        $actions.Count | Should Be 2
        (Get-FileHash -LiteralPath (Join-Path $dest 'Table (1990) [v2].vpx')).Hash | Should Be (Get-FileHash -LiteralPath $bracket).Hash
        (Get-FileHash -LiteralPath (Join-Path $dest 'dir with space\a b ä.txt')).Hash | Should Be (Get-FileHash -LiteralPath $spaced).Hash
    }

    It 'restores the registry through the registry filter (test key only)' {
        Remove-ItemProperty -LiteralPath "$testKey\Backup" -Name 'Path'
        $null = Restore-KitBackup -Path $zip -PathFilter { param($p) $null } -RegistryFilter { param($t) $t.Replace('C:\\Games\\Old', 'D:\\Games\\New') }
        Get-KitRegistryValue -Path "$testKey\Backup" -Name 'Path' | Should BeExactly 'D:\Games\New\vPinball'
    }
}
