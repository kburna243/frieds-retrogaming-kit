$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1') -Force
$newRetroBat = Join-Path $PSScriptRoot 'New-LightgunTestRetroBat.ps1'
$newTp = Join-Path $PSScriptRoot 'New-LightgunTestTeknoParrot.ps1'
$steps = Join-Path $kitRoot 'lightgun\steps'

function Get-Hash([string] $Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }

# Synthetic TeknoParrot setup (generic names, foreign build root "Z:\Some Build\RetroBat"). Nothing real is read.
Describe 'TeknoParrot profiles: paths, XInput binding, es_settings [W8]' {
    Set-KitCulture -Culture 'en-US'
    Mock -ModuleName 'RetroCabinetKit.Lightgun' Test-KitProcessesClosed { }
    $rb = Join-Path $TestDrive 'RetroBat'
    & $newRetroBat -Root $rb
    & $newTp -Root $rb
    [IO.File]::WriteAllText((Join-Path $TestDrive 'secret.txt'), 'outside roms')
    $up = Join-Path $rb 'emulators\teknoparrot\UserProfiles'
    $yml = Join-Path $rb 'system\resources\inputmapping\teknoparrot.yml'

    It 'path plan: foreign root repaired generically, nested roms, missing reported, ".." and "#" profiles left alone' {
        $plan = @(Get-LightgunTpPathPlan -RetroBatRoot $rb)
        $a = @($plan | Where-Object { $_.Profile -eq 'GunA' -and $_.Field -eq 'GamePath' })[0]
        $a.Action | Should Be 'Repair'
        $a.New | Should Be (Join-Path $rb 'roms\teknoparrot\GunA.parrot\game.exe')
        @($plan | Where-Object { $_.Profile -eq 'GunA' -and $_.Field -eq 'GamePath2' })[0].New | Should Be (Join-Path $rb 'roms\namco\roms\nested.bin')
        @($plan | Where-Object { $_.Profile -eq 'Missing' })[0].Action | Should Be 'Missing'
        @($plan | Where-Object { $_.Profile -eq 'PadGame' })[0].Action | Should Be 'Missing' # no file here either
        @($plan | Where-Object { $_.Profile -eq 'Escape' })[0].Action | Should Be 'Missing' # '..' never leaves roms
        @($plan | Where-Object { $_.Profile -like '#*' -or $_.Profile -eq 'GunB' }).Count | Should Be 0
    }

    It 'repair writes only the planned paths (backup, line ends kept) and is idempotent' {
        $before = Get-Hash "$up\GunB.xml"
        Repair-LightgunTpPath -Plan @(Get-LightgunTpPathPlan -RetroBatRoot $rb) -Confirm:$false | Should Be 2
        $doc = [xml][IO.File]::ReadAllText("$up\GunA.xml")
        $doc.GameProfile.GamePath | Should Be (Join-Path $rb 'roms\teknoparrot\GunA.parrot\game.exe')
        @(Get-ChildItem -LiteralPath $up -Filter 'GunA.xml.bak_lightgun_*').Count | Should Be 1
        Get-Hash "$up\GunB.xml" | Should Be $before
        [IO.File]::ReadAllText("$up\GunA.xml") | Should Match "`r`n  <ProfileName>GunA</ProfileName>`r`n"
        @(Get-LightgunTpPathPlan -RetroBatRoot $rb | Where-Object { $_.Action -eq 'Repair' }).Count | Should Be 0
        Repair-LightgunTpPath -Plan @(Get-LightgunTpPathPlan -RetroBatRoot $rb) -Confirm:$false | Should Be 0
    }

    It 'reads RetroBat''s yml: lower-case profiles, tabs, comments, empty values, touch screen mark' {
        $m = Read-LightgunTpInputMapping -Path $yml
        $m['guna']['P1Button1'] | Should Be 'righttrigger'
        $m['guna'].ContainsKey('P1RelativeUp') | Should Be $false
        $m['gunb']['P1Button1'] | Should Be 'righttrigger'
        $m['touchgame'].ContainsKey('#touchscreen') | Should Be $true
        $m['guna'].ContainsKey('#touchscreen') | Should Be $false
    }

    It 'XInput targets: shorts, sticks, triggers, unknown values' {
        $m = Get-Module 'RetroCabinetKit.Lightgun'
        $y = & $m { Get-LightgunTpXInputTarget 'north' 1 }
        $y.Fields.ButtonCode | Should BeExactly '-32768'
        $y.Fields.XInputIndex | Should Be '1'
        $y.Bind | Should BeExactly 'Input Device 1 Y'
        $s = & $m { Get-LightgunTpXInputTarget 'rightstickleft' 0 }
        $s.Fields.IsRightThumbX | Should Be 'true'
        $s.Fields.IsAxisMinus | Should Be 'true'
        $s.Bind | Should BeExactly 'Input Device 0 RightThumbInput Device 0 X-'
        (& $m { Get-LightgunTpXInputTarget 'righttrigger' 0 }).Fields.IsRightTrigger | Should Be 'true'
        & $m { Get-LightgunTpXInputTarget 'kb_5' 0 } | Should BeNullOrEmpty
        & $m { Get-LightgunTpXInputTarget 'mouseleft' 0 } | Should BeNullOrEmpty
    }

    It 'bind plan: gun games only, touch screen game and pad game untouched, missing game reported' {
        $plan = @(Get-LightgunTpBindPlan -RetroBatRoot $rb)
        ($plan | Where-Object { $_.Profile -eq 'GunA' }).Status | Should Be 'Bind'
        ($plan | Where-Object { $_.Profile -eq 'GunA' }).Rom | Should Be 'GunA.parrot'
        ($plan | Where-Object { $_.Profile -eq 'TouchGame' }).Status | Should Be 'Touch'
        ($plan | Where-Object { $_.Profile -eq 'Missing' }).Status | Should Be 'NoPath'
        @($plan | Where-Object { $_.Profile -eq 'PadGame' }).Count | Should Be 0
        (@(Get-LightgunTpBindPlan -RetroBatRoot $rb -Exclude 'GunA') | Where-Object { $_.Profile -eq 'GunA' }).Status | Should Be 'Excluded'
    }

    It 'binding: B = shot, A = reload, grenade on X, player 2 on pad 1, Test stays free, Input API XInput; second run changes nothing' {
        $touch = Get-Hash "$up\TouchGame.xml"
        Set-LightgunTpBinding -Plan @(Get-LightgunTpBindPlan -RetroBatRoot $rb) -MappingPath $yml -Confirm:$false | Should Be 2
        $doc = [xml][IO.File]::ReadAllText("$up\GunA.xml")
        $b = @{}; foreach ($j in $doc.GameProfile.JoystickButtons.JoystickButtons) { $b[$j.ButtonName] = $j }
        $b['Player 1 Trigger'].XInputButton.ButtonCode | Should Be '8192'
        $b['Player 1 Trigger'].BindName | Should BeExactly 'Input Device 0 B'
        $b['Player 1 Trigger'].BindNameXi | Should BeExactly 'Input Device 0 B'
        $b['Player 1 Trigger'].RawInputButton | Should Not BeNullOrEmpty # RawInput stays for going back
        $b['Player 1 Reload'].XInputButton.ButtonCode | Should Be '4096'
        $b['Player 1 Grenade'].XInputButton.ButtonCode | Should Be '16384'
        $b['Player 2 Trigger'].XInputButton.XInputIndex | Should Be '1'
        $b['Player 1 Gun X'].XInputButton.IsRightThumbX | Should Be 'true'
        $b['Player 1 Gun Y'].XInputButton.IsRightThumbY | Should Be 'true'
        $b['Player 1 Gun Y'].XInputButton.IsAxisMinus | Should Be 'false'
        $b['Test'].XInputButton | Should BeNullOrEmpty
        $b['Coin 1'].XInputButton.ButtonCode | Should Be '32'
        ($doc.GameProfile.ConfigValues.FieldInformation | Where-Object { $_.FieldName -eq 'Input API' }).FieldValue | Should Be 'XInput'
        # element order inside XInputButton as TeknoParrot writes it
        @($b['Player 1 Trigger'].XInputButton.ChildNodes | Where-Object { $_.NodeType -eq 'Element' } | ForEach-Object { $_.Name })[7] | Should Be 'ButtonCode'
        Get-Hash "$up\TouchGame.xml" | Should Be $touch
        $gunB = [IO.File]::ReadAllBytes("$up\GunB.xml")
        ($gunB[0] -eq 0xEF -and $gunB[1] -eq 0xBB -and $gunB[2] -eq 0xBF) | Should Be $true # BOM kept
        $bound = Get-Hash "$up\GunA.xml"
        @(Get-LightgunTpBindPlan -RetroBatRoot $rb | Where-Object { $_.Status -eq 'Bind' }).Count | Should Be 0
        Set-LightgunTpBinding -Plan @(Get-LightgunTpBindPlan -RetroBatRoot $rb) -MappingPath $yml -Confirm:$false | Should Be 0
        Get-Hash "$up\GunA.xml" | Should Be $bound
    }

    It 'binding repairs a wrong XInput entry and keeps the order of the other elements' {
        $f = "$up\GunA.xml"
        $text = [IO.File]::ReadAllText($f)
        [IO.File]::WriteAllText($f, $text.Replace('<ButtonCode>8192</ButtonCode>', '<ButtonCode>4096</ButtonCode>'), (New-Object Text.UTF8Encoding $false))
        (@(Get-LightgunTpBindPlan -RetroBatRoot $rb) | Where-Object { $_.Profile -eq 'GunA' }).Changes | Should Be 2 # both triggers
        Set-LightgunTpBinding -Plan @(Get-LightgunTpBindPlan -RetroBatRoot $rb) -MappingPath $yml -Confirm:$false | Should Be 1
        [IO.File]::ReadAllText($f) | Should Match '<ButtonCode>8192</ButtonCode>'
        ([regex]::Matches([IO.File]::ReadAllText($f), '<XInputButton>')).Count | Should Be 7
    }

    It 'es_settings: use_guns=0, disableautocontrollers per bound game, creator leftovers removed, other keys kept' {
        $es = (Get-LightgunRetroBatPath -Root $rb).EsSettings
        $roms = @(Get-LightgunTpBindPlan -RetroBatRoot $rb | Where-Object { $_.Status -in 'Bind', 'Ok' } | ForEach-Object { $_.Rom })
        $target = Get-LightgunTpEsTarget -Rom $roms
        $remove = @(Get-LightgunTpEsRemove -Path $es)
        ($remove | Sort-Object) -join '|' | Should Be 'teknoparrot.shaderset|teknoparrot.tp_nocrosshair|teknoparrot["GunA.parrot"].tp_inputdriver'
        $plan = @(Get-LightgunEsSettingsPlan -Path $es -Target $target -Remove $remove)
        @($plan | Where-Object { $_.Action -eq 'Remove' }).Count | Should Be 3
        @($plan | Where-Object { $_.Name -eq 'teknoparrot["GunB.parrot"].disableautocontrollers' -and $_.Action -eq 'Add' }).Count | Should Be 1
        Set-LightgunEsSettings -Path $es -Target $target -Remove $remove -Confirm:$false | Should Be $plan.Count
        $text = [IO.File]::ReadAllText($es)
        $text | Should Match 'teknoparrot\[&quot;GunA\.parrot&quot;\]\.disableautocontrollers" value="1"'
        $text | Should Match 'teknoparrot\[&quot;GunA\.parrot&quot;\]\.bezel" value="none"'
        $text | Should Match 'name="teknoparrot.use_guns" value="0"'
        $text | Should Not Match 'sindenborder|tp_inputdriver|tp_nocrosshair'
        $text | Should Match '<!-- kept by the kit: a user comment -->'
        $text | Should Not Match "(`r`n)[ ]*`r`n  <string" # no empty line left where a key was removed
        @(Get-LightgunEsSettingsPlan -Path $es -Target $target -Remove @(Get-LightgunTpEsRemove -Path $es)).Count | Should Be 0
    }

    It 'round trip keeps <a></a>, <a />, BOM and CRLF byte for byte' {
        $f = Join-Path $TestDrive 'roundtrip.xml'
        $text = "<?xml version=`"1.0`" encoding=`"utf-8`"?>`r`n<GameProfile>`r`n  <A></A>`r`n  <B />`r`n  <C>x</C>`r`n</GameProfile>`r`n"
        [IO.File]::WriteAllText($f, $text, (New-Object Text.UTF8Encoding $true))
        $before = Get-Hash $f
        $m = Get-Module 'RetroCabinetKit.Lightgun'
        & $m { param($p) Save-LightgunXml (Read-LightgunXml $p) $p } $f
        Get-Hash $f | Should Be $before
    }

    It 'step 10 as stand-alone script: dry run changes nothing, then green, a second run is skipped' {
        $rb2 = Join-Path $TestDrive 'RetroBat2'
        & $newRetroBat -Root $rb2
        & $newTp -Root $rb2
        $state = Join-Path $TestDrive 'state10.json'
        $common = @{ RetroBatRoot = $rb2; StatePath = $state; Culture = 'en-US' }
        $a = Get-Hash (Join-Path $rb2 'emulators\teknoparrot\UserProfiles\GunA.xml')
        $r = @(& "$steps\10-TeknoParrot.ps1" @common -WhatIf)
        @($r | Where-Object { -not $_.WhatIf }).Count | Should Be 0
        Get-Hash (Join-Path $rb2 'emulators\teknoparrot\UserProfiles\GunA.xml') | Should Be $a
        (@(& "$steps\10-TeknoParrot.ps1" @common) | ForEach-Object { $_.Status }) -join ',' | Should Be 'Done,Done,Done'
        (@(& "$steps\10-TeknoParrot.ps1" @common) | ForEach-Object { $_.Status }) -join ',' | Should Be 'Skipped,Skipped,Skipped'
    }
}

