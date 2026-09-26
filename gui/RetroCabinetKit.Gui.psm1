#Requires -Version 5.1
# WPF front end (Windows PowerShell 5.1, .NET Framework: nothing to install). A thin layer: it loads the views,
# maps API results to them and calls the Kit API (api\, API.md) for everything the cabinet is asked or told.
# It uses the core only for the language texts. Everything it does is also available from the command line.
# Public functions follow Verb-KitGui*.

Set-StrictMode -Version 2.0

$script:GuiDir  = $PSScriptRoot
$script:KitRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $script:KitRoot 'core\RetroCabinetKit.Core.psd1')  # texts and culture only
Import-Module (Join-Path $script:KitRoot 'api\RetroCabinetKit.Api.psd1')
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$script:LevelLook = @{
    Ok    = @{ Symbol = [string][char]0x2713; Color = '#3DDC84' }  # check mark, Pixel Green
    Info  = @{ Symbol = [string][char]0x00B7; Color = '#B9B4A8' }  # middle dot, muted cream
    Warn  = @{ Symbol = '!';                  Color = '#FFC857' }  # Crown Gold
    Error = @{ Symbol = [string][char]0x2717; Color = '#FF4B3A' }  # ballot x, Retro Red
}
$script:LevelRank = @{ Ok = 0; Info = 1; Warn = 2; Error = 3 }

function Get-KitGuiPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Child)
    Join-Path $script:GuiDir $Child
}

# Loads a view with the brand theme inserted as Window.Resources and returns the window plus its named
# elements (Controls.<x:Name>).
function New-KitGuiWindow {
    [CmdletBinding()]
    param([string] $View = 'Views\MainWindow.xaml', [string] $Theme = 'Themes\Brand.xaml')
    $themeText = [IO.File]::ReadAllText((Get-KitGuiPath $Theme))
    $open = [regex]::Match($themeText, '<ResourceDictionary\b[^>]*>')
    $close = $themeText.LastIndexOf('</ResourceDictionary>')
    if (-not $open.Success -or $close -lt 0) { throw "No ResourceDictionary in $Theme" }
    $resources = $themeText.Substring($open.Index + $open.Length, $close - $open.Index - $open.Length)

    $xaml = [IO.File]::ReadAllText((Get-KitGuiPath $View))
    $start = [regex]::Match($xaml, '<Window\b[^>]*>')
    if (-not $start.Success) { throw "No Window element in $View" }
    $at = $start.Index + $start.Length
    $xaml = $xaml.Substring(0, $at) + '<Window.Resources><ResourceDictionary>' + $resources +
            '</ResourceDictionary></Window.Resources>' + $xaml.Substring($at)
    $window = [Windows.Markup.XamlReader]::Parse($xaml)

    $controls = @{}
    foreach ($m in [regex]::Matches($xaml, 'x:Name="([A-Za-z0-9_]+)"')) {
        $name = $m.Groups[1].Value
        $element = $window.FindName($name)
        if ($element) { $controls[$name] = $element }
    }
    [pscustomobject]@{ PSTypeName = 'RetroCabinetKit.GuiWindow'; Window = $window; Controls = $controls; Values = @{} }
}

# Sets Text / Content of every element whose Tag is "i18n:<key>" (walks the logical tree).
function Update-KitGuiText {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Root)
    $queue = New-Object Collections.Generic.Queue[object]
    $queue.Enqueue($Root)
    $count = 0
    while ($queue.Count) {
        $node = $queue.Dequeue()
        if ($node -is [Windows.FrameworkElement] -and $node.Tag -is [string] -and $node.Tag.StartsWith('i18n:')) {
            $text = Get-KitText $node.Tag.Substring(5)
            if ($node -is [Windows.Controls.TextBlock]) { $node.Text = $text; $count++ }
            elseif ($node -is [Windows.Controls.ContentControl]) { $node.Content = $text; $count++ }
        }
        if ($node -is [Windows.DependencyObject]) {
            foreach ($child in [Windows.LogicalTreeHelper]::GetChildren($node)) { if ($child -is [Windows.DependencyObject]) { $queue.Enqueue($child) } }
        }
    }
    $count
}

