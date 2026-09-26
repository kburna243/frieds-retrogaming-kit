$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1') -Force
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1') -Force

$newPinballBuild = Join-Path $kitRoot 'tests\pinball\New-PinballTestBuild.ps1'
$newRetroBat = Join-Path $kitRoot 'tests\lightgun\New-LightgunTestRetroBat.ps1'
$newTeknoParrot = Join-Path $kitRoot 'tests\lightgun\New-LightgunTestTeknoParrot.ps1'
$newGunmote = Join-Path $kitRoot 'tests\lightgun\New-LightgunTestGunmote.ps1'

Describe 'CabinetProfile: path tokenization' {
    $roots = @{
        '{PinballRoot}'  = 'D:\vPinball'
        '{RetroBatRoot}' = 'E:\Emulation\RetroBat'
        '{GunmoteDir}'   = 'C:\Program Files\Gunmote'
    }

    It 'replaces root with token case-insensitively and uses forward slashes' {
        $p1 = 'd:\vpinball\PinUPSystem\POPMedia\Visual Pinball X'
        $t1 = ConvertTo-KitProfilePath -Path $p1 -Roots $roots
        $t1 | Should BeExactly '{PinballRoot}/PinUPSystem/POPMedia/Visual Pinball X'

        $p2 = 'E:\Emulation\RetroBat\roms\mame\alien3.zip'
        $t2 = ConvertTo-KitProfilePath -Path $p2 -Roots $roots
        $t2 | Should BeExactly '{RetroBatRoot}/roms/mame/alien3.zip'
    }

    It 'resolves token back to target root' {
        $targetRoots = @{
            '{PinballRoot}'  = 'X:\NewCabinet\VPin'
            '{RetroBatRoot}' = 'Y:\RetroBat'
        }
        $r1 = ConvertFrom-KitProfilePath -Path '{PinballRoot}/PinUPSystem/POPMedia' -Roots $targetRoots
        $r1 | Should BeExactly (Join-Path 'X:\NewCabinet\VPin' 'PinUPSystem\POPMedia')

        $r2 = ConvertFrom-KitProfilePath -Path '{RetroBatRoot}/roms/mame' -Roots $targetRoots
        $r2 | Should BeExactly (Join-Path 'Y:\RetroBat' 'roms\mame')
    }

    It 'leaves foreign paths untouched' {
        $foreign = 'C:\Program Files (x86)\Steam\steam.exe'
        (ConvertTo-KitProfilePath -Path $foreign -Roots $roots) | Should BeExactly $foreign
    }
}

Describe 'CabinetProfile: path safety & manifest validation' {
    It 'refuses path traversal' {
        { Assert-KitProfilePathSafe -Path '..\..\Windows\System32\cmd.exe' } | Should Throw 'Path traversal refused'
        { Assert-KitProfilePathSafe -Path 'files/../../../evil.exe' } | Should Throw 'Path traversal refused'
    }

    It 'refuses absolute paths' {
        { Assert-KitProfilePathSafe -Path 'C:\Windows\System32' } | Should Throw 'Absolute path refused'
        { Assert-KitProfilePathSafe -Path '/etc/passwd' } | Should Throw 'Absolute path refused'
        { Assert-KitProfilePathSafe -Path '\\nas\share\file' } | Should Throw 'Absolute path refused'
    }

    It 'refuses invalid manifest' {
        { Assert-KitProfileManifest -Manifest @{ Format = 99; Suite = 'Pinball'; Roots = @{} } } | Should Throw 'is newer than supported format'
        { Assert-KitProfileManifest -Manifest @{ Format = 1; Suite = 'Unknown'; Roots = @{} } } | Should Throw 'unknown Suite'
        { Assert-KitProfileManifest -Manifest @{ Format = 1; Suite = 'Pinball' } } | Should Throw 'missing Roots'
    }

    It 'refuses manifests containing absolute Windows paths or SIDs' {
        $bad1 = @{ Format = 1; Suite = 'Pinball'; Roots = @{ '{PinballRoot}' = 'present' }; BadPath = 'D:\SecretFolder' }
        { Assert-KitProfileManifest -Manifest $bad1 } | Should Throw 'contains absolute paths'

        $bad2 = @{ Format = 1; Suite = 'Pinball'; Roots = @{ '{PinballRoot}' = 'present' }; Sid = 'S-1-5-21-123456789-123456789-123456789-1001' }
        { Assert-KitProfileManifest -Manifest $bad2 } | Should Throw 'contains user SIDs'
    }
}

