#Requires -Version 5.1
# WPF front end (Windows PowerShell 5.1, .NET Framework: nothing to install). A thin layer: it loads the views,
# maps engine results (doctor rows, backups, step results) to them and calls the engine. No kit logic lives
# here; everything it does is also available from the command line (core\Start-KitTools.ps1, the step scripts).
# Public functions follow Verb-KitGui*.

Set-StrictMode -Version 2.0

$script:GuiDir  = $PSScriptRoot
$script:KitRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $script:KitRoot 'core\RetroCabinetKit.Core.psd1')
Import-Module (Join-Path $script:KitRoot 'pinball\RetroCabinetKit.Pinball.psd1')
Import-Module (Join-Path $script:KitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1')
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

# One row per doctor area (worst level wins) and the summary line.
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
        }
    }
    $s = Get-KitDoctorSummary -Result $Result
    $level = if ($s.Error) { 'Error' } elseif ($s.Warn) { 'Warn' } else { 'Ok' }
    $text = switch ($level) {
        'Error' { Get-KitText 'Gui.Status.Errors' -f $s.Error, $s.Warn }
        'Warn'  { Get-KitText 'Gui.Status.Warnings' -f $s.Warn }
        default { Get-KitText 'Gui.Status.Healthy' }
    }
    [pscustomobject]@{ Level = $level; Text = $text; Rows = @($rows) }
}

# Runs the doctor in a background runspace, so the window stays responsive. Receive-KitGuiDoctor returns the
# rows once it has finished ($null before).
function Start-KitGuiDoctor {
    [CmdletBinding()]
    param([string] $Culture = (Get-KitCulture))
    $ps = [PowerShell]::Create()
    $null = $ps.AddScript({
        param($KitRoot, $Culture)
        Import-Module (Join-Path $KitRoot 'core\RetroCabinetKit.Core.psd1')
        Import-Module (Join-Path $KitRoot 'pinball\RetroCabinetKit.Pinball.psd1')
        Import-Module (Join-Path $KitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1')
        Set-KitCulture -Culture $Culture
        Invoke-KitDoctor -Check @(@(Get-KitSystemCheck) + @(Get-PinballDoctorCheck) + @(Get-LightgunDoctorCheck))
    }).AddArgument($script:KitRoot).AddArgument($Culture)
    [pscustomobject]@{ PowerShell = $ps; Handle = $ps.BeginInvoke() }
}

function Receive-KitGuiDoctor {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Job)
    if (-not $Job.Handle.IsCompleted) { return $null }
    try { , @($Job.PowerShell.EndInvoke($Job.Handle)) } finally { $Job.PowerShell.Dispose() }
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
    $c.StatusDetails.Text = (Format-KitDoctorReport -Result $Result) -join [Environment]::NewLine
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

function Get-KitGuiBackupRoot {
    [CmdletBinding()]
    param([string] $PinballStatePath = (Get-PinballDefaultStatePath), [string] $LightgunStatePath = (Get-LightgunDefaultStatePath))
    @(@(Get-PinballBackupRoot -StatePath $PinballStatePath) + @(Get-LightgunBackupRoot -StatePath $LightgunStatePath) | Sort-Object -Unique)
}

function Write-KitGuiRecoverLog {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Ui, [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text)
    $log = $Ui.Controls.RecoverLog
    $log.Text = if ($log.Text) { $log.Text + [Environment]::NewLine + '> ' + $Text } else { '> ' + $Text }
    if ($Ui.Controls.ContainsKey('RecoverLogScroll')) { $Ui.Controls.RecoverLogScroll.ScrollToEnd() }
}

# Fills the backup list from the given roots (default: the roots of both suites); returns the rows.
function Update-KitGuiBackupList {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Ui, [string[]] $Root)
    if (-not $PSBoundParameters.ContainsKey('Root')) { $Root = if ($Ui.Values.ContainsKey('BackupRoots')) { $Ui.Values['BackupRoots'] } else { Get-KitGuiBackupRoot } }
    $rows = @(foreach ($b in Get-KitBackup -Path @($Root)) {
        $target = if ($b.Kind -eq 'Zip') { '{0} - {1}' -f (Get-KitText 'Recovery.ZipDetail' -f $b.Files, $b.Registry), $b.Path } else { $b.Original }
        $b | Add-Member -NotePropertyName CreatedText -NotePropertyValue ($b.Created.ToString('yyyy-MM-dd HH:mm')) -PassThru |
            Add-Member -NotePropertyName TargetText -NotePropertyValue $target -PassThru
    })
    $Ui.Controls.BackupList.ItemsSource = $rows
    if (-not $rows.Count) { Write-KitGuiRecoverLog -Ui $Ui -Text (Get-KitText 'Recovery.None' -f (@($Root) -join '; ')) }
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
    try {
        $r = Test-KitBackup -Path $b.Path
        if ($r.Ok) { Write-KitGuiRecoverLog -Ui $Ui -Text (Get-KitText 'Recovery.CheckOk' -f $r.Path) }
        else {
            Write-KitGuiRecoverLog -Ui $Ui -Text (Get-KitText 'Recovery.CheckBad' -f $r.Path)
            foreach ($p in $r.Problems) { Write-KitGuiRecoverLog -Ui $Ui -Text "  $p" }
        }
        $r
    } catch { Write-KitGuiRecoverLog -Ui $Ui -Text $_.Exception.Message }
}

