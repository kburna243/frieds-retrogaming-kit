$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1') -Force
$newBuild = Join-Path $PSScriptRoot 'New-PinballTestBuild.ps1'

Describe 'Detect (step 1)' {
    Set-KitCulture -Culture 'en-US'
    $root = Join-Path $TestDrive 'Src'
    & $newBuild -Root $root -OldRoot 'D:\Old Build'

    It 'recognises a build and rejects other folders' {
        Test-PinballBuild -Path $root | Should Be $true
        Test-PinballBuild -Path $TestDrive | Should Be $false
        { Get-PinballBuildInfo -Source $TestDrive } | Should Throw 'No build found'
    }

    It 'derives the old root case-insensitively from GlobalMediaDir' {
        $info = Get-PinballBuildInfo -Source "$root\"
        $info.SourceRoot | Should BeExactly $root
        $info.OldRoot | Should BeExactly 'D:\Old Build'
        $info.Siblings -join ',' | Should Be 'DOFLinx'
        $info.Files | Should BeGreaterThan 10
        $info.SizeBytes | Should BeGreaterThan 0
    }

    It 'stops with an explanation when the schema is unknown' {
        $bad = Join-Path $TestDrive 'Bad'
        & $newBuild -Root $bad -OldRoot 'D:\X'
        $c = Open-KitSqlite -Path (Get-PinballDatabasePath -Root $bad)
        try { $null = Invoke-KitSqlNonQuery -Connection $c -Sql 'DROP TABLE Screens; ALTER TABLE Games RENAME COLUMN GameFileName TO FileName' } finally { Close-KitSqlite $c }
        $s = Test-PinballDatabaseSchema -Path (Get-PinballDatabasePath -Root $bad)
        $s.IsValid | Should Be $false
        ($s.Missing | Sort-Object) -join ',' | Should Be 'Games.GameFileName,Screens'
        { Get-PinballBuildInfo -Source $bad } | Should Throw 'unknown layout'
    }

    It 'refuses a media folder without \vPinball\' {
        $odd = Join-Path $TestDrive 'Odd'
        & $newBuild -Root $odd -OldRoot 'D:\X'
        $db = Get-PinballDatabasePath -Root $odd
        $c = Open-KitSqlite -Path $db
        try { $null = Invoke-KitSqlNonQuery -Connection $c -Sql "UPDATE GlobalSettings SET GlobalMediaDir = 'D:\Media\Default'" } finally { Close-KitSqlite $c }
        { Get-PinballOldRoot -DatabasePath $db } | Should Throw 'cannot be derived'
    }

    It 'normalises roots' {
        ConvertTo-PinballRoot 'c:\' | Should BeExactly 'C:'
        ConvertTo-PinballRoot 'D:/Games/' | Should BeExactly 'D:\Games'
        ConvertTo-PinballRoot '\\nas\share\pin\' | Should BeExactly '\\nas\share\pin'
        { ConvertTo-PinballRoot 'Games\Pin' } | Should Throw
    }
}

