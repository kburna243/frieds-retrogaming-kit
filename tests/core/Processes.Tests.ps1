$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force

Describe 'Processes' {
    $self = Get-Process -Id $PID

    It 'returns nothing for processes that are not running' {
        @(Test-KitProcessesClosed -Names 'rck-no-such-process-1', 'rck-no-such-process-2.exe').Count | Should Be 0
    }

    It 'reports running processes (with or without .exe)' {
        $running = @(Test-KitProcessesClosed -Names ($self.ProcessName + '.exe'))
        @($running | Where-Object { $_.Id -eq $PID }).Count | Should Be 1
    }

    It 'Wait returns $true at once when everything is closed' {
        Wait-KitProcessesClosed -Names 'rck-no-such-process' -TimeoutSeconds 5 | Should Be $true
    }

    It 'Wait returns $false on timeout and never ends the process' {
        Wait-KitProcessesClosed -Names $self.ProcessName -TimeoutSeconds 1 -PollSeconds 1 | Should Be $false
        (Get-Process -Id $PID).HasExited | Should Be $false
    }
}
