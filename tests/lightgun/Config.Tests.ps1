$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1') -Force
$newRetroBat = Join-Path $PSScriptRoot 'New-LightgunTestRetroBat.ps1'
$newGunmote = Join-Path $PSScriptRoot 'New-LightgunTestGunmote.ps1'

function Get-Hash([string] $Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }

# Steam VDF, VMulti guard, Gunmote layouts and RetroBat settings on synthetic files in TestDrive.
# The process guard is mocked to "all closed" unless a test says otherwise; no real task is touched.
Describe 'Steam VDF editing' {
    Set-KitCulture -Culture 'en-US'
    Mock -ModuleName 'RetroCabinetKit.Lightgun' Test-KitProcessesClosed { }
    $steam = Join-Path $TestDrive 'Steam'
    & $newGunmote -Gunmote (Join-Path $TestDrive 'G') -Steam $steam
    $vdf = "$steam\config\config.vdf"
    $path = 'InstallConfigStore', 'Software', 'Valve', 'Steam'

    It 'reads nested values, escapes included' {
        $t = [IO.File]::ReadAllText($vdf)
        Get-LightgunVdfValue -Text $t -Path $path -Key 'controller_blacklist' | Should BeExactly '0x1234/0x5678'
        Get-LightgunVdfValue -Text $t -Path 'InstallConfigStore', 'Music' -Key 'LocalLibraryRoots' | Should BeExactly 'C:\Music "x"'
        Get-LightgunVdfValue -Text $t -Path $path -Key 'missing' | Should BeNullOrEmpty
    }

    It 'replaces only the value span; everything else stays byte for byte' {
        $t = [IO.File]::ReadAllText($vdf)
        $r = Set-LightgunVdfValue -Text $t -Path $path -Key 'controller_blacklist' -Value 'a,b'
        $r.Count | Should Be 1
        $r.Text | Should BeExactly ($t.Replace('"0x1234/0x5678"', '"a,b"'))
        (Set-LightgunVdfValue -Text $r.Text -Path $path -Key 'controller_blacklist' -Value 'a,b').Count | Should Be 0
    }

    It 'inserts a missing key before the closing brace with the block''s indentation' {
        $t = [IO.File]::ReadAllText($vdf)
        $r = Set-LightgunVdfValue -Text $t -Path 'InstallConfigStore', 'Music' -Key 'New' -Value 'v'
        $r.Text | Should BeExactly ($t.Replace("`"C:\\Music \`"x\`"`"`n`t}", "`"C:\\Music \`"x\`"`"`n`t`t`"New`"`t`t`"v`"`n`t}"))
        { Set-LightgunVdfValue -Text $t -Path 'InstallConfigStore', 'Nope' -Key 'k' -Value 'v' } | Should Throw
    }

    It 'merges the blacklist: foreign entries stay, known ones are not doubled (any case)' {
        Merge-LightgunBlacklist -Current '0x1234/0x5678,0X057E/0X0306' | Should BeExactly '0x1234/0x5678,0X057E/0X0306,0x0079/0x1802,0x0079/0x1803'
        Merge-LightgunBlacklist -Current '' | Should BeExactly '0x0079/0x1802,0x0079/0x1803,0x057e/0x0306'
    }

    It 'writes the blacklist once (backup, comment kept), the second run changes nothing' {
        Test-LightgunSteamBlacklist -ConfigVdf $vdf | Should Be $false
        Set-LightgunSteamBlacklist -ConfigVdf $vdf -Confirm:$false | Should Be 1
        $t = [IO.File]::ReadAllText($vdf)
        $t | Should Match '"controller_blacklist"\t\t"0x1234/0x5678,0x0079/0x1802,0x0079/0x1803,0x057e/0x0306"'
        $t | Should Match '// a comment the kit keeps'
        @(Get-ChildItem -LiteralPath "$steam\config" -Filter 'config.vdf.bak_lightgun_*').Count | Should Be 1
        Test-LightgunSteamBlacklist -ConfigVdf $vdf | Should Be $true
        Set-LightgunSteamBlacklist -ConfigVdf $vdf -Confirm:$false | Should Be 0
    }

    It 'adds the key when the Steam block has none' {
        $f = Join-Path $TestDrive 'plain.vdf'
        [IO.File]::WriteAllText($f, "`"InstallConfigStore`"`n{`n`t`"Software`"`n`t{`n`t`t`"Valve`"`n`t`t{`n`t`t`t`"Steam`"`n`t`t`t{`n`t`t`t}`n`t`t}`n`t}`n}`n")
        Set-LightgunSteamBlacklist -ConfigVdf $f -Confirm:$false | Should Be 1
        Test-LightgunSteamBlacklist -ConfigVdf $f | Should Be $true
    }

    It 'reports the Steam Input Xbox values of every user (read-only)' {
        $r = @(Get-LightgunSteamInputReport -SteamPath $steam)
        $r.Count | Should Be 1
        $r[0].Value | Should Be '1'
    }

    It 'writes nothing while Steam runs' {
        Mock -ModuleName 'RetroCabinetKit.Lightgun' Test-KitProcessesClosed { [pscustomobject]@{ Name = 'steam'; Id = 1 } }
        $f = Join-Path $TestDrive 'running.vdf'
        [IO.File]::WriteAllText($f, "`"InstallConfigStore`"`n{`n`t`"Software`"`n`t{`n`t`t`"Valve`"`n`t`t{`n`t`t`t`"Steam`"`n`t`t`t{`n`t`t`t}`n`t`t}`n`t}`n}`n")
        $hash = Get-Hash $f
        { Set-LightgunSteamBlacklist -ConfigVdf $f -Confirm:$false } | Should Throw 'steam'
        Get-Hash $f | Should Be $hash
    }
}

Describe 'GunmoteVMultiGuard task' {
    Set-KitCulture -Culture 'en-US'
    $guard = [pscustomobject]@{ TaskName = 'Gunmote Vmulti Guard'; TaskPath = '\EmuMote\'; State = 'Ready' }
    $off = [pscustomobject]@{ TaskName = 'GunmoteVMultiGuard'; TaskPath = '\'; State = 'Disabled' }
    $other = [pscustomobject]@{ TaskName = 'Something'; TaskPath = '\'; State = 'Ready' }

    It 'finds the guard task by name, enabled or not' {
        $r = @(Get-LightgunVMultiGuardTask -Tasks @($guard, $off, $other))
        $r.Count | Should Be 2
        ($r | Where-Object { $_.Enabled }).TaskPath | Should Be '\EmuMote\'
    }

    It 'disables only after confirmation and names the way back' {
        Mock -ModuleName 'RetroCabinetKit.Lightgun' Disable-ScheduledTask { }
        $t = Get-LightgunVMultiGuardTask -Tasks @($guard)
        { Disable-LightgunVMultiGuardTask -Task $t -Approve { $false } -Confirm:$false } | Should Throw
        Assert-MockCalled -ModuleName 'RetroCabinetKit.Lightgun' Disable-ScheduledTask -Times 0 -Exactly
        $script:asked = ''
        Disable-LightgunVMultiGuardTask -Task $t -Approve { param($text) $script:asked = $text; $true } -Confirm:$false
        $script:asked | Should Match ([regex]::Escape("Enable-ScheduledTask -TaskPath '\EmuMote\' -TaskName 'Gunmote Vmulti Guard'"))
        Assert-MockCalled -ModuleName 'RetroCabinetKit.Lightgun' Disable-ScheduledTask -Times 1 -Exactly -ParameterFilter { $TaskPath -eq '\EmuMote\' -and $TaskName -eq 'Gunmote Vmulti Guard' }
    }
}

Describe 'Gunmote layouts' {
    Set-KitCulture -Culture 'en-US'
    Mock -ModuleName 'RetroCabinetKit.Lightgun' Test-KitProcessesClosed { }
    $rb = 'X:\RetroBat'

    It 'every kit layout sets all keys, an explicit OffScreen state and Home off' {
        foreach ($kind in Get-LightgunLayoutKind) {
            $l = New-LightgunLayout -Kind $kind
            $l.All.OnScreen.Count | Should Be 64
            $l.All.OnScreen['Home'] | Should Be 'disable'
            foreach ($k in 'A', 'B', 'Pointer', 'Home') { $l.All.OffScreen.Contains($k) | Should Be $true }
            $l.All.OffScreen['Pointer'] | Should BeExactly $l.All.OnScreen['Pointer']
        }
        (New-LightgunLayout -Kind Menu).All.OnScreen['Pointer'] | Should Be 'disable'
        (New-LightgunLayout -Kind Menu).All.OnScreen['B'] | Should Be '360.a'
        (New-LightgunLayout -Kind Pad43).All.OnScreen['Pointer'] | Should Be '360.stickl-light-4:3'
        (New-LightgunLayout -Kind TP).All.OnScreen['Pointer'] | Should Be '360.stickr-light'
        (New-LightgunLayout -Kind Mouse).All.OnScreen['Pointer'] | Should Be 'lightgunmouse'
    }

    It 'fresh Gunmote: writes the four layouts, sets Default and the programs; second run changes nothing' {
        $g = Join-Path $TestDrive 'G1'
        & $newGunmote -Gunmote $g
        $plan = Get-LightgunLayoutPlan -KeymapsDir "$g\Keymaps" -RetroBatRoot $rb
        $plan.Files.Count | Should Be 4
        $plan.Titles['Menu'] | Should Be 'RCK Menu (no pointer)'
        Invoke-LightgunLayoutPlan -Plan $plan -Confirm:$false | Should Be $plan.Count
        $km = [IO.File]::ReadAllText("$g\Keymaps\Keymaps.json") | ConvertFrom-Json
        $km.Default | Should Be 'rck_menu.json'
        ($km.Applications | Where-Object { $_.Search -eq 'X:\RetroBat\emulators\teknoparrot\TeknoParrotUi.exe' }).Keymap | Should Be 'rck_tp.json'
        ($km.Applications | Where-Object { $_.Search -eq 'X:\RetroBat\emulators\retroarch\retroarch.exe' }).Keymap | Should Be 'rck_mouse.json'
        @($km.Applications | Where-Object { $_.Search -match 'duckstation' }).Count | Should Be 0
        $km.Calibration | Should Be 'Calibration.json'
        (Get-LightgunLayoutPlan -KeymapsDir "$g\Keymaps" -RetroBatRoot $rb).Count | Should Be 0
        (Get-LightgunLayoutPlan -KeymapsDir "$g\Keymaps" -RetroBatRoot $rb -Mode Replace).Count | Should Be 0
    }

    It 'Keep: correct own layouts stay; one with the inheritance trap (no OffScreen pointer) is replaced' {
        $g = Join-Path $TestDrive 'G2'
        & $newGunmote -Gunmote $g
        $menu = New-LightgunLayout -Kind Menu; $menu.Title = 'My menu'
        [IO.File]::WriteAllText("$g\Keymaps\my_menu.json", (ConvertTo-Json $menu -Depth 5))
        $tp = New-LightgunLayout -Kind TP; $tp.All.OffScreen.Remove('Pointer')
        [IO.File]::WriteAllText("$g\Keymaps\my_tp.json", (ConvertTo-Json $tp -Depth 5))
        $km = [IO.File]::ReadAllText("$g\Keymaps\Keymaps.json") | ConvertFrom-Json
        $km.Default = 'my_menu.json'
        $km.LayoutChooser = @($km.LayoutChooser) + [pscustomobject]@{ Title = 'My menu'; Keymap = 'my_menu.json' }
        $km.Applications = @([pscustomobject]@{ Keymap = 'my_tp.json'; Search = "$rb\emulators\teknoparrot\TeknoParrotUi.exe" })
        [IO.File]::WriteAllText("$g\Keymaps\Keymaps.json", (ConvertTo-Json $km -Depth 5))
        $plan = Get-LightgunLayoutPlan -KeymapsDir "$g\Keymaps" -RetroBatRoot $rb -Mode Keep
        $plan.Titles['Menu'] | Should Be 'My menu'
        $plan.Titles['TP'] | Should Be 'RCK TeknoParrot'
        @($plan.Changes | Where-Object { $_ -match '^Default' }).Count | Should Be 0
        @($plan.Changes | Where-Object { $_ -match 'TeknoParrotUi.exe: my_tp.json -> rck_tp.json' }).Count | Should Be 1
        (Get-LightgunLayoutPlan -KeymapsDir "$g\Keymaps" -RetroBatRoot $rb -Mode Replace).Titles['Menu'] | Should Be 'RCK Menu (no pointer)'
    }

    It 'writes nothing while Gunmote runs' {
        Mock -ModuleName 'RetroCabinetKit.Lightgun' Test-KitProcessesClosed { [pscustomobject]@{ Name = 'Gunmote'; Id = 1 } }
        $g = Join-Path $TestDrive 'G3'
        & $newGunmote -Gunmote $g
        $hash = Get-Hash "$g\Keymaps\Keymaps.json"
        $plan = Get-LightgunLayoutPlan -KeymapsDir "$g\Keymaps" -RetroBatRoot $rb
        { Invoke-LightgunLayoutPlan -Plan $plan -Confirm:$false } | Should Throw 'Gunmote'
        Get-Hash "$g\Keymaps\Keymaps.json" | Should Be $hash
        "$g\Keymaps\rck_menu.json" | Should Not Exist
    }

    It 'accepts only plain layout titles (they end up in task arguments)' {
        Test-LightgunLayoutTitle 'Gamepad (xinput) 4:3' | Should Be $true
        Test-LightgunLayoutTitle 'RCK Menu (no pointer)' | Should Be $true
        Test-LightgunLayoutTitle 'x" -Command calc' | Should Be $false
        Test-LightgunLayoutTitle 'a;b' | Should Be $false
        Test-LightgunLayoutTitle '' | Should Be $false
    }
}

Describe 'RetroBat settings (es_settings.cfg, es_input.cfg)' {
    Set-KitCulture -Culture 'en-US'
    Mock -ModuleName 'RetroCabinetKit.Lightgun' Test-KitProcessesClosed { }
    $root = Join-Path $TestDrive 'RB'
    & $newRetroBat -Root $root
    $p = Get-LightgunRetroBatPath -Root $root

    It 'plans exactly the missing and wrong keys' {
        $plan = @(Get-LightgunEsSettingsPlan -Path $p.EsSettings)
        ($plan | Where-Object { $_.Name -eq 'mame.use_guns' }).Old | Should Be '1'
        ($plan | Where-Object { $_.Name -eq 'mame.emulator' }).New | Should Be 'mame64'
        @($plan | Where-Object { $_.Name -in 'naomi.use_guns', 'psx.core' }).Count | Should Be 0
        @($plan | Where-Object { $_.Name -eq 'teknoparrot.use_guns' -and $_.Action -eq 'Add' }).Count | Should Be 1
    }

    It 'writes the settings: comment and order kept, sorted inserts, backup, second run 0 changes' {
        $count = Set-LightgunEsSettings -Path $p.EsSettings -Confirm:$false
        $count | Should BeGreaterThan 10
        $lines = [IO.File]::ReadAllLines($p.EsSettings)
        $lines[0] | Should BeExactly '<?xml version="1.0"?>'
        $lines[2] | Should BeExactly '  <!-- kept by the kit: a user comment -->'
        $lines[3] | Should BeExactly '  <bool name="FavoritesFirst" value="true" />'
        $lines[-2] | Should BeExactly '  <string name="zzz.last" value="stays last" />'
        $names = @($lines | Where-Object { $_ -match 'name="([^"]+)"' } | ForEach-Object { ([regex]::Match($_, 'name="([^"]+)"')).Groups[1].Value })
        $sorted = [string[]]$names.Clone(); [Array]::Sort($sorted, [StringComparer]::Ordinal)
        ($names -join '|') | Should BeExactly ($sorted -join '|')
        [IO.File]::ReadAllText($p.EsSettings) | Should Match '<string name="mame\.use_guns" value="0" />'
        [IO.File]::ReadAllText($p.EsSettings) | Should Match 'mame\[&quot;alien3\.zip&quot;\]\.use_guns'
        [IO.File]::ReadAllText($p.EsSettings) | Should Match "`r`n"
        @(Get-ChildItem -LiteralPath (Split-Path $p.EsSettings) -Filter 'es_settings.cfg.bak_lightgun_*').Count | Should Be 1
        $hash = Get-Hash $p.EsSettings
        Set-LightgunEsSettings -Path $p.EsSettings -Confirm:$false | Should Be 0
        Get-Hash $p.EsSettings | Should Be $hash
    }

    It 'restores the complete Xbox block (a = button 0, b = button 1, measured), other blocks untouched' {
        @(Get-LightgunEsInputPlan -Path $p.EsInput).Count | Should BeGreaterThan 2
        Set-LightgunEsInput -Path $p.EsInput -Confirm:$false | Should BeGreaterThan 2
        $t = [IO.File]::ReadAllText($p.EsInput)
        $t | Should Match "^<\?xml version='1.0' encoding='utf-8'\?>"
        $t | Should Match '<input name="a" type="key" id="120" value="1" />'
        $t | Should Match '<input name="a" type="button" id="0" value="1" />'
        $t | Should Match '<input name="b" type="button" id="1" value="1" />'
        ([regex]::Matches($t, '<input ')).Count | Should Be 22
        @(Get-LightgunEsInputPlan -Path $p.EsInput).Count | Should Be 0
        Set-LightgunEsInput -Path $p.EsInput -Confirm:$false | Should Be 0
    }

    It 'adds the block when es_input.cfg has none' {
        $f = Join-Path $TestDrive 'es_input_empty.cfg'
        [IO.File]::WriteAllText($f, "<?xml version=`"1.0`"?>`r`n<inputList>`r`n`t<inputConfig type=`"keyboard`" deviceName=`"Keyboard`" deviceGUID=`"-1`">`r`n`t</inputConfig>`r`n</inputList>`r`n")
        (Get-LightgunEsInputPlan -Path $f).Name | Should Be 'block'
        Set-LightgunEsInput -Path $f -Confirm:$false | Should Be 1
        @(Get-LightgunEsInputPlan -Path $f).Count | Should Be 0
        [IO.File]::ReadAllText($f) | Should Match 'deviceGUID="030000005e0400008e02000000007200"'
    }

    It 'reports per-game overrides and hard-wired gamelist emulators, never changes them' {
        $o = @(Get-LightgunEsOverride -Path $p.EsSettings)
        $o.Count | Should Be 1
        $o[0].Game | Should Be 'alien3.zip'
        $g = @(Get-LightgunGamelistOverride -RetroBatRoot $root)
        $g.Count | Should Be 1
        $g[0].Emulator | Should Be 'libretro'
    }

    It 'writes nothing while RetroBat runs' {
        Mock -ModuleName 'RetroCabinetKit.Lightgun' Test-KitProcessesClosed { [pscustomobject]@{ Name = 'emulationstation'; Id = 1 } }
        $root2 = Join-Path $TestDrive 'RB2'
        & $newRetroBat -Root $root2
        $p2 = Get-LightgunRetroBatPath -Root $root2
        $hash = Get-Hash $p2.EsSettings
        { Set-LightgunEsSettings -Path $p2.EsSettings -Confirm:$false } | Should Throw 'emulationstation'
        { Set-LightgunEsInput -Path $p2.EsInput -Confirm:$false } | Should Throw 'emulationstation'
        Get-Hash $p2.EsSettings | Should Be $hash
    }
}
