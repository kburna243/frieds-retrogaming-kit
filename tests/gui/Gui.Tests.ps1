$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
# The core is imported here as well: the GUI module loads it only into its own scope, and this file must not
# depend on another test file having imported it first.
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1') -Force
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1') -Force
Import-Module (Join-Path $kitRoot 'gui\RetroCabinetKit.Gui.psd1') -Force
$guiScript = Join-Path $kitRoot 'gui\Start-KitGui.ps1'

function New-TestResult([string] $Area, [string] $Name, [string] $Level, [string] $Detail = '') {
    New-KitCheckResult -Area $Area -Name $Name -Level $Level -Detail $Detail
}

# Dot-sourced with -NoShow: the window is built, never shown; the doctor rows and the wizard launcher are injected.
Describe 'Dashboard (WPF, no window is shown)' {
    $healthy = @(
        New-TestResult 'System' 'Windows' Ok 'Windows 11'
        New-TestResult 'System' 'Administrator' Info 'not elevated'
        New-TestResult 'Lightgun' 'ViGEmBus' Ok 'running'
    )

    It 'every text comes from the language files (de and en), no [[missing]] key' {
        foreach ($culture in 'de-DE', 'en-US') {
            $ui = . $guiScript -NoShow -Culture $culture -DoctorResult $healthy
            try {
                $texts = New-Object Collections.Generic.List[string]
                $queue = New-Object Collections.Generic.Queue[object]
                $queue.Enqueue($ui.Window)
                while ($queue.Count) {
                    $n = $queue.Dequeue()
                    if ($n -is [Windows.Controls.TextBlock]) { $texts.Add([string]$n.Text) }
                    elseif ($n -is [Windows.Controls.ContentControl] -and $n.Content -is [string]) { $texts.Add($n.Content) }
                    foreach ($child in [Windows.LogicalTreeHelper]::GetChildren($n)) { if ($child -is [Windows.DependencyObject]) { $queue.Enqueue($child) } }
                }
                @($texts | Where-Object { $_ -match '\[\[' }) | Should BeNullOrEmpty
                $ui.Controls.NewPinballButton.Content | Should Be (Get-KitText 'Gui.New.Pinball')
                ($ui.Controls.BackupList.View.Columns | ForEach-Object { $_.Header }) -join '|' | Should Not Match '\[\['
            } finally { $ui.Window.Close() }
        }
    }

    It 'healthy status: one row per area, crown shown, summary and footer filled' {
        $ui = . $guiScript -NoShow -Culture 'en-US' -DoctorResult $healthy
        try {
            @($ui.Controls.StatusRows.ItemsSource).Count | Should Be 2
            $ui.Controls.StatusSummary.Text | Should Match 'Everything healthy'
            $ui.Controls.StatusCrown.Visibility | Should Be 'Visible'
            $ui.Controls.FooterVersion.Text | Should Match ([regex]::Escape(([IO.File]::ReadAllText((Join-Path $kitRoot 'VERSION'))).Trim()))
            $ui.Controls.MigrateButton.IsEnabled | Should Be $true
        } finally { $ui.Window.Close() }
    }

    It 'the worst level of an area wins; errors hide the crown' {
        $mixed = @(
            New-TestResult 'System' 'Windows' Ok
            New-TestResult 'Lightgun' 'ViGEmBus' Error 'Not installed'
            New-TestResult 'Lightgun' 'DolphinBar' Warn 'Mode12'
        )
        $s = Get-KitGuiStatus -Result $mixed
        ($s.Rows | ForEach-Object { '{0}={1}' -f $_.Area, $_.Level }) -join ' ' | Should BeExactly 'System=Ok Lightgun=Error'
        $s.Level | Should Be 'Error'
        ($s.Rows | Where-Object { $_.Area -eq 'Lightgun' }).Detail -join ' | ' | Should Match 'ViGEmBus: Not installed \| DolphinBar: Mode12'
        ($s.Rows | Where-Object { $_.Area -eq 'Lightgun' }).DetailVisibility | Should Be 'Visible'
        ($s.Rows | Where-Object { $_.Area -eq 'System' }).DetailVisibility | Should Be 'Collapsed'
        $ui = . $guiScript -NoShow -Culture 'en-US' -DoctorResult $mixed
        try { $ui.Controls.StatusCrown.Visibility | Should Be 'Collapsed' } finally { $ui.Window.Close() }
    }

    It 'the tiles start the wizards through the launcher and open the migrate and recover views' {
        $script:launched = @()
        $ui = . $guiScript -NoShow -Culture 'en-US' -DoctorResult $healthy -Launcher { param($Suite) $script:launched += $Suite }
        try {
            $click = [Windows.Controls.Primitives.ButtonBase]::ClickEvent
            $ui.Controls.NewPinballButton.RaiseEvent((New-Object Windows.RoutedEventArgs $click))
            $ui.Controls.NewLightgunButton.RaiseEvent((New-Object Windows.RoutedEventArgs $click))
            $script:launched -join ',' | Should BeExactly 'Pinball,Lightgun'
            $ui.Controls.MigrateButton.RaiseEvent((New-Object Windows.RoutedEventArgs $click))
            $ui.Controls.MigrateView.Visibility | Should Be 'Visible'
            $ui.Controls.DashboardView.Visibility | Should Be 'Collapsed'
            $ui.Controls.BackButton.RaiseEvent((New-Object Windows.RoutedEventArgs $click))
            $ui.Values['BackupRoots'] = @(Join-Path $TestDrive 'no-backups-here')
            $ui.Controls.RecoverButton.RaiseEvent((New-Object Windows.RoutedEventArgs $click))
            $ui.Controls.MigrateView.Visibility | Should Be 'Collapsed'
            $ui.Controls.RecoverView.Visibility | Should Be 'Visible'
            $ui.Controls.DashboardView.Visibility | Should Be 'Collapsed'
            $ui.Controls.BackButton.RaiseEvent((New-Object Windows.RoutedEventArgs $click))
            $ui.Controls.DashboardView.Visibility | Should Be 'Visible'
        } finally { $ui.Window.Close() }
    }

    It 'renders a snapshot without showing a window (dashboard, migrate and recover view)' {
        $ui = . $guiScript -NoShow -Culture 'en-US' -DoctorResult $healthy
        try {
            $png = Save-KitGuiSnapshot -Ui $ui -Path (Join-Path $TestDrive 'dashboard.png')
            $png.Length | Should BeGreaterThan 10000
            Show-KitGuiView -Ui $ui -Name Migrate
            (Save-KitGuiSnapshot -Ui $ui -Path (Join-Path $TestDrive 'migrate.png')).Length | Should BeGreaterThan 5000
            Show-KitGuiView -Ui $ui -Name Recover
            (Save-KitGuiSnapshot -Ui $ui -Path (Join-Path $TestDrive 'recover.png')).Length | Should BeGreaterThan 5000
            $ui.Window.Content | Should Not BeNullOrEmpty # the content is back in the window
        } finally { $ui.Window.Close() }
    }

    It 'starts in a fresh Windows PowerShell process like Start-Kit.cmd does (only the script, nothing preloaded)' {
        $png = Join-Path $TestDrive 'fresh.png'
        $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
        $out = & $exe -NoProfile -ExecutionPolicy Bypass -File $guiScript -Culture 'en-US' -Screenshot $png 2>&1
        $LASTEXITCODE | Should Be 0
        ($out | Out-String) | Should Not Match 'not recognized|Exception'
        $png | Should Exist
    }

    It 'switching the language re-translates the window' {
        $ui = . $guiScript -NoShow -Culture 'en-US' -DoctorResult $healthy
        try {
            $click = [Windows.Controls.Primitives.ButtonBase]::ClickEvent
            $ui.Controls.LangEnButton.Tag | Should Be 'active'
            $ui.Controls.LangDeButton.RaiseEvent((New-Object Windows.RoutedEventArgs $click))
            $ui.Controls.NewPinballButton.Content | Should BeExactly 'Pinball einrichten'
            $ui.Controls.StatusSummary.Text | Should Match 'Alles gesund'
            $ui.Controls.LangDeButton.Tag | Should Be 'active'
            $ui.Controls.LangEnButton.Tag | Should BeNullOrEmpty
        } finally { $ui.Window.Close(); Set-KitCulture -Culture 'en-US' }
    }
}