Describe 'CabinetProfile: Pinball export on A and import on B' {
    Set-KitCulture -Culture 'en-US'
    $cabA = Join-Path $TestDrive 'cabA'
    $cabB = Join-Path $TestDrive 'cabB'
    $pinballA = Join-Path $cabA 'Pinball'
    $pinballB = Join-Path $cabB 'Pinball'

    # Build synthetic pinball setup on A
    & $newPinballBuild -Root $pinballA -OldRoot 'D:\OldBuild'

    # Simulate a relocated cabinet A (kit steps 4+5 already ran there): the database points at A's own root,
    # which is what a real profile export meets on a working cabinet.
    $dbA = Join-Path $pinballA 'vPinball\PinUPSystem\PUPDatabase.db'
    $connA = Open-KitSqlite -Path $dbA
    try {
        foreach ($col in @('DirGames', 'DirMedia', 'DirRoms', 'LaunchScript')) {
            $null = Invoke-KitSqlNonQuery -Connection $connA -Sql "UPDATE Emulators SET [$col] = REPLACE([$col], @old, @new)" -Parameters @{ old = 'D:\OldBuild'; new = $pinballA }
        }
    } finally {
        Close-KitSqlite $connA
    }

    # Registry test keys
    $regTestA = 'HKCU:\Software\retro-cabinet-kit-test-profile-a'
    $regTestB = 'HKCU:\Software\retro-cabinet-kit-test-profile-b'

    Set-KitRegistryValue -Path $regTestA -Name 'VPinballPath' -Value "$pinballA\vPinball\VisualPinball"
    Set-KitRegistryValue -Path $regTestA -Name 'PlayerMode' -Value 1 -Type 'DWord'

    $zipDest = Join-Path $TestDrive 'profiles'

    AfterAll {
        if (Test-Path -LiteralPath 'HKCU:\Software\retro-cabinet-kit-test-profile-a') {
            Remove-Item -LiteralPath 'HKCU:\Software\retro-cabinet-kit-test-profile-a' -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath 'HKCU:\Software\retro-cabinet-kit-test-profile-b') {
            Remove-Item -LiteralPath 'HKCU:\Software\retro-cabinet-kit-test-profile-b' -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'exports Pinball profile from A cleanly (read-only, depersonalized)' {
        $hashBefore = (Get-FileHash -LiteralPath (Join-Path $pinballA 'vPinball\PinUPSystem\PUPDatabase.db') -Algorithm SHA256).Hash

        $export = Export-KitCabinetProfile -Suite 'Pinball' -Destination $zipDest `
            -RootMap @{ '{PinballRoot}' = $pinballA } -RegistryRoots @($regTestA)

        $export.Suite | Should BeExactly 'Pinball'
        $export.Path | Should Match '\.zip$'
        Test-Path -LiteralPath $export.Path | Should Be $true

        # Verify read-only: hash of DB on A is untouched
        $hashAfter = (Get-FileHash -LiteralPath (Join-Path $pinballA 'vPinball\PinUPSystem\PUPDatabase.db') -Algorithm SHA256).Hash
        $hashAfter | Should BeExactly $hashBefore

        # Inspect zip contents
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($export.Path)
        try {
            $manifestEntry = $zip.GetEntry('profile.json')
            $manifestEntry | Should Not BeNullOrEmpty

            $sr = New-Object IO.StreamReader ($manifestEntry.Open(), [Text.Encoding]::UTF8)
            $manifest = $sr.ReadToEnd() | ConvertFrom-Json
            $sr.Dispose()

            $manifest.Format | Should Be 1
            $manifest.Suite | Should Be 'Pinball'
            $manifest.Roots.'{PinballRoot}' | Should Be 'present'

            # Ensure SQLite settings entry exists
            $sqliteEntry = $zip.GetEntry('files/pinball/sqlite-settings.json')
            $sqliteEntry | Should Not BeNullOrEmpty

            # Ensure registry export exists
            $regEntry = $zip.GetEntry('registry/001.reg')
            $regEntry | Should Not BeNullOrEmpty
        } finally {
            $zip.Dispose()
        }
    }

    It 'imports into B with -WhatIf and makes no changes' {
        # Set up destination B
        & $newPinballBuild -Root $pinballB -OldRoot 'D:\OldBuild'
        $dbB = Join-Path $pinballB 'vPinball\PinUPSystem\PUPDatabase.db'
        $hashBBefore = (Get-FileHash -LiteralPath $dbB -Algorithm SHA256).Hash

        $profileZip = @(Get-ChildItem -LiteralPath $zipDest -Filter 'cabinet-profile-pinball_*.zip')[0].FullName

        $plan = Import-KitCabinetProfile -Path $profileZip -RootMap @{ '{PinballRoot}' = $pinballB } `
            -RegistryRoots @($regTestB) -WhatIf

        $plan.Count | Should BeGreaterThan 0
        ($plan | Where-Object { $_.Status -eq 'WhatIf' }).Count | Should BeGreaterThan 0

        # Verify nothing was changed on B
        $hashBAfter = (Get-FileHash -LiteralPath $dbB -Algorithm SHA256).Hash
        $hashBAfter | Should BeExactly $hashBBefore
    }

    It 'imports into B for real, rewrites emulators, and creates backup' {
        $dbB = Join-Path $pinballB 'vPinball\PinUPSystem\PUPDatabase.db'
        $profileZip = @(Get-ChildItem -LiteralPath $zipDest -Filter 'cabinet-profile-pinball_*.zip')[0].FullName

        $results = Import-KitCabinetProfile -Path $profileZip -RootMap @{ '{PinballRoot}' = $pinballB } `
            -RegistryRoots @($regTestB)

        ($results | Where-Object { $_.Status -eq 'Done' }).Count | Should BeGreaterThan 0

        # Verify emulators in B's database point to B
        $conn = Open-KitSqlite -Path $dbB -ReadOnly
        try {
            $emu1 = @(Invoke-KitSqlQuery -Connection $conn -Sql "SELECT DirGames FROM Emulators WHERE EmuName = 'Visual Pinball X'")[0]
            $emu1.DirGames | Should Match ([regex]::Escape($pinballB))
        } finally {
            Close-KitSqlite $conn
        }

        # Verify backup exists
        $backups = @(Get-ChildItem -LiteralPath (Join-Path $pinballB 'vPinball\PinUPSystem') -Filter '*.zip')
        $backups.Count | Should BeGreaterThan 0
    }

    It 'second pinball import is idempotent' {
        $profileZip = @(Get-ChildItem -LiteralPath $zipDest -Filter 'cabinet-profile-pinball_*.zip')[0].FullName

        $results = Import-KitCabinetProfile -Path $profileZip -RootMap @{ '{PinballRoot}' = $pinballB } `
            -RegistryRoots @($regTestB)

        ($results | Where-Object { $_.Status -eq 'Done' }).Count | Should Be 0
        ($results | Where-Object { $_.Status -eq 'Skipped' }).Count | Should BeGreaterThan 0
    }
}

Describe 'CabinetProfile: Lightgun export on A and import on B' {
    Set-KitCulture -Culture 'en-US'
    $cabA = Join-Path $TestDrive 'lgCabA'
    $cabB = Join-Path $TestDrive 'lgCabB'

    $rbA = Join-Path $cabA 'RetroBat'
    $gmA = Join-Path $cabA 'Gunmote'
    $rbB = Join-Path $cabB 'RetroBat'
    $gmB = Join-Path $cabB 'Gunmote'

    & $newRetroBat -Root $rbA
    & $newTeknoParrot -Root $rbA
    & $newGunmote -Gunmote $gmA

    # Add RCK layout to A's Gunmote
    $rckLayout = @'
{
  "Title": "RCK Pad 4:3",
  "Keymap": "rck_pad43.json"
}
'@
    $kmJsonA = Join-Path $gmA 'Keymaps\Keymaps.json'
    $kmA = Get-Content -LiteralPath $kmJsonA -Raw | ConvertFrom-Json
    $kmA.LayoutChooser += @{ Title = 'RCK Pad 4:3'; Keymap = 'rck_pad43.json' }
    [IO.File]::WriteAllText($kmJsonA, (ConvertTo-Json $kmA -Depth 5), [Text.Encoding]::UTF8)
    [IO.File]::WriteAllText((Join-Path $gmA 'Keymaps\rck_pad43.json'), '{"pointer": "stick"}', [Text.Encoding]::UTF8)

    $zipDest = Join-Path $TestDrive 'lgProfiles'

    It 'exports Lightgun profile from A' {
        $export = Export-KitCabinetProfile -Suite 'Lightgun' -Destination $zipDest `
            -RetroBatRoot $rbA -GunmoteDir $gmA

        $export.Suite | Should BeExactly 'Lightgun'
        Test-Path -LiteralPath $export.Path | Should Be $true

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($export.Path)
        try {
            $manifestEntry = $zip.GetEntry('profile.json')
            $manifestEntry | Should Not BeNullOrEmpty

            $esEntry = $zip.GetEntry('files/lightgun/es_settings.json')
            $esEntry | Should Not BeNullOrEmpty

            $gmEntry = $zip.GetEntry('files/lightgun/gunmote/rck_pad43.json')
            $gmEntry | Should Not BeNullOrEmpty
        } finally {
            $zip.Dispose()
        }
    }

    It 'imports into B and merges es_settings and layouts' {
        & $newRetroBat -Root $rbB
        & $newGunmote -Gunmote $gmB

        $profileZip = @(Get-ChildItem -LiteralPath $zipDest -Filter 'cabinet-profile-lightgun_*.zip')[0].FullName

        $results = Import-KitCabinetProfile -Path $profileZip `
            -RetroBatRoot $rbB -GunmoteDir $gmB

        ($results | Where-Object { $_.Status -eq 'Done' }).Count | Should BeGreaterThan 0

        # Verify layout copied to B
        Test-Path -LiteralPath (Join-Path $gmB 'Keymaps\rck_pad43.json') | Should Be $true

        # Verify Keymaps.json on B updated
        $kmB = Get-Content -LiteralPath (Join-Path $gmB 'Keymaps\Keymaps.json') -Raw | ConvertFrom-Json
        @($kmB.LayoutChooser | Where-Object { $_.Keymap -eq 'rck_pad43.json' }).Count | Should Be 1
    }

    It 'second import is idempotent (all skipped)' {
        $profileZip = @(Get-ChildItem -LiteralPath $zipDest -Filter 'cabinet-profile-lightgun_*.zip')[0].FullName

        $results = Import-KitCabinetProfile -Path $profileZip `
            -RetroBatRoot $rbB -GunmoteDir $gmB

        ($results | Where-Object { $_.Status -eq 'Done' }).Count | Should Be 0
        ($results | Where-Object { $_.Status -eq 'Skipped' }).Count | Should BeGreaterThan 0
    }
}
