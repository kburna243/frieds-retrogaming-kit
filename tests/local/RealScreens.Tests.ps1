$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1') -Force

# Runs only with tests\Run-Tests.ps1 -Local. Rebuilds the screen files of a real cabinet from the measured
# values in tests\fixtures-local\schema.out (PinUpPlayer.ini, ScreenRes.txt, VPinMAME DmdDevice.ini, FP and VPX
# registry) plus a COPY of the real Popper database, all at runtime in TestDrive and a test key. No real value
# is written into this file. Expectation: mode "Keep" finds 0 changes and every file stays byte-identical.
$fixtures = Join-Path $kitRoot 'tests\fixtures-local'
$schema = Join-Path $fixtures 'schema.out'
$realDb = Join-Path $fixtures 'PUPDatabase-real.db'
$testKey = 'HKCU:\Software\retro-cabinet-kit-test-local-screens'

# Lines of the schema.out block whose header matches $Pattern (up to the next "########" or "== " line).
function Get-SchemaBlock([string[]] $Lines, [string] $Pattern) {
    $in = $false
    foreach ($l in $Lines) {
        if ($l -match '^(########|== )') { $in = $l -match $Pattern; continue }
        if ($in) { $l }
    }
}

function Get-SchemaPairs([string[]] $Block) {
    $h = [ordered]@{}
    foreach ($l in $Block) { if ($l -match '^\s*([^=;\[]+?)\s*=\s*(.*)$') { $h[$Matches[1]] = $Matches[2].Trim() } }
    $h
}

function Get-Hash([string] $Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }
function Get-KeyDump([string] $Key) { $k = Get-Item -LiteralPath $Key; ($k.GetValueNames() | Sort-Object | ForEach-Object { "$_=$($k.GetValue($_))" }) -join ';' }