# One row per doctor area (worst level wins) and the summary line. $Result: the checks of the API's status
# operation (Area, Name, Level, Detail).
function Get-KitGuiStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Result)
    $converter = New-Object Windows.Media.BrushConverter
    $rows = foreach ($area in @($Result | ForEach-Object { $_.Area } | Select-Object -Unique)) {
        $items = @($Result | Where-Object { $_.Area -eq $area })
        $worst = ($items | Sort-Object { $script:LevelRank[$_.Level] } -Descending | Select-Object -First 1).Level
        $n = @{}
        foreach ($l in 'Ok', 'Info', 'Warn', 'Error') { $n[$l] = @($items | Where-Object { $_.Level -eq $l }).Count }
        $look = $script:LevelLook[$worst]
        [pscustomobject]@{
            Area   = $area
            Level  = $worst
            Symbol = $look.Symbol
            Brush  = $converter.ConvertFromString($look.Color)
            Text   = Get-KitText 'Gui.Status.Row' -f $n.Ok, $n.Warn, $n.Error
            Detail = @($items | Where-Object { $_.Level -in 'Warn', 'Error' } | ForEach-Object { '{0}: {1}' -f $_.Name, $_.Detail })
        } | ForEach-Object {
            # The reason of a warning or error is shown under its row, not only behind "Details".
            $_ | Add-Member -NotePropertyName DetailText -NotePropertyValue ($_.Detail -join [Environment]::NewLine) -PassThru |
                Add-Member -NotePropertyName DetailVisibility -NotePropertyValue $(if ($_.Detail.Count) { 'Visible' } else { 'Collapsed' }) -PassThru
        }
    }
    $errors = @($Result | Where-Object { $_.Level -eq 'Error' }).Count
    $warnings = @($Result | Where-Object { $_.Level -eq 'Warn' }).Count
    $level = if ($errors) { 'Error' } elseif ($warnings) { 'Warn' } else { 'Ok' }
    $text = switch ($level) {
        'Error' { Get-KitText 'Gui.Status.Errors' -f $errors, $warnings }
        'Warn'  { Get-KitText 'Gui.Status.Warnings' -f $warnings }
        default { Get-KitText 'Gui.Status.Healthy' }
    }
    [pscustomobject]@{ Level = $level; Text = $text; Rows = @($rows) }
}

# The checks as text lines for "Details".
function Format-KitGuiCheck {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Result)
    foreach ($r in $Result) {
        $line = '{0,-6} {1} / {2}' -f $r.Level.ToUpperInvariant(), $r.Area, $r.Name
        if ($r.Detail) { "${line}: $($r.Detail)" } else { $line }
    }
}

# Runs the API's status operation in a background runspace, so the window stays responsive. Receive-KitGuiDoctor
# returns the checks once it has finished ($null before).
function Start-KitGuiDoctor {
    [CmdletBinding()]
    param([string] $Culture = (Get-KitCulture))
    $ps = [PowerShell]::Create()
    $null = $ps.AddScript({
        param($KitRoot, $Culture)
        Import-Module (Join-Path $KitRoot 'core\RetroCabinetKit.Core.psd1')
        Import-Module (Join-Path $KitRoot 'api\RetroCabinetKit.Api.psd1')
        Set-KitCulture -Culture $Culture
        Invoke-KitOperation -Name 'status'
    }).AddArgument($script:KitRoot).AddArgument($Culture)
    [pscustomobject]@{ PowerShell = $ps; Handle = $ps.BeginInvoke() }
}

function Receive-KitGuiDoctor {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Job)
    if (-not $Job.Handle.IsCompleted) { return $null }
    try {
        $result = @($Job.PowerShell.EndInvoke($Job.Handle)) | Select-Object -Last 1
        if ($result -and $result.Success -and $result.Data) { , @($result.Data.Checks) }
        else { , @(New-KitGuiCheck -Area 'Kit' -Name 'status' -Level Error -Detail $(if ($result) { $result.Message } else { 'no result' })) }
    } finally { $Job.PowerShell.Dispose() }
}

