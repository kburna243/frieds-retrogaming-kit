$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force

Describe 'Log' {
    It 'writes level and message to the log file (UTF-8)' {
        $log = Join-Path $TestDrive 'a\kit.log'
        Start-KitLog -Path $log -NoTranscript
        Write-KitLog 'Tür offen' -Level Warn
        Write-KitLog 'kaputt' -Level Error
        Stop-KitLog
        $content = [IO.File]::ReadAllText($log, [Text.Encoding]::UTF8)
        $content | Should Match '\[WARN\] Tür offen'
        $content | Should Match '\[ERROR\] kaputt'
    }

    It 'stops writing to the file after Stop-KitLog' {
        $log = Join-Path $TestDrive 'b.log'
        Start-KitLog -Path $log -NoTranscript
        Stop-KitLog
        Write-KitLog 'after stop'
        [IO.File]::ReadAllText($log) | Should Not Match 'after stop'
    }

    It 'starts and stops a transcript next to the log' {
        $log = Join-Path $TestDrive 'c.log'
        Start-KitLog -Path $log
        Write-KitLog 'in transcript'
        Stop-KitLog
        Join-Path $TestDrive 'c.transcript.log' | Should Exist
    }

    It 'rejects unknown levels' {
        { Write-KitLog 'x' -Level Debug } | Should Throw
    }
}