Describe 'Target (step 2)' {
    Set-KitCulture -Culture 'en-US'
    $src = Join-Path $TestDrive 'Src'
    & $newBuild -Root $src -OldRoot 'D:\Old'

    It 'accepts a folder with enough space' {
        $r = Test-PinballTarget -TargetRoot (Join-Path $TestDrive 'Dst') -SourceRoot $src -SizeBytes 1000
        $r.IsValid | Should Be $true
        $r.RequiredBytes | Should Be 1100
    }

    It 'refuses when the space is below size + 10 %' {
        $r = Test-PinballTarget -TargetRoot (Join-Path $TestDrive 'Dst') -SourceRoot $src -SizeBytes ([long]1PB)
        $r.IsValid | Should Be $false
        $r.Reason | Should Match 'Not enough free space'
    }

    It 'refuses a target inside the build and a missing drive' {
        (Test-PinballTarget -TargetRoot (Join-Path $src 'vPinball\Sub') -SourceRoot $src -SizeBytes 1).Reason | Should Match 'inside the build'
        $free = [char[]](90..68) | Where-Object { -not (Test-Path "$($_):\") } | Select-Object -First 1
        (Test-PinballTarget -TargetRoot "$($free):\Games" -SourceRoot $src -SizeBytes 1).Reason | Should Match 'not available'
        (Test-PinballTarget -TargetRoot '\\nas\share' -SourceRoot $src -SizeBytes 1).Reason | Should Match 'local drive'
    }

    It 'refuses target characters that would change the meaning of batch and INI files' {
        foreach ($bad in 'Games&Co', 'Pin%PATH%', 'A^B', 'Bang!', 'Tab"le', 'Spiele Ü') {
            (Test-PinballTarget -TargetRoot "C:\$bad" -SourceRoot $src -SizeBytes 1).Reason | Should Match 'characters'
        }
        (Test-PinballTarget -TargetRoot (Join-Path $TestDrive 'Dst (2)') -SourceRoot $src -SizeBytes 1).IsValid | Should Be $true
    }

    It 'names the problem of a root in every executing step' {
        Get-PinballRootProblem -Root $src | Should BeNullOrEmpty
        Get-PinballRootProblem -Root '\\nas\share' | Should Match 'local drive'
        Get-PinballRootProblem -Root (Join-Path $TestDrive 'Empty') | Should Match 'No build found'
        Get-PinballRootProblem -Root (Join-Path $TestDrive 'Empty') -NoDatabase | Should BeNullOrEmpty
        Get-PinballRootProblem -Root '' | Should Not BeNullOrEmpty
    }

    It 'accepts the source itself without a space check' {
        $r = Test-PinballTarget -TargetRoot $src -SourceRoot $src -SizeBytes ([long]1PB)
        $r.IsValid | Should Be $true
        $r.SameAsSource | Should Be $true
    }
}

Describe 'Kit files of the pinball package' {
    It 'stores every PowerShell file as UTF-8 with BOM' {
        $files = Get-ChildItem -LiteralPath (Join-Path $kitRoot 'pinball'), (Join-Path $kitRoot 'tests') -Recurse -File |
            Where-Object { $_.Extension -in '.ps1', '.psm1', '.psd1' -and $_.FullName -notlike '*\fixtures-local\*' }
        $withoutBom = $files | Where-Object {
            $b = [IO.File]::ReadAllBytes($_.FullName)
            -not ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
        }
        @($withoutBom | ForEach-Object { $_.Name }) -join ', ' | Should BeNullOrEmpty
    }

    It 'has every step script parse without errors' {
        foreach ($f in Get-ChildItem -LiteralPath (Join-Path $kitRoot 'pinball\steps') -Filter '*.ps1') {
            $errors = $null
            $null = [Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errors)
            "$($f.Name): $(@($errors).Count)" | Should Be "$($f.Name): 0"
        }
    }

    It 'uses only i18n keys that exist in both languages' {
        # Loaded like the kit does (Import-LocalizedData): Import-PowerShellDataFile stops at large files.
        Import-LocalizedData -BindingVariable de -BaseDirectory (Join-Path $kitRoot 'i18n') -FileName 'de-DE.psd1' -UICulture 'de-DE'
        Import-LocalizedData -BindingVariable en -BaseDirectory (Join-Path $kitRoot 'i18n') -FileName 'en-US.psd1' -UICulture 'en-US'
        $code = (Get-ChildItem -LiteralPath (Join-Path $kitRoot 'pinball') -Recurse -File -Include *.ps1 | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"
        $keys = [regex]::Matches($code, "'(Pinball\.[A-Za-z.]+)'") | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
        $keys += 'Pinball.Deps.NeedsUser.User', 'Pinball.Deps.NeedsUser.Dism', 'Pinball.Deps.NeedsUser.Download'
        @($keys | Where-Object { -not $en.ContainsKey($_) -or -not $de.ContainsKey($_) }) -join ', ' | Should BeNullOrEmpty
    }
}
