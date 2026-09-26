$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1') -Force
$wizardScript = Join-Path $kitRoot 'lightgun\ui\Wizard.ps1'

# Dot-sourced: the page builders use the wizard script's helper functions, which live as long as its scope.
Describe 'Lightgun wizard (smoke test, no window is shown)' {
    $state = Join-Path $TestDrive 'install-state.json'

    It 'lists start, steps 1-14, calibration, verify, credits and maintenance and builds every page without errors (de and en)' {
        foreach ($culture in 'de-DE', 'en-US') {
            $w = . $wizardScript -NoShow -Culture $culture -StatePath $state
            try {
                $w.Pages.Count | Should Be 18
                $w.List.Items.Count | Should Be 18
                $w.DryRunBox.Checked | Should Be $true # first run
                for ($i = 0; $i -lt $w.Pages.Count; $i++) { Show-KitWizardPage -Wizard $w -Index $i }
                $w.Log.Text | Should Not Match '\[X\]'
                $w.List.Items[16] | Should Be (Get-KitText 'Lightgun.Ui.Page.Credits')
                $w.List.Items[17] | Should Be (Get-KitText 'Ui.Care.Page')
                @($w.List.Items | Where-Object { $_ -match '^\[\[' }).Count | Should Be 0
            } finally { $w.Form.Dispose() }
        }
    }

    It 'shows German texts with umlauts' {
        $w = . $wizardScript -NoShow -Culture 'de-DE' -StatePath $state -Page 5
        try { $w.List.Items[5] | Should BeExactly '5  Störquellen' } finally { $w.Form.Dispose() }
    }

    It 'runs a step from the page as dry run: log lines in the log box, status WhatIf, nothing persisted' {
        $rb = Join-Path $TestDrive 'RetroBat'
        & (Join-Path $PSScriptRoot 'New-LightgunTestRetroBat.ps1') -Root $rb
        $dryState = Join-Path $TestDrive 'dry-state.json'
        $w = . $wizardScript -NoShow -Culture 'en-US' -StatePath $dryState -Page 1
        try {
            $w.Values['RetroBat'] = $rb
            Invoke-WizardStep 1 '01-Detect.ps1' @{ RetroBatRoot = $rb }
            $w.Status[1] | Should Be 'WhatIf'
            $w.Log.Text | Should Match '9\.9\.9-test'
            $w.Log.Text | Should Match 'dry run, nothing changed'
            $dryState | Should Not Exist
        } finally { $w.Form.Dispose() }
    }

    It 'shows the calibration guide and the credits' {
        $w = . $wizardScript -NoShow -Culture 'en-US' -StatePath $state -Page 14
        try {
            (@($w.Content.Controls[0].Controls | ForEach-Object { $_.Text }) -join ' ') | Should Match 'only ONE Wiimote'
            Show-KitWizardPage -Wizard $w -Index 16
            $box = @($w.Content.Controls[0].Controls | Where-Object { $_ -is [Windows.Forms.RichTextBox] })[0]
            $box.Text | Should Match 'https://github.com/gunmotelabs/Gunmote'
        } finally { $w.Form.Dispose() }
    }

    It 'maintenance page: doctor into the log, backups listed, restore follows the dry run, support bundle' {
        $rb = Join-Path $TestDrive 'CareRetroBat'
        & (Join-Path $PSScriptRoot 'New-LightgunTestRetroBat.ps1') -Root $rb
        $careState = Join-Path $TestDrive 'care-state.json'
        Set-KitStateValue -Path $careState -Key 'RetroBatRoot' -Value $rb
        $cfg = (Get-LightgunRetroBatPath -Root $rb).EsSettings
        $current = [IO.File]::ReadAllText($cfg)
        [IO.File]::WriteAllText("$cfg.bak_lightgun_20260101-100000-000", 'older settings')
        $w = . $wizardScript -NoShow -Culture 'en-US' -StatePath $careState -Page 17
        try {
            $w.Pages[17].Care.LogDir = Join-Path $TestDrive 'care-logs' # never the kit's own logs folder
            $w.Pages[17].Care.Guard = {}                                 # no guarded program check on a test machine
            @(Invoke-KitCareDoctor -Wizard $w).Count | Should BeGreaterThan 5
            $w.Log.Text | Should Match 'Result: \d+ error'

            $rows = @(Update-KitCareBackupList -Wizard $w)
            $rows.Count | Should Be 1
            $w.Values['CareList'].Items.Count | Should Be 1
            $w.Values['CareList'].SelectedIndex = 0

            $w.DryRunBox.Checked | Should Be $true # first run
            (Invoke-KitCareRestore -Wizard $w -Confirm { throw 'a dry run must not ask' }).Action | Should Be 'WhatIf'
            [IO.File]::ReadAllText($cfg) | Should BeExactly $current
            $w.DryRunBox.Checked = $false
            $null = Invoke-KitCareRestore -Wizard $w -Confirm { $false }
            [IO.File]::ReadAllText($cfg) | Should BeExactly $current # declined
            (Invoke-KitCareRestore -Wizard $w -Confirm { $true }).Action | Should Be 'Restored'
            [IO.File]::ReadAllText($cfg) | Should BeExactly 'older settings'

            $zip = Invoke-KitCareSupportBundle -Wizard $w
            $zip.FullName | Should Match 'care-logs'
            $w.Log.Text | Should Match 'Support bundle created'
        } finally { $w.Form.Dispose() }
    }
}
