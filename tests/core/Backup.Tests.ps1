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
        $actions = @(Restore-KitBackup -Path $zip -WhatIf -AllowedRoots $dest -AllowedRegistryRoots $testKey -PathFilter { param($p) $p.Replace($src, $dest) })
        @($actions | Where-Object { $_.Action -ne 'WhatIf' }).Count | Should Be 0
        $dest | Should Not Exist
    }

    It 'restores files through the path filter with identical hashes' {
        $dest = Join-Path $TestDrive 'restore'
        $actions = @(Restore-KitBackup -Path $zip -SkipRegistry -AllowedRoots $dest -PathFilter { param($p) $p.Replace($src, $dest) })
        $actions.Count | Should Be 2
        (Get-FileHash -LiteralPath (Join-Path $dest 'Table (1990) [v2].vpx')).Hash | Should Be (Get-FileHash -LiteralPath $bracket).Hash
        (Get-FileHash -LiteralPath (Join-Path $dest 'dir with space\a b ä.txt')).Hash | Should Be (Get-FileHash -LiteralPath $spaced).Hash
    }

    It 'refuses targets outside the allowed roots (also via ..) before writing anything' {
        $dest = Join-Path $TestDrive 'restore-allowed'
        { Restore-KitBackup -Path $zip -SkipRegistry -AllowedRoots $dest -PathFilter { param($p) $p } } | Should Throw
        { Restore-KitBackup -Path $zip -SkipRegistry -AllowedRoots $dest -PathFilter { param($p) $p.Replace($src, "$dest\..\escape") } } | Should Throw
        { Restore-KitBackup -Path $zip -SkipRegistry -AllowedRoots "$dest-x" -PathFilter { param($p) $p.Replace($src, $dest) } } | Should Throw
        $dest | Should Not Exist
        Join-Path $TestDrive 'escape' | Should Not Exist
    }

    It 'restores the registry through the registry filter (test key only)' {
        Remove-ItemProperty -LiteralPath "$testKey\Backup" -Name 'Path'
        $null = Restore-KitBackup -Path $zip -AllowedRoots @() -AllowedRegistryRoots $testKey -PathFilter { param($p) $null } -RegistryFilter { param($t) $t.Replace('C:\\Games\\Old', 'D:\\Games\\New') }
        Get-KitRegistryValue -Path "$testKey\Backup" -Name 'Path' | Should BeExactly 'D:\Games\New\vPinball'
    }

    It 'refuses the registry part without allowed roots or with a key outside them' {
        { Restore-KitBackup -Path $zip -AllowedRoots @() -PathFilter { param($p) $null } } | Should Throw
        { Restore-KitBackup -Path $zip -AllowedRoots @() -AllowedRegistryRoots "$testKey\Other" -PathFilter { param($p) $null } } | Should Throw
    }

    It 'refuses a crafted backup that deletes a key, even as a dry run' {
        $evil = Join-Path $TestDrive 'evil.zip'
        $z = [IO.Compression.ZipFile]::Open($evil, [IO.Compression.ZipArchiveMode]::Create)
        try {
            $w = New-Object IO.StreamWriter ($z.CreateEntry('manifest.json').Open())
            try { $w.Write('{"Format":1,"Files":[],"Registry":[{"Key":"x","Entry":"registry/001.reg","Sha256":""}],"Skipped":[]}') } finally { $w.Dispose() }
            $w = New-Object IO.StreamWriter ($z.CreateEntry('registry/001.reg').Open(), [Text.Encoding]::Unicode)
            try { $w.Write("Windows Registry Editor Version 5.00`r`n`r`n[-HKEY_CURRENT_USER\Software\retro-cabinet-kit-test]`r`n") } finally { $w.Dispose() }
        } finally { $z.Dispose() }
        { Restore-KitBackup -Path $evil -AllowedRoots @() -AllowedRegistryRoots $testKey -WhatIf } | Should Throw
        { Restore-KitBackup -Path $evil -AllowedRoots @() -AllowedRegistryRoots $testKey } | Should Throw
        Test-Path -LiteralPath "$testKey\Backup" | Should Be $true
    }
}

Describe 'Path helpers' {
    It 'Test-KitPathUnder normalizes and compares on folder boundaries' {
        Test-KitPathUnder -Path 'C:\Games\vPinball\a.ini' -Root 'C:\Games\vPinball' | Should Be $true
        Test-KitPathUnder -Path 'c:\games\VPINBALL\sub\..\a.ini' -Root 'C:\Games\vPinball\' | Should Be $true
        Test-KitPathUnder -Path 'C:\Games\vPinball2\a.ini' -Root 'C:\Games\vPinball' | Should Be $false
        Test-KitPathUnder -Path 'C:\Games\vPinball\..\Windows\a.dll' -Root 'C:\Games\vPinball' | Should Be $false
        Test-KitPathUnder -Path 'D:\x' -Root 'D:' | Should Be $true
        Test-KitPathUnder -Path 'C:\x' -Root @() | Should Be $false
    }

    It 'Get-KitFileTree lists hidden files and does not follow junctions' {
        $root = Join-Path $TestDrive 'tree'
        $outside = Join-Path $TestDrive 'outside'
        New-Item -ItemType Directory -Path "$root\a\b", $outside -Force | Out-Null
        [IO.File]::WriteAllText("$root\a\b\x.ini", 'x')
        [IO.File]::WriteAllText("$root\top.lnk", 'x')
        (Get-Item -LiteralPath "$root\top.lnk").Attributes = 'Hidden'
        [IO.File]::WriteAllText("$outside\secret.ini", 'x')
        $null = cmd /c mklink /J "$root\a\link" "$outside"
        try {
            (@(Get-KitFileTree -Path $root | ForEach-Object { $_.FullName.Substring($root.Length + 1) } | Sort-Object)) -join ',' | Should Be 'a\b\x.ini,top.lnk'
            @(Get-KitFileTree -Path $root -Filter '*.lnk').Count | Should Be 1
        } finally { cmd /c rmdir "$root\a\link" }
    }
}
