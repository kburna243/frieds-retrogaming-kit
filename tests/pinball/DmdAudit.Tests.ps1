$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1') -Force
$script:newTable = Join-Path $PSScriptRoot 'New-PinballVpxTestTable.ps1'

$script:newBuild = Join-Path $PSScriptRoot 'New-PinballDmdTestBuild.ps1'

function New-DmdAuditFixture([string] $Name) {
    & $script:newBuild -Root (Join-Path (Resolve-Path -LiteralPath $TestDrive).ProviderPath $Name)
}

function Get-DmdTreeHash([string] $Root) {
    @(Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName |
        ForEach-Object { '{0}|{1}' -f $_.FullName, (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join ';'
}

function Get-Row($Audit, [string] $Name) { @($Audit.Section | Where-Object { $_.Section -eq $Name })[0] }

Describe 'Pinball DMD audit: table script facts' {
    Set-KitCulture -Culture 'en-US'

    It 'reads cGameName, the pack name and the FIRST PuP switch, and skips comment lines' {
        $f = Get-PinballTableScriptFact -Text "' Const cGameName = `"old`"`r`nConst cGameName = `"goonies`"`r`nConst enablePupPack = False`r`nConst enablePupDMD = True`r`nDim pGameName : pGameName=`"TheGoonies`"`r`nPuPlayer.Init`r`nFlexDMD.Show = True"
        @($f.GameName) | Should Be @('goonies')
        @($f.PackName) | Should Be @('TheGoonies')
        $f.PupSwitch | Should Be 'enablePupPack=False'
        $f.PupSwitchOn | Should Be $false
        $f.PuPlayer | Should Be 1
        $f.FlexDmd | Should Be 1
    }

    It 'does not take the DMD driver type for a switch and reports no switch when there is none' {
        $f = Get-PinballTableScriptFact -Text "Const cGameName = `"x`"`r`nDim PuPDMDDriverType: PuPDMDDriverType = 1"
        $f.PupSwitch | Should Be ''
        $f.PupSwitchOn | Should Be $null
    }

    It 'a switch that gets True and False is detected at run time (auto); a Const or a single value is the setting' {
        $gotg = Get-PinballTableScriptFact -Text "Dim bUsePUPDMD`r`nbUsePUPDMD=False`r`nOn Error Resume Next`r`nbUsePUPDMD = True`r`nif bUsePUPDMD = False then Exit Sub"
        $gotg.PupSwitch | Should Be 'bUsePUPDMD=auto'
        $gotg.PupSwitchOn | Should Be $null
        $jp = Get-PinballTableScriptFact -Text "Dim usePUP: usePUP = true ' set false to not use PuP`r`nusePUP=false"
        $jp.PupSwitch | Should Be 'usePUP=auto'
        $const = Get-PinballTableScriptFact -Text "Const HasPuP = false  'False=FlexDMD`r`nIf HasPuP=False then exit Sub"
        $const.PupSwitch | Should Be 'HasPuP=False'
        $const.PupSwitchOn | Should Be $false
    }

    It 'reads the script of a real OLE table file and reports a file that is none' {
        $p = & $script:newTable -Path (Join-Path $TestDrive 'one\Table.vpx') -Script "Const cGameName = `"abc_l1`""
        $r = Read-PinballTableScript -Path $p
        $r.Error | Should Be ''
        @($r.GameName) | Should Be @('abc_l1')
        [IO.File]::WriteAllText((Join-Path $TestDrive 'one\Bad.vpx'), 'x')
        (Read-PinballTableScript -Path (Join-Path $TestDrive 'one\Bad.vpx')).Error | Should Match 'not a Visual Pinball table'
    }
}

Describe 'Pinball DMD audit: sections of DmdDevice.ini' {
    It 'lists table sections with virtualdmd keys only, never the global [virtualdmd]' {
        $s = @(Get-PinballDmdSection -Text "[virtualdmd]`r`nleft = 1`r`n[a]`r`nvirtualdmd enabled = false`r`n[b]`r`nvirtualdmd.left = 5`r`nvirtualdmd.width = 6`r`n[c]`r`npindmd2 enabled = false`r`n[d]`r`nvirtualdmd enabled = true")
        @($s | ForEach-Object { $_.Section }) | Should Be @('a', 'b', 'd')
        ($s | Where-Object Section -eq 'a').Kind | Should Be 'Off'
        ($s | Where-Object Section -eq 'b').Kind | Should Be 'Position'
        ($s | Where-Object Section -eq 'd').Kind | Should Be 'On'
    }
}

Describe 'Pinball DMD audit: verdicts' {
    Set-KitCulture -Culture 'en-US'
    $fx = New-DmdAuditFixture 'audit'
    $before = Get-DmdTreeHash $fx.Root
    $a = Get-PinballDmdAudit -Root $fx.Root

    It 'reads every table and names the one it cannot read' {
        $a.TableCount | Should Be 13
        @($a.Unreadable | ForEach-Object { $_.Table }) | Should Be @('Broken.vpx')
    }

    It 'a ROM table without a pack and a table that switches PuP off are NoPup' {
        (Get-Row $a 'romnopack').Verdict | Should Be 'NoPup'
        (Get-Row $a 'scriptoff').Verdict | Should Be 'NoPup'
        (Get-Row $a 'scriptoff').Reason | Should Match 'usePUP=False'
    }

    It 'a pack switched off by dashes does not count, and the reason names it' {
        $r = Get-Row $a 'disabled'
        $r.Verdict | Should Be 'NoPup'
        $r.Reason | Should Match 'disabled-----'
        (Get-Row $a 'flexonly').Verdict | Should Be 'NoPup'
        (Get-Row $a 'romoff').Verdict | Should Be 'NoPup'
        (Get-Row $a 'romoff').Reason | Should Match 'romoff---'
    }

    It 'a ROM pack and a script with its own pack are Ok' {
        (Get-Row $a 'rompack').Verdict | Should Be 'Ok'
        (Get-Row $a 'scriptpup').Verdict | Should Be 'Ok'
    }

    It 'DMD off is Ok when PuP draws the score, Unclear when it does not' {
        (Get-Row $a 'drawsscore').Verdict | Should Be 'Ok'
        (Get-Row $a 'offnoscore').Verdict | Should Be 'Unclear'
        (Get-Row $a 'autodetect').Verdict | Should Be 'Ok'
    }

    It 'two tables with different answers make Mixed, a name without a table makes Orphan' {
        (Get-Row $a 'shared').Verdict | Should Be 'Mixed'
        @((Get-Row $a 'shared').Tables).Count | Should Be 2
        (Get-Row $a 'nosuchtable').Verdict | Should Be 'Orphan'
        (Get-Row $a 'nosuchtable').Reason | Should Match '1 table'
    }

    It 'sections that only switch the DMD on, or carry no virtualdmd key, are no findings' {
        Get-Row $a 'onlyon' | Should Be $null
        Get-Row $a 'otherkey' | Should Be $null
        $a.Count.NoPup | Should Be 5
    }

    It 'changes nothing' {
        Get-DmdTreeHash $fx.Root | Should Be $before
    }
}

Describe 'Pinball DMD audit: repair' {
    Set-KitCulture -Culture 'en-US'
    Mock -ModuleName RetroCabinetKit.Pinball Assert-PinballProcessesClosed { }

    It 'plans only NoPup sections and writes nothing without -Apply' {
        $fx = New-DmdAuditFixture 'plan'
        $before = Get-DmdTreeHash $fx.Root
        $plan = Invoke-PinballDmdRepair -Root $fx.Root -Section 'romnopack', 'scriptpup', 'nosuchtable', 'missing'
        $plan.Status | Should Be 'Plan'
        @($plan.Ready | ForEach-Object { $_.Section }) | Should Be @('romnopack')
        @($plan.Pending | ForEach-Object { $_.Verdict }) | Should Be @('Ok', 'Orphan', 'Missing')
        Get-DmdTreeHash $fx.Root | Should Be $before
    }

    It 'removes the virtualdmd lines of every NoPup section, keeps everything else and the encoding' {
        $fx = New-DmdAuditFixture 'apply'
        $done = Invoke-PinballDmdRepair -Root $fx.Root -Apply -BackupDir $fx.Backup
        $done.Status | Should Be 'Written'
        @($done.Ready | ForEach-Object { $_.Section } | Sort-Object) | Should Be @('disabled', 'flexonly', 'romnopack', 'romoff', 'scriptoff')
        @($done.Removed).Count | Should Be 17
        Test-Path -LiteralPath $done.Backup | Should Be $true

        $bytes = [IO.File]::ReadAllBytes($fx.Ini)
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should Be $true
        $text = [Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
        $text | Should Not Match '\[romnopack\]'
        $text | Should Not Match '\[scriptoff\]'
        $text | Should Match '\[flexonly\]\r\npin2dmd enabled = false'
        $text | Should Match '\[scriptpup\]\r\nvirtualdmd left = 10'
        $text | Should Match '\[shared\]'
        $text | Should Match '\[nosuchtable\]'
        $text | Should Match '\[virtualdmd\]\r\nenabled = true\r\nleft = 100'
        ($text -split "`r`n" | Where-Object { $_ -match "`n" }).Count | Should Be 0
    }

    It 'a second run finds nothing left to do' {
        $fx = New-DmdAuditFixture 'twice'
        $null = Invoke-PinballDmdRepair -Root $fx.Root -Apply -BackupDir $fx.Backup
        $again = Invoke-PinballDmdRepair -Root $fx.Root -Apply -BackupDir $fx.Backup
        $again.Status | Should Be 'Skipped'
        @($again.Ready).Count | Should Be 0
    }

    It 'refuses the whole write when a planned section changed after the plan, and leaves the file alone' {
        $fx = New-DmdAuditFixture 'drift'
        $audit = Get-PinballDmdAudit -Root $fx.Root
        $changed = ([IO.File]::ReadAllText($fx.Ini)) -replace '\[romnopack\]\r\nvirtualdmd left = 10', "[romnopack]`r`nvirtualdmd left = 11"
        [IO.File]::WriteAllText($fx.Ini, $changed, (New-Object Text.UTF8Encoding($true)))
        $before = (Get-FileHash -LiteralPath $fx.Ini).Hash
        { Invoke-PinballDmdRepair -Root $fx.Root -Audit $audit -Apply -BackupDir $fx.Backup } | Should Throw 'romnopack'
        (Get-FileHash -LiteralPath $fx.Ini).Hash | Should Be $before
        Test-Path -LiteralPath $fx.Backup | Should Be $false
    }
}
