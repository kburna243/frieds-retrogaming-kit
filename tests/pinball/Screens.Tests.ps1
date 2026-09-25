$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1') -Force
$golden = Join-Path $PSScriptRoot 'golden'
$steps = Join-Path $kitRoot 'pinball\steps'

# Test keys only; the real VP10 / Future Pinball keys are never touched.
$testKey = 'HKCU:\Software\retro-cabinet-kit-test-screens'

function New-Mon([int] $N, [int] $X, [int] $Y, [int] $W, [int] $H, [switch] $Primary, [int] $Scale = 100) {
    [pscustomobject]@{ DeviceName = "\\.\DISPLAY$N"; X = $X; Y = $Y; Width = $W; Height = $H; Primary = [bool]$Primary; Scale = $Scale; RefreshRate = 60 }
}
# Synthetic 3-monitor cabinet: playfield, backglass right of it, DMD right of that.
function Get-ThreeMonitors { @((New-Mon 1 0 0 1920 1080 -Primary), (New-Mon 2 1920 0 1280 1024), (New-Mon 3 3200 0 1366 768)) }
function Get-Hash([string] $Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Get-Bytes([string] $Path) { [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path)) }

function New-PopperDb([string] $Path) {
    New-Item -ItemType Directory -Path (Split-Path $Path) -Force | Out-Null
    $c = Open-KitSqlite -Path $Path -Create
    try {
        $null = Invoke-KitSqlNonQuery -Connection $c -Sql 'CREATE TABLE Screens (ScreenID INTEGER PRIMARY KEY AUTOINCREMENT, ScreenName VARCHAR (50) NOT NULL, ScreenDisplay VARCHAR (50) NOT NULL, POSx INTEGER NOT NULL, POSy INTEGER NOT NULL, ScreenWidth INTEGER NOT NULL, ScreenHeight INTEGER NOT NULL, Rotation INTEGER DEFAULT (0))'
        # IDs deliberately in a different order than Popper's own: only the NAME may count.
        foreach ($r in @(
            @{ id = 1; n = 'Menu'; x = 3200; y = 0; w = 1366; h = 768 }
            @{ id = 2; n = 'DMD'; x = 3200; y = 2000; w = 1366; h = 768 }
            @{ id = 3; n = 'BackGlass'; x = 1920; y = 0; w = 1280; h = 1024 }
            @{ id = 4; n = 'Table'; x = 0; y = 0; w = 1920; h = 1080 }
            @{ id = 5; n = 'Topper'; x = 0; y = 0; w = 0; h = 0 })) {
            $null = Invoke-KitSqlNonQuery -Connection $c -Parameters $r -Sql "INSERT INTO Screens(ScreenID, ScreenName, ScreenDisplay, POSx, POSy, ScreenWidth, ScreenHeight) VALUES (@id, @n, @n, @x, @y, @w, @h)"
        }
    } finally { Close-KitSqlite $c }
}

function Get-PopperRect([string] $Path, [string] $Name) {
    $c = Open-KitSqlite -Path $Path -ReadOnly
    try { $r = @(Invoke-KitSqlQuery -Connection $c -Parameters @{ n = $Name } -Sql 'SELECT POSx, POSy, ScreenWidth, ScreenHeight FROM Screens WHERE ScreenName = @n')[0] }
    finally { Close-KitSqlite $c }
    '{0},{1} {2}x{3}' -f $r.POSx, $r.POSy, $r.ScreenWidth, $r.ScreenHeight
}