Describe 'TeknoParrot game list and duplicates [W8]' {
    Set-KitCulture -Culture 'en-US'
    Mock -ModuleName 'RetroCabinetKit.Lightgun' Test-KitProcessesClosed { }
    $rb = Join-Path $TestDrive 'RetroBat'
    & $newRetroBat -Root $rb
    & $newTp -Root $rb
    $null = Repair-LightgunTpPath -Plan @(Get-LightgunTpPathPlan -RetroBatRoot $rb) -Confirm:$false
    $roms = Join-Path $rb 'roms\teknoparrot'
    $gamelist = Join-Path $roms 'gamelist.xml'

    It 'classifies folders: active from profiles, duplicate by name (.parrot/.teknoparrot) and by content, unregistered' {
        $c = @{}; foreach ($r in Get-LightgunTpFolderClass -RetroBatRoot $rb) { $c[$r.Folder] = $r }
        $c['GunA.parrot'].Kind | Should Be 'Active'
        $c['GunB.parrot'].Kind | Should Be 'Active'
        $c['GunA.teknoparrot'].Kind | Should Be 'Duplicate'
        $c['GunA.teknoparrot'].Profile | Should Be 'GunA.parrot'
        $c['Copy of B'].Kind | Should Be 'Duplicate'
        $c['Copy of B'].Profile | Should Be 'GunB.parrot'
        $c['Stray.parrot'].Kind | Should Be 'Unregistered'
        $c['Stray.parrot'].Profile | Should Be 'Stray'
        $c.ContainsKey('images') | Should Be $false
    }

    It 'plan: move duplicates, hide unregistered, add registered games, report missing media and orphans' {
        $plan = @(Get-LightgunTpGamelistPlan -RetroBatRoot $rb)
        $by = { param($a, $f) @($plan | Where-Object { $_.Action -eq $a -and $_.Folder -eq $f }).Count }
        & $by 'Move' 'GunA.teknoparrot' | Should Be 1
        & $by 'Move' 'Copy of B' | Should Be 1
        & $by 'Hide' 'Stray.parrot' | Should Be 1
        & $by 'Add' 'GunB.parrot' | Should Be 1
        & $by 'Add' 'TouchGame.parrot' | Should Be 1
        & $by 'NoMedia' 'GunA.parrot' | Should Be 1
        & $by 'Orphan' 'Old.parrot' | Should Be 1
        @($plan | Where-Object { $_.Action -eq 'Move' })[0].Detail | Should Be (Join-Path $rb '_duplicates\teknoparrot\Copy of B')
    }

    It 'declined move plan: nothing moved; confirmed: moved, never deleted, an existing target is never overwritten' {
        $plan = @(Get-LightgunTpGamelistPlan -RetroBatRoot $rb)
        { Move-LightgunTpDuplicate -RetroBatRoot $rb -Plan $plan -Approve { $false } -Confirm:$false } | Should Throw
        Join-Path $roms 'GunA.teknoparrot' | Should Exist
        $dup = Join-Path $rb '_duplicates\teknoparrot'
        New-Item -ItemType Directory -Path "$dup\Copy of B" -Force | Out-Null
        $shown = $null
        $moved = @(Move-LightgunTpDuplicate -RetroBatRoot $rb -Plan $plan -Approve { param($t) $script:shownPlan = $t; $true } -Confirm:$false)
        $moved -join '|' | Should Be 'GunA.teknoparrot'
        "$dup\GunA.teknoparrot\game.exe" | Should Exist
        Join-Path $roms 'GunA.teknoparrot' | Should Not Exist
        "$roms\Copy of B\bin\b.elf" | Should Exist # target existed: left where it was
        $script:shownPlan | Should Match 'MOVED'
        Remove-Item -LiteralPath "$dup\Copy of B" -Recurse -Force
    }

    It 'gamelist: entries added and hidden, comments and other entries kept, second run changes nothing' {
        $null = @(Move-LightgunTpDuplicate -RetroBatRoot $rb -Plan @(Get-LightgunTpGamelistPlan -RetroBatRoot $rb) -Approve { $true } -Confirm:$false)
        Set-LightgunTpGamelist -Path $gamelist -Plan @(Get-LightgunTpGamelistPlan -RetroBatRoot $rb) -Confirm:$false | Should Be 3
        $doc = [xml][IO.File]::ReadAllText($gamelist)
        $g = @{}; foreach ($x in $doc.gameList.game) { $g[$x.path] = $x }
        $g['./Stray.parrot'].hidden | Should Be 'true'
        $g['./GunB.parrot'].name | Should Be 'GunB'
        $g['./GunA.parrot'].GetAttribute('id') | Should Be '1'
        $g.ContainsKey('./Old.parrot') | Should Be $true # orphans are only reported
        [IO.File]::ReadAllText($gamelist) | Should Match "`n`t<game>`n`t`t<path>./GunB.parrot</path>`n`t`t<name>GunB</name>`n`t</game>"
        Set-LightgunTpGamelist -Path $gamelist -Plan @(Get-LightgunTpGamelistPlan -RetroBatRoot $rb) -Confirm:$false | Should Be 0
    }

    It 'reports hard-wired emulators in any gamelist.xml' {
        $h = @(Get-LightgunGamelistOverride -RetroBatRoot $rb -AllSystems)
        @($h | Where-Object { $_.System -eq 'mame' -and $_.Game -eq './area51.zip' }).Count | Should Be 1
    }

    It 'step 11 as stand-alone script: dry run moves nothing; approved run is green; second run skipped' {
        $rb2 = Join-Path $TestDrive 'RetroBat2'
        & $newRetroBat -Root $rb2
        & $newTp -Root $rb2
        $null = Repair-LightgunTpPath -Plan @(Get-LightgunTpPathPlan -RetroBatRoot $rb2) -Confirm:$false
        $state = Join-Path $TestDrive 'state11.json'
        $common = @{ RetroBatRoot = $rb2; StatePath = $state; Culture = 'en-US'; Approve = { $true } }
        $null = & "$steps\11-GameLists.ps1" @common -WhatIf
        Join-Path $rb2 'roms\teknoparrot\GunA.teknoparrot' | Should Exist
        (@(& "$steps\11-GameLists.ps1" @common) | ForEach-Object { $_.Status }) -join ',' | Should Be 'Done,Done'
        (@(& "$steps\11-GameLists.ps1" @common) | ForEach-Object { $_.Status }) -join ',' | Should Be 'Skipped,Skipped'
    }
}
