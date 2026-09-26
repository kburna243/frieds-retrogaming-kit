$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

Describe 'Recovery: backup names' {
    It 'reads original, purpose and time of both stamp formats' {
        $a = ConvertFrom-KitFileBackupName -Path (Join-Path $TestDrive 'es_settings.cfg.bak_lightgun_20260925-231000-123')
        $a.Original | Should BeExactly (Join-Path $TestDrive 'es_settings.cfg')
        $a.Purpose | Should BeExactly 'lightgun'
        $a.Created | Should Be ([datetime]::new(2026, 9, 25, 23, 10, 0, 123))
        $b = ConvertFrom-KitFileBackupName -Path (Join-Path $TestDrive 'PUPDatabase.db.bak_relocate_20260101-080000')
        $b.Purpose | Should BeExactly 'relocate'
        $b.Created | Should Be ([datetime]::new(2026, 1, 1, 8, 0, 0))
    }

    It 'anything else is no backup' {
        ConvertFrom-KitFileBackupName -Path (Join-Path $TestDrive 'notes.bak') | Should BeNullOrEmpty
        ConvertFrom-KitFileBackupName -Path (Join-Path $TestDrive 'x.bak_lightgun_yesterday') | Should BeNullOrEmpty
    }
}

Describe 'Recovery: list, check, restore, export, remove' {
    Set-KitCulture -Culture 'en-US'
    $root = Join-Path $TestDrive 'cab'
    $cfg = Join-Path $root 'RetroBat\emulationstation\.emulationstation\es_settings.cfg'
    New-Item -ItemType Directory -Path (Split-Path -Parent $cfg) -Force | Out-Null
    [IO.File]::WriteAllText($cfg, 'current')
    [IO.File]::WriteAllText("$cfg.bak_lightgun_20260101-100000-000", 'older')
    [IO.File]::WriteAllText("$cfg.bak_lightgun_20260201-100000-000", 'newer')
    [IO.File]::WriteAllText((Join-Path $root 'readme.txt'), 'no backup')
    $backups = Join-Path $root 'backups'
    $zipPath = Join-Path $backups 'pinball-finish_20260301-100000.zip'
    $null = New-KitBackup -Files $cfg -Destination $zipPath
    [IO.File]::WriteAllText((Join-Path $backups 'random.zip'), 'not a zip')

    It 'lists zip backups and file copies, newest first, and ignores other files' {
        $list = @(Get-KitBackup -Path $backups, $root)
        $list.Count | Should Be 3
        $list[0].Kind | Should Be 'Zip'
        $list[0].Files | Should Be 1
        ($list | Select-Object -Skip 1 | ForEach-Object { Split-Path -Leaf $_.Path }) -join ',' |
            Should BeExactly 'es_settings.cfg.bak_lightgun_20260201-100000-000,es_settings.cfg.bak_lightgun_20260101-100000-000'
        $list[1].Original | Should BeExactly $cfg
    }

    It 'an intact zip passes; a changed entry is reported' {
        (Test-KitBackup -Path $zipPath).Ok | Should Be $true
        $bad = Join-Path $TestDrive 'tampered.zip'
        Copy-Item -LiteralPath $zipPath -Destination $bad
        $zip = [IO.Compression.ZipFile]::Open($bad, [IO.Compression.ZipArchiveMode]::Update)
        try {
            $entry = @($zip.Entries | Where-Object { $_.FullName -like 'files/*' })[0]
            $name = $entry.FullName; $entry.Delete()
            $w = New-Object IO.StreamWriter ($zip.CreateEntry($name).Open())
            try { $w.Write('changed') } finally { $w.Dispose() }
        } finally { $zip.Dispose() }
        $r = Test-KitBackup -Path $bad
        $r.Ok | Should Be $false
        $r.Problems[0] | Should Match 'Checksum does not match'
    }

    It 'a file copy that differs from the current file is marked' {
        (Test-KitBackup -Path "$cfg.bak_lightgun_20260101-100000-000").Differs | Should Be $true
    }

    It 'dry run changes nothing' {
        $r = Restore-KitFileBackup -Path "$cfg.bak_lightgun_20260101-100000-000" -WhatIf
        $r.Action | Should Be 'WhatIf'
        [IO.File]::ReadAllText($cfg) | Should BeExactly 'current'
        @(Get-ChildItem -LiteralPath (Split-Path -Parent $cfg) -Filter '*.bak_recovery_*').Count | Should Be 0
    }

    It 'restores a file copy and saves the current file first, so the restore can be undone' {
        $r = Restore-KitFileBackup -Path "$cfg.bak_lightgun_20260101-100000-000" -Confirm:$false
        $r.Action | Should Be 'Restored'
        [IO.File]::ReadAllText($cfg) | Should BeExactly 'older'
        [IO.File]::ReadAllText($r.SavedCurrent) | Should BeExactly 'current'
        (ConvertFrom-KitFileBackupName -Path $r.SavedCurrent).Purpose | Should BeExactly 'recovery'
        Test-Path -LiteralPath "$cfg.restore_tmp" | Should Be $false
    }

    It 'refuses to restore or remove something that is no backup' {
        { Restore-KitFileBackup -Path (Join-Path $root 'readme.txt') -Confirm:$false } | Should Throw 'Not a backup'
        { Remove-KitBackup -Path (Join-Path $root 'readme.txt') -Confirm:$false } | Should Throw 'Not a backup'
        Join-Path $root 'readme.txt' | Should Exist
    }

    It 'exports with a checksum line and never overwrites' {
        $dest = Join-Path $TestDrive 'usb'
        $item = Export-KitBackup -Path $zipPath -Destination $dest
        $hash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        [IO.File]::ReadAllText((Join-Path $dest 'SHA256SUMS.txt')) | Should BeExactly "$hash  $($item.Name)`n"
        { Export-KitBackup -Path $zipPath -Destination $dest } | Should Throw 'already exists'
    }

    It 'removes a backup' {
        $victim = "$cfg.bak_lightgun_20260201-100000-000"
        Remove-KitBackup -Path $victim -Confirm:$false
        $victim | Should Not Exist
    }
}
