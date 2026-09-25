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

Describe 'Support log export' {
    It 'replaces profile path, user name, computer name and account SIDs' {
        $text = 'C:\Users\Max Muster\AppData\x | user Max Muster on CAB-PC | S-1-5-21-1111111111-2222222222-3333333333-1001 | S-1-5-18 | Maximilian'
        $out = ConvertTo-KitAnonymousText -Text $text -UserName 'Max Muster' -ComputerName 'CAB-PC' -UserProfile 'C:\Users\Max Muster'
        $out | Should BeExactly '<USERPROFILE>\AppData\x | user <USER> on <COMPUTER> | <SID> | S-1-5-18 | Maximilian'
    }

    It 'does not eat parts of words for a short user name' {
        ConvertTo-KitAnonymousText -Text 'Tables and a table' -UserName 'a' -ComputerName '' -UserProfile '' | Should BeExactly 'Tables and <USER> table'
    }

    It 'writes one anonymized file from this machine''s log and transcript' {
        $log = Join-Path $TestDrive 'support\kit.log'
        Start-KitLog -Path $log -NoTranscript
        Write-KitLog "profile $env:USERPROFILE, user $env:USERNAME, computer $env:COMPUTERNAME, sid $([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)"
        Get-KitLogFile | Should BeExactly $log
        Stop-KitLog
        $dest = Join-Path $TestDrive 'support\kit.support.txt'
        $null = Export-KitSupportLog -Path $log, (Join-Path $TestDrive 'support\missing.log') -Destination $dest
        $out = [IO.File]::ReadAllText($dest)
        $out | Should Match '<USERPROFILE>'
        $out | Should Match '<SID>'
        $out.IndexOf($env:USERNAME, [StringComparison]::OrdinalIgnoreCase) | Should Be -1
        $out.IndexOf($env:COMPUTERNAME, [StringComparison]::OrdinalIgnoreCase) | Should Be -1
    }
}