# Copies the golden inputs + a synthetic database into $Dir, fills the test keys; returns the -Paths table.
function New-ScreenFixture([string] $Dir) {
    New-Item -ItemType Directory -Path $Dir -Force | Out-Null
    $p = @{
        Popper       = Join-Path $Dir 'PUPDatabase.db'
        PinUpPlayer  = Join-Path $Dir 'PinUpPlayer.ini'
        VpmDmdDevice = Join-Path $Dir 'VpmDmdDevice.ini'
        FpDmdDevice  = Join-Path $Dir 'FpDmdDevice.ini'
        ScreenRes    = Join-Path $Dir 'ScreenRes.txt'
        VpxIni       = Join-Path $Dir 'VPinballX.ini'
        VpxRegistry  = "$testKey\VP10"
        FpRegistry   = "$testKey\FP"
    }
    New-PopperDb $p.Popper
    Copy-Item (Join-Path $golden 'PinUpPlayer.in.ini') $p.PinUpPlayer
    Copy-Item (Join-Path $golden 'VpmDmdDevice.in.ini') $p.VpmDmdDevice
    Copy-Item (Join-Path $golden 'FpDmdDevice.in.ini') $p.FpDmdDevice
    Copy-Item (Join-Path $golden 'ScreenRes.in.txt') $p.ScreenRes
    Copy-Item (Join-Path $golden 'VPinballX.in.ini') $p.VpxIni
    if (Test-Path -LiteralPath $testKey) { Remove-Item -LiteralPath $testKey -Recurse -Force }
    Set-KitRegistryValue -Path $p.VpxRegistry -Name 'Display' -Value 0 -Type DWord
    Set-KitRegistryValue -Path $p.VpxRegistry -Name 'FullScreen' -Value 1 -Type DWord
    Set-KitRegistryValue -Path $p.FpRegistry -Name 'PlayfieldMonitorID' -Value '\\.\DISPLAY1'
    Set-KitRegistryValue -Path $p.FpRegistry -Name 'Width' -Value 1920 -Type DWord
    Set-KitRegistryValue -Path $p.FpRegistry -Name 'Height' -Value 1080 -Type DWord
    Set-KitRegistryValue -Path $p.FpRegistry -Name 'BackboxMonitorID' -Value '\\.\DISPLAY7'
    Set-KitRegistryValue -Path $p.FpRegistry -Name 'SecondMonitorWidth' -Value 1280 -Type DWord
    Set-KitRegistryValue -Path $p.FpRegistry -Name 'SecondMonitorHeight' -Value 1024 -Type DWord
    Set-KitRegistryValue -Path $p.FpRegistry -Name 'FullScreen' -Value 1 -Type DWord
    $p
}

Describe 'Screens: layout rules and lock' {
    Set-KitCulture -Culture 'en-US'

    It 'accepts the official layout (100 %, playfield = main display, others right of it)' {
        @(Test-PinballMonitorLayout -Monitors (Get-ThreeMonitors)).Count | Should Be 0
    }

    It 'refuses scaling other than 100 % with an explanation' {
        $m = Get-ThreeMonitors; $m[2].Scale = 125
        $v = @(Test-PinballMonitorLayout -Monitors $m)
        $v.Code | Should Be 'Scaling'
        $v[0].Message | Should Match '125 %'
    }

    It 'refuses negative coordinates and monitors left of the playfield' {
        $m = @((New-Mon 1 0 0 1920 1080 -Primary), (New-Mon 2 -1280 0 1280 1024))
        (@(Test-PinballMonitorLayout -Monitors $m).Code | Sort-Object) -join ',' | Should Be 'LeftOrAbove,Negative'
    }

    It 'refuses a playfield that is not the main display (and a main display left of it)' {
        $codes = @(Test-PinballMonitorLayout -Monitors (Get-ThreeMonitors) -Roles @{ Playfield = '\\.\DISPLAY2' }).Code
        ($codes | Sort-Object) -join ',' | Should Be 'LeftOrAbove,PlayfieldNotPrimary'
    }

    It 'refuses a monitor above the playfield' {
        $m = @((New-Mon 1 0 600 1920 1080 -Primary), (New-Mon 2 0 0 1920 600))
        @(Test-PinballMonitorLayout -Monitors $m).Code | Should Be 'LeftOrAbove'
    }

    It 'locks the step in session 0 and in an unattended run' {
        Get-PinballScreenLock -SessionId 0 | Should Match 'session 0'
        Get-PinballScreenLock -SessionId 1 -AnswerFile 'C:\answers.json' | Should Match 'answers.json'
        Get-PinballScreenLock -SessionId 1 | Should BeNullOrEmpty
    }
}

