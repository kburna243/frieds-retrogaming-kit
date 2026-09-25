$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1') -Force
$newBuild = Join-Path $PSScriptRoot 'New-PinballTestBuild.ps1'

# The ONLY registry locations these tests touch; created and removed here.
$testKey = 'HKCU:\Software\retro-cabinet-kit-test-pinball'
$reg     = "$testKey\Settings"
$compat  = "$testKey\Layers"

function Get-Hash([string] $Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Get-Value($db, [string] $sql) {
    $c = Open-KitSqlite -Path $db -ReadOnly
    try { @(Invoke-KitSqlQuery -Connection $c -Sql $sql) } finally { Close-KitSqlite $c }
}
function Convert([string] $Old, [string] $New, [string] $Text, [string[]] $Siblings = @(), [switch] $Escaped) {
    Convert-PinballPath -Relocator (New-PinballRelocator -OldRoot $Old -NewRoot $New -Siblings $Siblings -RegFileEscaping:$Escaped) -Text $Text
}

Describe 'Convert-PinballPath rules' {
    Set-KitCulture -Culture 'en-US'

    It 'replaces only the root in front of vPinball and keeps the rest (case-insensitive)' {
        $r = Convert 'D:\Old Build' 'E:\Games' 'd:\OLD BUILD\vpinball\pinupsystem\POPMedia'
        $r.Text | Should BeExactly 'E:\Games\vpinball\pinupsystem\POPMedia'
        $r.Count | Should Be 1
    }

    It 'leaves foreign paths and look-alike folders alone' {
        $text = 'C:\Program Files (x86)\Steam|D:\Old Build\vPinballX\a|D:\Old Build\Other\b|XD:\Old Build\vPinball\c|D:\Old Builds\vPinball\d'
        $r = Convert 'D:\Old Build' 'E:\Games' $text
        $r.Count | Should Be 0
        $r.Text | Should BeExactly $text
    }

    It 'handles a build directly on a drive without touching other folders of that drive' {
        $r = Convert 'C:\' 'E:\Games' 'C:\vPinball\VisualPinball;C:\Program Files (x86)\Steam;C:\vPinballFoo;"C:\vPinball"'
        $r.Text | Should BeExactly 'E:\Games\vPinball\VisualPinball;C:\Program Files (x86)\Steam;C:\vPinballFoo;"E:\Games\vPinball"'
        $r.Count | Should Be 2
    }

    It 'rewrites sibling folders only when they are known' {
        (Convert 'D:\Old' 'E:\New' 'D:\Old\DOFLinx\DOFLinx.exe' -Siblings 'DOFLinx').Text | Should BeExactly 'E:\New\DOFLinx\DOFLinx.exe'
        (Convert 'D:\Old' 'E:\New' 'D:\Old\DOFLinx\DOFLinx.exe').Count | Should Be 0
    }

    It 'does not replace twice when the new root contains the old one' {
        $once = Convert 'D:\Pin' 'D:\Pin\Cab' 'D:\Pin\vPinball\a'
        $once.Text | Should BeExactly 'D:\Pin\Cab\vPinball\a'
        (Convert 'D:\Pin' 'D:\Pin\Cab' $once.Text).Count | Should Be 0
        $deep = Convert 'D:\Pin' 'D:\Pin\vPinball' 'D:\Pin\vPinball\a'
        $deep.Text | Should BeExactly 'D:\Pin\vPinball\vPinball\a'
        (Convert 'D:\Pin' 'D:\Pin\vPinball' $deep.Text).Count | Should Be 0
    }

    It 'changes nothing when the root did not change' {
        (Convert 'D:\Pin' 'd:\pin\' 'D:\Pin\vPinball\a').Count | Should Be 0
    }

    It 'keeps apostrophes and forward-slash spellings intact' {
        (Convert 'D:\Old' 'E:\New' "D:\Old\vPinball\Pinball PC\Demon's Tilt").Text | Should BeExactly "E:\New\vPinball\Pinball PC\Demon's Tilt"
        (Convert 'D:\Old' 'E:\New Dir' 'file:///D:/Old/vPinball/x.dll').Text | Should BeExactly 'file:///E:/New Dir/vPinball/x.dll'
    }

    It 'understands the doubled backslashes of .reg files' {
        (Convert 'D:\Old' 'E:\New' '"Dir"="D:\\Old\\vPinball\\Tables"' -Escaped).Text | Should BeExactly '"Dir"="E:\\New\\vPinball\\Tables"'
    }

    It 'rewrites an exported hive to HKCU' {
        $rel = New-PinballRelocator -OldRoot 'D:\Old' -NewRoot 'E:\New'
        $text = "[HKEY_USERS\Mnt\Software\B2S]`r`n`"P`"=`"D:\\Old\\vPinball\\Tables`"`r`n"
        ConvertFrom-PinballHiveExport -Text $text -MountName 'Mnt' -Relocator $rel |
            Should BeExactly "[HKEY_CURRENT_USER\Software\B2S]`r`n`"P`"=`"E:\\New\\vPinball\\Tables`"`r`n"
    }
}

Describe 'Relocation of a synthetic build (move mode)' {
    Set-KitCulture -Culture 'en-US'
    $old  = 'D:\Old Build'
    $root = Join-Path $TestDrive 'Cab'
    & $newBuild -Root $root -OldRoot $old
    $v    = Join-Path $root 'vPinball'
    $db   = Join-Path $v 'PinUPSystem\PUPDatabase.db'
    $opt = @{ OldRoot = $old; NewRoot = $root; Siblings = @('DOFLinx'); RegistryRoots = @($reg); AppCompatRoots = @($compat) }

    BeforeAll {
        if (Test-Path -LiteralPath $testKey) { Remove-Item -LiteralPath $testKey -Recurse -Force }
        Set-KitRegistryValue -Path $reg -Name 'TablesDir' -Value 'D:\Old Build\vPinball\FuturePinball\Tables'
        Set-KitRegistryValue -Path $reg -Name 'Expand' -Value '%SystemRoot%;D:\Old Build\vPinball\x' -Type ExpandString
        Set-KitRegistryValue -Path $reg -Name 'Multi' -Value @('D:\Old Build\vPinball\a', 'C:\Program Files (x86)\Steam') -Type MultiString
        Set-KitRegistryValue -Path "$reg\Rom\deep" -Name 'Path' -Value 'D:\OLD BUILD\VPINBALL\VisualPinball\VPinMAME'
        Set-KitRegistryValue -Path $reg -Name 'Steam' -Value 'C:\Program Files (x86)\Steam'
        Set-KitRegistryValue -Path $reg -Name 'Number' -Value 7 -Type DWord
        Set-KitRegistryValue -Path $compat -Name 'D:\Old Build\vPinball\FuturePinball\BAM\FPLoader.exe' -Value '~ DISABLEDXMAXIMIZEDWINDOWEDMODE'
    }
    AfterAll {
        if (Test-Path -LiteralPath $testKey) { Remove-Item -LiteralPath $testKey -Recurse -Force }
    }

    $logs = @{}
    foreach ($l in 'PinUPSystem\log.txt', 'VisualPinball\VPinMAME\PUPLOG.txt', 'PinUPSystem\menu.log') { $logs[$l] = Get-Hash (Join-Path $v $l) }

    It 'finds everything in a dry run and changes nothing' {
        $hash = Get-Hash $db
        $r = Invoke-PinballRelocation @opt -DryRun
        $r.Database.Occurrences | Should Be 10
        $r.Database.Rows | Should Be 6
        $r.Database.Columns.Count | Should Be 6
        @($r.TextFiles).Count | Should Be 5
        @($r.Registry).Count | Should Be 4
        $r.Remaining | Should Be (10 + 5 + 4 + 2)
        Get-Hash $db | Should Be $hash
        Get-KitRegistryValue -Path $reg -Name 'TablesDir' | Should BeExactly 'D:\Old Build\vPinball\FuturePinball\Tables'
    }

    It 'rewrites database, text files, registry and shortcuts' {
        $r = Invoke-PinballRelocation @opt
        $r.Database.Applied | Should Be $true
        $r.Database.Occurrences | Should Be 10
        [IO.Path]::GetFileName($r.Database.Backup) | Should Match '^PUPDatabase\.db\.bak_relocate_\d{8}-\d{6}$'
        $r.ChangedFiles -contains $db | Should Be $true
    }

    It 'changed only build paths in the database' {
        $e = Get-Value $db 'SELECT * FROM Emulators ORDER BY EMUID'
        $e[0].DirGames | Should BeExactly "$root\vPinball\VisualPinball\Tables"
        $e[0].LaunchScript | Should BeExactly "START `"`" `"$root\vPinball\VisualPinball\VPinballX.exe`" -play `"[GAMEFULLNAME]`"`r`ncd /d `"$root\vPinball\VisualPinball`""
        $e[1].DirGames | Should BeExactly 'C:\Program Files (x86)\Steam\steamapps\common'
        $e[1].LaunchScript | Should BeExactly 'START "" "C:\Program Files (x86)\Steam\steam.exe" -applaunch 442120'
        $e[2].DirGames | Should BeExactly "$root\vPinball\Pinball PC\Demon's Tilt"
        $e[3].LaunchScript | Should BeExactly "START `"`" `"$root\DOFLinx\DOFLinx.exe`""
        $e[4].DirGames | Should BeExactly 'D:\Old Build\vPinballBackup\Tables'
        $e[4].DirMedia | Should BeExactly 'D:\Old Build\Other\Media'
        (Get-Value $db 'SELECT GlobalMediaDir FROM GlobalSettings')[0].GlobalMediaDir | Should BeExactly "$root\vPinball\pinupsystem\POPMedia\Default"
        (Get-Value $db 'PRAGMA integrity_check')[0].integrity_check | Should Be 'ok'
    }

    It 'rewrote the text files in their own encoding and left the logs alone' {
        $xml = [IO.File]::ReadAllBytes((Join-Path $v 'VisualPinball\Tables\B2STableSettings.xml'))
        $xml[0] | Should Be 0xFF
        $xml[1] | Should Be 0xFE
        [Text.Encoding]::Unicode.GetString($xml, 2, $xml.Length - 2) | Should BeExactly "<B2S><Path>$root\vPinball\VisualPinball\Tables\</Path></B2S>"
        [IO.File]::ReadAllText((Join-Path $v 'PinUPSystem\Launch\curlaunch.bat')) | Should BeExactly "rem Läuft`r`ncd /d `"$root\vPinball\PinUPSystem`"`r`n"
        [IO.File]::ReadAllText((Join-Path $root 'DOFLinx\DOFLinx.INI'), [Text.Encoding]::Default) | Should BeExactly "PATH_PINUP=$root\vPinball\PinUPSystem\`r`nPATH_FX=C:\Program Files (x86)\Steam\`r`n"
        [IO.File]::ReadAllText((Join-Path $v "Pinball PC\Demon's Tilt.bat"), [Text.Encoding]::Default) | Should Match ([regex]::Escape("cd /d `"$root\vPinball\Pinball PC\Demon's Tilt`""))
        foreach ($l in $logs.Keys) { Get-Hash (Join-Path $v $l) | Should Be $logs[$l] }
    }

    It 'rewrote registry value data and kept the value kinds' {
        Get-KitRegistryValue -Path $reg -Name 'TablesDir' | Should BeExactly "$root\vPinball\FuturePinball\Tables"
        Get-KitRegistryValue -Path $reg -Name 'Expand' | Should BeExactly "%SystemRoot%;$root\vPinball\x"
        (Get-Item -LiteralPath $reg).GetValueKind('Expand') | Should Be 'ExpandString'
        (Get-KitRegistryValue -Path $reg -Name 'Multi') -join '|' | Should BeExactly "$root\vPinball\a|C:\Program Files (x86)\Steam"
        (Get-Item -LiteralPath $reg).GetValueKind('Multi') | Should Be 'MultiString'
        Get-KitRegistryValue -Path "$reg\Rom\deep" -Name 'Path' | Should BeExactly "$root\VPINBALL\VisualPinball\VPinMAME"
        Get-KitRegistryValue -Path $reg -Name 'Steam' | Should BeExactly 'C:\Program Files (x86)\Steam'
        Get-KitRegistryValue -Path $reg -Name 'Number' | Should Be 7
    }

    It 'rewrote the shortcut and reports the dead B2S plugin link as redundant' {
        $s = Get-KitShortcut -Path (Join-Path $v 'Deluxe\Arcade - Shortcut.lnk')
        $s.TargetPath | Should BeExactly "$root\vPinball\Deluxe\Arcade.exe"
        $s.WorkingDirectory | Should BeExactly "$root\vPinball\Deluxe"
        $check = Test-PinballRelocation @opt
        $plugin = @($check.Shortcuts | Where-Object { $_.Path -like '*PinUPPlayerB2SDriver LINK.lnk' })
        $plugin.Count | Should Be 1
        $plugin[0].Link | Should Be 'Redundant'
    }

    It 'verifies clean and reports the AppCompat entry only as legacy' {
        $check = Test-PinballRelocation @opt
        $check.Remaining | Should Be 0
        $check.Clean | Should Be $true
        @($check.Legacy).Count | Should Be 1
        $check.Legacy[0].Name | Should BeExactly 'D:\Old Build\vPinball\FuturePinball\BAM\FPLoader.exe'
        Get-KitRegistryValue -Path $compat -Name 'D:\Old Build\vPinball\FuturePinball\BAM\FPLoader.exe' | Should BeExactly '~ DISABLEDXMAXIMIZEDWINDOWEDMODE'
    }

    It 'changes nothing on a second run (idempotent, no second backup)' {
        $hash = Get-Hash $db
        $r = Invoke-PinballRelocation @opt
        $r.Remaining | Should Be 0
        $r.Database.Applied | Should Be $false
        Get-Hash $db | Should Be $hash
        @(Get-ChildItem -LiteralPath (Split-Path $db) -Filter 'PUPDatabase.db.bak_relocate_*').Count | Should Be 1
    }
}

Describe 'Relocation edge cases on the database' {
    Set-KitCulture -Culture 'en-US'

    It 'moves a build from a drive root without touching Steam on the same drive' {
        $root = Join-Path $TestDrive 'DriveRoot'
        & $newBuild -Root $root -OldRoot 'C:\'
        $db = Get-PinballDatabasePath -Root $root
        Get-PinballOldRoot -DatabasePath $db | Should BeExactly 'C:'
        $rel = New-PinballRelocator -OldRoot 'C:' -NewRoot 'E:\Games' -Siblings 'DOFLinx'
        (Invoke-PinballDatabaseRelocation -Path $db -Relocator $rel).Occurrences | Should Be 10
        $e = Get-Value $db 'SELECT DirGames, LaunchScript FROM Emulators ORDER BY EMUID'
        $e[0].DirGames | Should BeExactly 'E:\Games\vPinball\VisualPinball\Tables'
        $e[1].DirGames | Should BeExactly 'C:\Program Files (x86)\Steam\steamapps\common'
        $e[1].LaunchScript | Should BeExactly 'START "" "C:\Program Files (x86)\Steam\steam.exe" -applaunch 442120'
        (Invoke-PinballDatabaseRelocation -Path $db -Relocator $rel).Occurrences | Should Be 0
    }

    It 'moves into a subfolder of the old root without double replacement' {
        $root = Join-Path $TestDrive 'Nested'
        & $newBuild -Root $root -OldRoot 'D:\Pin'
        $db = Get-PinballDatabasePath -Root $root
        $rel = New-PinballRelocator -OldRoot 'D:\Pin' -NewRoot 'D:\Pin\Cab'
        (Invoke-PinballDatabaseRelocation -Path $db -Relocator $rel).Occurrences | Should Be 9
        (Invoke-PinballDatabaseRelocation -Path $db -Relocator $rel).Occurrences | Should Be 0
        (Get-Value $db 'SELECT DirGames FROM Emulators WHERE EMUID = 1')[0].DirGames | Should BeExactly 'D:\Pin\Cab\vPinball\VisualPinball\Tables'
    }

    It 'counts in a dry run and leaves the file byte-identical' {
        $root = Join-Path $TestDrive 'Dry'
        & $newBuild -Root $root -OldRoot 'D:\Pin'
        $db = Get-PinballDatabasePath -Root $root
        $hash = Get-Hash $db
        (Invoke-PinballDatabaseRelocation -Path $db -Relocator (New-PinballRelocator -OldRoot 'D:\Pin' -NewRoot 'F:\X') -DryRun).Occurrences | Should Be 9
        Get-Hash $db | Should Be $hash
    }
}

Describe 'Rebuild mode (fresh Windows)' {
    Set-KitCulture -Culture 'en-US'
    $old  = 'D:\Old Build'
    $root = Join-Path $TestDrive 'Fresh'
    & $newBuild -Root $root -OldRoot $old
    $reg = "$testKey\Rebuild"

    BeforeAll { if (Test-Path -LiteralPath $testKey) { Remove-Item -LiteralPath $testKey -Recurse -Force } }
    AfterAll { if (Test-Path -LiteralPath $testKey) { Remove-Item -LiteralPath $testKey -Recurse -Force } }

    It 'imports the registry from a kit backup through the path rewrite' {
        Set-KitRegistryValue -Path $reg -Name 'TablesDir' -Value "$old\vPinball\FuturePinball\Tables"
        Set-KitRegistryValue -Path $reg -Name 'Steam' -Value 'C:\Program Files (x86)\Steam'
        $zip = Join-Path $TestDrive 'settings.zip'
        $null = New-KitBackup -Registry $reg -Destination $zip
        Remove-Item -LiteralPath $reg -Recurse -Force

        $r = Invoke-PinballRelocation -OldRoot $old -NewRoot $root -Mode Rebuild -RegistryBackup $zip -RegistryRoots @($reg) -AppCompatRoots @()
        @($r.Imported).Count | Should Be 1
        Get-KitRegistryValue -Path $reg -Name 'TablesDir' | Should BeExactly "$root\vPinball\FuturePinball\Tables"
        Get-KitRegistryValue -Path $reg -Name 'Steam' | Should BeExactly 'C:\Program Files (x86)\Steam'
        (Test-PinballRelocation -OldRoot $old -NewRoot $root -RegistryRoots @($reg) -AppCompatRoots @()).Clean | Should Be $true
    }

    It 'lists the missing settings when there is no source' {
        $missing = @(Get-PinballMissingSetting -Roots "$testKey\DoesNotExist")
        $missing.Count | Should Be 2
        $missing[0] | Should Match 'DoesNotExist'
    }
}
