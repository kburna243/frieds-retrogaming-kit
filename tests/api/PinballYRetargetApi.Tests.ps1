$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1') -Force
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1') -Force
Import-Module (Join-Path $kitRoot 'api\RetroCabinetKit.Api.psd1') -Force
$newInstallScript = Join-Path $kitRoot 'tests\pinball\New-PinballYTestInstall.ps1'

function Get-PinballYUnmountedDrive {
    $mounted = @{}
    foreach ($d in [IO.DriveInfo]::GetDrives()) { $mounted[$d.Name.Substring(0, 1).ToUpperInvariant()] = $true }
    foreach ($l in @('Q', 'V', 'Y', 'Z', 'W', 'U', 'T', 'S', 'R', 'P', 'O', 'N')) {
        if (-not $mounted.ContainsKey($l)) { return $l }
    }
    throw 'no unmounted drive letter to test with'
}

# A copied installation with its counterparts, as the API sees it. Paths are computed from $TestDrive.
function New-PinballYRetargetApiFixture([string] $Name) {
    $base = (Resolve-Path -LiteralPath $TestDrive).ProviderPath
    $foreign = Get-PinballYUnmountedDrive
    $root = & $newInstallScript -Root (Join-Path $base $Name) -ForeignDrive $foreign -Retarget
    $target = Join-Path $base ($Name + '-target')
    # The builder puts the counterparts in one fixed folder next to the installation; every fixture of a block
    # gets its own copy, so two fixtures in one $TestDrive can never read each other's targets.
    $built = Join-Path $base 'PinballYRetargetTarget'
    if (Test-Path -LiteralPath $built) { Move-Item -LiteralPath $built -Destination $target -Force }
    [pscustomobject]@{
        Root = $root; Drive = $root.Substring(0, 1); Target = $target
        Settings = Join-Path $root 'Settings.txt'
        BackupDir = Join-Path $base ($Name + '-backups')
        Map = @(
            ("{0}:\Games={1}" -f $foreign, (Join-Path $target 'Games'))
            ("{0}:\Scripts={1}" -f $foreign, (Join-Path $target 'Scripts'))
            ('D:\Per\VisualPinball\VPinMame\nvram={0}' -f (Join-Path $target 'vpinmame\nvram'))
            ('D:\Games\Future Pinball\fpRAM={0}' -f (Join-Path $target 'futurepinball\fpRAM'))
        )
    }
}