Describe 'Recover view' {
    Set-KitCulture -Culture 'en-US'
    $root = Join-Path $TestDrive 'cab'
    $cfg = Join-Path $root 'RetroBat\es_settings.cfg'
    New-Item -ItemType Directory -Path (Split-Path -Parent $cfg) -Force | Out-Null
    [IO.File]::WriteAllText($cfg, 'current')
    [IO.File]::WriteAllText("$cfg.bak_lightgun_20260101-100000-000", 'older')

    It 'lists the backups, restores in the dry run without asking, then for real after a yes' {
        $ui = . $guiScript -NoShow -Culture 'en-US' -DoctorResult @()
        try {
            $ui.Values['BackupRoots'] = @($root)
            $rows = @(Update-KitGuiBackupList -Ui $ui)
            $rows.Count | Should Be 1
            $rows[0].TargetText | Should BeExactly $cfg
            $ui.Controls.BackupList.SelectedIndex = 0

            $ui.Controls.DryRunBox.IsChecked | Should Be $true
            (Invoke-KitGuiRestoreBackup -Ui $ui -Confirm { throw 'a dry run must not ask' }).Status | Should Be 'WhatIf'
            [IO.File]::ReadAllText($cfg) | Should BeExactly 'current'

            $ui.Controls.DryRunBox.IsChecked = $false
            $null = Invoke-KitGuiRestoreBackup -Ui $ui -Confirm { $false }
            [IO.File]::ReadAllText($cfg) | Should BeExactly 'current' # declined
            (Invoke-KitGuiRestoreBackup -Ui $ui -Confirm { $true }).Status | Should Be 'Done'
            [IO.File]::ReadAllText($cfg) | Should BeExactly 'older'
            $ui.Controls.RecoverLog.Text | Should Match 'Restored'
        } finally { $ui.Window.Close() }
    }

    It 'a running guarded program blocks the restore; nothing selected only asks to select' {
        $ui = . $guiScript -NoShow -Culture 'en-US' -DoctorResult @()
        try {
            $ui.Values['BackupRoots'] = @($root)
            $null = Update-KitGuiBackupList -Ui $ui
            Invoke-KitGuiRestoreBackup -Ui $ui -Confirm { $true } | Should BeNullOrEmpty
            $ui.Controls.RecoverLog.Text | Should Match 'Select a backup'
            $ui.Controls.BackupList.SelectedIndex = 0
            $ui.Controls.DryRunBox.IsChecked = $false
            $null = Invoke-KitGuiRestoreBackup -Ui $ui -Guard { throw 'Please close RetroBat first.' } -Confirm { $true }
            $ui.Controls.RecoverLog.Text | Should Match 'Please close RetroBat'
        } finally { $ui.Window.Close() }
    }

    It 'deletes the selected backup only after a yes' {
        $ui = . $guiScript -NoShow -Culture 'en-US' -DoctorResult @()
        try {
            $victim = "$cfg.bak_lightgun_20260301-100000-000"
            [IO.File]::WriteAllText($victim, 'to delete')
            $ui.Values['BackupRoots'] = @($root)
            $rows = @(Update-KitGuiBackupList -Ui $ui)
            $ui.Controls.BackupList.SelectedIndex = [array]::IndexOf(@($rows | ForEach-Object { $_.Path }), $victim)
            $null = Invoke-KitGuiRemoveBackup -Ui $ui -Confirm { $false }
            $victim | Should Exist
            (Invoke-KitGuiRemoveBackup -Ui $ui -Confirm { $true }).Status | Should Be 'Done'
            $victim | Should Not Exist
        } finally { $ui.Window.Close() }
    }

    It 'checks and exports the selected backup' {
        $ui = . $guiScript -NoShow -Culture 'en-US' -DoctorResult @()
        try {
            $ui.Values['BackupRoots'] = @($root)
            $null = Update-KitGuiBackupList -Ui $ui
            $ui.Controls.BackupList.SelectedIndex = 0
            (Invoke-KitGuiCheckBackup -Ui $ui).Data.Ok | Should Be $true
            $r = Invoke-KitGuiExportBackup -Ui $ui -Destination (Join-Path $TestDrive 'usb')
            $r.Status | Should Be 'Done'
            Join-Path (Join-Path $TestDrive 'usb') 'SHA256SUMS.txt' | Should Exist
            $r.Data.Exported | Should Match '\.bak_'
        } finally { $ui.Window.Close() }
    }
}