# A check row in the shape of the API's status checks (tests, and an error row when the status fails).
function New-KitGuiCheck {
    [CmdletBinding()]
    param([string] $Area, [string] $Name, [ValidateSet('Ok', 'Info', 'Warn', 'Error')] [string] $Level, [string] $Detail = '')
    [pscustomobject]@{ Area = $Area; Name = $Name; Level = $Level; Detail = $Detail }
}

# Shows doctor rows in the dashboard (status rows, summary, crown when healthy, details, mascot mood).
function Show-KitGuiStatus {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Ui, [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Result)
    $Ui.Values['DoctorResult'] = $Result
    $status = Get-KitGuiStatus -Result $Result
    $c = $Ui.Controls
    $c.StatusRows.ItemsSource = $status.Rows
    $c.StatusSummary.Text = $status.Text
    $c.StatusCrown.Visibility = if ($status.Level -eq 'Ok') { 'Visible' } else { 'Collapsed' }
    $c.StatusDetails.Text = (Format-KitGuiCheck -Result $Result) -join [Environment]::NewLine
    $mood = @{ Ok = 'mascot-thumbsup.png'; Warn = 'mascot-friendly.png'; Error = 'mascot-surprised.png' }[$status.Level]
    Set-KitGuiImage -Image $c.Mascot -Path (Get-KitGuiPath "Assets\$mood")
    $status
}

function Set-KitGuiImage {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Image, [Parameter(Mandatory)] [string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $bitmap = New-Object Windows.Media.Imaging.BitmapImage
    $bitmap.BeginInit()
    $bitmap.CacheOption = 'OnLoad' # the file is not kept open
    $bitmap.UriSource = New-Object Uri $Path
    $bitmap.EndInit()
    $Image.Source = $bitmap
}

# --- recover --------------------------------------------------------------------------------------------------


function Write-KitGuiRecoverLog {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Ui, [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text)
    $log = $Ui.Controls.RecoverLog
    $log.Text = if ($log.Text) { $log.Text + [Environment]::NewLine + '> ' + $Text } else { '> ' + $Text }
    if ($Ui.Controls.ContainsKey('RecoverLogScroll')) { $Ui.Controls.RecoverLogScroll.ScrollToEnd() }
}

# Fills the backup list through the API (backups.list; default roots: those of both suites); returns the rows.
# $Ui.Values['BackupRoots'] overrides the roots (tests).
function Update-KitGuiBackupList {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Ui)
    $p = @{}
    if ($Ui.Values.ContainsKey('BackupRoots')) { $p.Root = [string[]]@($Ui.Values['BackupRoots']) }
    $r = Invoke-KitOperation -Name 'backups.list' -Parameters $p
    if (-not $r.Success) { Write-KitGuiRecoverLog -Ui $Ui -Text $r.Message; $Ui.Controls.BackupList.ItemsSource = @(); return @() }
    $rows = @(foreach ($b in @($r.Data.Backups)) {
        $target = if ($b.Kind -eq 'Zip') { '{0} - {1}' -f (Get-KitText 'Recovery.ZipDetail' -f $b.Files, $b.Registry), $b.Path } else { $b.Original }
        $created = [datetime]::Parse($b.Created, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
        $b | Add-Member -NotePropertyName CreatedText -NotePropertyValue ($created.ToString('yyyy-MM-dd HH:mm')) -PassThru |
            Add-Member -NotePropertyName TargetText -NotePropertyValue $target -PassThru
    })
    $Ui.Controls.BackupList.ItemsSource = $rows
    if (-not $rows.Count) { Write-KitGuiRecoverLog -Ui $Ui -Text (Get-KitText 'Recovery.None' -f (@($r.Data.Roots) -join '; ')) }
    $rows
}

function Get-KitGuiSelectedBackup([psobject] $Ui) {
    $b = $Ui.Controls.BackupList.SelectedItem
    if (-not $b) { Write-KitGuiRecoverLog -Ui $Ui -Text (Get-KitText 'Ui.Care.SelectFirst') }
    $b
}

# Yes/No question in a WPF message box (tests pass their own -Confirm).
function Confirm-KitGuiAction {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Text)
    [Windows.MessageBox]::Show($Text, (Get-KitText 'Ui.Confirm.Title'), 'YesNo', 'Question') -eq 'Yes'
}

