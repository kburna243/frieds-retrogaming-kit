$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1') -Force
$newInstallScript = Join-Path $PSScriptRoot 'New-PinballYTestInstall.ps1'

# A letter that answers to nobody: the case "this value comes from another computer". The kit CI mounts the
# synthetic drives E and X, so those are deliberately not candidates here.
function Get-PinballYUnmountedDrive {
    $mounted = @{}
    foreach ($d in [IO.DriveInfo]::GetDrives()) { $mounted[$d.Name.Substring(0, 1).ToUpperInvariant()] = $true }
    foreach ($l in @('Q', 'V', 'Y', 'Z', 'W', 'U', 'T', 'S', 'R', 'P', 'O', 'N')) {
        if (-not $mounted.ContainsKey($l)) { return $l }
    }
    throw 'no unmounted drive letter to test with'
}

# PinballY paths are absolute by design (the kit refuses a relative root), and Pester's TestDrive is a PSDrive
# named "TestDrive:", which is not a drive letter. The tests therefore work in the folder behind it.
function New-PinballYFixture([string] $Name) {
    $base = (Resolve-Path -LiteralPath $TestDrive).ProviderPath
    & $newInstallScript -Root (Join-Path $base $Name) -ForeignDrive (Get-PinballYUnmountedDrive)
}

