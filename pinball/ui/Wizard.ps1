<#
.SYNOPSIS
    Pinball wizard (Windows Forms): the pinball steps 1-9 as pages, status list on the left (green only after
    the step's Verify), log below, language de/en, mode Move/Rebuild, dry-run switch (on for the first run),
    a confirmation before every writing action, the credits page (read from CREDITS.md at runtime) and the
    maintenance page (doctor, backups, support bundle).
    Opens without administrator rights; the start page can restart it elevated.
.PARAMETER NoShow
    Build the wizard and return it without showing a window (tests). The caller disposes $wizard.Form.
.PARAMETER Screenshot
    Show the window, save it as PNG to this path and close (for reviews).
.PARAMETER Page
    Index of the start page (0 = start, 8 = screens, 10 = thanks, 11 = maintenance).
.PARAMETER Monitors
    Injected monitors instead of the real ones (tests, screenshots).
.PARAMETER KitUserSid
    Passed by the elevation; step 6 locks registry work if the elevated user differs.
#>
[CmdletBinding()]
param(
    [string] $Culture,
    [switch] $NoShow,
    [string] $Screenshot,
    [int] $Page = 0,
    [string] $StatePath,
    [object[]] $Monitors,
    [string] $KitUserSid
)
$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# Files downloaded as ZIP carry a Zone.Identifier; remove it from the kit's own files only.
Get-ChildItem -LiteralPath (Join-Path $kitRoot 'core'), (Join-Path $kitRoot 'pinball'), (Join-Path $kitRoot 'i18n') -Recurse -File | Unblock-File
Get-ChildItem -LiteralPath $kitRoot -Filter '*.cmd' -File | Unblock-File

Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1')
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1')
if ($Culture) { Set-KitCulture -Culture $Culture }
if (-not $StatePath) { $StatePath = Get-PinballDefaultStatePath }
Initialize-KitForms

$script:KitRootDir = $kitRoot
$script:StepsDir = Join-Path $kitRoot 'pinball\steps'
$script:StateFile = $StatePath
$script:WizardScript = $PSCommandPath
# Started directly "as administrator": the logged-on user counts when it is the same account.
$script:UserSid = Get-KitStartUserSid -OriginalSid $KitUserSid
$script:MonitorOverride = $Monitors
$script:ShotPath = $Screenshot
$script:RoleColors = @{ Playfield = 'SteelBlue'; Backglass = 'DarkOrange'; DMD = 'MediumPurple'; FullDMD = 'Teal'; Topper = 'Goldenrod' }
# Plans (files with SHA256 and signature, icacls) are confirmed in a dialog, never silently.
$script:Approve = { param($text) Confirm-KitAction -Text $text }

# --- helpers ------------------------------------------------------------------------------------------------

# Steps that write HKCU get the SID of the user who started the wizard (set by the elevation).
function Add-UserSid([hashtable] $Params) {
    if ($script:UserSid) { $Params.KitUserSid = $script:UserSid }
    $Params
}

function Get-StepPageStatus([object[]] $Results) {
    if (-not $Results) { return 'Failed' }
    $s = @($Results | ForEach-Object { $_.Status })
    if ($s -contains 'Failed') { return 'Failed' }
    if ($s -contains 'NeedsUser') { return 'NeedsUser' }
    if (@($Results | Where-Object { $_.WhatIf }).Count) { return 'WhatIf' }
    'Done' # Done or Skipped without -WhatIf: both mean Verify returned $true
}

# Runs a step script in this process; its log lines (Write-Host = information stream) go to the log box.
function Invoke-WizardStep([int] $Index, [string] $Script, [hashtable] $Params = @{}, [string] $ConfirmText) {
    $w = $script:W
    $dry = Test-KitWizardDryRun -Wizard $w
    $title = Get-KitText $w.Pages[$Index].TitleKey
    if (-not $dry) {
        if (-not $ConfirmText) { $ConfirmText = Get-KitText 'Pinball.Ui.Confirm.Step' -f $title }
        if (-not (Confirm-KitAction -Text $ConfirmText)) { return }
    }
    $Params.StatePath = $script:StateFile
    $Params.Culture = Get-KitCulture
    if ($dry) { $Params.WhatIf = $true }
    Write-KitWizardLog -Wizard $w -Text ('--- {0}{1}' -f $title, $(if ($dry) { ' (' + (Get-KitText 'Ui.DryRun') + ')' } else { '' }))
    $results = New-Object Collections.ArrayList
    $w.Form.Cursor = 'WaitCursor'
    try {
        & (Join-Path $script:StepsDir $Script) @Params 6>&1 | ForEach-Object {
            if ($_ -is [Management.Automation.InformationRecord]) { Write-KitWizardLog -Wizard $w -Text ([string]$_.MessageData) }
            elseif ($_ -and $_.PSObject.TypeNames -contains 'RetroCabinetKit.StepResult') { $null = $results.Add($_) }
            [Windows.Forms.Application]::DoEvents()
        }
    } catch {
        Write-KitWizardLog -Wizard $w -Text (Get-KitText 'Pinball.Ui.StepError' -f $title, $_.Exception.Message) -Level Error
        $null = $results.Add([pscustomobject]@{ Status = 'Failed'; WhatIf = $false })
    } finally { $w.Form.Cursor = 'Default' }
    Set-KitWizardStatus -Wizard $w -Index $Index -Status (Get-StepPageStatus @($results))
}

function Get-SavedStatus([string[]] $StepNames) {
    $s = @($StepNames | ForEach-Object { Get-KitStepStatus -Path $script:StateFile -Name $_ })
    if (-not $s -or @($s | Where-Object { -not $_ }).Count) { return 'None' }
    if ($s -contains 'Failed') { return 'Failed' }
    if ($s -contains 'NeedsUser') { return 'NeedsUser' }
    'Done'
}

function Add-RunButton($Panel, [scriptblock] $OnClick) {
    $b = Add-KitUiButton -Panel $Panel -Text (Get-KitText 'Pinball.Ui.Run') -OnClick $OnClick
    $b.Margin = New-Object Windows.Forms.Padding (3, 12, 3, 3)
    $b
}

function Get-WizardMonitor {
    if (-not $script:W.Values['Monitors']) { $script:W.Values['Monitors'] = @(Get-PinballMonitor -Monitors $script:MonitorOverride) }
    $script:W.Values['Monitors']
}

function Get-WizardLayout {
    $v = $script:W.Values
    $layout = New-PinballScreenLayout -Monitors (Get-WizardMonitor) -Roles $v['Roles'] -Windows $v['Windows']
    $v['Roles'] = $layout.Roles
    $v['Windows'] = $layout.Windows
    $layout
}

function Get-WizardTargets {
    $root = Get-KitStateValue -Path $script:StateFile -Key 'TargetRoot'
    if (-not $root) { Write-KitWizardLog -Wizard $script:W -Text (Get-KitText 'Pinball.Step.RunTargetFirst') -Level Warn; return }
    Get-PinballScreenTarget -Root $root
}

# Monitor tiles to scale; returns the tile rectangle of every monitor inside the panel.
function Get-TileRects($Panel, [object[]] $MonitorList) {
    $d = Get-PinballDesktop -Monitors $MonitorList
    $scale = [math]::Min(($Panel.ClientSize.Width - 20) / $d.Width, ($Panel.ClientSize.Height - 20) / $d.Height)
    foreach ($m in $MonitorList) {
        [pscustomobject]@{
            Monitor = $m
            Rect = New-Object Drawing.Rectangle ([int](10 + ($m.X - $d.X) * $scale)), ([int](10 + ($m.Y - $d.Y) * $scale)), ([int]($m.Width * $scale) - 2), ([int]($m.Height * $scale) - 2)
        }
    }
}

# --- pages --------------------------------------------------------------------------------------------------

$pages = @(
    @{ TitleKey = 'Pinball.Ui.Page.Start'; Build = {
        param($w, $p)
        $null = Add-KitUiText $p (Get-KitText 'Pinball.Ui.Start.Intro')
        $admin = Test-KitAdmin
        $null = Add-KitUiText $p (Get-KitText $(if ($admin) { 'Admin.Yes' } else { 'Admin.No' })) -Color $(if ($admin) { 'ForestGreen' } else { 'DarkOrange' })
        if (-not $admin) {
            $null = Add-KitUiButton $p (Get-KitText 'Pinball.Ui.Elevate') {
                Start-KitElevated -ScriptPath $script:WizardScript -ArgumentList @('-Culture', (Get-KitCulture)) -PassUserSid -Confirm:$false
                $script:W.Form.Close()
            }
        }
        $null = Add-KitUiText $p (Get-KitText 'Pinball.Ui.Mode') -Bold
        foreach ($mode in 'Move', 'Rebuild') {
            $r = New-Object Windows.Forms.RadioButton
            $r.AutoSize = $true
            $r.Text = Get-KitText "Pinball.Ui.Mode.$mode"
            $r.Tag = $mode
            $r.Checked = $w.Values['Mode'] -eq $mode
            $r.add_CheckedChanged({ if ($this.Checked) { $script:W.Values['Mode'] = $this.Tag } })
            $p.Controls.Add($r)
        }
        $null = Add-KitUiText $p (Get-KitText 'Pinball.Ui.DryRunHint')
        $null = Add-KitUiButton $p (Get-KitText 'Pinball.Ui.SupportLog') {
            $log = Get-KitLogFile
            if (-not $log) { Write-KitWizardLog -Wizard $script:W -Text (Get-KitText 'Pinball.Ui.NoLog') -Level Warn; return }
            $null = Export-KitSupportLog -Path $log, ([IO.Path]::ChangeExtension($log, '.transcript.log')) -Destination ([IO.Path]::ChangeExtension($log, '.support.txt'))
            Write-KitWizardLog -Wizard $script:W -Text (Get-KitText 'Log.SupportExported' -f ([IO.Path]::ChangeExtension($log, '.support.txt')))
        }
    } }
    @{ TitleKey = 'Pinball.Ui.Page.Detect'; StepNames = @('pinball-1-detect'); Build = {
        param($w, $p)
        $null = Add-KitUiText $p (Get-KitText 'Pinball.Ui.Detect.Desc')
        $null = Add-KitUiPathBox $p (Get-KitText 'Pinball.Ui.Detect.Source') $w.Values['Source'] { $script:W.Values['Source'] = $this.Text }
        $null = Add-RunButton $p { Invoke-WizardStep 1 '01-Detect.ps1' @{ Source = $script:W.Values['Source'] } }
    } }
    @{ TitleKey = 'Pinball.Ui.Page.Target'; StepNames = @('pinball-2-target'); Build = {
        param($w, $p)
        $null = Add-KitUiText $p (Get-KitText 'Pinball.Ui.Target.Desc')
        $null = Add-KitUiPathBox $p (Get-KitText 'Pinball.Ui.Target.Folder') $w.Values['Target'] { $script:W.Values['Target'] = $this.Text }
        $null = Add-RunButton $p { Invoke-WizardStep 2 '02-Target.ps1' @{ TargetRoot = $script:W.Values['Target'] } }
    } }
    @{ TitleKey = 'Pinball.Ui.Page.Dependencies'; StepNames = @('pinball-3-dependencies'); Build = {
        param($w, $p)
        $null = Add-KitUiText $p (Get-KitText 'Pinball.Ui.Deps.Desc')
        $null = Add-KitUiCheck $p (Get-KitText 'Pinball.Ui.Deps.AllowDownload') ([bool]$w.Values['AllowDownload']) { $script:W.Values['AllowDownload'] = $this.Checked }
        $null = Add-KitUiCheck $p (Get-KitText 'Pinball.Ui.Deps.AllowDism') ([bool]$w.Values['AllowDism']) { $script:W.Values['AllowDism'] = $this.Checked }
        $null = Add-RunButton $p {
            $v = $script:W.Values
            Invoke-WizardStep 3 '03-Dependencies.ps1' @{ AllowDownload = [bool]$v['AllowDownload']; AllowDism = [bool]$v['AllowDism']; Approve = $script:Approve }
        }
    } }
    @{ TitleKey = 'Pinball.Ui.Page.Copy'; StepNames = @('pinball-4-copy'); Build = {
        param($w, $p)
        $null = Add-KitUiText $p (Get-KitText 'Pinball.Ui.Copy.Desc')
        $null = Add-KitUiCheck $p (Get-KitText 'Pinball.Ui.Copy.Update') ([bool]$w.Values['CopyUpdate']) { $script:W.Values['CopyUpdate'] = $this.Checked }
        $null = Add-RunButton $p { Invoke-WizardStep 4 '04-Copy.ps1' @{ Update = [bool]$script:W.Values['CopyUpdate'] } }
    } }
    @{ TitleKey = 'Pinball.Ui.Page.Relocate'; StepNames = @('pinball-5-relocate'); Build = {
        param($w, $p)
        $null = Add-KitUiText $p (Get-KitText 'Pinball.Ui.Relocate.Desc')
        $null = Add-KitUiText $p (Get-KitText "Pinball.Ui.Mode.$($w.Values['Mode'])") -Bold
        if ($w.Values['Mode'] -eq 'Rebuild') {
            $null = Add-KitUiPathBox $p (Get-KitText 'Pinball.Ui.Relocate.RegistryBackup') $w.Values['RegistryBackup'] { $script:W.Values['RegistryBackup'] = $this.Text } -File
            $null = Add-KitUiPathBox $p (Get-KitText 'Pinball.Ui.Relocate.OldUserHive') $w.Values['OldUserHive'] { $script:W.Values['OldUserHive'] = $this.Text } -File
            $null = Add-KitUiText $p (Get-KitText 'Pinball.Ui.Relocate.RegMerge') -Color 'DarkOrange'
        }
        $null = Add-RunButton $p {
            $v = $script:W.Values
            $params = Add-UserSid @{ Mode = $v['Mode'] }
            if ($v['Mode'] -eq 'Rebuild') {
                if ($v['RegistryBackup']) { $params.RegistryBackup = $v['RegistryBackup'] }
                if ($v['OldUserHive']) { $params.OldUserHive = $v['OldUserHive'] }
            }
            Invoke-WizardStep 5 '05-Relocate.ps1' $params
        }
    } }
    @{ TitleKey = 'Pinball.Ui.Page.Register'; StepNames = @('pinball-6-register'); Build = {
        param($w, $p)
        $null = Add-KitUiText $p (Get-KitText 'Pinball.Ui.Register.Desc')
        if (-not (Test-KitAdmin)) { $null = Add-KitUiText $p (Get-KitText 'Pinball.Step.NeedsAdmin') -Color 'DarkOrange' }
        $null = Add-RunButton $p { Invoke-WizardStep 6 '06-Register.ps1' (Add-UserSid @{ Approve = $script:Approve }) }
        # Own command, not part of the step: shows broad write rights on vPinball, hardens after confirmation.
        $null = Add-KitUiButton $p (Get-KitText 'Pinball.Ui.Register.Harden') {
            $root = Get-KitStateValue -Path $script:StateFile -Key 'TargetRoot'
            $problem = Get-PinballRootProblem -Root $root
            if ($problem) { Write-KitWizardLog -Wizard $script:W -Text $problem -Level Warn; return }
            $v = Join-PinballPath (ConvertTo-PinballRoot $root) 'vPinball'
            $risks = @(Get-PinballFolderAclRisk -Path $v)
            foreach ($r in $risks) { Write-KitWizardLog -Wizard $script:W -Text (Get-KitText 'Pinball.Acl.Risk' -f $r.Path, $r.Name, $r.Rights) -Level Warn }
            if (-not $risks) { Write-KitWizardLog -Wizard $script:W -Text (Get-KitText 'Pinball.Acl.Ok' -f $v); return }
            if (-not (Test-KitAdmin)) { Write-KitWizardLog -Wizard $script:W -Text (Get-KitText 'Pinball.Step.NeedsAdmin') -Level Warn; return }
            if (-not $script:UserSid) { Write-KitWizardLog -Wizard $script:W -Text (Get-KitRegistryUserLock) -Level Warn; return }
            if (Test-KitWizardDryRun -Wizard $script:W) { return }
            try { $left = @(Protect-PinballBuildFolder -Root $root -UserSid $script:UserSid -Approve $script:Approve -Confirm:$false) }
            catch { Write-KitWizardLog -Wizard $script:W -Text $_.Exception.Message -Level Error; return }
            foreach ($r in $left) { Write-KitWizardLog -Wizard $script:W -Text (Get-KitText 'Pinball.Acl.Risk' -f $r.Path, $r.Name, $r.Rights) -Level Warn }
        }
    } }
    @{ TitleKey = 'Pinball.Ui.Page.FpBam'; StepNames = @('pinball-7-fpbam', 'pinball-7-fploader-admin'); Build = {
        param($w, $p)
        $null = Add-KitUiText $p (Get-KitText 'Pinball.Ui.FpBam.Desc')
        $null = Add-KitUiCheck $p (Get-KitText 'Pinball.Ui.FpBam.Confirm') ([bool]$w.Values['FpLoaderConfirmed']) { $script:W.Values['FpLoaderConfirmed'] = $this.Checked }
        $null = Add-RunButton $p { Invoke-WizardStep 7 '07-FpBamSetup.ps1' (Add-UserSid @{ ConfirmFpLoaderAdminRun = [bool]$script:W.Values['FpLoaderConfirmed']; Approve = $script:Approve }) }
    } }
    @{ TitleKey = 'Pinball.Ui.Page.Screens'; StepNames = @('pinball-8-screens'); Build = {
        param($w, $p)
        $null = Add-KitUiText $p (Get-KitText 'Pinball.Ui.Screens.Desc')
        $layout = Get-WizardLayout
        $violations = @(Test-PinballMonitorLayout -Monitors $layout.Monitors -Roles $layout.Roles)
        if ($violations) { foreach ($v in $violations) { $null = Add-KitUiText $p $v.Message -Color 'Firebrick' } }
        else { $null = Add-KitUiText $p (Get-KitText 'Pinball.Ui.Screens.RulesOk') -Color 'ForestGreen' }

        # Role chooser + monitor tiles: choose a role, click a tile (again = remove).
        $row = New-Object Windows.Forms.FlowLayoutPanel
        $row.AutoSize = $true
        $row.WrapContents = $false
        $label = New-Object Windows.Forms.Label
        $label.AutoSize = $true
        $label.Text = Get-KitText 'Pinball.Ui.Screens.RoleLabel'
        $label.Margin = New-Object Windows.Forms.Padding (3, 6, 3, 3)
        $roleBox = New-Object Windows.Forms.ComboBox
        $roleBox.DropDownStyle = 'DropDownList'
        foreach ($r in 'Playfield', 'Backglass', 'DMD', 'FullDMD', 'Topper') { $null = $roleBox.Items.Add($r) }
        $roleBox.SelectedItem = if ($w.Values['SelectedRole']) { $w.Values['SelectedRole'] } else { 'Playfield' }
        $roleBox.add_SelectedIndexChanged({ $script:W.Values['SelectedRole'] = [string]$this.SelectedItem })
        $row.Controls.AddRange(@($label, $roleBox))
        $p.Controls.Add($row)
        $null = Add-KitUiText $p (Get-KitText 'Pinball.Ui.Screens.RoleHint')

        $tiles = New-Object Windows.Forms.Panel
        $tiles.Size = New-Object Drawing.Size ([math]::Min(760, $p.ClientSize.Width - 40)), 190
        $tiles.BorderStyle = 'FixedSingle'
        $tiles.BackColor = [Drawing.Color]::FromArgb(245, 245, 245)
        $tiles.Tag = $roleBox
        $tiles.add_Paint({
            $v = $script:W.Values
            $g = $_.Graphics
            $g.SmoothingMode = 'AntiAlias'
            foreach ($t in Get-TileRects $this $v['Monitors']) {
                $m = $t.Monitor
                $roles = @($v['Roles'].Keys | Where-Object { $v['Roles'][$_] -eq $m.DeviceName } | Sort-Object)
                $fill = if ($roles) { [Drawing.Color]::FromName($script:RoleColors[$roles[0]]) } else { [Drawing.Color]::DimGray }
                $brush = New-Object Drawing.SolidBrush $fill
                $g.FillRectangle($brush, $t.Rect)
                $g.DrawRectangle([Drawing.Pens]::Black, $t.Rect)
                $text = '{0}{1}{2} x {3}  {4} Hz  {5} %{1}{6}' -f ($m.DeviceName -replace '^\\\\\.\\', ''), [Environment]::NewLine, $m.Width, $m.Height, $m.RefreshRate, $m.Scale, $(if ($roles) { $roles -join ' + ' } else { '-' })
                $g.DrawString($text, $this.Font, [Drawing.Brushes]::White, (New-Object Drawing.RectangleF ($t.Rect.X + 4), ($t.Rect.Y + 4), ($t.Rect.Width - 8), ($t.Rect.Height - 8)))
                $brush.Dispose()
            }
        })
        $tiles.add_MouseClick({
            $v = $script:W.Values
            $role = [string]$this.Tag.SelectedItem
            $point = $_.Location
            $hit = Get-TileRects $this $v['Monitors'] | Where-Object { $_.Rect.Contains($point) } | Select-Object -First 1
            if (-not $hit -or -not $role) { return }
            if ($v['Roles'][$role] -eq $hit.Monitor.DeviceName) { $v['Roles'].Remove($role) } else { $v['Roles'][$role] = $hit.Monitor.DeviceName }
            Show-KitWizardPage -Wizard $script:W -Index 8 -Force
        })
        $p.Controls.Add($tiles)

        # Measuring window per consumer.
        $row2 = New-Object Windows.Forms.FlowLayoutPanel
        $row2.AutoSize = $true
        $row2.WrapContents = $false
        $label2 = New-Object Windows.Forms.Label
        $label2.AutoSize = $true
        $label2.Text = Get-KitText 'Pinball.Ui.Screens.Consumer'
        $label2.Margin = New-Object Windows.Forms.Padding (3, 6, 3, 3)
        $consumerBox = New-Object Windows.Forms.ComboBox
        $consumerBox.DropDownStyle = 'DropDownList'
        $consumerBox.Width = 180
        foreach ($c in Get-PinballScreenConsumer) { $null = $consumerBox.Items.Add($c) }
        $consumerBox.SelectedItem = if ($w.Values['SelectedConsumer']) { $w.Values['SelectedConsumer'] } else { 'PuP.INFO1' }
        $consumerBox.add_SelectedIndexChanged({ $script:W.Values['SelectedConsumer'] = [string]$this.SelectedItem })
        $measure = New-Object Windows.Forms.Button
        $measure.AutoSize = $true
        $measure.Text = Get-KitText 'Pinball.Ui.Screens.Measure'
        $measure.Tag = $consumerBox
        $measure.add_Click({
            $consumer = [string]$this.Tag.SelectedItem
            $layout = Get-WizardLayout
            $rect = Get-PinballConsumerRect -Layout $layout -Consumer $consumer
            if (-not $rect) { $rect = Get-PinballRoleArea -Layout $layout -Role 'Playfield' }
            $color = $script:RoleColors[(Get-PinballConsumerRole -Consumer $consumer)]
            $new = Show-KitMeasureWindow -Rect $rect -Title $consumer -Color $color -Monitors $layout.Monitors
            if ($new) {
                $script:W.Values['Windows'][$consumer] = $new
                Write-KitWizardLog -Wizard $script:W -Text (Get-KitText 'Pinball.Ui.Screens.Measured' -f $consumer, (Format-PinballRect $new))
            }
        })
        $row2.Controls.AddRange(@($label2, $consumerBox, $measure))
        $p.Controls.Add($row2)

        $null = Add-KitUiText $p (Get-KitText 'Pinball.Ui.Screens.ModeLabel') -Bold
        foreach ($mode in 'Keep', 'Replace') {
            $r = New-Object Windows.Forms.RadioButton
            $r.AutoSize = $true
            $r.Text = Get-KitText "Pinball.Ui.Screens.Mode.$mode"
            $r.Tag = $mode
            $r.Checked = $w.Values['ScreenMode'] -eq $mode
            $r.add_CheckedChanged({ if ($this.Checked) { $script:W.Values['ScreenMode'] = $this.Tag } })
            $p.Controls.Add($r)
        }

        $buttons = New-Object Windows.Forms.FlowLayoutPanel
        $buttons.AutoSize = $true
        $p.Controls.Add($buttons)
        $null = Add-KitUiButton $buttons (Get-KitText 'Pinball.Ui.Screens.Preview') {
            $targets = @(Get-WizardTargets)
            if (-not $targets) { return }
            $plan = @(Get-PinballScreenPlan -Layout (Get-WizardLayout) -Targets $targets -Mode $script:W.Values['ScreenMode'])
            foreach ($line in Format-PinballScreenPlan -Plan $plan) { Write-KitWizardLog -Wizard $script:W -Text $line }
            Write-KitWizardLog -Wizard $script:W -Text (Get-KitText 'Pinball.Ui.Screens.ChangeCount' -f (Get-PinballScreenChangeCount -Plan $plan))
        }
        $null = Add-KitUiButton $buttons (Get-KitText 'Pinball.Ui.Screens.Write') {
            $layout = Get-WizardLayout
            $params = Add-UserSid @{ Mode = $script:W.Values['ScreenMode']; Layout = [pscustomobject]@{ Roles = $layout.Roles; Windows = $layout.Windows } }
            if ($script:MonitorOverride) { $params.Monitors = $script:MonitorOverride }
            Invoke-WizardStep 8 '08-Screens.ps1' $params
        }
        $null = Add-KitUiButton $buttons (Get-KitText 'Pinball.Ui.Screens.Undo') {
            $last = @(Get-KitStateValue -Path $script:StateFile -Key 'ScreenLastWritten' | Where-Object { $_ })
            if (-not $last) { Write-KitWizardLog -Wizard $script:W -Text (Get-KitText 'Pinball.Ui.Screens.NothingToUndo'); return }
            foreach ($l in $last) { Write-KitWizardLog -Wizard $script:W -Text ('{0} <- {1}' -f $l.Path, $l.Backup) }
            if (Test-KitWizardDryRun -Wizard $script:W) { return }
            $targets = @(Get-WizardTargets)
            if (-not $targets) { return }
            if (-not (Confirm-KitAction -Text (Get-KitText 'Pinball.Ui.Screens.UndoConfirm' -f $last.Count))) { return }
            try { Restore-PinballScreenBackup -Written $last -Targets $targets -Confirm:$false; Set-KitWizardStatus -Wizard $script:W -Index 8 -Status 'None' }
            catch { Write-KitWizardLog -Wizard $script:W -Text $_.Exception.Message -Level Error }
        }
        $null = Add-KitUiButton $buttons (Get-KitText 'Pinball.Ui.Screens.Card') {
            $card = (Get-PinballValueCard -Layout (Get-WizardLayout)) -join [Environment]::NewLine
            Write-KitWizardLog -Wizard $script:W -Text $card
            [Windows.Forms.Clipboard]::SetText($card)
            Write-KitWizardLog -Wizard $script:W -Text (Get-KitText 'Pinball.Ui.Screens.CardCopied')
        }
        $null = Add-KitUiButton $buttons (Get-KitText 'Pinball.Ui.Screens.TableDmd') {
            $targets = @(Get-WizardTargets | Where-Object { $_.Name -in 'VpmDmdDevice', 'FpDmdDevice' -and (Test-Path -LiteralPath $_.Path) })
            $found = @(foreach ($t in $targets) { Remove-PinballTableDmdPosition -Path $t.Path -WhatIf | ForEach-Object { [pscustomobject]@{ Path = $t.Path; Line = $_ } } })
            Write-KitWizardLog -Wizard $script:W -Text (Get-KitText 'Pinball.Ui.Screens.TableDmdFound' -f $found.Count)
            foreach ($f in $found | Select-Object -First 50) { Write-KitWizardLog -Wizard $script:W -Text ('  [{0}] {1}' -f $f.Line.Section, $f.Line.Line) }
            if (-not $found -or (Test-KitWizardDryRun -Wizard $script:W)) { return }
            if (-not (Confirm-KitAction -Text (Get-KitText 'Pinball.Ui.Screens.TableDmdConfirm' -f $found.Count))) { return }
            try { foreach ($t in $targets) { $null = Remove-PinballTableDmdPosition -Path $t.Path -Confirm:$false } }
            catch { Write-KitWizardLog -Wizard $script:W -Text $_.Exception.Message -Level Error }
        }
    } }
    @{ TitleKey = 'Pinball.Ui.Page.Finish'; StepNames = @('pinball-9-backup'); Build = {
        param($w, $p)
        $null = Add-KitUiText $p (Get-KitText 'Pinball.Ui.Finish.Desc')
        $null = Add-KitUiCheck $p (Get-KitText 'Pinball.Ui.Finish.Autostart') ([bool]$w.Values['Autostart']) { $script:W.Values['Autostart'] = $this.Checked }
        $null = Add-RunButton $p {
            $auto = [bool]$script:W.Values['Autostart']
            $text = if ($auto) { Get-KitText 'Pinball.Ui.Finish.AutostartConfirm' } else { $null }
            Invoke-WizardStep 9 '09-Finish.ps1' (Add-UserSid @{ EnableAutostart = $auto; Approve = $script:Approve }) $text
        }
    } }
    @{ TitleKey = 'Pinball.Ui.Page.Credits'; Build = {
        param($w, $p)
        $null = Add-KitUiText $p (Get-KitText 'Pinball.Ui.Credits.Desc')
        $null = Add-KitCreditsView -Panel $p -Path (Join-Path $script:KitRootDir 'CREDITS.md')
    } }
    (New-KitCarePage -StatePath $StatePath -LogDir (Join-Path $kitRoot 'logs') -Guard { Assert-PinballProcessesClosed } -Checks {
        Get-KitSystemCheck
        Get-PinballDoctorCheck -StatePath $script:StateFile
    } -BackupRoots {
        Join-Path (Split-Path -Parent $script:StateFile) 'backups'
        foreach ($key in 'TargetRoot', 'SourceRoot') { [string](Get-KitStateValue -Path $script:StateFile -Key $key) }
    })
)

# --- start --------------------------------------------------------------------------------------------------

$state = Read-KitState -Path $StatePath
$firstRun = -not @($state.Steps.PSObject.Properties | Where-Object { $_.Value.Status -eq 'Done' }).Count
$saved = ConvertTo-PinballHashtable (Get-KitStateValue -Path $StatePath -Key 'ScreenLayout')

$script:W = $null
$wizard = New-KitWizard -TitleKey 'Pinball.Ui.Title' -Pages $pages -DryRun $firstRun -StartPage -1
$script:W = $wizard
$v = $wizard.Values
$v['Mode'] = 'Move'
$v['ScreenMode'] = 'Keep'
$v['Source'] = [string](Get-KitStateValue -Path $StatePath -Key 'SourceRoot')
$v['Target'] = [string](Get-KitStateValue -Path $StatePath -Key 'TargetRoot')
$v['Roles'] = $saved['Roles']
$v['Windows'] = $saved['Windows']
for ($i = 0; $i -lt $pages.Count; $i++) {
    if ($pages[$i]['StepNames']) { Set-KitWizardStatus -Wizard $wizard -Index $i -Status (Get-SavedStatus $pages[$i]['StepNames']) }
}
Show-KitWizardPage -Wizard $wizard -Index $Page

if ($NoShow) { return $wizard }

if ($script:ShotPath) {
    $wizard.Form.add_Shown({
        [Windows.Forms.Application]::DoEvents()
        $f = $script:W.Form
        $bmp = New-Object Drawing.Bitmap $f.Width, $f.Height
        $f.DrawToBitmap($bmp, (New-Object Drawing.Rectangle 0, 0, $f.Width, $f.Height))
        $dir = Split-Path -Parent $script:ShotPath
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $bmp.Save($script:ShotPath, [Drawing.Imaging.ImageFormat]::Png)
        $bmp.Dispose()
        $f.Close()
    })
}

Start-KitLog -Path (Join-Path $kitRoot ('logs\pinball-wizard_{0:yyyyMMdd-HHmmss}.log' -f (Get-Date)))
try { [void]$wizard.Form.ShowDialog() }
finally {
    $wizard.Form.Dispose()
    Stop-KitLog
}