Describe 'Screens: model and name mapping' {
    Set-KitCulture -Culture 'en-US'
    $layout = New-PinballScreenLayout -Monitors (Get-ThreeMonitors)

    It 'assigns default roles by position and proposes the role area per consumer' {
        $layout.Roles.Playfield | Should Be '\\.\DISPLAY1'
        $layout.Roles.Backglass | Should Be '\\.\DISPLAY2'
        $layout.Roles.DMD | Should Be '\\.\DISPLAY3'
        $layout.Roles.ContainsKey('Topper') | Should Be $false
        Format-PinballRect (Get-PinballConsumerRect -Layout $layout -Consumer 'PuP.INFO1') | Should Be '3200,0 1366x768'
        Get-PinballConsumerRect -Layout $layout -Consumer 'PuP.INFO' | Should BeNullOrEmpty
    }

    It 'anchors monitor-bound programs (FP, VPX) at the monitor origin of a measured window' {
        $l = New-PinballScreenLayout -Monitors (Get-ThreeMonitors) -Windows @{ 'FP.Backbox' = (New-PinballRect 2000 100 1000 700) }
        Format-PinballRect (Get-PinballConsumerRect -Layout $l -Consumer 'FP.Backbox') | Should Be '1920,0 1000x700'
    }

    It 'matches Popper rows by ScreenName even when the IDs are swapped' {
        $db = Join-Path $TestDrive 'names\PUPDatabase.db'
        New-PopperDb $db
        $t = Get-PinballScreenTarget -Paths @{ Popper = $db } | Where-Object Name -eq 'Popper'
        $r = Read-PinballScreenTarget -Target $t -Monitors (Get-ThreeMonitors)
        Format-PinballRect $r['Popper.Table'] | Should Be '0,0 1920x1080'
        Format-PinballRect $r['Popper.Menu'] | Should Be '3200,0 1366x768'
        Format-PinballRect $r['Popper.BackGlass'] | Should Be '1920,0 1280x1024'
    }

    It 'matches PuP sections by name: [INFO]=Topper, [INFO1]=DMD, [INFO2]=BG, [INFO3]=PF, [INFO5]=FullDMD' {
        $ini = Join-Path $TestDrive 'names\PinUpPlayer.ini'
        [IO.File]::WriteAllText($ini, "[INFO5]`r`nScreenXPos=5`r`nScreenYPos=5`r`nScreenWidth=5`r`nScreenHeight=5`r`n[INFO3]`r`nScreenXPos=3`r`nScreenYPos=3`r`nScreenWidth=3`r`nScreenHeight=3`r`n[INFO]`r`nScreenXPos=9`r`nScreenYPos=9`r`nScreenWidth=9`r`nScreenHeight=9`r`n")
        $t = Get-PinballScreenTarget -Paths @{ PinUpPlayer = $ini } | Where-Object Name -eq 'PinUpPlayer'
        $r = Read-PinballScreenTarget -Target $t -Monitors (Get-ThreeMonitors)
        Format-PinballRect $r['PuP.INFO3'] | Should Be '3,3 3x3'
        Format-PinballRect $r['PuP.INFO5'] | Should Be '5,5 5x5'
        Format-PinballRect $r['PuP.INFO'] | Should Be '9,9 9x9'
        $r['PuP.INFO1'] | Should BeNullOrEmpty
    }
}

