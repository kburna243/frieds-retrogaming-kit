<#
.SYNOPSIS
    Lightgun wizard (Windows Forms): the lightgun steps 1-9 as pages, then calibration (guided, last) and the
    thanks page. Status list on the left (green only after the step's Verify), log below, language de/en,
    dry-run switch (on for the first run), a confirmation before every writing action.
    Opens without administrator rights; the start page can restart it elevated.
.PARAMETER NoShow
    Build the wizard and return it without showing a window (tests). The caller disposes $wizard.Form.
.PARAMETER Screenshot
    Show the window, save it as PNG to this path and close (for reviews).
.PARAMETER Page
    Index of the start page (0 = start, 9 = verify, 11 = thanks).
.PARAMETER KitUserSid
    Passed by the elevation; the tasks of steps 4 and 8 run for this user.
#>
[CmdletBinding()]
param(
    [string] $Culture,
    [switch] $NoShow,
    [string] $Screenshot,
    [int] $Page = 0,
    [string] $StatePath,
    [string] $KitUserSid
)
$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# Files downloaded as ZIP carry a Zone.Identifier; remove it from the kit's own files only.
Get-ChildItem -LiteralPath (Join-Path $kitRoot 'core'), (Join-Path $kitRoot 'lightgun'), (Join-Path $kitRoot 'i18n') -Recurse -File | Unblock-File
Get-ChildItem -LiteralPath $kitRoot -Filter '*.cmd' -File | Unblock-File

Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1')
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1')
if ($Culture) { Set-KitCulture -Culture $Culture }
if (-not $StatePath) { $StatePath = Get-LightgunDefaultStatePath }
Initialize-KitForms

$script:KitRootDir = $kitRoot
$script:StepsDir = Join-Path $kitRoot 'lightgun\steps'
$script:StateFile = $StatePath
$script:WizardScript = $PSCommandPath
# Started directly "as administrator": the logged-on user counts when it is the same account.
$script:UserSid = Get-KitStartUserSid -OriginalSid $KitUserSid
$script:ShotPath = $Screenshot
# Plans (installer with SHA256 and signature, disabling a task) are confirmed in a dialog, never silently.
$script:Approve = { param($text) Confirm-KitAction -Text $text }

# --- helpers ------------------------------------------------------------------------------------------------

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
# -Preview always runs as dry run (shows the planned changes) and asks nothing.
function Invoke-WizardStep([int] $Index, [string] $Script, [hashtable] $Params = @{}, [string] $ConfirmText, [switch] $Preview) {
    $w = $script:W
    $dry = $Preview -or (Test-KitWizardDryRun -Wizard $w)
    $title = Get-KitText $w.Pages[$Index].TitleKey
    if (-not $dry) {
        if (-not $ConfirmText) { $ConfirmText = Get-KitText 'Lightgun.Ui.Confirm.Step' -f $title }
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
        Write-KitWizardLog -Wizard $w -Text (Get-KitText 'Lightgun.Ui.StepError' -f $title, $_.Exception.Message) -Level Error
        $null = $results.Add([pscustomobject]@{ Status = 'Failed'; WhatIf = $false })
    } finally { $w.Form.Cursor = 'Default' }
    if (-not $Preview) { Set-KitWizardStatus -Wizard $w -Index $Index -Status (Get-StepPageStatus @($results)) }
}

function Get-SavedStatus([string[]] $StepNames) {
    $s = @($StepNames | ForEach-Object { Get-KitStepStatus -Path $script:StateFile -Name $_ })
    if (-not $s -or @($s | Where-Object { -not $_ }).Count) { return 'None' }
    if ($s -contains 'Failed') { return 'Failed' }
    if ($s -contains 'NeedsUser') { return 'NeedsUser' }
    'Done'
}

function Add-RunButton($Panel, [scriptblock] $OnClick) {
    $b = Add-KitUiButton -Panel $Panel -Text (Get-KitText 'Lightgun.Ui.Run') -OnClick $OnClick
    $b.Margin = New-Object Windows.Forms.Padding (3, 12, 3, 3)
    $b
}

# Button that opens an official web page (only https links, nothing else is ever started).
function Add-LinkButton($Panel, [string] $Url) {
    $null = Add-KitUiButton -Panel $Panel -Text (Get-KitText 'Lightgun.Ui.OpenLink' -f $Url) -Tag $Url -OnClick { if ([string]$this.Tag -match '^https://') { Start-Process ([string]$this.Tag) } }
}

# --- pages --------------------------------------------------------------------------------------------------

$pages = @(
    @{ TitleKey = 'Lightgun.Ui.Page.Start'; Build = {
        param($w, $p)
        $null = Add-KitUiText $p (Get-KitText 'Lightgun.Ui.Start.Intro')
        $admin = Test-KitAdmin
        $null = Add-KitUiText $p (Get-KitText $(if ($admin) { 'Admin.Yes' } else { 'Admin.No' })) -Color $(if ($admin) { 'ForestGreen' } else { 'DarkOrange' })
        if (-not $admin) {
            $null = Add-KitUiButton $p (Get-KitText 'Lightgun.Ui.Elevate') {
                Start-KitElevated -ScriptPath $script:WizardScript -ArgumentList @('-Culture', (Get-KitCulture)) -PassUserSid -Confirm:$false
                $script:W.Form.Close()
            }
        } elseif (-not $script:UserSid) { $null = Add-KitUiText $p (Get-KitRegistryUserLock) -Color 'DarkOrange' }
        $null = Add-KitUiText $p (Get-KitText 'Lightgun.Ui.DryRunHint')
        $null = Add-KitUiButton $p (Get-KitText 'Lightgun.Ui.SupportLog') {
            $log = Get-KitLogFile
            if (-not $log) { Write-KitWizardLog -Wizard $script:W -Text (Get-KitText 'Lightgun.Ui.NoLog') -Level Warn; return }
            $null = Export-KitSupportLog -Path $log, ([IO.Path]::ChangeExtension($log, '.transcript.log')) -Destination ([IO.Path]::ChangeExtension($log, '.support.txt'))
            Write-KitWizardLog -Wizard $script:W -Text (Get-KitText 'Log.SupportExported' -f ([IO.Path]::ChangeExtension($log, '.support.txt')))
        }
    } }
    @{ TitleKey = 'Lightgun.Ui.Page.Detect'; StepNames = @('lightgun-1-detect'); Build = {
        param($w, $p)
        $null = Add-KitUiText $p (Get-KitText 'Lightgun.Ui.Detect.Desc')
        $null = Add-KitUiPathBox $p (Get-KitText 'Lightgun.Ui.Detect.Folder') $w.Values['RetroBat'] { $script:W.Values['RetroBat'] = $this.Text }
        Add-LinkButton $p (Get-LightgunRetroBatReleaseUrl)
        $null = Add-RunButton $p {
            if (-not $script:W.Values['RetroBat']) { Write-KitWizardLog -Wizard $script:W -Text (Get-KitText 'Lightgun.Ui.Detect.Missing') -Level Warn; return }
            Invoke-WizardStep 1 '01-Detect.ps1' @{ RetroBatRoot = $script:W.Values['RetroBat'] }
        }
    } }
    @{ TitleKey = 'Lightgun.Ui.Page.Hardware'; StepNames = @('lightgun-2-hardware'); Build = {
        param($w, $p)
        $null = Add-KitUiText $p (Get-KitText 'Lightgun.Ui.Hardware.Desc')
        $null = Add-RunButton $p { Invoke-WizardStep 2 '02-Hardware.ps1' }
    } }
    @{ TitleKey = 'Lightgun.Ui.Page.ViGEm'; StepNames = @('lightgun-3-vigembus'); Build = {
        param($w, $p)
        $null = Add-KitUiText $p (Get-KitText 'Lightgun.Ui.ViGEm.Desc')
        $null = Add-KitUiText $p (Get-KitText 'Lightgun.ViGEm.Archived') -Color 'DimGray'
        $null = Add-KitUiCheck $p (Get-KitText 'Lightgun.Ui.ViGEm.Allow') ([bool]$w.Values['AllowViGEm']) { $script:W.Values['AllowViGEm'] = $this.Checked }
        Add-LinkButton $p (Get-LightgunViGEmRelease).Releases
        $null = Add-RunButton $p { Invoke-WizardStep 3 '03-ViGEmBus.ps1' @{ AllowInstall = [bool]$script:W.Values['AllowViGEm']; Approve = $script:Approve } }
    } }
    @{ TitleKey = 'Lightgun.Ui.Page.Gunmote'; StepNames = @('lightgun-4-gunmote'); Build = {
        param($w, $p)
        $null = Add-KitUiText $p (Get-KitText 'Lightgun.Ui.Gunmote.Desc')
        Add-LinkButton $p (Get-LightgunGunmoteReleaseUrl)
        $null = Add-KitUiPathBox $p (Get-KitText 'Lightgun.Ui.Gunmote.Folder') $w.Values['Gunmote'] { $script:W.Values['Gunmote'] = $this.Text }
        $null = Add-RunButton $p {
            $params = Add-UserSid @{}
            if ($script:W.Values['Gunmote']) { $params.GunmotePath = $script:W.Values['Gunmote'] }
            Invoke-WizardStep 4 '04-Gunmote.ps1' $params
        }
    } }
    @{ TitleKey = 'Lightgun.Ui.Page.Interference'; StepNames = @('lightgun-5-steam-blacklist', 'lightgun-5-vmulti-guard'); Build = {
        param($w, $p)
        $null = Add-KitUiText $p (Get-KitText 'Lightgun.Ui.Interference.Desc')
        $null = Add-KitUiCheck $p (Get-KitText 'Lightgun.Ui.Interference.Guard') ([bool]$w.Values['DisableGuard']) { $script:W.Values['DisableGuard'] = $this.Checked }
        $null = Add-RunButton $p { Invoke-WizardStep 5 '05-Interference.ps1' @{ DisableVMultiGuard = [bool]$script:W.Values['DisableGuard']; Approve = $script:Approve } }
    } }
    @{ TitleKey = 'Lightgun.Ui.Page.Layouts'; StepNames = @('lightgun-6-layouts'); Build = {
        param($w, $p)
        $null = Add-KitUiText $p (Get-KitText 'Lightgun.Ui.Layouts.Desc')
        foreach ($mode in 'Keep', 'Replace') {
            $r = New-Object Windows.Forms.RadioButton
            $r.AutoSize = $true
            $r.Text = Get-KitText "Lightgun.Ui.Mode.$mode"
            $r.Tag = $mode
            $r.Checked = $w.Values['LayoutMode'] -eq $mode
            $r.add_CheckedChanged({ if ($this.Checked) { $script:W.Values['LayoutMode'] = $this.Tag } })
            $p.Controls.Add($r)
        }
        $null = Add-KitUiButton $p (Get-KitText 'Lightgun.Ui.Preview') { Invoke-WizardStep 6 '06-GunmoteLayouts.ps1' @{ Mode = $script:W.Values['LayoutMode'] } -Preview }
        $null = Add-RunButton $p { Invoke-WizardStep 6 '06-GunmoteLayouts.ps1' @{ Mode = $script:W.Values['LayoutMode'] } }
    } }
    @{ TitleKey = 'Lightgun.Ui.Page.Settings'; StepNames = @('lightgun-7-retrobat-settings'); Build = {
        param($w, $p)
        $null = Add-KitUiText $p (Get-KitText 'Lightgun.Ui.Settings.Desc')
        $null = Add-KitUiButton $p (Get-KitText 'Lightgun.Ui.Preview') { Invoke-WizardStep 7 '07-RetroBatSettings.ps1' -Preview }
        $null = Add-RunButton $p { Invoke-WizardStep 7 '07-RetroBatSettings.ps1' }
    } }
    @{ TitleKey = 'Lightgun.Ui.Page.Automation'; StepNames = @('lightgun-8-profile-automation'); Build = {
        param($w, $p)
        $null = Add-KitUiText $p (Get-KitText 'Lightgun.Ui.Automation.Desc')
        $null = Add-RunButton $p { Invoke-WizardStep 8 '08-ProfileAutomation.ps1' (Add-UserSid @{}) }
    } }
    @{ TitleKey = 'Lightgun.Ui.Page.Verify'; StepNames = @('lightgun-9-xinput', 'lightgun-9-profile', 'lightgun-9-launcher'); Build = {
        param($w, $p)
        $null = Add-KitUiText $p (Get-KitText 'Lightgun.Ui.Verify.Desc')
        $null = Add-KitUiCheck $p (Get-KitText 'Lightgun.Ui.Verify.Again') ([bool]$w.Values['VerifyAgain']) { $script:W.Values['VerifyAgain'] = $this.Checked }
        # Measuring changes nothing, so it also runs in the dry run (no confirmation needed).
        $null = Add-RunButton $p {
            $dry = $script:W.DryRunBox.Checked
            $script:W.DryRunBox.Checked = $false
            try { Invoke-WizardStep 9 '09-Verify.ps1' @{ Again = [bool]$script:W.Values['VerifyAgain'] } (Get-KitText 'Lightgun.Ui.Verify.Confirm') }
            finally { $script:W.DryRunBox.Checked = $dry }
        }
    } }
    @{ TitleKey = 'Lightgun.Ui.Page.Calibration'; Build = {
        param($w, $p)
        foreach ($k in 'Lightgun.Ui.Calibration.Last', 'Lightgun.Ui.Calibration.One', 'Lightgun.Ui.Calibration.How', 'Lightgun.Ui.Calibration.Check') {
            $null = Add-KitUiText $p (Get-KitText $k)
        }
    } }
    @{ TitleKey = 'Lightgun.Ui.Page.Credits'; Build = {
        param($w, $p)
        $null = Add-KitUiText $p (Get-KitText 'Lightgun.Ui.Credits.Desc')
        $null = Add-KitCreditsView -Panel $p -Path (Join-Path $script:KitRootDir 'CREDITS.md')
    } }
)

# --- start --------------------------------------------------------------------------------------------------

$state = Read-KitState -Path $StatePath
$firstRun = -not @($state.Steps.PSObject.Properties | Where-Object { $_.Value.Status -eq 'Done' }).Count

$script:W = $null
$wizard = New-KitWizard -TitleKey 'Lightgun.Ui.Title' -Pages $pages -DryRun $firstRun -StartPage -1
$script:W = $wizard
$v = $wizard.Values
$v['LayoutMode'] = 'Keep'
$v['RetroBat'] = [string](Get-KitStateValue -Path $StatePath -Key 'RetroBatRoot')
$v['Gunmote'] = [string](Get-KitStateValue -Path $StatePath -Key 'GunmoteDir')
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

Start-KitLog -Path (Join-Path $kitRoot ('logs\lightgun-wizard_{0:yyyyMMdd-HHmmss}.log' -f (Get-Date)))
try { [void]$wizard.Form.ShowDialog() }
finally {
    $wizard.Form.Dispose()
    Stop-KitLog
}
