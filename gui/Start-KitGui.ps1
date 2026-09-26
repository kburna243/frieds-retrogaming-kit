<#
.SYNOPSIS
    Opens the kit's dashboard (WPF): new cabinet (pinball / lightgun wizards), migrate (v0.3), recover (backups),
    and the system status from the doctor (read-only, runs in the background).
.PARAMETER Culture
    UI language (de-DE, en-US). Default: the Windows display language.
.PARAMETER NoShow
    Build the window and return it without showing it (tests). The caller closes $ui.Window.
.PARAMETER DoctorResult
    Doctor rows to show instead of running the doctor (tests, screenshots).
.PARAMETER Launcher
    { param($Suite) ... } instead of starting a wizard process (tests).
.PARAMETER Screenshot
    Show the window, save it as PNG to this path and close.
#>
[CmdletBinding()]
param(
    [string] $Culture,
    [switch] $NoShow,
    [object[]] $DoctorResult,
    [scriptblock] $Launcher,
    [string] $Screenshot
)
$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent $PSScriptRoot

# Files downloaded as ZIP carry a Zone.Identifier; remove it from the kit's own files only.
Get-ChildItem -LiteralPath (Join-Path $kitRoot 'core'), (Join-Path $kitRoot 'pinball'), (Join-Path $kitRoot 'lightgun'), (Join-Path $kitRoot 'gui'), (Join-Path $kitRoot 'i18n') -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue

Import-Module (Join-Path $PSScriptRoot 'RetroCabinetKit.Gui.psd1')
if ($Culture) { Set-KitCulture -Culture $Culture }
if (-not $Launcher) { $Launcher = { param($Suite) Start-KitGuiWizard -Suite $Suite } }

$ui = New-KitGuiWindow
$c = $ui.Controls
$ui.Values['Launcher'] = $Launcher
foreach ($l in 'de-DE', 'en-US') { $null = $c.LanguageBox.Items.Add($l) }
$c.LanguageBox.SelectedItem = if ((Get-KitCulture) -like 'de*') { 'de-DE' } else { 'en-US' }
$version = ([IO.File]::ReadAllText((Join-Path $kitRoot 'VERSION'))).Trim()

function Update-Texts {
    $null = Update-KitGuiText -Root $ui.Window
    Update-KitGuiColumnText -Ui $ui
    $ui.Window.Title = Get-KitText 'Gui.Title'
    $c.FooterVersion.Text = Get-KitText 'Gui.Footer.Version' -f $version, $PSVersionTable.PSVersion
    if ($ui.Values.ContainsKey('DoctorResult')) { $null = Show-KitGuiStatus -Ui $ui -Result $ui.Values['DoctorResult'] }
}

function Start-Doctor {
    $c.StatusSummary.Text = Get-KitText 'Gui.Status.Running'
    $c.DoctorButton.IsEnabled = $false
    $job = Start-KitGuiDoctor
    $timer = New-Object Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $timer.Tag = $job
    $timer.add_Tick({
        $rows = Receive-KitGuiDoctor -Job $this.Tag
        if ($null -eq $rows) { return }
        $this.Stop()
        $null = Show-KitGuiStatus -Ui $ui -Result $rows
        $c.DoctorButton.IsEnabled = $true
    })
    $timer.Start()
}

# --- events ---------------------------------------------------------------------------------------------------
$c.LanguageBox.add_SelectionChanged({ Set-KitCulture -Culture ([string]$c.LanguageBox.SelectedItem); Update-Texts })
$c.NewPinballButton.add_Click({ & $ui.Values['Launcher'] 'Pinball' })
$c.NewLightgunButton.add_Click({ & $ui.Values['Launcher'] 'Lightgun' })
$c.RecoverButton.add_Click({ Show-KitGuiView -Ui $ui -Name Recover; $null = Update-KitGuiBackupList -Ui $ui })
$c.BackButton.add_Click({ Show-KitGuiView -Ui $ui -Name Dashboard })
$c.DoctorButton.add_Click({ Start-Doctor })
$c.DetailsButton.add_Click({ $c.StatusDetails.Visibility = if ($c.StatusDetails.Visibility -eq 'Visible') { 'Collapsed' } else { 'Visible' } })
$c.RefreshBackupsButton.add_Click({ $null = Update-KitGuiBackupList -Ui $ui })
$c.CheckBackupButton.add_Click({ $null = Invoke-KitGuiCheckBackup -Ui $ui })
$c.RestoreBackupButton.add_Click({ $null = Invoke-KitGuiRestoreBackup -Ui $ui })
$c.ExportBackupButton.add_Click({ $null = Invoke-KitGuiExportBackup -Ui $ui })
$c.DeleteBackupButton.add_Click({ $null = Invoke-KitGuiRemoveBackup -Ui $ui })

Update-Texts
Show-KitGuiView -Ui $ui -Name Dashboard
Set-KitGuiImage -Image $c.Mascot -Path (Get-KitGuiPath 'Assets\mascot-friendly.png')
if ($PSBoundParameters.ContainsKey('DoctorResult')) { $null = Show-KitGuiStatus -Ui $ui -Result @($DoctorResult) }

if ($NoShow) { return $ui }

if ($Screenshot) {
    $ui.Window.add_ContentRendered({
        $w = $ui.Window
        $bmp = New-Object Windows.Media.Imaging.RenderTargetBitmap ([int]$w.ActualWidth), ([int]$w.ActualHeight), 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
        $bmp.Render($w)
        $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder
        $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bmp))
        $stream = [IO.File]::Create($Screenshot)
        try { $enc.Save($stream) } finally { $stream.Dispose() }
        $w.Close()
    })
} elseif (-not $PSBoundParameters.ContainsKey('DoctorResult')) {
    $ui.Window.add_ContentRendered({ Start-Doctor })
}
[void]$ui.Window.ShowDialog()
