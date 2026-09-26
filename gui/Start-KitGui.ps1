<#
.SYNOPSIS
    Opens the kit's dashboard (WPF): new cabinet (pinball / lightgun wizards), migrate (cabinet profile A -> B),
    recover (backups),
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
    Render the window to this PNG without showing it (Save-KitGuiSnapshot) and exit.
.PARAMETER View
    The view to open with: Dashboard (default), Migrate or Recover (screenshots, tests).
#>
[CmdletBinding()]
param(
    [string] $Culture,
    [switch] $NoShow,
    [object[]] $DoctorResult,
    [scriptblock] $Launcher,
    [string] $Screenshot,
    [ValidateSet('Dashboard', 'Migrate', 'Recover')] [string] $View = 'Dashboard'
)
$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent $PSScriptRoot

# Files downloaded as ZIP carry a Zone.Identifier; remove it from the kit's own files only.
Get-ChildItem -LiteralPath (Join-Path $kitRoot 'core'), (Join-Path $kitRoot 'pinball'), (Join-Path $kitRoot 'lightgun'), (Join-Path $kitRoot 'gui'), (Join-Path $kitRoot 'i18n') -Recurse -File -ErrorAction SilentlyContinue | Unblock-File -ErrorAction SilentlyContinue

# The core is imported here too: this script calls core functions itself (texts, culture), and the GUI module
# loads the core only into its own scope.
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1')
Import-Module (Join-Path $PSScriptRoot 'RetroCabinetKit.Gui.psd1')
if ($Culture) { Set-KitCulture -Culture $Culture }
if (-not $Launcher) { $Launcher = { param($Suite) Start-KitGuiWizard -Suite $Suite } }

$ui = New-KitGuiWindow
$c = $ui.Controls
$ui.Values['Launcher'] = $Launcher
# Language chips: the button's Tag "active" fills it (ChipButton style); the culture itself is kept in the core.
function Set-Language([string] $Culture) {
    Set-KitCulture -Culture $Culture
    $c.LangDeButton.Tag = if ($Culture -like 'de*') { 'active' } else { $null }
    $c.LangEnButton.Tag = if ($Culture -like 'de*') { $null } else { 'active' }
}
Set-Language $(if ((Get-KitCulture) -like 'de*') { 'de-DE' } else { 'en-US' })
$version = ([IO.File]::ReadAllText((Join-Path $kitRoot 'VERSION'))).Trim()

function Update-Texts {
    $null = Update-KitGuiText -Root $ui.Window
    Update-KitGuiColumnText -Ui $ui
    $ui.Window.Title = Get-KitText 'Gui.Title'
    $c.FooterVersion.Text = Get-KitText 'Gui.Footer.Version' -f $version, $PSVersionTable.PSVersion
    if (-not $ui.Values.ContainsKey('ProfilePath')) { $c.ProfilePathText.Text = Get-KitText 'Gui.Migrate.NoProfile' }
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
$c.LangDeButton.add_Click({ Set-Language 'de-DE'; Update-Texts })
$c.LangEnButton.add_Click({ Set-Language 'en-US'; Update-Texts })
$c.NewPinballButton.add_Click({ & $ui.Values['Launcher'] 'Pinball' })
$c.NewLightgunButton.add_Click({ & $ui.Values['Launcher'] 'Lightgun' })
$c.MigrateButton.add_Click({ Show-KitGuiView -Ui $ui -Name Migrate })
$c.ExportPinballButton.add_Click({ $null = Invoke-KitGuiExportProfile -Ui $ui -Suite Pinball })
$c.ExportLightgunButton.add_Click({ $null = Invoke-KitGuiExportProfile -Ui $ui -Suite Lightgun })
$c.ChooseProfileButton.add_Click({ $null = Select-KitGuiProfile -Ui $ui })
$c.ImportProfileButton.add_Click({ $null = Invoke-KitGuiImportProfile -Ui $ui })
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
Show-KitGuiView -Ui $ui -Name $View
Set-KitGuiImage -Image $c.Mascot -Path (Get-KitGuiPath 'Assets\mascot-friendly.png')
if ($PSBoundParameters.ContainsKey('DoctorResult')) { $null = Show-KitGuiStatus -Ui $ui -Result @($DoctorResult) }

if ($NoShow -and -not $Screenshot) { return $ui }

if ($Screenshot) {
    $null = Save-KitGuiSnapshot -Ui $ui -Path $Screenshot
    $ui.Window.Close()
    return
}
if (-not $PSBoundParameters.ContainsKey('DoctorResult')) {
    $ui.Window.add_ContentRendered({ Start-Doctor })
}
[void]$ui.Window.ShowDialog()
