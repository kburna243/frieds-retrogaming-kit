$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1') -Force
$wizardScript = Join-Path $kitRoot 'lightgun\ui\Wizard.ps1'

# Dot-sourced: the page builders use the wizard script's helper functions, which live as long as its scope.
Describe 'Lightgun wizard (smoke test, no window is shown)' {
    $state = Join-Path $TestDrive 'install-state.json'

    It 'lists start, steps 1-9, calibration and thanks and builds every page without errors (de and en)' {
        foreach ($culture in 'de-DE', 'en-US') {
            $w = . $wizardScript -NoShow -Culture $culture -StatePath $state
            try {
                $w.Pages.Count | Should Be 12
                $w.List.Items.Count | Should Be 12
                $w.DryRunBox.Checked | Should Be $true # first run
                for ($i = 0; $i -lt $w.Pages.Count; $i++) { Show-KitWizardPage -Wizard $w -Index $i }
                $w.Log.Text | Should Not Match '\[X\]'
                $w.List.Items[11] | Should Be (Get-KitText 'Lightgun.Ui.Page.Credits')
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
        $w = . $wizardScript -NoShow -Culture 'en-US' -StatePath $state -Page 10
        try {
            (@($w.Content.Controls[0].Controls | ForEach-Object { $_.Text }) -join ' ') | Should Match 'only ONE Wiimote'
            Show-KitWizardPage -Wizard $w -Index 11
            $box = @($w.Content.Controls[0].Controls | Where-Object { $_ -is [Windows.Forms.RichTextBox] })[0]
            $box.Text | Should Match 'https://github.com/gunmotelabs/Gunmote'
        } finally { $w.Form.Dispose() }
    }
}