function Invoke-KitGuiCheckBackup {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Ui)
    $b = Get-KitGuiSelectedBackup $Ui
    if (-not $b) { return }
    $r = Invoke-KitOperation -Name 'backup.check' -Parameters @{ Path = $b.Path }
    Write-KitGuiRecoverLog -Ui $Ui -Text $r.Message
    if ($r.Data) { foreach ($p in @($r.Data.Problems)) { Write-KitGuiRecoverLog -Ui $Ui -Text "  $p" } }
    $r
}

# Restores the selected backup through the API. Follows the dry-run box (the API runs a dry run without -Apply);
# asks first; -Guard lets the window say early that a guarded program still runs (the API checks it again).
function Invoke-KitGuiRestoreBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $Ui,
        [scriptblock] $Confirm = { param($text) Confirm-KitGuiAction -Text $text },
        [scriptblock] $Guard = {}
    )
    $b = Get-KitGuiSelectedBackup $Ui
    if (-not $b) { return }
    if ($b.Kind -ne 'File') { Write-KitGuiRecoverLog -Ui $Ui -Text (Get-KitText 'Ui.Care.ZipOnCommandLine'); return }
    $dry = [bool]$Ui.Controls.DryRunBox.IsChecked
    if (-not $dry -and -not (& $Confirm (Get-KitText 'Ui.Care.ConfirmRestore' -f $b.Original, $b.Path))) { return }
    try { & $Guard } catch { Write-KitGuiRecoverLog -Ui $Ui -Text $_.Exception.Message; return }
    $r = Invoke-KitOperation -Name 'backup.restore' -Parameters @{ Path = $b.Path } -Apply:(-not $dry)
    Write-KitGuiRecoverLog -Ui $Ui -Text $r.Message
    if ($r.Status -eq 'Done') { $null = Update-KitGuiBackupList -Ui $Ui }
    $r
}

function Invoke-KitGuiExportBackup {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Ui, [string] $Destination)
    $b = Get-KitGuiSelectedBackup $Ui
    if (-not $b) { return }
    if (-not $Destination) {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object Windows.Forms.FolderBrowserDialog
        try { if ($dialog.ShowDialog() -ne 'OK') { return }; $Destination = $dialog.SelectedPath } finally { $dialog.Dispose() }
    }
    # Choosing the folder is the person's decision, so the export is applied.
    $r = Invoke-KitOperation -Name 'backup.export' -Parameters @{ Path = $b.Path; Destination = $Destination } -Apply
    Write-KitGuiRecoverLog -Ui $Ui -Text $r.Message
    $r
}

function Invoke-KitGuiRemoveBackup {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Ui, [scriptblock] $Confirm = { param($text) Confirm-KitGuiAction -Text $text })
    $b = Get-KitGuiSelectedBackup $Ui
    if (-not $b) { return }
    if (-not (& $Confirm (Get-KitText 'Ui.Care.ConfirmDelete' -f $b.Path))) { return }
    $r = Invoke-KitOperation -Name 'backup.remove' -Parameters @{ Path = $b.Path } -Apply
    Write-KitGuiRecoverLog -Ui $Ui -Text $r.Message
    if ($r.Status -eq 'Done') { $null = Update-KitGuiBackupList -Ui $Ui }
    $r
}

# --- migrate --------------------------------------------------------------------------------------------------

function Write-KitGuiMigrateLog {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Ui, [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text)
    $log = $Ui.Controls.MigrateLog
    $log.Text = if ($log.Text) { $log.Text + [Environment]::NewLine + '> ' + $Text } else { '> ' + $Text }
    if ($Ui.Controls.ContainsKey('MigrateLogScroll')) { $Ui.Controls.MigrateLogScroll.ScrollToEnd() }
}