# Restores the selected file copy. Follows the dry-run box; asks first; checks that no guarded program runs.
function Invoke-KitGuiRestoreBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $Ui,
        [scriptblock] $Confirm = { param($text) Confirm-KitGuiAction -Text $text },
        [scriptblock] $Guard = { Assert-PinballProcessesClosed; Assert-LightgunProcessesClosed }
    )
    $b = Get-KitGuiSelectedBackup $Ui
    if (-not $b) { return }
    if ($b.Kind -ne 'File') { Write-KitGuiRecoverLog -Ui $Ui -Text (Get-KitText 'Ui.Care.ZipOnCommandLine'); return }
    $dry = [bool]$Ui.Controls.DryRunBox.IsChecked
    if (-not $dry -and -not (& $Confirm (Get-KitText 'Ui.Care.ConfirmRestore' -f $b.Original, $b.Path))) { return }
    try {
        & $Guard
        $r = Restore-KitFileBackup -Path $b.Path -WhatIf:$dry -Confirm:$false
        if ($r.Action -eq 'WhatIf') { Write-KitGuiRecoverLog -Ui $Ui -Text (Get-KitText 'Ui.Care.RestorePlan' -f $r.Target, $r.Source) }
        else {
            Write-KitGuiRecoverLog -Ui $Ui -Text (Get-KitText 'Recovery.Restored' -f $r.Target, $r.Source)
            $null = Update-KitGuiBackupList -Ui $Ui
        }
        $r
    } catch { Write-KitGuiRecoverLog -Ui $Ui -Text $_.Exception.Message }
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
    try {
        $item = Export-KitBackup -Path $b.Path -Destination $Destination
        Write-KitGuiRecoverLog -Ui $Ui -Text (Get-KitText 'Recovery.Exported' -f $item.FullName)
        $item
    } catch { Write-KitGuiRecoverLog -Ui $Ui -Text $_.Exception.Message }
}

function Invoke-KitGuiRemoveBackup {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Ui, [scriptblock] $Confirm = { param($text) Confirm-KitGuiAction -Text $text })
    $b = Get-KitGuiSelectedBackup $Ui
    if (-not $b) { return }
    if (-not (& $Confirm (Get-KitText 'Ui.Care.ConfirmDelete' -f $b.Path))) { return }
    try {
        Remove-KitBackup -Path $b.Path -Confirm:$false
        Write-KitGuiRecoverLog -Ui $Ui -Text (Get-KitText 'Recovery.Deleted' -f $b.Path)
        $null = Update-KitGuiBackupList -Ui $Ui
    } catch { Write-KitGuiRecoverLog -Ui $Ui -Text $_.Exception.Message }
}

# Switches between the dashboard and the recover view.
function Show-KitGuiView {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Ui, [Parameter(Mandatory)] [ValidateSet('Dashboard', 'Recover')] [string] $Name)
    $c = $Ui.Controls
    $c.DashboardView.Visibility = if ($Name -eq 'Dashboard') { 'Visible' } else { 'Collapsed' }
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
