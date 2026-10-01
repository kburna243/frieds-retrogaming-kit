$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'arcade\RetroCabinetKit.Arcade.psd1') -Force

# Input matrix: one profile -> a MAME ctrlr file of the kit's own. Everything runs in a fake RetroBat in
# TestDrive; the user profile folder is pointed at TestDrive too, so no real profile is read or written.
Describe 'Input matrix (profiles -> MAME ctrlr)' {
    Set-KitCulture -Culture 'en-US'
    $userDir = Join-Path $TestDrive 'home\InputProfiles'
    foreach ($m in @(Get-Module -All 'RetroCabinetKit.Arcade')) { & $m { $script:InputUserDir = $args[0] } $userDir }
    $null = New-Item -ItemType Directory -Path $userDir -Force
    $rb = Join-Path $TestDrive 'RetroBat'
    $ctrlrDir = Join-Path $rb 'saves\mame\ctrlr'
    $esDir = Join-Path $rb 'emulationstation\.emulationstation'
    $null = New-Item -ItemType Directory -Path $ctrlrDir, $esDir -Force

    function Set-TestEs([hashtable] $Values) {
        $lines = @('<?xml version="1.0"?>', '<config>') + @($Values.Keys | ForEach-Object { "  <string name=`"$_`" value=`"$($Values[$_])`" />" }) + '</config>'
        [IO.File]::WriteAllText((Join-Path $esDir 'es_settings.cfg'), ($lines -join "`r`n"))
    }

    It 'ships the I-PAC 2 profile and reads it into intents with their sources' {
        $p = Get-ArcadeInputProfile -Name 'ipac2-default'
        $p.Builtin | Should Be $true
        $p.Mapping['START1'] | Should Be 'KEY_1'
        @($p.Mapping['P1_BUTTON1']) -join ',' | Should Be 'KEY_LCONTROL,MOUSE1_BUTTON1'
    }

    It 'translates every source family into MAME codes and refuses what it does not know' {
        ConvertTo-ArcadeMameCode 'KEY_LCONTROL' | Should Be 'KEYCODE_LCONTROL'
        ConvertTo-ArcadeMameCode 'JOY1_BUTTON2' | Should Be 'JOYCODE_1_BUTTON2'
        ConvertTo-ArcadeMameCode 'JOY2_UP' | Should Be 'JOYCODE_2_YAXIS_UP_SWITCH'
        ConvertTo-ArcadeMameCode 'JOY1_HAT_LEFT' | Should Be 'JOYCODE_1_HAT1LEFT'
        ConvertTo-ArcadeMameCode 'MOUSE1_BUTTON3' | Should Be 'MOUSECODE_1_BUTTON3'
        ConvertTo-ArcadeMameCode 'NONE' | Should Be 'NONE'
        ConvertTo-ArcadeMameCode 'JOY1_DPAD_UP' | Should Be 'JOYCODE_1_HAT1UP'
        ConvertTo-ArcadeMameCode 'JOY2_XAXIS' | Should Be 'JOYCODE_2_XAXIS'
        ConvertTo-ArcadeMameCode 'JOY1_RZAXIS' | Should Be 'JOYCODE_1_RZAXIS'
        ConvertTo-ArcadeMameCode 'JOY1_SELECT+JOY1_START' | Should Be 'JOYCODE_1_SELECT JOYCODE_1_START'
        { ConvertTo-ArcadeMameCode 'JOY1_SELECT+KEY_NOPE' } | Should Throw
        { ConvertTo-ArcadeMameCode 'JOY1_WAXIS' } | Should Throw
        { ConvertTo-ArcadeMameCode 'KEY_LCTRL' } | Should Throw
        { ConvertTo-ArcadeMameCode 'key_1' } | Should Throw
    }

    It 'refuses a profile with an unknown intent or source instead of leaving a button dead' {
        [IO.File]::WriteAllText((Join-Path $userDir 'bad-intent.json'), '{ "Mapping": { "P1_FIRE": "KEY_1" } }')
        [IO.File]::WriteAllText((Join-Path $userDir 'bad-source.json'), '{ "Mapping": { "P1_BUTTON1": "KEY_LCTRL" } }')
        { Get-ArcadeInputProfile -Name 'bad-intent' } | Should Throw
        { Get-ArcadeInputProfile -Name 'bad-source' } | Should Throw
        Remove-Item (Join-Path $userDir 'bad-*.json')
    }

    It 'a user profile of the same name wins over the built-in one' {
        [IO.File]::WriteAllText((Join-Path $userDir 'ipac2-default.json'), '{ "Mapping": { "START1": "JOY1_START" } }')
        (Get-ArcadeInputProfile -Name 'ipac2-default').Builtin | Should Be $false
        Remove-Item (Join-Path $userDir 'ipac2-default.json')
    }

    It 'plans a new file with every port and warns about each RetroBat setting that would not load it' {
        Set-TestEs @{ 'mame.emulator' = 'mame64'; 'mame.mame_ctrlr_profile' = 'custom1' }
        $plan = Get-ArcadeInputMatrixPlan -ProfileName 'ipac2-default' -RetroBatRoot $rb
        $plan.Target | Should Be (Join-Path $ctrlrDir 'kit-ipac2-default.cfg')
        $plan.Exists | Should Be $false
        @($plan.Changes).Count | Should Be 26
        @($plan.Warnings).Count | Should Be 1
        ($plan.Warnings -join ' ') | Should Match 'mame_ctrlr_profile'
        Test-Path (Join-Path $ctrlrDir 'kit-ipac2-default.cfg') | Should Be $false
    }

    It 'writes a ctrlr file MAME can read, then skips the second run' {
        Set-TestEs @{ 'mame.emulator' = 'mame64'; 'mame.mame_ctrlr_profile' = 'kit-ipac2-default' }
        $r = Set-ArcadeInputMatrix -ProfileName 'ipac2-default' -RetroBatRoot $rb -Confirm:$false
        $r.Written | Should Be $true
        $r.Backup | Should BeNullOrEmpty
        @($r.Warnings).Count | Should Be 0
        $xml = [xml][IO.File]::ReadAllText($r.Target)
        $xml.mameconfig.system.name | Should Be 'default'
        $b1 = $xml.SelectSingleNode("//port[@type='P1_BUTTON1']/newseq").InnerText
        $b1 | Should Be 'KEYCODE_LCONTROL OR MOUSECODE_1_BUTTON1'
        $again = Set-ArcadeInputMatrix -ProfileName 'ipac2-default' -RetroBatRoot $rb -Confirm:$false
        $again.Written | Should Be $false
        @($again.Changes).Count | Should Be 0
    }

    It 'backs up its own file before rewriting it and plans only the ports that change' {
        [IO.File]::WriteAllText((Join-Path $userDir 'swap.json'), '{ "Mapping": { "START1": "KEY_2", "COIN1": "KEY_5" } }')
        $null = Set-ArcadeInputMatrix -ProfileName 'swap' -CtrlrName 'swap' -RetroBatRoot $rb -Confirm:$false
        [IO.File]::WriteAllText((Join-Path $userDir 'swap.json'), '{ "Mapping": { "START1": "KEY_1", "COIN1": "KEY_5" } }')
        $backupDir = Join-Path $TestDrive 'backups'
        $r = Set-ArcadeInputMatrix -ProfileName 'swap' -CtrlrName 'swap' -RetroBatRoot $rb -BackupDir $backupDir -Confirm:$false
        @($r.Changes).Count | Should Be 1
        $r.Changes[0].Port | Should Be 'START1'
        $r.Changes[0].Old | Should Be 'KEYCODE_2'
        Test-Path -LiteralPath $r.Backup | Should Be $true
    }

    It 'never touches a ctrlr file it did not write, nor retrobat_auto' {
        $hand = Join-Path $ctrlrDir 'custom1.cfg'
        [IO.File]::WriteAllText($hand, '<mameconfig version="10"><system name="default"><input /></system></mameconfig>')
        { Set-ArcadeInputMatrix -ProfileName 'ipac2-default' -CtrlrName 'custom1' -RetroBatRoot $rb -Confirm:$false } | Should Throw
        { Get-ArcadeInputMatrixPlan -ProfileName 'ipac2-default' -CtrlrName 'retrobat_auto' -RetroBatRoot $rb } | Should Throw
        { Get-ArcadeInputMatrixPlan -ProfileName 'ipac2-default' -CtrlrName '..\evil' -RetroBatRoot $rb } | Should Throw
        [IO.File]::ReadAllText($hand) | Should Not Match 'kit:input-matrix'
    }


}
