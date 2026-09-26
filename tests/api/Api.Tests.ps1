$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
# Core and suites are re-imported together, like in the suite tests: a suite still bound to a core instance from an
# earlier test file would report its backups into that instance, not into the step running in the new one.
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1') -Force
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1') -Force
Import-Module (Join-Path $kitRoot 'api\RetroCabinetKit.Api.psd1') -Force
$apiScript = Join-Path $kitRoot 'api\Invoke-KitApi.ps1'
$newRetroBat = Join-Path $kitRoot 'tests\lightgun\New-LightgunTestRetroBat.ps1'

# Contract tests: the fields and rules of API.md. A change here is an API change (see "Versioning" there).
Describe 'Kit API contract' {
    Set-KitCulture -Culture 'en-US'
    $fields = 'ApiVersion', 'Operation', 'Kind', 'Success', 'Status', 'Applied', 'Message', 'Warnings', 'Errors',
              'Changes', 'Backups', 'Approvals', 'Duration', 'StartedAt', 'Data'

    It 'every result carries exactly the documented fields' {
        $r = Invoke-KitOperation -Name 'operations'
        ($r.PSObject.Properties.Name -join ',') | Should BeExactly ($fields -join ',')
        $r.ApiVersion | Should BeExactly (Get-KitApiVersion)
        $r.Status | Should Be 'Ok'
        $r.Success | Should Be $true
    }

    It 'the catalog lists the fixed operations, every step and the migration placeholders' {
        $names = @(Get-KitOperation | ForEach-Object { $_.Name })
        foreach ($n in 'operations', 'status', 'components', 'backups.list', 'backup.check', 'backup.restore', 'backup.export', 'support.bundle', 'profile.export', 'profile.import') {
            $names -contains $n | Should Be $true
        }
        $steps = @($names | Where-Object { $_ -like 'step.*' })
        $steps.Count | Should Be (@(Get-ChildItem (Join-Path $kitRoot 'pinball\steps') -Filter *.ps1).Count + @(Get-ChildItem (Join-Path $kitRoot 'lightgun\steps') -Filter *.ps1).Count)
        @(Get-KitOperation | Where-Object { $_.Name -like 'step.*' -and -not $_.Description }).Count | Should Be 0
    }

    It 'never offers script blocks, objects or security bindings as parameters' {
        $denied = 'Approve', 'StatePath', 'Culture', 'KitUserSid', 'TrustedOwner', 'TaskPrefix', 'AutomationDir', 'Devices', 'Monitors', 'Tasks', 'XInputReader'
        foreach ($op in Get-KitOperation) {
            foreach ($p in @($op.Parameters)) {
                $denied -contains $p.Name | Should Be $false
                $p.Type | Should Match '^(String|String\[\]|Int32|Int64|Boolean|switch)$'
            }
        }
    }

    It 'refuses unknown operations, unknown or denied parameters and missing mandatory ones, without throwing' {
        (Invoke-KitOperation -Name 'no.such.thing').Status | Should Be 'NotAvailable'
        $r = Invoke-KitOperation -Name 'step.lightgun.08-profileautomation' -Parameters @{ KitUserSid = 'S-1-5-18' }
        $r.Status | Should Be 'Failed'
        $r.Message | Should Match 'KitUserSid'
        (Invoke-KitOperation -Name 'step.lightgun.10-teknoparrot' -Parameters @{ Approve = { $true } }).Status | Should Be 'Failed'
        (Invoke-KitOperation -Name 'backup.check').Message | Should Match 'Missing parameter: Path'
    }

    It 'interactive steps and the migration without its engine are not available' {
        (Invoke-KitOperation -Name 'step.lightgun.09-verify').Status | Should Be 'NotAvailable'
        (Invoke-KitOperation -Name 'step.pinball.08-screens').Status | Should Be 'NotAvailable'
        if (-not (Get-Command Import-KitCabinetProfile -ErrorAction SilentlyContinue)) {
            (Invoke-KitOperation -Name 'profile.import').Status | Should Be 'NotAvailable'
        }
    }
}

