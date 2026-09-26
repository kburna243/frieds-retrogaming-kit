$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

function Read-ZipText([string] $Path) {
    $zip = [IO.Compression.ZipFile]::OpenRead($Path)
    try {
        $out = [ordered]@{}
        foreach ($e in $zip.Entries) {
            $r = New-Object IO.StreamReader ($e.Open())
            try { $out[$e.FullName] = $r.ReadToEnd() } finally { $r.Dispose() }
        }
        $out
    } finally { $zip.Dispose() }
}

Describe 'Support text anonymization' {
    # Built at run time: the repository itself must stay free of private addresses (tools\Test-Depersonalized.ps1).
    $lanIp = '192.' + '168.178.20'
    $cgnat = '100.' + '64.1.2'
    $mail = 'max' + '@' + 'evil.example'

    It 'hides profile path, user, computer, private IPs, e-mail and other users'' profile folders' {
        $text = "C:\Users\Max Muster\x | Max Muster on CAB-PC | $lanIp | $cgnat | $mail | D:\Users\Max Muster\y | 8.8.8.8"
        $out = ConvertTo-KitSupportText -Text $text -UserName 'Max Muster' -ComputerName 'CAB-PC' -UserProfile 'C:\Users\Max Muster'
        $d = 'D:' # a literal drive path ending in a placeholder would trip the repository's own depersonalization scan
        $out | Should BeExactly "<USERPROFILE>\x | <USER> on <COMPUTER> | <IP> | <IP> | <EMAIL> | $d\Users\<USER>\y | 8.8.8.8"
    }

    It 'hides a second account''s profile folder but keeps Public and Default' {
        $c = 'C:'; $d = 'D:'
        $out = ConvertTo-KitSupportText -Text "$d\Users\Max Muster\a | $c\Users\Public\b | $c\Users\Default\c" -UserName 'nobody' -ComputerName '' -UserProfile ''
        $out | Should BeExactly "$d\Users\<OTHERUSER>\a | $c\Users\Public\b | $c\Users\Default\c"
    }
}

Describe 'Support bundle' {
    Set-KitCulture -Culture 'en-US'
    $user = $env:USERNAME
    if (-not $user) { $user = 'Max Muster' }

    $state = Join-Path $TestDrive 'lightgun\install-state.json'
    New-Item -ItemType Directory -Path (Split-Path -Parent $state) -Force | Out-Null
    [IO.File]::WriteAllText($state, "{ ""Values"": { ""Note"": ""owner $user"" } }")
    $logs = Join-Path $TestDrive 'logs'
    New-Item -ItemType Directory -Path $logs -Force | Out-Null
    for ($i = 1; $i -le 7; $i++) {
        $f = Join-Path $logs "run$i.log"
        [IO.File]::WriteAllText($f, "log $i by $user")
        (Get-Item -LiteralPath $f).LastWriteTime = (Get-Date).AddMinutes($i)
    }
    [IO.File]::WriteAllText((Join-Path $logs 'notes.txt'), 'not a log')
    $doctor = @(
        New-KitCheckResult -Area 'System' -Name 'Windows' -Level Ok -Detail 'Windows 11'
        New-KitCheckResult -Area 'Lightgun' -Name 'ViGEmBus' -Level Error -Detail "missing for $user"
    )
    $env1 = @{ OsBuild = '22631'; PSVersion = '5.1'; Account = $user }
    $zipPath = Join-Path $TestDrive 'out\support.zip'
    $item = Export-KitSupportBundle -Destination $zipPath -DoctorResult $doctor -StatePath $state, (Join-Path $TestDrive 'missing.json') -LogDir $logs -Environment $env1
    $content = Read-ZipText $item.FullName

    It 'contains summary, environment, doctor report, the state and the five newest logs' {
        @($content.Keys) -join ',' | Should BeExactly 'environment.json,doctor.txt,doctor.json,state/lightgun-install-state.json,logs/run7.log,logs/run6.log,logs/run5.log,logs/run4.log,logs/run3.log,summary.json'
        $summary = $content['summary.json'] | ConvertFrom-Json
        $summary.Doctor.Error | Should Be 1
        $summary.Version | Should BeExactly ([IO.File]::ReadAllText((Join-Path $kitRoot 'VERSION'))).Trim()
        $content['doctor.txt'] | Should Match '\[ERROR\] ViGEmBus'
    }

    It 'no entry contains the user name' {
        foreach ($k in $content.Keys) { $content[$k] | Should Not Match ([regex]::Escape($user)) }
        $content['logs/run7.log'] | Should BeExactly 'log 7 by <USER>'
    }

    It 'never overwrites an existing file' {
        { Export-KitSupportBundle -Destination $zipPath -Environment $env1 } | Should Throw 'already exists'
    }
}