Describe 'Screens on a real cabinet (local fixture): Keep changes nothing' {
    Set-KitCulture -Culture 'en-US'
    AfterAll { if (Test-Path -LiteralPath $testKey) { Remove-Item -LiteralPath $testKey -Recurse -Force } }

    It 'has the local fixtures' {
        $schema | Should Exist
        $realDb | Should Exist
    }

    $lines = [IO.File]::ReadAllLines($schema, [Text.Encoding]::UTF8)
    $dir = Join-Path $TestDrive 'real'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $p = @{
        Popper       = Join-Path $dir 'PUPDatabase.db'
        PinUpPlayer  = Join-Path $dir 'PinUpPlayer.ini'
        VpmDmdDevice = Join-Path $dir 'DmdDevice.ini'
        FpDmdDevice  = Join-Path $dir 'missing-fp-DmdDevice.ini'
        ScreenRes    = Join-Path $dir 'ScreenRes.txt'
        VpxIni       = Join-Path $dir 'VPinballX.ini'
        VpxRegistry  = "$testKey\VP10"
        FpRegistry   = "$testKey\FP"
    }
    $crlf = "`r`n"
    Copy-Item -LiteralPath $realDb -Destination $p.Popper
    [IO.File]::WriteAllText($p.PinUpPlayer, ((@(Get-SchemaBlock $lines 'PinUpPlayer\.ini') -join $crlf) + $crlf), [Text.Encoding]::Default)
    [IO.File]::WriteAllText($p.ScreenRes, ((@(Get-SchemaBlock $lines 'Tables\\ScreenRes\.txt') | Select-Object -First 12) -join $crlf) + $crlf, [Text.Encoding]::Default)
    [IO.File]::WriteAllText($p.VpmDmdDevice, ((@(Get-SchemaBlock $lines 'VPinMAME DmdDevice') -join $crlf) + $crlf), [Text.Encoding]::Default)
    $vpx = Get-SchemaPairs @(Get-SchemaBlock $lines 'VPX Registry Player')
    [IO.File]::WriteAllText($p.VpxIni, ('[Player]' + $crlf + ((@($vpx.Keys | ForEach-Object { "$_ = $($vpx[$_])" })) -join $crlf) + $crlf), [Text.Encoding]::Default)
    if (Test-Path -LiteralPath $testKey) { Remove-Item -LiteralPath $testKey -Recurse -Force }
    foreach ($k in $vpx.Keys) { Set-KitRegistryValue -Path $p.VpxRegistry -Name $k -Value ([int]$vpx[$k]) -Type DWord }
    $fp = Get-SchemaPairs @(Get-SchemaBlock $lines 'FP GamePlayer Registry')
    foreach ($k in $fp.Keys) {
        $n = 0
        if ([int]::TryParse($fp[$k], [ref]$n)) { Set-KitRegistryValue -Path $p.FpRegistry -Name $k -Value $n -Type DWord }
        else { Set-KitRegistryValue -Path $p.FpRegistry -Name $k -Value $fp[$k] }
    }

    # Monitors derived from the measured values: playfield = PuP [INFO3] (main display), backglass monitor at the
    # [INFO2] origin (ScreenRes names it by number, 2), the third monitor at the [INFO1] origin, large enough for
    # every stored rectangle (Popper rows, PuP sections, virtual DMD, ScreenRes DMD).
    $pupText = [IO.File]::ReadAllText($p.PinUpPlayer, [Text.Encoding]::Default)
    $info = { param($s) $v = @('ScreenXPos', 'ScreenYPos', 'ScreenWidth', 'ScreenHeight' | ForEach-Object { [int](Get-PinballIniValue -Text $pupText -Section $s -Key $_) }); New-PinballRect $v[0] $v[1] $v[2] $v[3] }
    $pf = & $info 'INFO3'; $bg = & $info 'INFO2'; $dmd = & $info 'INFO1'
    $rects = @('INFO', 'INFO1', 'INFO2', 'INFO3', 'INFO5' | ForEach-Object { & $info $_ })
    $c = Open-KitSqlite -Path $p.Popper -ReadOnly
    try { $rects += @(Invoke-KitSqlQuery -Connection $c -Sql 'SELECT POSx, POSy, ScreenWidth, ScreenHeight FROM Screens WHERE ScreenWidth > 0' | ForEach-Object { New-PinballRect $_.POSx $_.POSy $_.ScreenWidth $_.ScreenHeight }) }
    finally { Close-KitSqlite $c }
    $dmdText = [IO.File]::ReadAllText($p.VpmDmdDevice)
    $rects += New-PinballRect ([int](Get-PinballIniValue $dmdText 'virtualdmd' 'left')) ([int](Get-PinballIniValue $dmdText 'virtualdmd' 'top')) ([int](Get-PinballIniValue $dmdText 'virtualdmd' 'width')) ([int](Get-PinballIniValue $dmdText 'virtualdmd' 'height'))
    $sr = [IO.File]::ReadAllLines($p.ScreenRes)
    $rects += New-PinballRect ($bg.X + [int]$sr[9]) ($bg.Y + [int]$sr[10]) ([int]$sr[7]) ([int]$sr[8])
    $right = ($rects | ForEach-Object { $_.X + $_.Width } | Measure-Object -Maximum).Maximum
    $bottom = ($rects | ForEach-Object { $_.Y + $_.Height } | Measure-Object -Maximum).Maximum
    $monitors = @(
        [pscustomobject]@{ DeviceName = '\\.\DISPLAY1'; X = $pf.X; Y = $pf.Y; Width = $pf.Width; Height = $pf.Height; Primary = $true; Scale = 100; RefreshRate = 60 }
        [pscustomobject]@{ DeviceName = '\\.\DISPLAY2'; X = $bg.X; Y = $bg.Y; Width = $bg.Width; Height = $bg.Height; Primary = $false; Scale = 100; RefreshRate = 60 }
        [pscustomobject]@{ DeviceName = '\\.\DISPLAY3'; X = $dmd.X; Y = $dmd.Y; Width = $right - $dmd.X; Height = $bottom - $dmd.Y; Primary = $false; Scale = 100; RefreshRate = 60 }
    )

    It 'Keep finds 0 changes, writes nothing and leaves every file and key identical' {
        $files = 'Popper', 'PinUpPlayer', 'VpmDmdDevice', 'ScreenRes', 'VpxIni'
        $before = @($files | ForEach-Object { Get-Hash $p[$_] }) + (Get-KeyDump $p.VpxRegistry) + (Get-KeyDump $p.FpRegistry)
        $originalDb = Get-Hash $realDb
        $layout = New-PinballScreenLayout -Monitors $monitors
        $targets = @(Get-PinballScreenTarget -Paths $p)
        $plan = @(Get-PinballScreenPlan -Layout $layout -Targets $targets -Mode Keep)
        foreach ($line in Format-PinballScreenPlan -Plan $plan) { Write-Host "    $line" }
        @($plan | Where-Object { $_.Exists }).Count | Should Be 7
        Get-PinballScreenChangeCount -Plan $plan | Should Be 0
        @(Invoke-PinballScreenPlan -Plan $plan -Layout $layout -BackupDir (Join-Path $TestDrive 'backups') -Confirm:$false).Count | Should Be 0
        $after = @($files | ForEach-Object { Get-Hash $p[$_] }) + (Get-KeyDump $p.VpxRegistry) + (Get-KeyDump $p.FpRegistry)
        ($after -join '|') | Should BeExactly ($before -join '|')
        Get-Hash $realDb | Should Be $originalDb
    }

    It 'reads the real ScreenRes display number and the DMD relative to the backglass monitor' {
        $t = @(Get-PinballScreenTarget -Paths @{ ScreenRes = $p.ScreenRes } | Where-Object Name -eq 'ScreenRes')
        $r = Read-PinballScreenTarget -Target $t[0] -Monitors $monitors
        $r['B2S.Backglass'].X | Should Be $bg.X
        $r['B2S.DMD'].X | Should Be ($bg.X + [int]$sr[9])
        Test-PinballRectInDesktop -Rect $r['B2S.DMD'] -Monitors $monitors | Should Be $true
    }
}
