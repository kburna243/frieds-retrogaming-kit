$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1') -Force
$wizardScript = Join-Path $kitRoot 'pinball\ui\Wizard.ps1'

# Dot-sourced: the page builders use the wizard script's helper functions, which live as long as its scope.
Describe 'Pinball wizard (smoke test, no window is shown)' {
    $monitors = @(
        [pscustomobject]@{ DeviceName = '\\.\DISPLAY1'; X = 0; Y = 0; Width = 1920; Height = 1080; Primary = $true; Scale = 100; RefreshRate = 60 }
        [pscustomobject]@{ DeviceName = '\\.\DISPLAY2'; X = 1920; Y = 0; Width = 1280; Height = 1024; Primary = $false; Scale = 100; RefreshRate = 60 }
    )
    $state = Join-Path $TestDrive 'install-state.json'

    It 'loads, lists steps 1-9 plus start and thanks, and builds every page without errors (de and en)' {
        foreach ($culture in 'de-DE', 'en-US') {
            $w = . $wizardScript -NoShow -Culture $culture -StatePath $state -Monitors $monitors
            try {
                $w.Pages.Count | Should Be 11
                $w.List.Items.Count | Should Be 11
                $w.DryRunBox.Checked | Should Be $true # first run
                for ($i = 0; $i -lt $w.Pages.Count; $i++) { Show-KitWizardPage -Wizard $w -Index $i }
                $w.Log.Text | Should Not Match '\[X\]'
                $w.List.Items[10] | Should Be (Get-KitText 'Pinball.Ui.Page.Credits')
                @($w.List.Items | Where-Object { $_ -match '^\[\[' }).Count | Should Be 0
            } finally { $w.Form.Dispose() }
        }
    }

    It 'starts directly on the screens page without errors' {
        $w = . $wizardScript -NoShow -Culture 'de-DE' -StatePath $state -Monitors $monitors -Page 8
        try {
            $w.Index | Should Be 8
            $w.Log.Text | Should Not Match '\[X\]'
            $w.Values['Roles'].Backglass | Should Be '\\.\DISPLAY2'
        } finally { $w.Form.Dispose() }
    }

    It 'runs a step from the page as dry run: log lines in the log box, status WhatIf, nothing persisted' {
        $src = Join-Path $TestDrive 'Src'
        & (Join-Path $PSScriptRoot 'New-PinballTestBuild.ps1') -Root $src -OldRoot 'D:\Old Build'
        $dryState = Join-Path $TestDrive 'dry-state.json'
        $w = . $wizardScript -NoShow -Culture 'en-US' -StatePath $dryState -Monitors $monitors -Page 1
        try {
            $w.DryRunBox.Checked | Should Be $true
            $w.Values['Source'] = $src
            Invoke-WizardStep 1 '01-Detect.ps1' @{ Source = $src }
            $w.Status[1] | Should Be 'WhatIf'
            $w.Log.Text | Should Match 'D:\\Old Build'
            $w.Log.Text | Should Match 'dry run, nothing changed'
            $dryState | Should Not Exist
        } finally { $w.Form.Dispose() }
    }

    It 'shows the credits from CREDITS.md with clickable web links' {
        $w = . $wizardScript -NoShow -Culture 'en-US' -StatePath $state -Monitors $monitors -Page 10
        try {
            $box = @($w.Content.Controls[0].Controls | Where-Object { $_ -is [Windows.Forms.RichTextBox] })[0]
            $box.DetectUrls | Should Be $true
            $box.Text | Should Match 'https://github.com/gunmotelabs/Gunmote'
            $box.Text | Should Not Match '\*\*'
        } finally { $w.Form.Dispose() }
    }

    It 'shows steps as green only when the saved status says verified' {
        Set-KitStepStatus -Path $state -Name 'pinball-1-detect' -Status Done
        Set-KitStepStatus -Path $state -Name 'pinball-2-target' -Status NeedsUser
        $w = . $wizardScript -NoShow -Culture 'en-US' -StatePath $state -Monitors $monitors
        try {
            $w.Status[1] | Should Be 'Done'
            $w.Status[2] | Should Be 'NeedsUser'
            $w.Status[3] | Should Be 'None'
            $w.DryRunBox.Checked | Should Be $false # not the first run any more
        } finally { $w.Form.Dispose() }
    }
}

Describe 'Core UI helpers' {
    It 'turns CREDITS markdown into plain text with links kept' {
        $t = ConvertFrom-KitCreditsMarkdown "## Head`r`n| | |`r`n|---|---|`r`n| **A** | uses <https://example.org/a> |`r`n_Link folgt_"
        $t | Should Match '^Head'
        $t | Should Match '  - A  \|  uses https://example.org/a'
        $t | Should Match 'Link folgt'
        $t | Should Not Match '---'
    }

    It 'captures the real monitors read-only with scale and refresh rate' {
        $m = @(Get-KitMonitor)
        $m.Count | Should BeGreaterThan 0
        @($m | Where-Object { $_.Primary }).Count | Should Be 1
        @($m | Where-Object { $_.Scale -lt 100 -or $_.RefreshRate -lt 0 }).Count | Should Be 0
    }
}