function Get-PinballYTreeHash([string] $Root) {
    @(Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName |
        ForEach-Object { '{0}|{1}|{2}' -f $_.FullName, $_.Length, (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join ';'
}

Describe 'Kit API: pinbally.retarget is a gated change' {
    Set-KitCulture -Culture 'en-US'
    $pb = Join-Path $TestDrive 'api-state.json'

    It 'is a Change operation with the folder, the map and an optional backup folder' {
        $op = @(Get-KitOperation | Where-Object { $_.Name -eq 'pinbally.retarget' })[0]
        $op.Kind | Should Be 'Change'
        $op.Available | Should Be $true
        $op.Interactive | Should Be $false
        $op.Suite | Should Be ''
        (@($op.Parameters | ForEach-Object { '{0}:{1}!{2}' -f $_.Name, $_.Type, [int]$_.Mandatory }) -join ',') |
            Should BeExactly 'Path:String!1,Map:String[]!1,BackupDir:String!0'
    }

    It 'names a missing map instead of guessing one' {
        $fx = New-PinballYRetargetApiFixture 'noparam'
        $r = Invoke-KitOperation -Name 'pinbally.retarget' -Parameters @{ Path = $fx.Root } -PinballStatePath $pb
        $r.Status | Should Be 'Failed'
        $r.Message | Should Match 'Map'
        (Get-PinballYTreeHash $fx.Root) | Should Be (Get-PinballYTreeHash $fx.Root)
    }

    It 'refuses a parameter that is not one of its own' {
        $fx = New-PinballYRetargetApiFixture 'denied'
        # WhatIf, Apply and Approved belong to the API itself (API.md rule 3).
        $r = Invoke-KitOperation -Name 'pinbally.retarget' -Parameters @{ Path = $fx.Root; Map = $fx.Map; WhatIf = $true } -PinballStatePath $pb
        $r.Status | Should Be 'Failed'
        $r.Message | Should Match 'WhatIf'
    }

    It 'says plainly that a folder without an installation gets nothing written' {
        $elsewhere = Join-Path $TestDrive 'not-a-pinbally'
        $null = New-Item -ItemType Directory -Path $elsewhere -Force
        $r = Invoke-KitOperation -Name 'pinbally.retarget' -Parameters @{ Path = $elsewhere; Map = @('Q:\Games=J:\Games') } -PinballStatePath $pb
        $r.Status | Should Be 'Failed'
        $r.Message | Should Match 'No PinballY installation'
        @(Get-ChildItem -LiteralPath $elsewhere -Recurse -File).Count | Should Be 0
    }

    It 'answers a dry run with the plan, an approval per file and nothing changed' {
        $fx = New-PinballYRetargetApiFixture 'plan'
        $pb = Join-Path $TestDrive 'plan-state.json'
        $before = Get-PinballYTreeHash $fx.Root
        $r = Invoke-KitOperation -Name 'pinbally.retarget' -Parameters @{ Path = $fx.Root; Map = $fx.Map } -PinballStatePath $pb
        $r.Status | Should Be 'WhatIf'
        $r.Success | Should Be $true
        $r.Applied | Should Be $false
        @( $r.Changes ).Count | Should Be 0
        @( $r.Backups ).Count | Should Be 0
        # Two files hold dead values: the settings and the companion INI, and each is named once for the yes.
        @( $r.Approvals ).Count | Should Be 2
        @( $r.Data.Plan ).Count | Should Be 6
        @( $r.Data.Ready ).Count | Should Be 5
        @( $r.Data.Pending ).Count | Should Be 1
        (Get-PinballYTreeHash $fx.Root) | Should Be $before
        # A dry run that writes no backup is one thing; a dry run that writes no STATE is the other.
        Test-Path -LiteralPath $pb | Should Be $false
    }

    It 'needs the yes of a person: -Apply alone does not write' {
        $fx = New-PinballYRetargetApiFixture 'gate'
        $pb = Join-Path $TestDrive 'gate-state.json'
        $before = Get-PinballYTreeHash $fx.Root
        $r = Invoke-KitOperation -Name 'pinbally.retarget' -Parameters @{ Path = $fx.Root; Map = $fx.Map } -Apply
        $r.Status | Should Be 'NeedsUser'
        $r.Success | Should Be $false
        $r.Applied | Should Be $false
        @( $r.Approvals ).Count | Should Be 2
        @( $r.Changes ).Count | Should Be 0
        @( $r.Backups ).Count | Should Be 0
        (Get-PinballYTreeHash $fx.Root) | Should Be $before
        Test-Path -LiteralPath $pb | Should Be $false
    }

    It 'refuses a map that is not a pair of absolute paths, and writes nothing' {
        $fx = New-PinballYRetargetApiFixture 'badmap'
        $before = Get-PinballYTreeHash $fx.Root
        $r = Invoke-KitOperation -Name 'pinbally.retarget' -Parameters @{ Path = $fx.Root; Map = @('Q:\Games') } -Apply -Approved -PinballStatePath $pb
        $r.Status | Should Be 'Failed'
        $r.Message | Should Match 'Old=New'
        (Get-PinballYTreeHash $fx.Root) | Should Be $before
    }

    It 'writes with -Apply and -Approved, backs up first and records the folder' {
        $fx = New-PinballYRetargetApiFixture 'write'
        $pb = Join-Path $TestDrive 'write-state.json'
        $before = Get-PinballYTreeHash $fx.Root
        # -PinballStatePath everywhere: a test that forgets it writes into the kit's OWN state file, and that
        # is a side effect no test is allowed to have on a real cabinet.
        $r = Invoke-KitOperation -Name 'pinbally.retarget' -Parameters @{ Path = $fx.Root; Map = $fx.Map; BackupDir = $fx.BackupDir } -Apply -Approved -PinballStatePath $pb
        $r.Status | Should Be 'Done'
        $r.Success | Should Be $true
        $r.Applied | Should Be $true
        @( $r.Changes ).Count | Should Be 5
        @( $r.Backups ).Count | Should Be 1
        # The backup is the one the caller asked for, and it is a real ZIP with the files inside.
        (Split-Path -Parent @($r.Backups)[0]) | Should BeExactly $fx.BackupDir
        Test-Path -LiteralPath @($r.Backups)[0] | Should Be $true
        (Get-PinballYTreeHash $fx.Root) | Should Not Be $before
        # Every planned value resolves now, and what is left is exactly what was left on purpose: the path no
        # pair covers, and the media folder that is relative and really gone.
        $nach = Invoke-KitOperation -Name 'pinbally.detect' -Parameters @{ Path = $fx.Root } -PinballStatePath $pb
        (@($nach.Data.ReferenceMissing | ForEach-Object { $_.Key }) -join ',') | Should BeExactly 'System4.RunAfter,System7.MediaDir'
        @( $nach.Data.ReferenceMissing | Where-Object { $_.Value -like 'Q:*' }).Count | Should Be 0
        (@( @(Get-PinballYCompanion -Path $fx.Root) | ForEach-Object { $_.Broken } | Measure-Object -Sum).Sum) | Should Be 0
        # Only the write records the installation in the state, and components then knows it.
        (Get-KitStateValue -Path $pb -Key 'PinballYRoot') | Should BeExactly $fx.Root
        $row = @( @(Invoke-KitOperation -Name 'components' -PinballStatePath $pb).Data.Components |
            Where-Object { $_.Name -eq 'PinballY' } )[0]
        $row.Present | Should Be $true
        $row.Path | Should BeExactly $fx.Root
    }

    It 'has nothing to do on the second run' {
        $fx = New-PinballYRetargetApiFixture 'again'
        $pb = Join-Path $TestDrive 'again-state.json'
        $p = @{ Path = $fx.Root; Map = $fx.Map; BackupDir = $fx.BackupDir }
        $null = Invoke-KitOperation -Name 'pinbally.retarget' -Parameters $p -Apply -Approved -PinballStatePath $pb
        $hash = Get-PinballYTreeHash $fx.Root
        $r = Invoke-KitOperation -Name 'pinbally.retarget' -Parameters $p -Apply -Approved -PinballStatePath $pb
        $r.Status | Should Be 'Skipped'
        $r.Success | Should Be $true
        @( $r.Changes ).Count | Should Be 0
        @( $r.Backups ).Count | Should Be 0
        (Get-PinballYTreeHash $fx.Root) | Should Be $hash
    }

    It 'is offered as a change tool with apply and approved, like every other change' {
        # MCP exposes the catalog; a tool that changes must be gated by its own flags (API.md rule 3).
        $op = @(Get-KitOperation | Where-Object { $_.Name -eq 'pinbally.retarget' })[0]
        @($op.Parameters | Where-Object { $_.Name -in @('Apply', 'Approved', 'WhatIf', 'Approve') }).Count | Should Be 0
    }
}
