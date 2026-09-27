$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1') -Force
$builder = Join-Path $PSScriptRoot 'New-PinballYTestInstall.ps1'

function Get-PinballYUnmountedDrive {
    $mounted = @{}
    foreach ($d in [IO.DriveInfo]::GetDrives()) { $mounted[$d.Name.Substring(0, 1).ToUpperInvariant()] = $true }
    foreach ($l in @('Q', 'V', 'Y', 'Z', 'W', 'U', 'T', 'S', 'R', 'P', 'O', 'N')) {
        if (-not $mounted.ContainsKey($l)) { return $l }
    }
    throw 'no unmounted drive letter to test with'
}

# The installation AND the counterparts next to it: retargeting only means something for a copy whose content
# exists somewhere on this machine. Every path is computed from $TestDrive, never typed, so no detail of the
# test machine decides an outcome and no real cabinet folder is ever written by a test.
function New-PinballYRetargetFixture {
    $base = (Resolve-Path -LiteralPath $TestDrive).ProviderPath
    $foreign = Get-PinballYUnmountedDrive
    $root = & $builder -Root (Join-Path $base 'PinballY') -ForeignDrive $foreign -Retarget
    $target = Join-Path $base 'PinballYRetargetTarget'
    [pscustomobject]@{
        Root = $root; Drive = $root.Substring(0, 1); Foreign = $foreign; Target = $target
        Settings = Join-Path $root 'Settings.txt'
        Companion = Join-Path $root 'PINemHi\pinemhi.ini'
        Backup = Join-Path $base 'backups'
        Map = @(
            ("{0}:\Games={1}" -f $foreign, (Join-Path $target 'Games'))
            ("{0}:\Scripts={1}" -f $foreign, (Join-Path $target 'Scripts'))
            ('D:\Per\VisualPinball\VPinMame\nvram={0}' -f (Join-Path $target 'vpinmame\nvram'))
            ('D:\Games\Future Pinball\fpRAM={0}' -f (Join-Path $target 'futurepinball\fpRAM'))
        )
    }
}

function Get-PinballYPlanRow([object] $Rows, [string] $Key) { @($Rows | Where-Object { $_.Key -eq $Key })[0] }