# Parameters every profile call gets on top of its own: $Ui.Values['ProfileRoots'] (tests: RetroBatRoot,
# GunmoteDir, PupDatabasePath, ... of a test cabinet). Without it the engine finds the installed programs itself.
function Get-KitGuiProfileParameter([psobject] $Ui, [hashtable] $Own) {
    $p = @{} + $Own
    if ($Ui.Values.ContainsKey('ProfileRoots')) { foreach ($k in $Ui.Values['ProfileRoots'].Keys) { $p[$k] = $Ui.Values['ProfileRoots'][$k] } }
    $p
}

# One line per row of the engine (Name, Status, Detail), so the person sees what an import checked or changed.
function Write-KitGuiProfileRows([psobject] $Ui, $Result) {
    Write-KitGuiMigrateLog -Ui $Ui -Text $Result.Message
    if (-not $Result.Data -or -not $Result.Data.PSObject.Properties['Result']) { return }
    foreach ($row in @($Result.Data.Result)) {
        if ($row -and $row.PSObject.Properties['Status'] -and $row.PSObject.Properties['Name']) {
            $detail = if ($row.PSObject.Properties['Detail']) { $row.Detail } else { '' }
            Write-KitGuiMigrateLog -Ui $Ui -Text ('  [{0}] {1}: {2}' -f $row.Status, $row.Name, $detail)
        }
    }
}

# Cabinet A: writes the profile of one suite into a folder the person chooses (choosing it is the decision, so
# the export is applied; it only reads the cabinet and writes the zip).
function Invoke-KitGuiExportProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Ui, [Parameter(Mandatory)] [ValidateSet('Pinball', 'Lightgun')] [string] $Suite, [string] $Destination)
    if (-not $Destination) {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object Windows.Forms.FolderBrowserDialog
        try { if ($dialog.ShowDialog() -ne 'OK') { return }; $Destination = $dialog.SelectedPath } finally { $dialog.Dispose() }
    }
    $r = Invoke-KitOperation -Name 'profile.export' -Parameters (Get-KitGuiProfileParameter $Ui @{ Suite = $Suite; Destination = $Destination }) -Apply
    Write-KitGuiProfileRows $Ui $r
    if (-not $r.Success) { foreach ($e in @($r.Errors)) { Write-KitGuiMigrateLog -Ui $Ui -Text "  $e" } }
    $r
}

# Cabinet B: remembers the profile zip to import (file dialog unless -Path).
function Select-KitGuiProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Ui, [string] $Path)
    if (-not $Path) {
        Add-Type -AssemblyName System.Windows.Forms
        $dialog = New-Object Windows.Forms.OpenFileDialog
        $dialog.Filter = 'Cabinet profile (*.zip)|cabinet-profile-*.zip|*.zip|*.zip'
        try { if ($dialog.ShowDialog() -ne 'OK') { return }; $Path = $dialog.FileName } finally { $dialog.Dispose() }
    }
    $Ui.Values['ProfilePath'] = $Path
    $Ui.Controls.ProfilePathText.Text = $Path
    $Path
}

# Cabinet B: imports the chosen profile through the API. Follows the dry-run box (the engine checks everything and
# writes nothing); a real import asks first. Plans that need approval (installers with SHA-256 and signature) come
# back in Approvals: they are shown to the person, and only after a yes the import runs again with -Approved (the
# engine skips what is already in place). Then the system status is the verification.
function Invoke-KitGuiImportProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $Ui,
        [scriptblock] $Confirm = { param($text) Confirm-KitGuiAction -Text $text }
    )
    if (-not $Ui.Values.ContainsKey('ProfilePath') -or -not $Ui.Values['ProfilePath']) { Write-KitGuiMigrateLog -Ui $Ui -Text (Get-KitText 'Gui.Migrate.ChooseFirst'); return }
    $path = [string]$Ui.Values['ProfilePath']
    $dry = [bool]$Ui.Controls.MigrateDryRunBox.IsChecked
    $own = @{ Path = $path }
    if ($Ui.Controls.AutoInstallBox.IsChecked) { $own.AutoInstall = $true }
    if (-not $dry -and -not (& $Confirm (Get-KitText 'Gui.Migrate.ConfirmImport' -f $path))) { return }
    $p = Get-KitGuiProfileParameter $Ui $own
    $r = Invoke-KitOperation -Name 'profile.import' -Parameters $p -Apply:(-not $dry)
    if (-not $dry -and @($r.Approvals).Count) {
        $text = (Get-KitText 'Gui.Migrate.Approve') + [Environment]::NewLine + [Environment]::NewLine + (@($r.Approvals) -join ([Environment]::NewLine + [Environment]::NewLine))
        if (& $Confirm $text) { $r = Invoke-KitOperation -Name 'profile.import' -Parameters $p -Apply -Approved }
    }
    Write-KitGuiProfileRows $Ui $r
    if ($r.Status -eq 'Failed') { foreach ($e in @($r.Errors)) { Write-KitGuiMigrateLog -Ui $Ui -Text "  $e" } }
    if (-not $dry -and $r.Success) { Write-KitGuiMigrateLog -Ui $Ui -Text (Get-KitText 'Gui.Migrate.Verify') }
    $r
}

