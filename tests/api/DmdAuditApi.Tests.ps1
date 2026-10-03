$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1') -Force
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1') -Force
Import-Module (Join-Path $kitRoot 'api\RetroCabinetKit.Api.psd1') -Force
$script:newBuild = Join-Path $kitRoot 'tests\pinball\New-PinballDmdTestBuild.ps1'

# Contract of the two DMD operations (API 1.7). The build lives in $TestDrive; no real cabinet file is touched.
function New-DmdApiFixture([string] $Name) {
    & $script:newBuild -Root (Join-Path (Resolve-Path -LiteralPath $TestDrive).ProviderPath $Name)
}

function Get-DmdApiHash([string] $Root) {
    @(Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName |
        ForEach-Object { '{0}|{1}' -f $_.FullName, (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join ';'
}

Describe 'API 1.7 -- pinball.dmd_audit' {
    Set-KitCulture -Culture 'en-US'
    $pb = Join-Path $TestDrive 'audit-state.json'

    It 'is a Read operation of the pinball package with an optional Root' {
        $op = @(Get-KitOperation | Where-Object { $_.Name -eq 'pinball.dmd_audit' })[0]
        $op.Kind | Should Be 'Read'
        $op.Module | Should Be 'pinball'
        @($op.Parameters | ForEach-Object { $_.Name }) | Should Be @('Root')
        (Get-KitApiVersion) | Should Be '1.7'
    }

    It 'reports every verdict with counts and warnings, and changes nothing (not even with -Apply)' {
        $fx = New-DmdApiFixture 'read'
        $before = Get-DmdApiHash $fx.Root
        $r = Invoke-KitOperation -Name 'pinball.dmd_audit' -Parameters @{ Root = $fx.Root } -Apply -PinballStatePath $pb
        $r.Status | Should Be 'Ok'
        $r.Kind | Should Be 'Read'
        $r.Data.TableCount | Should Be 13
        $r.Data.Count.NoPup | Should Be 5
        $r.Data.Count.Mixed | Should Be 1
        $r.Data.Count.Orphan | Should Be 1
        $r.Data.Count.Unclear | Should Be 1
        @($r.Warnings).Count | Should Be 7
        $r.Message | Should Match '5 without active PuP'
        @($r.Data.Section | Where-Object { $_.Section -eq 'romnopack' })[0].Verdict | Should Be 'NoPup'
        Get-DmdApiHash $fx.Root | Should Be $before
        Test-Path -LiteralPath $pb | Should Be $false
    }

    It 'takes the build root from the pinball state when none is given' {
        $fx = New-DmdApiFixture 'state'
        $state = Join-Path $TestDrive 'with-root.json'
        $null = Set-KitStateValue -Path $state -Key 'TargetRoot' -Value $fx.Root
        $r = Invoke-KitOperation -Name 'pinball.dmd_audit' -PinballStatePath $state
        $r.Status | Should Be 'Ok'
        $r.Data.Root | Should Be $fx.Root
    }

    It 'fails with a clear message when there is no root at all' {
        $r = Invoke-KitOperation -Name 'pinball.dmd_audit' -PinballStatePath (Join-Path $TestDrive 'none.json')
        $r.Status | Should Be 'Failed'
        $r.Message | Should Match 'No build root'
    }
}

Describe 'API 1.7 -- pinball.dmd_repair is a gated change' {
    Set-KitCulture -Culture 'en-US'
    $pb = Join-Path $TestDrive 'repair-state.json'
    Mock -ModuleName RetroCabinetKit.Pinball Assert-PinballProcessesClosed { }

    It 'is a Change operation with Root, Section and BackupDir, all optional' {
        $op = @(Get-KitOperation | Where-Object { $_.Name -eq 'pinball.dmd_repair' })[0]
        $op.Kind | Should Be 'Change'
        @($op.Parameters | ForEach-Object { $_.Name }) | Should Be @('Root', 'Section', 'BackupDir')
        @($op.Parameters | Where-Object { $_.Mandatory }).Count | Should Be 0
    }

    It 'answers with the plan and one approval per section, and writes nothing' {
        $fx = New-DmdApiFixture 'plan'
        $before = Get-DmdApiHash $fx.Root
        $r = Invoke-KitOperation -Name 'pinball.dmd_repair' -Parameters @{ Root = $fx.Root } -PinballStatePath $pb
        $r.Status | Should Be 'WhatIf'
        $r.Applied | Should Be $false
        @($r.Approvals).Count | Should Be 5
        @($r.Data.Ready | ForEach-Object { $_.Section } | Sort-Object) | Should Be @('disabled', 'flexonly', 'romnopack', 'romoff', 'scriptoff')
        Get-DmdApiHash $fx.Root | Should Be $before
    }

    It '-Apply alone needs a person''s yes and writes nothing' {
        $fx = New-DmdApiFixture 'noyes'
        $before = Get-DmdApiHash $fx.Root
        $r = Invoke-KitOperation -Name 'pinball.dmd_repair' -Parameters @{ Root = $fx.Root } -Apply -PinballStatePath $pb
        $r.Status | Should Be 'NeedsUser'
        Get-DmdApiHash $fx.Root | Should Be $before
    }

    It 'a section that is not NoPup is never planned and comes back as a warning' {
        $fx = New-DmdApiFixture 'named'
        $r = Invoke-KitOperation -Name 'pinball.dmd_repair' -Parameters @{ Root = $fx.Root; Section = @('scriptpup', 'shared') } -PinballStatePath $pb
        $r.Status | Should Be 'WhatIf'
        @($r.Data.Ready).Count | Should Be 0
        @($r.Warnings).Count | Should Be 2
    }

    It '-Apply -Approved writes after a backup, and the second run is Skipped' {
        $fx = New-DmdApiFixture 'write'
        $r = Invoke-KitOperation -Name 'pinball.dmd_repair' -Parameters @{ Root = $fx.Root; BackupDir = $fx.Backup } -Apply -Approved -PinballStatePath $pb
        $r.Status | Should Be 'Done'
        $r.Applied | Should Be $true
        @($r.Changes).Count | Should Be 17
        @($r.Backups).Count | Should Be 1
        Test-Path -LiteralPath $r.Backups[0] | Should Be $true
        (Get-Content -LiteralPath $fx.Ini -Raw) | Should Not Match '\[romnopack\]'

        $again = Invoke-KitOperation -Name 'pinball.dmd_repair' -Parameters @{ Root = $fx.Root; BackupDir = $fx.Backup } -Apply -Approved -PinballStatePath $pb
        $again.Status | Should Be 'Skipped'
    }
}