# Every file of the installation with its hash: the only proof that a read or a refused write changed nothing.
function Get-PinballYTreeHash([string] $Root) {
    @(Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName |
        ForEach-Object { '{0}|{1}|{2}' -f $_.FullName, $_.Length, (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join ';'
}

# Writes the lines back with the file's own byte order mark, so a test can play the program that rewrites it.
function Set-PinballYTestFile([string] $Path, [object[]] $Lines) {
    $bytes = [Text.Encoding]::UTF8.GetBytes(($Lines -join ''))
    [IO.File]::WriteAllBytes($Path, ([Text.Encoding]::UTF8.GetPreamble() + $bytes))
}

Describe 'PinballY retarget: the map' {
    Set-KitCulture -Culture 'en-US'

    It 'applies the more specific pair before the general one' {
        $pairs = @(ConvertFrom-PinballYMap -Map @('R:=S:\Whole', 'R:\Scripts=S:\Narrow'))
        $pairs[0].Old | Should Be 'R:\Scripts'
        $pairs[1].Old | Should Be 'R:'
    }

    It 'takes a whole drive as a pair, because a copied cabinet usually keeps its folder names' {
        $pairs = @(ConvertFrom-PinballYMap -Map @('Q:=J:'))
        $pairs.Count | Should Be 1
        $pairs[0].Text | Should Be 'Q:=J:'
    }

    It 'refuses a pair that is not Old=New with two absolute paths' {
        { $null = ConvertFrom-PinballYMap -Map @('nurEinPfad') } | Should Throw 'Old=New'
        { $null = ConvertFrom-PinballYMap -Map @('Q:\Games=relative\ordner') } | Should Throw 'Old=New'
        { $null = ConvertFrom-PinballYMap -Map @('   ') } | Should Throw 'Old=New'
    }

    It 'maps a value at a path boundary only' {
        $pairs = @(ConvertFrom-PinballYMap -Map @('Q:\Scripts=J:\Scripts'))
        (Convert-PinballYMapValue -Value 'Q:\Scripts\Run.exe' -Pairs $pairs).Value | Should Be 'J:\Scripts\Run.exe'
        # The folder that only STARTS with the same letters is other content and stays untouched.
        (Convert-PinballYMapValue -Value 'Q:\ScriptsOld\Run.exe' -Pairs $pairs) | Should Be $null
        # Case is not a boundary problem: a file spells a path as it likes.
        (Convert-PinballYMapValue -Value 'q:\scripts\Run.exe' -Pairs $pairs).Value | Should Be 'J:\Scripts\Run.exe'
    }

    It 'keeps a trailing separator, because a folder value is written with one' {
        $pairs = @(ConvertFrom-PinballYMap -Map @('D:\Per\VisualPinball\VPinMame\nvram=J:\Media\Pinball\VPinMame\nvram'))
        $mapped = Convert-PinballYMapValue -Value 'D:\Per\VisualPinball\VPinMame\nvram\' -Pairs $pairs
        $mapped.Value | Should Be 'J:\Media\Pinball\VPinMame\nvram\'
        $mapped.Bare | Should Be 'J:\Media\Pinball\VPinMame\nvram'
    }
}

Describe 'PinballY retarget: lines and their values' {
    Set-KitCulture -Culture 'en-US'

    It 'splits and joins a file exactly, whatever line endings it holds' {
        $mixed = "a`r`nb`nc`rd"
        $lines = @(Split-PinballYLine -Text $mixed)
        $lines.Count | Should Be 4
        ($lines -join '') | Should BeExactly $mixed
        (@(Split-PinballYLine -Text '')).Count | Should Be 0
        (@(Split-PinballYLine -Text 'nur eine zeile')).Count | Should Be 1
    }

    It 'counts the lines the way the settings reader counts them' {
        # The plan takes its line numbers from Get-PinballYSetting, the write from Split-PinballYLine. Two
        # readers of one file may not disagree about where a line is, or every later check is worthless.
        $fx = New-PinballYRetargetFixture
        $st = Get-PinballYSetting -Path $fx.Root
        $mine = @(Read-PinballYLine -Path $fx.Settings)
        $mine.Count | Should Be $st.Lines
        foreach ($s in @($st.Setting)) {
            (Get-PinballYLineKey -Line $mine[$s.Line - 1]) | Should Be $s.Key
            (Get-PinballYLineValue -Line $mine[$s.Line - 1]) | Should Be $s.Value
        }
    }

    It 'reads the value after the first separator, so a value may hold one itself' {
        (Get-PinballYLineValue -Line 'System1.Exe = Q:\a\b.exe') | Should Be 'Q:\a\b.exe'
        (Get-PinballYLineValue -Line 'System1.Parameters = -table="x=y"') | Should Be '-table="x=y"'
        (Get-PinballYLineValue -Line '#    "q:\my path\my program"') | Should Be ''
        (Get-PinballYLineKey -Line 'System1.Exe = Q:\a\b.exe') | Should Be 'System1.Exe'
        (Get-PinballYLineKey -Line 'nur text ohne zuweisung') | Should Be ''
    }

    It 'replaces a value and no other character of the line' {
        # The padding of the original is kept: a diff of the file has to show the path and nothing else.
        (Set-PinballYLineValue -Line "System1.Exe=  Q:\a\b.exe  `r`n" -Key 'System1.Exe' -Old 'Q:\a\b.exe' -New 'J:\c\d.exe') |
            Should BeExactly "System1.Exe=  J:\c\d.exe  `r`n"
        # Another line, or another value than planned: nothing comes back, and the caller refuses the file.
        (Set-PinballYLineValue -Line "System2.Exe=Q:\a\b.exe`r`n" -Key 'System1.Exe' -Old 'Q:\a\b.exe' -New 'J:\c\d.exe') | Should Be ''
        (Set-PinballYLineValue -Line "System1.Exe=Q:\other.exe`r`n" -Key 'System1.Exe' -Old 'Q:\a\b.exe' -New 'J:\c\d.exe') | Should Be ''
    }
}

Describe 'PinballY retarget: what becomes a plan' {
    Set-KitCulture -Culture 'en-US'
    $fx = New-PinballYRetargetFixture
    $plan = @(Get-PinballYRetargetPlan -Path $fx.Root -Pairs @(ConvertFrom-PinballYMap -Map $fx.Map))

    It 'plans the dead values of the settings file AND of the companion file' {
        @( $plan | Where-Object { $_.FileKind -eq 'Settings' }).Count | Should Be 3
        @( $plan | Where-Object { $_.FileKind -eq 'Companion' }).Count | Should Be 3
        @( $plan | Where-Object { $_.Status -eq 'Ready' }).Count | Should Be 5
        @( @($plan | Where-Object { $_.File -eq $fx.Companion }) | Where-Object { $_.Status -eq 'Ready' }).Count | Should Be 3
    }

    It 'never plans a value that resolves here, even when a pair would match it' {
        # System4.MediaDir is an absolute EXISTING path on the drive the map covers: a correct path is not
        # dirt, and a rewrite that "cleans up" is not this operation's job.
        (Get-PinballYPlanRow $plan 'System4.MediaDir') | Should Be $null
        (Get-PinballYPlanRow $plan 'System4.Exe') | Should Be $null
        @( @(Get-PinballYRetargetCandidate -Path $fx.Root) | Where-Object { $_.Key -eq 'System4.MediaDir' }).Count | Should Be 0
    }

    It 'never plans a token, a relative path or an empty value' {
        foreach ($key in 'System2.Exe', 'System3.TablePath', 'System2.TablePath', 'System7.MediaDir', 'System8.Exe') {
            (Get-PinballYPlanRow $plan $key) | Should Be $null
        }
    }

    It 'never plans the factory file or the rolling copies of the program' {
        foreach ($f in @($plan | ForEach-Object { $_.File } | Sort-Object -Unique)) {
            (Split-Path -Leaf $f) | Should Not Match 'DefaultSettings'
            (Split-Path -Leaf $f) | Should Not Match 'Settings backup'
        }
        # Both files hold the same dead path as the settings: they are there and they are not planned.
        (Select-String -LiteralPath (Join-Path $fx.Root 'DefaultSettings.txt') -Pattern 'Games' -SimpleMatch).Count | Should Be 1
        @( $plan | Where-Object { $_.File -like '*DefaultSettings*' }).Count | Should Be 0
    }

    It 'marks a value no pair covers as NoMap and says so' {
        $row = Get-PinballYPlanRow $plan 'System4.RunAfter'
        $row.Status | Should Be 'NoMap'
        $row.New | Should Be ''
        $row.Reason | Should Not Be ''
    }

    It 'plans a new path only when it exists on this machine' {
        $withMissing = @($fx.Map + ("{0}:\not-mounted-for-pinbally={1}" -f $fx.Drive, (Join-Path $fx.Target 'no-such-place')))
        $rows = @(Get-PinballYRetargetPlan -Path $fx.Root -Pairs @(ConvertFrom-PinballYMap -Map $withMissing))
        $row = Get-PinballYPlanRow $rows 'System4.RunAfter'
        $row.Status | Should Be 'NoTarget'
        # What it WOULD become is named, so a person can create the folder and run again.
        $row.Target | Should Be ((Join-Path $fx.Target 'no-such-place') + '\Game.exe')
        $row.Reason | Should Not Be ''
        # Ready rows are unaffected by a pair that leads nowhere.
        (Get-PinballYPlanRow $rows 'System5.Exe').Status | Should Be 'Ready'
    }

    It 'names the line, the key and the old value of every planned change' {
        $lines = @(Read-PinballYLine -Path $fx.Settings)
        foreach ($row in $plan) {
            $row.Line | Should BeGreaterThan 0
            $row.Key | Should Not Be ''
            $row.Old | Should Not Be ''
            if ($row.Status -eq 'Ready') {
                $row.New | Should Not Be ''
                $row.Pair | Should Not Be ''
            }
        }
        $row = Get-PinballYPlanRow $plan 'System5.Exe'
        (Get-PinballYLineValue -Line $lines[$row.Line - 1]) | Should Be $row.Old
        (Get-PinballYLineKey -Line $lines[$row.Line - 1]) | Should Be $row.Key
    }
}

Describe 'PinballY retarget: the dry run' {
    Set-KitCulture -Culture 'en-US'
    $fx = New-PinballYRetargetFixture

    It 'changes nothing anywhere, not the settings file and not the backups' {
        $before = Get-PinballYTreeHash $fx.Root
        $res = Invoke-PinballYRetarget -Path $fx.Root -Map $fx.Map
        $res.Status | Should Be 'Plan'
        @( $res.Written ).Count | Should Be 0
        $res.Backup | Should Be ''
        (Get-PinballYTreeHash $fx.Root) | Should Be $before
        Test-Path -LiteralPath $fx.Backup | Should Be $false
    }

    It 'answers the same questions with the same plan' {
        $a = @(Invoke-PinballYRetarget -Path $fx.Root -Map $fx.Map).Plan
        $b = @(Invoke-PinballYRetarget -Path $fx.Root -Map $fx.Map).Plan
        (@($a | ForEach-Object { '{0}|{1}|{2}' -f $_.File, $_.Line, $_.Status }) -join ';') |
            Should Be ((@($b | ForEach-Object { '{0}|{1}|{2}' -f $_.File, $_.Line, $_.Status }) -join ';'))
    }
}

Describe 'PinballY retarget: the write' {
    Set-KitCulture -Culture 'en-US'
    $fx = New-PinballYRetargetFixture
    $original = @(Read-PinballYLine -Path $fx.Settings)
    $originalCompanion = @(Read-PinballYLine -Path $fx.Companion)

    It 'writes exactly the planned lines and no others' {
        $res = Invoke-PinballYRetarget -Path $fx.Root -Map $fx.Map -Apply -BackupDir $fx.Backup
        $res.Status | Should Be 'Done'
        @( $res.Written ).Count | Should Be 5
        $now = @(Read-PinballYLine -Path $fx.Settings)
        $now.Count | Should Be $original.Count
        $touched = @()
        for ($i = 0; $i -lt $now.Count; $i++) { if ($now[$i] -ne $original[$i]) { $touched += ($i + 1) } }
        $expected = @( @($res.Written | Where-Object { $_.File -eq $fx.Settings } | ForEach-Object { $_.Line }) | Sort-Object )
        $expected.Count | Should Be 2
        ($touched -join ',') | Should Be ($expected -join ',')
        # Not one comment line moved, including the file's own path examples.
        $now[1] | Should BeExactly $original[1]
        $now[2] | Should BeExactly $original[2]
    }

    It 'keeps the byte order mark and the line endings of the file' {
        $bytes = [IO.File]::ReadAllBytes($fx.Settings)
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should Be $true
        ([regex]::Matches([IO.File]::ReadAllText($fx.Settings), "(?<!`r)`n")).Count | Should Be 0
    }

    It 'writes the companion file too, including a value that appears on two lines' {
        $now = @(Read-PinballYLine -Path $fx.Companion)
        $now.Count | Should Be $originalCompanion.Count
        $nvram = (Join-Path $fx.Target 'vpinmame\nvram') + '\'
        (Get-PinballYLineValue -Line $now[1]) | Should Be $nvram
        (Get-PinballYLineValue -Line $now[3]) | Should Be $nvram
        (Get-PinballYLineValue -Line $now[2]) | Should Be ((Join-Path $fx.Target 'futurepinball\fpRAM') + '\')
        # The comment of the companion file is untouched.
        $now[0] | Should BeExactly $originalCompanion[0]
    }

    It 'leaves a line alone whose target does not exist here' {
        $withMissing = @($fx.Map + ("{0}:\not-mounted-for-pinbally={1}" -f $fx.Drive, (Join-Path $fx.Target 'no-such-place')))
        $res = Invoke-PinballYRetarget -Path $fx.Root -Map $withMissing -Apply -BackupDir $fx.Backup
        @( @($res.Written) | Where-Object { $_.Key -eq 'System4.RunAfter' }).Count | Should Be 0
        $still = @(Read-PinballYLine -Path $fx.Settings)
        (Get-PinballYLineValue -Line $still[17]) | Should Be ('{0}:\not-mounted-for-pinbally\Game.exe' -f $fx.Drive)
    }

    It 'answers a second run with nothing to do' {
        $res = Invoke-PinballYRetarget -Path $fx.Root -Map $fx.Map -Apply -BackupDir $fx.Backup
        $res.Status | Should Be 'Skipped'
        @( $res.Written ).Count | Should Be 0
        $res.Backup | Should Be ''
        (Test-PinballYRetarget -Path $fx.Root -Pairs @(ConvertFrom-PinballYMap -Map $fx.Map)) | Should Be $true
    }

    It 'names a second backup of the same second differently instead of overwriting the first' {
        $fx2 = New-PinballYRetargetFixture
        # Its own backup folder: the other tests of this block have already written backups next to it.
        $dir = $fx2.Backup + '-zweiter-lauf'
        $a = Invoke-PinballYRetarget -Path $fx2.Root -Map $fx2.Map -Apply -BackupDir $dir
        # The same files again in the same second, with a map that still has something to do.
        $fp = ('D:\Games\Future Pinball\fpRAM={0}' -f (Join-Path $fx2.Target 'futurepinball\fpRAM'))
        $lines = @(Read-PinballYLine -Path $fx2.Companion)
        $lines[2] = ('FP=D:\Games\Future Pinball\fpRAM\' + "`r`n")
        Set-PinballYTestFile -Path $fx2.Companion -Lines $lines
        $b = Invoke-PinballYRetarget -Path $fx2.Root -Map @($fp) -Apply -BackupDir $dir
        $b.Status | Should Be 'Done'
        (Split-Path -Leaf $a.Backup) | Should Not Be (Split-Path -Leaf $b.Backup)
        @(Get-ChildItem -LiteralPath $dir -File).Count | Should Be 2
    }
}

Describe 'PinballY retarget: a plan that no longer fits' {
    Set-KitCulture -Culture 'en-US'

    It 'refuses a row whose line no longer holds the planned key and value' {
        # PinballY rewrites its settings when it closes, so a plan can be old by the time -Apply arrives. The
        # guard is the line check itself: it names the line it could not find again.
        $fx = New-PinballYRetargetFixture
        $rows = @(Get-PinballYRetargetPlan -Path $fx.Root -Pairs @(ConvertFrom-PinballYMap -Map $fx.Map) |
            Where-Object { $_.Status -eq 'Ready' })
        $row = @($rows | Where-Object { $_.File -eq $fx.Settings })[0]
        Test-PinballYRetargetFit -File $fx.Settings -Rows @($row) | Should Be 0
        # The same plan one line later: the file was rewritten and the value is not there any more.
        $stale = [pscustomobject]@{
            File = $row.File; FileKind = $row.FileKind; Line = $row.Line + 1; Key = $row.Key
            Old = $row.Old; New = $row.New; Pair = $row.Pair; Status = 'Ready'; Target = $row.Target; Reason = ''
        }
        Test-PinballYRetargetFit -File $fx.Settings -Rows @($stale) | Should Be ($row.Line + 1)
    }

    It 'writes what still fits and leaves a line the program has fixed itself' {
        # The plan is made again at -Apply, on the file as it is then: a value PinballY corrected in the
        # meantime is simply not in the new plan, and the rest of the plan is written as approved.
        $fx = New-PinballYRetargetFixture
        $row = @( @(Get-PinballYRetargetPlan -Path $fx.Root -Pairs @(ConvertFrom-PinballYMap -Map $fx.Map)) |
            Where-Object { $_.Key -eq 'System5.Exe' })[0]
        $lines = @(Read-PinballYLine -Path $fx.Settings)
        $fixed = ('System5.Exe = ' + (Join-Path $fx.Target 'Games\Pinball Arcade\TPAFreeCamMod.exe') + "`r`n")
        $lines[$row.Line - 1] = $fixed
        Set-PinballYTestFile -Path $fx.Settings -Lines $lines
        $res = Invoke-PinballYRetarget -Path $fx.Root -Map $fx.Map -Apply -BackupDir $fx.Backup
        $res.Status | Should Be 'Done'
        # That line is not in the result: the program had already written what the plan wanted.
        @( @($res.Written) | Where-Object { $_.Key -eq 'System5.Exe' }).Count | Should Be 0
        @( @($res.Written) | Where-Object { $_.Key -eq 'System5.RunBeforePre' }).Count | Should Be 1
        # The line the program fixed stays exactly as it is.
        $now = @(Read-PinballYLine -Path $fx.Settings)
        $now[$row.Line - 1] | Should BeExactly $fixed
    }

    It 'is a way back: the backup holds the files exactly as they were' {
        $fx = New-PinballYRetargetFixture
        $vorher = @(Read-PinballYLine -Path $fx.Settings)
        $res = Invoke-PinballYRetarget -Path $fx.Root -Map $fx.Map -Apply -BackupDir $fx.Backup
        $res.Backup | Should Not Be ''
        Test-Path -LiteralPath $res.Backup | Should Be $true
        $null = Restore-KitBackup -Path $res.Backup -AllowedRoots @($fx.Root) -Confirm:$false
        (@(Read-PinballYLine -Path $fx.Settings) -join '|') | Should Be (($vorher -join '|'))
    }
}

# Its own Describe: a Mock of the process guard must not be seen by the tests that write (Pester 3.4 keeps the
# mocks of a block for the whole block, and a leaked guard would break every later test in silence).
Describe 'PinballY retarget: the process guard' {
    Set-KitCulture -Culture 'en-US'
    $fx = New-PinballYRetargetFixture

    It 'refuses to write while the front end is running' {
        Mock -ModuleName 'RetroCabinetKit.Pinball' Assert-PinballYProcessesClosed { throw 'close PinballY first' }
        $before = Get-PinballYTreeHash $fx.Root
        { $null = Invoke-PinballYRetarget -Path $fx.Root -Map $fx.Map -Apply -BackupDir $fx.Backup } | Should Throw 'close PinballY'
        (Get-PinballYTreeHash $fx.Root) | Should Be $before
        # Refused means refused: not even a backup of files that were not touched.
        Test-Path -LiteralPath $fx.Backup | Should Be $false
    }

    It 'still plans while the front end is running, because a plan is not a danger' {
        Mock -ModuleName 'RetroCabinetKit.Pinball' Assert-PinballYProcessesClosed { throw 'close PinballY first' }
        $res = Invoke-PinballYRetarget -Path $fx.Root -Map $fx.Map
        $res.Status | Should Be 'Plan'
        @( $res.Ready ).Count | Should BeGreaterThan 0
    }
}