# Switches between the dashboard, the migrate and the recover view.
function Show-KitGuiView {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Ui, [Parameter(Mandatory)] [ValidateSet('Dashboard', 'Migrate', 'Recover')] [string] $Name)
    $c = $Ui.Controls
    $c.DashboardView.Visibility = if ($Name -eq 'Dashboard') { 'Visible' } else { 'Collapsed' }
    $c.MigrateView.Visibility = if ($Name -eq 'Migrate') { 'Visible' } else { 'Collapsed' }
    $c.RecoverView.Visibility = if ($Name -eq 'Recover') { 'Visible' } else { 'Collapsed' }
    $c.BackButton.Visibility = if ($Name -eq 'Dashboard') { 'Collapsed' } else { 'Visible' }
    $Ui.Values['View'] = $Name
}

# Column headers of the backup list (a GridViewColumn has no Tag, so Update-KitGuiText cannot reach them).
function Update-KitGuiColumnText {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Ui)
    $keys = 'Gui.Recover.ColCreated', 'Gui.Recover.ColKind', 'Gui.Recover.ColPurpose', 'Gui.Recover.ColTarget'
    $columns = $Ui.Controls.BackupList.View.Columns
    for ($i = 0; $i -lt [Math]::Min($columns.Count, $keys.Count); $i++) { $columns[$i].Header = Get-KitText $keys[$i] }
}

# Starts a wizard in its own Windows PowerShell process (full path, like the *.cmd launchers).
function Start-KitGuiWizard {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [ValidateSet('Pinball', 'Lightgun')] [string] $Suite, [string] $Culture = (Get-KitCulture))
    $script = Join-Path $script:KitRoot ('{0}\ui\Wizard.ps1' -f $Suite.ToLowerInvariant())
    $exe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    Start-Process -FilePath $exe -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $script), '-Culture', $Culture)
}

# Renders the window's content to a PNG without showing the window (reviews, CI artifacts). The content is
# moved into a Border with the window background, measured and arranged at the given size, then put back.
# Its StaticResource references were resolved when the view was loaded, so it renders the same outside.
function Save-KitGuiSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $Ui,
        [Parameter(Mandatory)] [string] $Path,
        [int] $Width = 1120,
        [int] $Height = 760
    )
    $window = $Ui.Window
    $content = $window.Content
    $window.Content = $null
    $frame = New-Object Windows.Controls.Border
    $frame.Background = $window.FindResource('NightBrush')
    $frame.Child = $content
    try {
        $size = New-Object Windows.Size $Width, $Height
        $frame.Measure($size)
        $frame.Arrange((New-Object Windows.Rect $size))
        $frame.UpdateLayout()
        $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap $Width, $Height, 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
        $bitmap.Render($frame)
        $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
        $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
        $dir = Split-Path -Parent ([IO.Path]::GetFullPath($Path))
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $stream = [IO.File]::Create($Path)
        try { $encoder.Save($stream) } finally { $stream.Dispose() }
    } finally {
        $frame.Child = $null
        $window.Content = $content
    }
    Get-Item -LiteralPath $Path
}

Export-ModuleMember -Function '*-KitGui*'
