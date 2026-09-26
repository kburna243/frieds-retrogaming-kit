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
            $ui.Controls.MigrateButton.IsEnabled | Should Be $false # arrives with v0.3
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

    It 'the tiles start the wizards through the launcher and open the recover view' {
        $script:launched = @()
        $ui = . $guiScript -NoShow -Culture 'en-US' -DoctorResult $healthy -Launcher { param($Suite) $script:launched += $Suite }
        try {
            $click = [Windows.Controls.Primitives.ButtonBase]::ClickEvent
            $ui.Controls.NewPinballButton.RaiseEvent((New-Object Windows.RoutedEventArgs $click))
            $ui.Controls.NewLightgunButton.RaiseEvent((New-Object Windows.RoutedEventArgs $click))
            $script:launched -join ',' | Should BeExactly 'Pinball,Lightgun'
            $ui.Values['BackupRoots'] = @(Join-Path $TestDrive 'no-backups-here')
            $ui.Controls.RecoverButton.RaiseEvent((New-Object Windows.RoutedEventArgs $click))
            $ui.Controls.RecoverView.Visibility | Should Be 'Visible'
            $ui.Controls.DashboardView.Visibility | Should Be 'Collapsed'
            $ui.Controls.BackButton.RaiseEvent((New-Object Windows.RoutedEventArgs $click))
            $ui.Controls.DashboardView.Visibility | Should Be 'Visible'
        } finally { $ui.Window.Close() }
    }

    It 'renders a snapshot without showing a window (dashboard and recover view)' {
        $ui = . $guiScript -NoShow -Culture 'en-US' -DoctorResult $healthy
        try {
            $png = Save-KitGuiSnapshot -Ui $ui -Path (Join-Path $TestDrive 'dashboard.png')
            $png.Length | Should BeGreaterThan 10000
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
            (Invoke-KitGuiRestoreBackup -Ui $ui -Guard {} -Confirm { throw 'a dry run must not ask' }).Action | Should Be 'WhatIf'
            [IO.File]::ReadAllText($cfg) | Should BeExactly 'current'

            $ui.Controls.DryRunBox.IsChecked = $false
            $null = Invoke-KitGuiRestoreBackup -Ui $ui -Guard {} -Confirm { $false }
            [IO.File]::ReadAllText($cfg) | Should BeExactly 'current' # declined
            (Invoke-KitGuiRestoreBackup -Ui $ui -Guard {} -Confirm { $true }).Action | Should Be 'Restored'
            [IO.File]::ReadAllText($cfg) | Should BeExactly 'older'
            $ui.Controls.RecoverLog.Text | Should Match 'Restored'
        } finally { $ui.Window.Close() }
    }

    It 'a running guarded program blocks the restore; nothing selected only asks to select' {
        $ui = . $guiScript -NoShow -Culture 'en-US' -DoctorResult @()
        try {
            $ui.Values['BackupRoots'] = @($root)
            $null = Update-KitGuiBackupList -Ui $ui
            Invoke-KitGuiRestoreBackup -Ui $ui -Guard {} -Confirm { $true } | Should BeNullOrEmpty
            $ui.Controls.RecoverLog.Text | Should Match 'Select a backup'
            $ui.Controls.BackupList.SelectedIndex = 0
            $ui.Controls.DryRunBox.IsChecked = $false
            $null = Invoke-KitGuiRestoreBackup -Ui $ui -Guard { throw 'Please close RetroBat first.' } -Confirm { $true }
            $ui.Controls.RecoverLog.Text | Should Match 'Please close RetroBat'
        } finally { $ui.Window.Close() }
    }

    It 'checks and exports the selected backup' {
        $ui = . $guiScript -NoShow -Culture 'en-US' -DoctorResult @()
        try {
            $ui.Values['BackupRoots'] = @($root)
            $null = Update-KitGuiBackupList -Ui $ui
            $ui.Controls.BackupList.SelectedIndex = 0
            (Invoke-KitGuiCheckBackup -Ui $ui).Ok | Should Be $true
            $item = Invoke-KitGuiExportBackup -Ui $ui -Destination (Join-Path $TestDrive 'usb')
            Join-Path (Join-Path $TestDrive 'usb') 'SHA256SUMS.txt' | Should Exist
            $item.Name | Should Match '\.bak_'
        } finally { $ui.Window.Close() }
    }
}
