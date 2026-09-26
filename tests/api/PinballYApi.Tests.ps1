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

function New-PinballYApiFixture([string] $Name) {
    $base = (Resolve-Path -LiteralPath $TestDrive).ProviderPath
    & $newInstallScript -Root (Join-Path $base $Name) -ForeignDrive (Get-PinballYUnmountedDrive)
}

function Get-PinballYTreeHash([string] $Root) {
    @(Get-ChildItem -LiteralPath $Root -Recurse -File | Sort-Object FullName |
        ForEach-Object { '{0}|{1}|{2}' -f $_.FullName, $_.Length, (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }) -join ';'
}

# Contract tests for the second front end: what the catalog promises and what one call answers (API.md).
Describe 'Kit API: pinbally.detect' {
    Set-KitCulture -Culture 'en-US'
    $pb = Join-Path $TestDrive 'pinball-state.json'

    It 'is a Read operation that asks for one folder and nothing else' {
        $op = @(Get-KitOperation | Where-Object { $_.Name -eq 'pinbally.detect' })[0]
        $op.Kind | Should Be 'Read'
        $op.Available | Should Be $true
        $op.Interactive | Should Be $false
        $op.Suite | Should Be ''
        $names = @($op.Parameters | ForEach-Object { $_.Name })
        $names -join ',' | Should BeExactly 'Path'
        @($op.Parameters)[0].Type | Should Be 'String'
        @($op.Parameters)[0].Mandatory | Should Be $true
    }

    It 'names a missing parameter instead of guessing a folder' {
        $r = Invoke-KitOperation -Name 'pinbally.detect' -PinballStatePath $pb
        $r.Status | Should Be 'Failed'
        $r.Message | Should Match 'Path'
        $r.Success | Should Be $false
    }

    It 'describes the installation and puts every path that does not resolve into Warnings' {
        $root = New-PinballYApiFixture 'detect'
        $r = Invoke-KitOperation -Name 'pinbally.detect' -Parameters @{ Path = $root } -PinballStatePath $pb
        $r.Status | Should Be 'Ok'
        $r.Success | Should Be $true
        $r.Kind | Should Be 'Read'
        $r.Applied | Should Be $false
        $r.Data.Root | Should BeExactly $root
        $r.Data.Encoding | Should BeExactly 'utf-8-bom'
        $r.Data.Game | Should Be 3
        $r.Data.WriteSafe | Should Be $true
        @($r.Data.Reference).Count | Should Be 13
        @( @( $r.Data.ReferenceMissing ) ).Count | Should Be 2
        @( @( $r.Data.ReferenceForeign ) ).Count | Should Be 2
        # Two broken here, two from another machine: a person reading only the Message would miss all four.
        @($r.Warnings).Count | Should Be 4
        (@($r.Warnings) | Where-Object { $_ -match 'another machine' }).Count | Should Be 2
    }

    It 'stays a Read when somebody passes -Apply, and writes nothing either way' {
        $root = New-PinballYApiFixture 'apply'
        $before = Get-PinballYTreeHash -Root $root
        $r = Invoke-KitOperation -Name 'pinbally.detect' -Parameters @{ Path = $root } -Apply -PinballStatePath $pb
        $r.Status | Should Be 'Ok'
        $r.Applied | Should Be $false
        $r.Changes.Count | Should Be 0
        $r.Backups.Count | Should Be 0
        Get-PinballYTreeHash -Root $root | Should BeExactly $before
    }

    It 'reports a folder that is not an installation as failed, with the reason' {
        $base = (Resolve-Path -LiteralPath $TestDrive).ProviderPath
        $elsewhere = Join-Path $base 'not-pinbally'
        $null = New-Item -ItemType Directory -Path $elsewhere -Force
        $r = Invoke-KitOperation -Name 'pinbally.detect' -Parameters @{ Path = $elsewhere } -PinballStatePath $pb
        $r.Status | Should Be 'Failed'
        $r.Message | Should Match 'No PinballY installation'
        $r.Success | Should Be $false
    }

    It 'is unknown to the API without becoming a change: no approval is ever asked for' {
        $root = New-PinballYApiFixture 'approval'
        $r = Invoke-KitOperation -Name 'pinbally.detect' -Parameters @{ Path = $root } -PinballStatePath $pb
        @($r.Approvals).Count | Should Be 0
    }
}

Describe 'Kit API: components knows the second front end' {
    Set-KitCulture -Culture 'en-US'
    $pb = Join-Path $TestDrive 'components-state.json'

    It 'reports PinballY as unknown while no folder is recorded' {
        $row = @( @(Invoke-KitOperation -Name 'components' -PinballStatePath $pb).Data.Components |
            Where-Object { $_.Name -eq 'PinballY' } )[0]
        $row.Present | Should Be $false
        # Not found is not the same as absent: the kit does not search drives for a folder a person never named.
        $row.Detail | Should Match 'pinbally.detect'
    }

    It 'reports the version and the folder once the state names it' {
        $root = New-PinballYApiFixture 'component'
        Set-KitStateValue -Path $pb -Key 'PinballYRoot' -Value $root
        $row = @( @(Invoke-KitOperation -Name 'components' -PinballStatePath $pb).Data.Components |
            Where-Object { $_.Name -eq 'PinballY' } )[0]
        $row.Present | Should Be $true
        $row.Path | Should BeExactly $root
    }

    It 'says what is wrong when the recorded folder no longer holds an installation' {
        Set-KitStateValue -Path $pb -Key 'PinballYRoot' -Value (Join-Path $TestDrive 'moved-away')
        $row = @( @(Invoke-KitOperation -Name 'components' -PinballStatePath $pb).Data.Components |
            Where-Object { $_.Name -eq 'PinballY' } )[0]
        $row.Present | Should Be $false
        # The recorded folder is named, so the answer names what is missing there instead of saying "no".
        $row.Detail | Should Match 'No PinballY installation'
    }
}