Describe 'Migrate view' {
    Set-KitCulture -Culture 'en-US'
    $newRetroBat = Join-Path $kitRoot 'tests\lightgun\New-LightgunTestRetroBat.ps1'
    $newGunmote = Join-Path $kitRoot 'tests\lightgun\New-LightgunTestGunmote.ps1'
    $rbA = Join-Path "$TestDrive" 'A\RetroBat'; $gmA = Join-Path "$TestDrive" 'A\Gunmote'
    $rbB = Join-Path "$TestDrive" 'B\RetroBat'; $gmB = Join-Path "$TestDrive" 'B\Gunmote'
    & $newRetroBat -Root $rbA; & $newGunmote -Gunmote $gmA
    & $newRetroBat -Root $rbB; & $newGunmote -Gunmote $gmB
    # A layout only cabinet A has, so the import has something to bring over.
    $kmJsonA = Join-Path $gmA 'Keymaps\Keymaps.json'
    $kmA = Get-Content -LiteralPath $kmJsonA -Raw | ConvertFrom-Json
    $kmA.LayoutChooser += @{ Title = 'RCK Pad 4:3'; Keymap = 'rck_pad43.json' }
    [IO.File]::WriteAllText($kmJsonA, (ConvertTo-Json $kmA -Depth 5), [Text.Encoding]::UTF8)
    [IO.File]::WriteAllText((Join-Path $gmA 'Keymaps\rck_pad43.json'), '{"pointer": "stick"}', [Text.Encoding]::UTF8)
    $layoutB = Join-Path $gmB 'Keymaps\rck_pad43.json'

    It 'exports on A, checks on B in the dry run without asking, imports only after a yes' {
        # The runner has no ViGEmBus; the driver check is not what this test is about.
        Mock -ModuleName 'RetroCabinetKit.Core' Get-LightgunViGEmState { [pscustomobject]@{ Installed = $true } }
        $ui = . $guiScript -NoShow -Culture 'en-US' -DoctorResult @() -View Migrate
        try {
            $ui.Controls.MigrateView.Visibility | Should Be 'Visible'
            $ui.Controls.ProfilePathText.Text | Should Be (Get-KitText 'Gui.Migrate.NoProfile')

            $ui.Values['ProfileRoots'] = @{ RetroBatRoot = $rbA; GunmoteDir = $gmA }
            $e = Invoke-KitGuiExportProfile -Ui $ui -Suite Lightgun -Destination (Join-Path "$TestDrive" 'usb')
            $e.Status | Should Be 'Done'
            $zip = @($e.Data.Result)[0].Path
            $zip | Should Exist
            $ui.Controls.MigrateLog.Text | Should Match 'exported'

            $ui.Values['ProfileRoots'] = @{ RetroBatRoot = $rbB; GunmoteDir = $gmB }
            Invoke-KitGuiImportProfile -Ui $ui -Confirm { throw 'nothing chosen, nothing to ask' } | Should BeNullOrEmpty
            $ui.Controls.MigrateLog.Text | Should Match 'Choose a profile first'
            $null = Select-KitGuiProfile -Ui $ui -Path $zip
            $ui.Controls.ProfilePathText.Text | Should BeExactly $zip

            $ui.Controls.MigrateDryRunBox.IsChecked | Should Be $true
            (Invoke-KitGuiImportProfile -Ui $ui -Confirm { throw 'a dry run must not ask' }).Status | Should Be 'WhatIf'
            $layoutB | Should Not Exist

            $ui.Controls.MigrateDryRunBox.IsChecked = $false
            Invoke-KitGuiImportProfile -Ui $ui -Confirm { $false } | Should BeNullOrEmpty
            $layoutB | Should Not Exist
            $r = Invoke-KitGuiImportProfile -Ui $ui -Confirm { $true }
            $r.Applied | Should Be $true
            $layoutB | Should Exist
            $ui.Controls.MigrateLog.Text | Should Match '\[Done\]'
        } finally { $ui.Window.Close() }
    }

    It 'a plan that needs approval is shown to the person, and the import runs again only after a yes' {
        Mock -ModuleName 'RetroCabinetKit.Core' Get-LightgunViGEmState { [pscustomobject]@{ Installed = $false } }
        Mock -ModuleName 'RetroCabinetKit.Core' Test-KitAdmin { $true }
        Mock -ModuleName 'RetroCabinetKit.Core' Install-LightgunViGEm { if ($Approve -and (& $Approve 'ViGEmBus 1.22 SHA-256 ...')) { 0 } else { throw 'declined' } }
        $ui = . $guiScript -NoShow -Culture 'en-US' -DoctorResult @() -View Migrate
        try {
            $ui.Values['ProfileRoots'] = @{ RetroBatRoot = $rbB; GunmoteDir = $gmB }
            $null = Select-KitGuiProfile -Ui $ui -Path @(Get-ChildItem -LiteralPath (Join-Path "$TestDrive" 'usb') -Filter '*.zip')[0].FullName
            $ui.Controls.MigrateDryRunBox.IsChecked = $false
            $ui.Controls.AutoInstallBox.IsChecked = $true
            $script:asked = @()
            $r = Invoke-KitGuiImportProfile -Ui $ui -Confirm { param($t) $script:asked += $t; $script:asked.Count -eq 1 }
            $script:asked.Count | Should Be 2
            $script:asked[1] | Should Match 'ViGEmBus 1.22'
            $r.Status | Should Be 'NeedsUser' # the person said no to the installer
            $script:asked = @()
            $r = Invoke-KitGuiImportProfile -Ui $ui -Confirm { param($t) $script:asked += $t; $true }
            $script:asked.Count | Should Be 2
            $r.Approvals.Count | Should Be 1
            @($r.Data.Result | Where-Object { $_.Name -eq 'lightgun-vigem' })[0].Status | Should Be 'Done'
        } finally { $ui.Window.Close() }
    }
}
