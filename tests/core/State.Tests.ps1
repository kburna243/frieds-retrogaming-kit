$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force

Describe 'State' {
    It 'returns an empty state when the file does not exist' {
        $s = Read-KitState -Path (Join-Path $TestDrive 'none.json')
        $s.Version | Should Be 1
        @($s.Steps.PSObject.Properties).Count | Should Be 0
    }

    It 'round-trips values of several types' {
        $p = Join-Path $TestDrive 'values.json'
        Set-KitStateValue -Path $p -Key 'OldRoot' -Value 'C:\Games\Alt Ordner ä'
        Set-KitStateValue -Path $p -Key 'Count' -Value 42
        Set-KitStateValue -Path $p -Key 'Columns' -Value @('DirGames', 'LaunchScript')
        Get-KitStateValue -Path $p -Key 'OldRoot' | Should BeExactly 'C:\Games\Alt Ordner ä'
        Get-KitStateValue -Path $p -Key 'Count' | Should Be 42
        (Get-KitStateValue -Path $p -Key 'Columns') -join ',' | Should Be 'DirGames,LaunchScript'
        Get-KitStateValue -Path $p -Key 'Missing' | Should BeNullOrEmpty
    }

    It 'stores step status and overwrites it' {
        $p = Join-Path $TestDrive 'steps.json'
        Set-KitStepStatus -Path $p -Name 'copy' -Status Failed -Message 'x'
        Set-KitStepStatus -Path $p -Name 'copy' -Status Done
        Get-KitStepStatus -Path $p -Name 'copy' | Should Be 'Done'
        Get-KitStepStatus -Path $p -Name 'other' | Should BeNullOrEmpty
    }

    It 'leaves no temp file after saving' {
        $p = Join-Path $TestDrive 'clean.json'
        Set-KitStateValue -Path $p -Key 'a' -Value 1
        Set-KitStateValue -Path $p -Key 'b' -Value 2
        "$p.tmp" | Should Not Exist
    }

    It 'keeps the old file byte-identical when writing fails (atomic)' {
        $p = Join-Path $TestDrive 'atomic.json'
        Set-KitStateValue -Path $p -Key 'a' -Value 'before'
        $before = [IO.File]::ReadAllBytes($p)
        $lock = [IO.File]::Open("$p.tmp", 'Create', 'ReadWrite', 'None')
        try {
            { Set-KitStateValue -Path $p -Key 'a' -Value 'after' } | Should Throw
        } finally { $lock.Dispose() }
        [Convert]::ToBase64String([IO.File]::ReadAllBytes($p)) | Should Be ([Convert]::ToBase64String($before))
        Get-KitStateValue -Path $p -Key 'a' | Should Be 'before'
    }
}