Describe 'Kit API operations' {
    Set-KitCulture -Culture 'en-US'
    $rb = Join-Path $TestDrive 'RetroBat'
    & $newRetroBat -Root $rb
    $lg = Join-Path $TestDrive 'lightgun-state.json'
    $pb = Join-Path $TestDrive 'pinball-state.json'

    It 'a step runs as dry run by default: plan only, state untouched; with -Apply it is done and verified' {
        $r = Invoke-KitOperation -Name 'step.lightgun.01-detect' -Parameters @{ RetroBatRoot = $rb } -LightgunStatePath $lg -PinballStatePath $pb
        $r.Kind | Should Be 'Change'
        $r.Status | Should Be 'WhatIf'
        $r.Applied | Should Be $false
        $r.Success | Should Be $true
        $lg | Should Not Exist
        @($r.Data.Steps).Count | Should BeGreaterThan 0

        $r = Invoke-KitOperation -Name 'step.lightgun.01-detect' -Parameters @{ RetroBatRoot = $rb } -Apply -LightgunStatePath $lg -PinballStatePath $pb
        $r.Status | Should Be 'Done'
        Get-KitStateValue -Path $lg -Key 'RetroBatRoot' | Should BeExactly $rb
        (Invoke-KitOperation -Name 'step.lightgun.01-detect' -Parameters @{ RetroBatRoot = $rb } -Apply -LightgunStatePath $lg -PinballStatePath $pb).Status | Should Be 'Skipped'
    }

    It 'a step that changes files reports changes and backups; the dry run reports none' {
        $null = Invoke-KitOperation -Name 'step.lightgun.01-detect' -Parameters @{ RetroBatRoot = $rb } -Apply -LightgunStatePath $lg -PinballStatePath $pb
        $dry = Invoke-KitOperation -Name 'step.lightgun.07-retrobatsettings' -LightgunStatePath $lg -PinballStatePath $pb
        $dry.Status | Should Be 'WhatIf'
        @($dry.Changes).Count | Should Be 0
        $real = Invoke-KitOperation -Name 'step.lightgun.07-retrobatsettings' -Apply -LightgunStatePath $lg -PinballStatePath $pb
        $real.Status | Should Be 'Done'
        @($real.Backups).Count | Should BeGreaterThan 0
        @($real.Changes | Where-Object { $_.Kind -eq 'File' }).Count | Should BeGreaterThan 0
    }

    It 'status and components answer read-only with the documented data' {
        $s = Invoke-KitOperation -Name 'status' -LightgunStatePath $lg -PinballStatePath $pb
        $s.Status | Should Be 'Ok'
        $s.Data.Summary.Level | Should Match '^(Ok|Warn|Error)$'
        @($s.Data.Checks).Count | Should BeGreaterThan 5
        $c = Invoke-KitOperation -Name 'components' -LightgunStatePath $lg -PinballStatePath $pb
        @($c.Data.Components | ForEach-Object { $_.Name }) -contains 'RetroBat' | Should Be $true
    }

    It 'backup restore: dry run by default, restored with -Apply, current file saved first' {
        $f = Join-Path $TestDrive 'restore\es.cfg'
        New-Item -ItemType Directory -Path (Split-Path -Parent $f) -Force | Out-Null
        [IO.File]::WriteAllText($f, 'current')
        [IO.File]::WriteAllText("$f.bak_lightgun_20260101-100000-000", 'older')
        $list = Invoke-KitOperation -Name 'backups.list' -Parameters @{ Root = [string[]]@(Split-Path -Parent $f) }
        @($list.Data.Backups).Count | Should Be 1
        $p = @{ Path = "$f.bak_lightgun_20260101-100000-000" }
        (Invoke-KitOperation -Name 'backup.restore' -Parameters $p).Status | Should Be 'WhatIf'
        [IO.File]::ReadAllText($f) | Should BeExactly 'current'
        $r = Invoke-KitOperation -Name 'backup.restore' -Parameters $p -Apply
        $r.Status | Should Be 'Done'
        [IO.File]::ReadAllText($f) | Should BeExactly 'older'
        [IO.File]::ReadAllText($r.Data.SavedCurrent) | Should BeExactly 'current'
    }
}

Describe 'Kit API over JSON (another process)' {
    $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

    It 'writes exactly one JSON document, also for a dry run (no "What if" line on standard output)' {
        $f = Join-Path $TestDrive 'json\es.cfg'
        New-Item -ItemType Directory -Path (Split-Path -Parent $f) -Force | Out-Null
        [IO.File]::WriteAllText($f, 'current')
        [IO.File]::WriteAllText("$f.bak_lightgun_20260101-100000-000", 'older')
        $json = (@{ Path = "$f.bak_lightgun_20260101-100000-000" } | ConvertTo-Json -Compress) -replace '"', '\"'
        $out = & $exe -NoProfile -ExecutionPolicy Bypass -File $apiScript -Operation 'backup.restore' -ParametersJson $json
        $LASTEXITCODE | Should Be 0
        $r = ($out -join "`n") | ConvertFrom-Json
        $r.Status | Should Be 'WhatIf'
        [IO.File]::ReadAllText($f) | Should BeExactly 'current'
    }

    It 'exit code 2 and a JSON error for a refused request' {
        $out = & $exe -NoProfile -ExecutionPolicy Bypass -File $apiScript -Operation 'no.such.thing'
        $LASTEXITCODE | Should Be 2
        (($out -join "`n") | ConvertFrom-Json).Status | Should Be 'NotAvailable'
    }

    It '-Anonymize removes the user name and profile path from every value' {
        $r = New-KitOperationResult -Operation 'x' -Status Ok -Message "by $env:USERNAME in $env:USERPROFILE" -Data ([pscustomobject]@{ Nested = @("$env:USERPROFILE\x") })
        $json = ConvertTo-KitApiJson -Result $r -Anonymize
        $json | Should Not Match ([regex]::Escape($env:USERNAME))
        ($json | ConvertFrom-Json).Data.Nested[0] | Should BeExactly '<USERPROFILE>\x'
    }
}