function Get-PinballYTreeHash([string] $Root) {
    @(Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName |
        ForEach-Object { '{0}|{1}|{2}' -f $_.FullName, $_.Length, (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join ';'
}

function Get-PinballYRefByKey([string] $Root, [string] $Key) {
    @(Get-PinballYReference -Path $Root) | Where-Object { $_.Key -eq $Key } | Select-Object -First 1
}

Describe 'PinballY installation' {
    Set-KitCulture -Culture 'en-US'

    Context 'what counts as an installation' {
        It 'is a folder with Settings.txt and PinballY.exe' {
            $root = New-PinballYFixture 'install'
            Test-PinballYInstall -Path $root | Should Be $true
        }

        It 'does not accept the file names a tool guesses from another front end' {
            # "PinballY.ini" and "Media Database.xml" are what a program note about another frontend invents.
            # Neither exists in a PinballY folder, so a checker that demands them calls every real install broken.
            $base = (Resolve-Path -LiteralPath $TestDrive).ProviderPath
            $guessed = Join-Path $base 'guessed'
            $null = New-Item -ItemType Directory -Path $guessed -Force
            [IO.File]::WriteAllText((Join-Path $guessed 'PinballY.ini'), '[settings]' + "`r`n")
            [IO.File]::WriteAllText((Join-Path $guessed 'Media Database.xml'), '<menu />' + "`r`n")
            Test-PinballYInstall -Path $guessed | Should Be $false
        }

        It 'says no to an empty path instead of walking the drive' {
            Test-PinballYInstall -Path '' | Should Be $false
        }

        It 'refuses to describe a folder that is not an installation' {
            $base = (Resolve-Path -LiteralPath $TestDrive).ProviderPath
            $empty = Join-Path $base 'empty'
            $null = New-Item -ItemType Directory -Path $empty -Force
            $message = ''
            try { $null = Get-PinballYInfo -Path $empty } catch { $message = $_.Exception.Message }
            $message | Should Match 'No PinballY installation'
        }
    }

    Context 'the settings file' {
        It 'is read as what it is: UTF-8 with BOM, no sections' {
            $root = New-PinballYFixture 'settings'
            $settings = Get-PinballYSetting -Path $root
            $settings.Bom | Should Be $true
            $settings.CodePage | Should Be 65001
        }

        It 'counts the assignments and the comments apart' {
            $root = New-PinballYFixture 'settings2'
            $settings = Get-PinballYSetting -Path $root
            $settings.Setting.Count | Should Be 20
            $settings.Comment | Should Be 4
        }

        It 'never treats a comment as a setting, even when it holds a path' {
            # The file explains itself with examples ("c:\my path\my program", "X:\...\my launch.cmd"). A
            # replace over the raw text rewrites the help: that is the difference between a repair and damage.
            $root = New-PinballYFixture 'settings3'
            $settings = Get-PinballYSetting -Path $root
            @($settings.Setting | Where-Object { $_.Value -match 'my path|my launch' }).Count | Should Be 0
            @($settings.Setting | Where-Object { $_.Key -match '#' }).Count | Should Be 0
        }
    }

    Context 'path values' {
        It 'keeps [STEAM] a token and does not call it broken' {
            $root = New-PinballYFixture 'token'
            $r = Get-PinballYRefByKey -Root $root -Key 'System2.Exe'
            $r.Kind | Should Be 'token'
            $r.Status | Should Be 'Token'
            $r.TokenName | Should Be 'STEAM'
            $r.Resolved | Should Be ''
        }

        It 'expands [PinballY] to the install folder and can check it' {
            $root = New-PinballYFixture 'tokenroot'
            $r = Get-PinballYRefByKey -Root $root -Key 'System3.TablePath'
            $r.Kind | Should Be 'token'
            $r.Status | Should Be 'Present'
            $r.Resolved | Should BeExactly (Join-Path $root 'Farsight')
        }

        It 'looks for media inside MediaPath, not next to the program' {
            # The false alarm this rule prevents: "Sub" does exist, only under Media\.
            $root = New-PinballYFixture 'media'
            $r = Get-PinballYRefByKey -Root $root -Key 'System1.MediaDir'
            $r.Status | Should Be 'Present'
            $r.Resolved | Should BeExactly (Join-Path $root 'Media\Sub')
            Test-Path -LiteralPath (Join-Path $root 'Sub') | Should Be $false
        }

        It 'looks for table databases inside TableDatabasePath' {
            $root = New-PinballYFixture 'dbanchor'
            $r = Get-PinballYRefByKey -Root $root -Key 'System1.DatabaseDir'
            $r.Resolved | Should BeExactly (Join-Path $root 'Databases\vp')
            $r.Status | Should Be 'Present'
        }

        It 'leaves a folder that belongs to another emulator alone' {
            # "steamapps\common\Pinball FX3\data\steam" is relative to that system's own install, not to PinballY.
            # Checking it against the PinballY folder would invent a broken path that no person could fix.
            $root = New-PinballYFixture 'relative'
            (Get-PinballYRefByKey -Root $root -Key 'System2.TablePath').Status | Should Be 'Relative'
            (Get-PinballYRefByKey -Root $root -Key 'System1.TablePath').Status | Should Be 'Relative'
        }

        It 'separates a path that works here from one that is only broken here' {
            $root = New-PinballYFixture 'absolute'
            (Get-PinballYRefByKey -Root $root -Key 'System4.Exe').Status | Should Be 'Present'
            (Get-PinballYRefByKey -Root $root -Key 'System4.RunAfter').Status | Should Be 'Missing'
        }

        It 'names a path from another machine as what it is' {
            $root = New-PinballYFixture 'foreign'
            (Get-PinballYRefByKey -Root $root -Key 'System5.Exe').Status | Should Be 'ForeignDrive'
            (Get-PinballYRefByKey -Root $root -Key 'System5.RunBeforePre').Status | Should Be 'ForeignDrive'
        }

        It 'reports media that is really gone' {
            $root = New-PinballYFixture 'gone'
            (Get-PinballYRefByKey -Root $root -Key 'System7.MediaDir').Status | Should Be 'Missing'
        }

        It 'ignores an unset value instead of reporting an empty path' {
            $root = New-PinballYFixture 'unset'
            @(@(Get-PinballYReference -Path $root) | Where-Object { $_.Key -eq 'System8.Exe' }).Count | Should Be 0
        }

        It 'lists exactly the values that address something on disk' {
            # 13 of the 20 settings are addresses: two anchors, two media and one database folder, three table
            # paths, four exe or helper paths and one token exe. System6.Class and the empty System8.Exe are not.
            $root = New-PinballYFixture 'count'
            @(Get-PinballYReference -Path $root).Count | Should Be 13
        }
    }

    Context 'systems' {
        It 'reads every system with its class and its enabled state' {
            $root = New-PinballYFixture 'systems'
            $systems = @(Get-PinballYSystem -Path $root)
            $systems.Count | Should Be 8
            @($systems | Where-Object { $_.Enabled }).Count | Should Be 2
            (@($systems | Where-Object { $_.Number -eq 1 })[0]).Class | Should Be 'VPinball'
            # "Enabled = true" and "Enabled = 1" both mean on; "0" means off.
            (@($systems | Where-Object { $_.Number -eq 2 })[0]).Enabled | Should Be $true
            (@($systems | Where-Object { $_.Number -eq 6 })[0]).Enabled | Should Be $false
        }
    }

    Context 'table databases' {
        It 'counts the games of a HyperList export and finds no path to rewrite in it' {
            $root = New-PinballYFixture 'databases'
            $good = @( @(Get-PinballYDatabase -Path $root) | Where-Object { $_.File -eq 'vp.xml' } )[0]
            $good.Games | Should Be 3
            $good.AbsolutePath | Should Be 0
            $good.System | Should Be 'vp'
        }

        It 'says which database it could not read instead of counting zero' {
            $root = New-PinballYFixture 'databases2'
            $broken = @( @(Get-PinballYDatabase -Path $root) | Where-Object { $_.File -eq 'broken.xml' } )[0]
            $broken.ParseError | Should Not BeNullOrEmpty
        }
    }

    Context 'other programs in the folder' {
        It 'sees the overlay configuration with its dead paths' {
            $root = New-PinballYFixture 'companion'
            $c = @( @(Get-PinballYCompanion -Path $root) | Where-Object { $_.File -eq 'PINemHi\pinemhi.ini' } )[0]
            $c.PathLine | Should Be 2
            $c.Broken | Should Be 2
        }
    }

    Context 'reading is reading' {
        It 'reports no running program as an empty list, not as nothing' {
            # Set-StrictMode -Version 2.0 turns a property of $null into an error, and a function that returns an
            # empty array hands back $null through the pipeline. Without @() at the call site this threw.
            $root = New-PinballYFixture 'running'
            $info = Get-PinballYInfo -Path $root
            ($info.Running -is [array]) | Should Be $true
            @($info.Running).Count | Should Be 0
            $info.WriteSafe | Should Be $true
        }

        It 'describes the same installation twice with the same answer' {
            $root = New-PinballYFixture 'twice'
            $a = Get-PinballYInfo -Path $root
            $b = Get-PinballYInfo -Path $root
            $a.Detail | Should BeExactly $b.Detail
            @($a.Reference).Count | Should Be @($b.Reference).Count
        }

        It 'writes nothing, anywhere' {
            $root = New-PinballYFixture 'hash'
            $before = Get-PinballYTreeHash -Root $root
            $null = Get-PinballYInfo -Path $root
            $null = Get-PinballYReference -Path $root
            $null = Get-PinballYCompanion -Path $root
            Get-PinballYTreeHash -Root $root | Should BeExactly $before
        }

        It 'names where the version comes from' {
            $root = New-PinballYFixture 'version'
            $v = Get-PinballYVersion -Path $root
            # The fixture exe is a stand-in, so there is no version to read; the source is still named.
            $v.Source | Should Be 'PinballY.exe'
            $v.Version | Should Be ''
        }
    }

    Context 'the aggregate report' {
        It 'holds the whole picture in one object' {
            $root = New-PinballYFixture 'report'
            $info = Get-PinballYInfo -Path $root
            $info.Root | Should BeExactly $root
            $info.Encoding | Should BeExactly 'utf-8-bom'
            $info.Setting | Should Be 20
            $info.SystemEnabled | Should Be 2
            $info.ReferenceAbsolute | Should Be 4
            $info.ReferenceToken | Should Be 2
            $info.Game | Should Be 3
            @($info.Companion).Count | Should Be 1
        }

        It 'splits broken here from coming from another machine' {
            $root = New-PinballYFixture 'report2'
            $info = Get-PinballYInfo -Path $root
            @($info.ReferenceMissing).Count | Should Be 2
            @($info.ReferenceForeign).Count | Should Be 2
        }

        It 'says it in one line a person can read' {
            $root = New-PinballYFixture 'report3'
            $info = Get-PinballYInfo -Path $root
            $info.Detail | Should Match 'PinballY'
            # The three numbers a cabinet owner acts on, named so that none of them can be read as another.
            $info.Detail | Should Match 'path references: 13'
            $info.Detail | Should Match 'broken here: 2'
            $info.Detail | Should Match 'from another machine: 2'
        }
    }

    Context 'the guard before any write' {
        It 'passes while no PinballY program is open' {
            { Assert-PinballYProcessesClosed } | Should Not Throw
        }
    }
}