Describe 'Screens: writers' {
    Set-KitCulture -Culture 'en-US'
    AfterAll { if (Test-Path -LiteralPath $testKey) { Remove-Item -LiteralPath $testKey -Recurse -Force } }

    It 'Keep: writes the expected files (golden), fixes only missing/outside values, keeps FullScreen' {
        $p = New-ScreenFixture (Join-Path $TestDrive 'golden-run')
        # One measured window: the VPinMAME virtual DMD.
        $layout = New-PinballScreenLayout -Monitors (Get-ThreeMonitors) -Windows @{ 'VPinMAME.DMD' = (New-PinballRect 3250 50 1200 400) }
        $targets = @(Get-PinballScreenTarget -Paths $p)
        $plan = @(Get-PinballScreenPlan -Layout $layout -Targets $targets -Mode Keep)
        $written = @(Invoke-PinballScreenPlan -Plan $plan -Layout $layout -BackupDir (Join-Path $TestDrive 'golden-run\backups') -Confirm:$false)
        ($written.Target | Sort-Object) -join ',' | Should Be 'FpDmdDevice,FpRegistry,PinUpPlayer,Popper,ScreenRes,VpmDmdDevice,VpxIni,VpxRegistry'
        foreach ($name in 'PinUpPlayer', 'VpmDmdDevice', 'FpDmdDevice', 'VPinballX', 'ScreenRes') {
            $key = if ($name -eq 'VPinballX') { 'VpxIni' } else { $name }
            $ext = [IO.Path]::GetExtension($p[$key])
            Get-Bytes $p[$key] | Should BeExactly (Get-Bytes (Join-Path $golden "$name.expected$ext"))
        }
        Get-PopperRect $p.Popper 'DMD' | Should Be '3200,0 1366x768'
        Get-PopperRect $p.Popper 'Table' | Should Be '0,0 1920x1080'
        Get-PopperRect $p.Popper 'Topper' | Should Be '0,0 0x0'
        Get-KitRegistryValue -Path $p.VpxRegistry -Name 'Width' | Should Be 1920
        Get-KitRegistryValue -Path $p.VpxRegistry -Name 'FullScreen' | Should Be 1
        Get-KitRegistryValue -Path $p.FpRegistry -Name 'BackboxMonitorID' | Should BeExactly '\\.\DISPLAY2'
        Get-KitRegistryValue -Path $p.FpRegistry -Name 'SecondMonitorHeight' | Should Be 1024
        Get-KitRegistryValue -Path $p.FpRegistry -Name 'PlayfieldMonitorID' | Should BeExactly '\\.\DISPLAY1'
    }

    It 'Keep on valid files changes nothing: 0 changes and byte-identical files' {
        $p = New-ScreenFixture (Join-Path $TestDrive 'keep')
        $layout = New-PinballScreenLayout -Monitors (Get-ThreeMonitors)
        $targets = @(Get-PinballScreenTarget -Paths $p)
        $null = Invoke-PinballScreenPlan -Plan @(Get-PinballScreenPlan -Layout $layout -Targets $targets) -Layout $layout -BackupDir (Join-Path $TestDrive 'keep\backups') -Confirm:$false
        $files = 'Popper', 'PinUpPlayer', 'VpmDmdDevice', 'FpDmdDevice', 'ScreenRes', 'VpxIni'
        $before = @($files | ForEach-Object { Get-Hash $p[$_] })
        $plan = @(Get-PinballScreenPlan -Layout $layout -Targets $targets -Mode Keep)
        Get-PinballScreenChangeCount -Plan $plan | Should Be 0
        @(Invoke-PinballScreenPlan -Plan $plan -Layout $layout -Confirm:$false).Count | Should Be 0
        @($files | ForEach-Object { Get-Hash $p[$_] }) -join ',' | Should Be ($before -join ',')
    }

    It 'keeps INI comments, order and unrelated sections' {
        $text = [IO.File]::ReadAllText((Join-Path $golden 'VpmDmdDevice.in.ini'))
        $r = Set-PinballIniValue -Text $text -Section 'virtualdmd' -Values ([ordered]@{ left = 1; top = 2 }) -Separator ' = '
        $r.Count | Should Be 2
        $r.Text | Should Match '; x-axis of the window position\r\nleft = 1\r\n'
        $r.Text | Should Match '\[afm_113b\]\r\nvirtualdmd left = 100'
        ($r.Text -split "`r`n").Count | Should Be ($text -split "`r`n").Count
    }

    It 'ScreenRes: DMD relative to the backglass monitor origin, display as @X' {
        $dir = Join-Path $TestDrive 'screenres'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $file = Join-Path $dir 'ScreenRes.txt'
        [IO.File]::WriteAllText($file, "1920`r`n1080`r`n1280`r`n1024`r`n2`r`n0`r`n0`r`n1366`r`n768`r`n1280`r`n0`r`n0`r`n")
        $monitors = @((New-Mon 1 0 0 1920 1080 -Primary), (New-Mon 2 1920 40 1280 1024), (New-Mon 3 3200 500 1366 768))
        $t = @(Get-PinballScreenTarget -Paths @{ ScreenRes = $file } | Where-Object Name -eq 'ScreenRes')
        # Display "2" = \\.\DISPLAY2 at 1920/40: the DMD sits at 1920+1280 / 40+0.
        $r = Read-PinballScreenTarget -Target $t[0] -Monitors $monitors
        Format-PinballRect $r['B2S.DMD'] | Should Be '3200,40 1366x768'
        $layout = New-PinballScreenLayout -Monitors $monitors -Windows @{ 'B2S.DMD' = (New-PinballRect 3300 600 1000 300) }
        $null = Invoke-PinballScreenPlan -Plan @(Get-PinballScreenPlan -Layout $layout -Targets $t) -Layout $layout -Confirm:$false
        $lines = [IO.File]::ReadAllLines($file)
        $lines[4] | Should BeExactly '2'
        ($lines[7..10] -join ',') | Should Be '1000,300,1380,560'
        $layout.Roles.Backglass = '\\.\DISPLAY3'
        $null = Invoke-PinballScreenPlan -Plan @(Get-PinballScreenPlan -Layout $layout -Targets $t -Mode Replace) -Layout $layout -Confirm:$false
        $lines = [IO.File]::ReadAllLines($file)
        ($lines[2..10] -join ',') | Should Be '1366,768,@3200,0,0,1000,300,100,100'
    }

    It 'VPX writer sets only Display/Width/Height and never FullScreen (ini and registry)' {
        $p = New-ScreenFixture (Join-Path $TestDrive 'vpx')
        $monitors = Get-ThreeMonitors
        $layout = New-PinballScreenLayout -Monitors $monitors -Windows @{ 'VPX.Playfield' = (New-PinballRect 0 0 1600 900) }
        $t = @(Get-PinballScreenTarget -Paths $p | Where-Object { $_.Name -in 'VpxIni', 'VpxRegistry' })
        $null = Invoke-PinballScreenPlan -Plan @(Get-PinballScreenPlan -Layout $layout -Targets $t) -Layout $layout -BackupDir (Join-Path $TestDrive 'vpx\backups') -Confirm:$false
        $text = [IO.File]::ReadAllText($p.VpxIni)
        $text | Should Match 'FullScreen = 1\r\n'
        $text | Should Match 'Width = 1600\r\nHeight = 900\r\n'
        Get-KitRegistryValue -Path $p.VpxRegistry -Name 'FullScreen' | Should Be 1
        Get-KitRegistryValue -Path $p.VpxRegistry -Name 'Height' | Should Be 900
        @((Get-Item -LiteralPath $p.VpxRegistry).GetValueNames() | Sort-Object) -join ',' | Should Be 'Display,FullScreen,Height,Width'
    }

    It 'plausibility: a value outside the desktop is proposed anew, even in Keep mode' {
        $monitors = Get-ThreeMonitors
        Test-PinballRectInDesktop -Rect (New-PinballRect 3210 2000 900 14) -Monitors $monitors | Should Be $false
        Test-PinballRectInDesktop -Rect (New-PinballRect 3200 0 1366 768) -Monitors $monitors | Should Be $true
        $p = New-ScreenFixture (Join-Path $TestDrive 'plaus')
        $t = @(Get-PinballScreenTarget -Paths $p | Where-Object Name -eq 'PinUpPlayer')
        $c = @((Get-PinballScreenPlan -Layout (New-PinballScreenLayout -Monitors $monitors) -Targets $t).Changes | Where-Object Consumer -eq 'PuP.INFO1')
        $c[0].Reason | Should Be 'Outside'
        Format-PinballRect $c[0].New | Should Be '3200,0 1366x768'
    }

    It 'Popper Screens are written through a safe database copy (backup, integrity kept)' {
        $p = New-ScreenFixture (Join-Path $TestDrive 'popper')
        $layout = New-PinballScreenLayout -Monitors (Get-ThreeMonitors)
        $t = @(Get-PinballScreenTarget -Paths $p | Where-Object Name -eq 'Popper')
        $before = Get-Hash $p.Popper
        $w = @(Invoke-PinballScreenPlan -Plan @(Get-PinballScreenPlan -Layout $layout -Targets $t) -Layout $layout -Confirm:$false)
        $w[0].Backup | Should Match 'PUPDatabase\.db\.bak_screens_'
        Get-Hash $w[0].Backup | Should Be $before
        $c = Open-KitSqlite -Path $p.Popper -ReadOnly
        try { (@(Invoke-KitSqlQuery -Connection $c -Sql 'PRAGMA integrity_check'))[0].integrity_check | Should Be 'ok' } finally { Close-KitSqlite $c }
        Get-PopperRect $p.Popper 'DMD' | Should Be '3200,0 1366x768'
    }

    It 'the way back restores every written target' {
        $p = New-ScreenFixture (Join-Path $TestDrive 'undo')
        $files = 'Popper', 'PinUpPlayer', 'VpmDmdDevice', 'FpDmdDevice', 'ScreenRes', 'VpxIni'
        $before = @($files | ForEach-Object { Get-Hash $p[$_] })
        $layout = New-PinballScreenLayout -Monitors (Get-ThreeMonitors)
        $w = @(Invoke-PinballScreenPlan -Plan @(Get-PinballScreenPlan -Layout $layout -Targets @(Get-PinballScreenTarget -Paths $p) -Mode Replace) -Layout $layout -BackupDir (Join-Path $TestDrive 'undo\backups') -Confirm:$false)
        Get-KitRegistryValue -Path $p.FpRegistry -Name 'BackboxMonitorID' | Should BeExactly '\\.\DISPLAY2'
        Restore-PinballScreenBackup -Written $w -Confirm:$false
        @($files | ForEach-Object { Get-Hash $p[$_] }) -join ',' | Should Be ($before -join ',')
        Get-KitRegistryValue -Path $p.FpRegistry -Name 'BackboxMonitorID' | Should BeExactly '\\.\DISPLAY7'
    }

    It 'removes foreign DMD positions only from table sections, with a dry run first' {
        $file = Join-Path $TestDrive 'tabledmd.ini'
        Copy-Item (Join-Path $golden 'VpmDmdDevice.in.ini') $file
        $hash = Get-Hash $file
        @(Remove-PinballTableDmdPosition -Path $file -WhatIf).Count | Should Be 4
        Get-Hash $file | Should Be $hash
        $removed = @(Remove-PinballTableDmdPosition -Path $file -Confirm:$false)
        ($removed | ForEach-Object { $_.Section } | Sort-Object -Unique) | Should Be 'afm_113b'
        $text = [IO.File]::ReadAllText($file)
        $text | Should Not Match 'virtualdmd left'
        $text | Should Match '\[virtualdmd\]\r\nenabled = true'
        $text | Should Match 'left = 3210'
        @(Remove-PinballTableDmdPosition -Path $file -Confirm:$false).Count | Should Be 0
    }

    It 'value card: FX3 unrotated, Pinball Arcade shifted by playfield width - height' {
        $card = @(Get-PinballValueCard -Layout (New-PinballScreenLayout -Monitors (Get-ThreeMonitors))) -join "`n"
        $card | Should Match 'Backglass\s+x=1920\s+y=0\s+w=1280\s+h=1024'
        $card | Should Match 'Backglass\s+x=1080\s+y=0\s+w=1280\s+h=1024'
        $card | Should Match 'DMD\s+x=2360\s+y=0'
    }
}

Describe 'Screens: steps 8 and 9 as stand-alone scripts' {
    Set-KitCulture -Culture 'en-US'
    AfterAll { if (Test-Path -LiteralPath $testKey) { Remove-Item -LiteralPath $testKey -Recurse -Force } }
    $state = Join-Path $TestDrive 'install-state.json'
    $common = @{ StatePath = $state; Culture = 'en-US' }

    It '8: dry run changes nothing, then writes and verifies; second run is skipped' {
        $p = New-ScreenFixture (Join-Path $TestDrive 'step8')
        $opt = @{ Paths = $p; Monitors = (Get-ThreeMonitors); BackupDir = (Join-Path $TestDrive 'step8\backups') }
        $hash = Get-Hash $p.PinUpPlayer
        (& "$steps\08-Screens.ps1" @common @opt -WhatIf).Status | Should Be 'Skipped'
        Get-Hash $p.PinUpPlayer | Should Be $hash
        $state | Should Not Exist
        (& "$steps\08-Screens.ps1" @common @opt).Status | Should Be 'Done'
        Get-Hash $p.PinUpPlayer | Should Not Be $hash
        @(Get-KitStateValue -Path $state -Key 'ScreenLastWritten').Count | Should Be 8
        (& "$steps\08-Screens.ps1" @common @opt).Status | Should Be 'Skipped'
    }

    It '8: refuses a scaled monitor and an unattended run' {
        $p = New-ScreenFixture (Join-Path $TestDrive 'step8b')
        $m = Get-ThreeMonitors; $m[1].Scale = 150
        (& "$steps\08-Screens.ps1" @common -Paths $p -Monitors $m).Status | Should Be 'NeedsUser'
        (& "$steps\08-Screens.ps1" @common -Paths $p -Monitors (Get-ThreeMonitors) -AnswerFile 'x.json').Status | Should Be 'NeedsUser'
    }

    It '9: final backup, autostart only when asked' {
        $root = Join-Path $TestDrive 'Cab'
        $pup = Join-Path $root 'vPinball\PinUPSystem'
        New-Item -ItemType Directory -Path $pup -Force | Out-Null
        New-PopperDb (Join-Path $pup 'PUPDatabase.db')
        [IO.File]::WriteAllText((Join-Path $pup 'PinUpPlayer.ini'), "[INFO]`r`n")
        [IO.File]::WriteAllText((Join-Path $pup 'RunWindowsStartup.bat'), "@echo off`r`necho ok> autostart_ran.txt`r`n")
        Set-KitRegistryValue -Path "$testKey\FP" -Name 'Width' -Value 1 -Type DWord
        $opt = @{ Root = $root; BackupDir = (Join-Path $TestDrive 'finish'); Paths = @{ VpxIni = (Join-Path $TestDrive 'none.ini') }; RegistryKeys = @("$testKey\FP") }
        $r = @(& "$steps\09-Finish.ps1" @common @opt)
        $r.Status | Should Be 'Done'
        $manifest = Get-KitBackupManifest -Path (Get-KitStateValue -Path $state -Key 'FinishBackup')
        @($manifest.Files).Count | Should Be 2
        @($manifest.Registry).Count | Should Be 1
        Join-Path $pup 'autostart_ran.txt' | Should Not Exist
        $r = @(& "$steps\09-Finish.ps1" @common @opt -EnableAutostart)
        ($r | ForEach-Object { "$($_.Name)=$($_.Status)" }) -join ',' | Should Be 'pinball-9-backup=Skipped,pinball-9-autostart=Done'
        Join-Path $pup 'autostart_ran.txt' | Should Exist
    }
}
