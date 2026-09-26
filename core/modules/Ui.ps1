# Ui: DPI awareness, monitor capture and a small generic WinForms wizard frame (pages, status list,
# log box, language switch, dry-run switch, credits view, measuring window, confirmation dialog).
# Windows Forms is loaded lazily (Initialize-KitForms), so importing the core never creates a window.
# DPI awareness must be set before the first window or Screen call, otherwise Windows hands out scaled
# ("virtualized") coordinates; E_ACCESSDENIED means it was already set (e.g. by the host) and is fine.

if (-not ('RetroCabinetKit.DisplayNative' -as [type])) {
    Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace RetroCabinetKit
{
    public sealed class MonitorData
    {
        public string DeviceName;
        public int X, Y, Width, Height, Dpi, PelsWidth, PelsHeight, RefreshRate;
        public bool Primary;
    }

    public static class DisplayNative
    {
        [StructLayout(LayoutKind.Sequential)]
        struct RECT { public int Left, Top, Right, Bottom; }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct MONITORINFOEX
        {
            public int cbSize; public RECT rcMonitor; public RECT rcWork; public int dwFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string szDevice;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct POINTL { public int x; public int y; }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct DEVMODE
        {
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
            public short dmSpecVersion, dmDriverVersion, dmSize, dmDriverExtra;
            public int dmFields;
            public POINTL dmPosition;
            public int dmDisplayOrientation, dmDisplayFixedOutput;
            public short dmColor, dmDuplex, dmYResolution, dmTTOption, dmCollate;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
            public short dmLogPixels;
            public int dmBitsPerPel, dmPelsWidth, dmPelsHeight, dmDisplayFlags, dmDisplayFrequency;
            public int dmICMMethod, dmICMIntent, dmMediaType, dmDitherType, dmReserved1, dmReserved2, dmPanningWidth, dmPanningHeight;
        }

        delegate bool MonitorEnumProc(IntPtr monitor, IntPtr hdc, IntPtr rect, IntPtr data);

        [DllImport("user32.dll", SetLastError = true)] static extern bool SetProcessDpiAwarenessContext(IntPtr value);
        [DllImport("shcore.dll")] static extern int SetProcessDpiAwareness(int value);
        [DllImport("user32.dll")] static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr clip, MonitorEnumProc proc, IntPtr data);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFOEX info);
        [DllImport("shcore.dll")] static extern int GetDpiForMonitor(IntPtr monitor, int type, out uint dpiX, out uint dpiY);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern bool EnumDisplaySettings(string device, int mode, ref DEVMODE mode2);

        // "PerMonitorV2", "PerMonitor", "AlreadySet" (E_ACCESSDENIED / ERROR_ACCESS_DENIED) or "Failed".
        public static string EnableDpiAwareness()
        {
            try
            {
                if (SetProcessDpiAwarenessContext(new IntPtr(-4))) return "PerMonitorV2";
                if (Marshal.GetLastWin32Error() == 5) return "AlreadySet";
            }
            catch (EntryPointNotFoundException) { }
            try
            {
                int hr = SetProcessDpiAwareness(2);
                if (hr == 0) return "PerMonitor";
                if (hr == unchecked((int)0x80070005)) return "AlreadySet";
            }
            catch (DllNotFoundException) { }
            catch (EntryPointNotFoundException) { }
            return "Failed";
        }

        public static MonitorData[] GetMonitors()
        {
            var list = new List<MonitorData>();
            MonitorEnumProc proc = delegate (IntPtr monitor, IntPtr hdc, IntPtr rect, IntPtr data)
            {
                var info = new MONITORINFOEX();
                info.cbSize = Marshal.SizeOf(typeof(MONITORINFOEX));
                if (!GetMonitorInfo(monitor, ref info)) return true;
                var m = new MonitorData();
                m.DeviceName = info.szDevice;
                m.X = info.rcMonitor.Left; m.Y = info.rcMonitor.Top;
                m.Width = info.rcMonitor.Right - info.rcMonitor.Left;
                m.Height = info.rcMonitor.Bottom - info.rcMonitor.Top;
                m.Primary = (info.dwFlags & 1) != 0;
                uint dx, dy;
                try { m.Dpi = GetDpiForMonitor(monitor, 0, out dx, out dy) == 0 ? (int)dx : 96; }
                catch (DllNotFoundException) { m.Dpi = 96; }
                catch (EntryPointNotFoundException) { m.Dpi = 96; }
                var dm = new DEVMODE();
                dm.dmDeviceName = new string(' ', 32);
                dm.dmFormName = new string(' ', 32);
                dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
                if (EnumDisplaySettings(info.szDevice, -1, ref dm))
                {
                    m.PelsWidth = dm.dmPelsWidth; m.PelsHeight = dm.dmPelsHeight; m.RefreshRate = dm.dmDisplayFrequency;
                }
                list.Add(m);
                return true;
            };
            EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, proc, IntPtr.Zero);
            GC.KeepAlive(proc);
            return list.ToArray();
        }
    }
}
'@
}

$script:KitDpiAwareness = $null
$script:KitFormsReady = $false

function Enable-KitDpiAwareness {
    [CmdletBinding()]
    param()
    if (-not $script:KitDpiAwareness) {
        $script:KitDpiAwareness = [RetroCabinetKit.DisplayNative]::EnableDpiAwareness()
        if ($script:KitDpiAwareness -eq 'Failed') { Write-KitLog (Get-KitText 'Ui.DpiFailed') -Level Warn }
    }
    $script:KitDpiAwareness
}

# Scale in percent: from the monitor DPI (reliable when the process is DPI aware) and from the ratio of the
# real mode width to the reported width (reliable when it is not, because Windows then reports scaled bounds).
function Get-KitMonitor {
    [CmdletBinding()]
    param()
    $null = Enable-KitDpiAwareness
    foreach ($m in [RetroCabinetKit.DisplayNative]::GetMonitors() | Sort-Object X, Y) {
        $dpiScale  = [int][math]::Round($m.Dpi * 100 / 96)
        $pelsScale = if ($m.Width -gt 0 -and $m.PelsWidth -gt 0) { [int][math]::Round($m.PelsWidth * 100 / $m.Width) } else { 100 }
        [pscustomobject]@{
            DeviceName  = $m.DeviceName
            X           = $m.X
            Y           = $m.Y
            Width       = $m.Width
            Height      = $m.Height
            Primary     = $m.Primary
            Scale       = [math]::Max($dpiScale, $pelsScale)
            RefreshRate = $m.RefreshRate
        }
    }
}

function Initialize-KitForms {
    [CmdletBinding()]
    param()
    if ($script:KitFormsReady) { return }
    $null = Enable-KitDpiAwareness
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    [Windows.Forms.Application]::EnableVisualStyles()
    try { [Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false) } catch [InvalidOperationException] { Write-Verbose 'Text rendering already set.' }
    $script:KitFormsReady = $true
}

function Confirm-KitAction {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Text)
    Initialize-KitForms
    $answer = [Windows.Forms.MessageBox]::Show($Text, (Get-KitText 'Ui.Confirm.Title'), 'YesNo', 'Question', 'Button2')
    $answer -eq [Windows.Forms.DialogResult]::Yes
}

# --- small layout helpers for pages (a page is a top-down FlowLayoutPanel) ---------------------------------

function Get-PanelInnerWidth($Panel) { [math]::Max(300, $Panel.ClientSize.Width - 30) }

function Add-KitUiText {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Panel, [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text, [switch] $Bold, [string] $Color)
    $label = New-Object Windows.Forms.Label
    $label.AutoSize = $true
    $label.MaximumSize = New-Object Drawing.Size ((Get-PanelInnerWidth $Panel), 0)
    $label.Text = $Text
    $label.Margin = New-Object Windows.Forms.Padding (3, 3, 3, 6)
    if ($Bold) { $label.Font = New-Object Drawing.Font ($label.Font, [Drawing.FontStyle]::Bold) }
    if ($Color) { $label.ForeColor = [Drawing.Color]::FromName($Color) }
    $Panel.Controls.Add($label)
    $label
}

function Add-KitUiButton {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Panel, [Parameter(Mandatory)] [string] $Text, [Parameter(Mandatory)] [scriptblock] $OnClick, [object] $Tag)
    $button = New-Object Windows.Forms.Button
    $button.AutoSize = $true
    $button.Text = $Text
    $button.Tag = $Tag
    $button.add_Click($OnClick)
    $Panel.Controls.Add($button)
    $button
}

function Add-KitUiCheck {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Panel, [Parameter(Mandatory)] [string] $Text, [bool] $Checked, [scriptblock] $OnChange, [object] $Tag)
    $box = New-Object Windows.Forms.CheckBox
    $box.AutoSize = $true
    $box.MaximumSize = New-Object Drawing.Size ((Get-PanelInnerWidth $Panel), 0)
    $box.Text = $Text
    $box.Checked = $Checked
    $box.Tag = $Tag
    if ($OnChange) { $box.add_CheckedChanged($OnChange) }
    $Panel.Controls.Add($box)
    $box
}

# Text box with a browse button. $OnChange receives the new text via $this.Text.
function Add-KitUiPathBox {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Panel, [Parameter(Mandatory)] [string] $Label, [AllowEmptyString()] [string] $Value,
          [scriptblock] $OnChange, [switch] $File, [object] $Tag)
    $null = Add-KitUiText -Panel $Panel -Text $Label
    $row = New-Object Windows.Forms.FlowLayoutPanel
    $row.AutoSize = $true
    $row.WrapContents = $false
    $box = New-Object Windows.Forms.TextBox
    $box.Width = [math]::Min(560, (Get-PanelInnerWidth $Panel) - 120)
    $box.Text = $Value
    $box.Tag = $Tag
    if ($OnChange) { $box.add_TextChanged($OnChange) }
    $browse = New-Object Windows.Forms.Button
    $browse.Text = '...'
    $browse.Width = 40
    $browse.Tag = @{ Box = $box; File = [bool]$File }
    $browse.add_Click({
        $t = $this.Tag
        if ($t.File) {
            $dialog = New-Object Windows.Forms.OpenFileDialog
            if ($dialog.ShowDialog() -eq 'OK') { $t.Box.Text = $dialog.FileName }
        } else {
            $dialog = New-Object Windows.Forms.FolderBrowserDialog
            $dialog.SelectedPath = $t.Box.Text
            if ($dialog.ShowDialog() -eq 'OK') { $t.Box.Text = $dialog.SelectedPath }
        }
        $dialog.Dispose()
    })
    $row.Controls.Add($box)
    $row.Controls.Add($browse)
    $Panel.Controls.Add($row)
    $box
}

# --- credits ------------------------------------------------------------------------------------------------

# Markdown -> readable plain text: headings and table rows kept, emphasis and <link> brackets removed.
function ConvertFrom-KitCreditsMarkdown {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Text)
    $out = foreach ($line in $Text -split "`r?`n") {
        if ($line -match '^\|\s*-') { continue }             # table separator
        if ($line -match '^\|\s*\|\s*\|\s*$') { continue }  # empty table header
        $l = $line -replace '\*\*', '' -replace '(?<![\w])_(.+?)_(?![\w])', '$1' -replace '<(https?://[^>\s]+)>', '$1'
        if ($l -match '^\|(.*)\|\s*$') {
            $cells = @($Matches[1] -split '\|' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            $l = '  - ' + ($cells -join '  |  ')
        }
        $l = $l -replace '^#+\s*', '' -replace '^>\s*', ''
        $l
    }
    ($out -join "`r`n").Trim()
}

function Add-KitCreditsView {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Panel, [Parameter(Mandatory)] [string] $Path)
    $box = New-Object Windows.Forms.RichTextBox
    $box.ReadOnly = $true
    $box.DetectUrls = $true
    $box.BorderStyle = 'None'
    $box.BackColor = [Drawing.SystemColors]::Window
    $box.Width = Get-PanelInnerWidth $Panel
    $box.Height = [math]::Max(300, $Panel.ClientSize.Height - 60)
    $box.Text = if (Test-Path -LiteralPath $Path) { ConvertFrom-KitCreditsMarkdown ([IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)) } else { $Path }
    # Only web links are opened (through explorer.exe, never elevated), nothing else from the file is executed.
    $box.add_LinkClicked({ $null = Open-KitWebLink -Url $_.LinkText })
    $Panel.Controls.Add($box)
    $box
}

# --- measuring window ---------------------------------------------------------------------------------------

# Borderless, labeled, colored window. Mouse: drag to move, drag the right/bottom edge to resize.
# Keys: arrows move 1 px, Shift+arrows resize 1 px, Ctrl = 10 px, Enter = take, Esc = cancel.
# Returns the rectangle (X, Y, Width, Height) or $null when cancelled.
function Show-KitMeasureWindow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $Rect,
        [Parameter(Mandatory)] [string] $Title,
        [string] $Color = 'SteelBlue',
        [object[]] $Monitors = @()
    )
    Initialize-KitForms
    $form = New-Object Windows.Forms.Form
    $form.FormBorderStyle = 'None'
    $form.StartPosition = 'Manual'
    $form.ShowInTaskbar = $false
    $form.TopMost = $true
    $form.KeyPreview = $true
    $form.MinimumSize = New-Object Drawing.Size (40, 20)
    $form.BackColor = [Drawing.Color]::FromName($Color)
    $form.Bounds = New-Object Drawing.Rectangle ([int]$Rect.X, [int]$Rect.Y, [int]$Rect.Width, [int]$Rect.Height)
    $form.Tag = @{ Title = $Title; Drag = $null; Monitors = $Monitors }

    $label = New-Object Windows.Forms.Label
    $label.Dock = 'Fill'
    $label.TextAlign = 'MiddleCenter'
    $label.ForeColor = [Drawing.Color]::White
    $label.Font = New-Object Drawing.Font ('Segoe UI', 12, [Drawing.FontStyle]::Bold)

    $buttons = New-Object Windows.Forms.FlowLayoutPanel
    $buttons.Dock = 'Top'
    $buttons.AutoSize = $true
    $buttons.BackColor = [Drawing.Color]::Transparent
    $full = New-Object Windows.Forms.Button
    $full.Text = Get-KitText 'Ui.Measure.FullMonitor'
    $full.AutoSize = $true
    $full.BackColor = [Drawing.SystemColors]::Control
    $ok = New-Object Windows.Forms.Button
    $ok.Text = Get-KitText 'Ui.Measure.Take'
    $ok.AutoSize = $true
    $ok.BackColor = [Drawing.SystemColors]::Control
    $ok.DialogResult = 'OK'
    $cancel = New-Object Windows.Forms.Button
    $cancel.Text = Get-KitText 'Ui.Measure.Cancel'
    $cancel.AutoSize = $true
    $cancel.BackColor = [Drawing.SystemColors]::Control
    $cancel.DialogResult = 'Cancel'
    $buttons.Controls.AddRange(@($full, $ok, $cancel))
    $form.Controls.Add($label)
    $form.Controls.Add($buttons)
    $form.AcceptButton = $ok
    $form.CancelButton = $cancel

    $refresh = {
        $f = $this.FindForm(); if (-not $f) { $f = $this }
        $b = $f.Bounds
        $f.Controls[0].Text = '{0}{1}{2}, {3}   {4} x {5}{1}{6}' -f $f.Tag.Title, [Environment]::NewLine, $b.X, $b.Y, $b.Width, $b.Height, (Get-KitText 'Ui.Measure.Help')
    }
    $form.add_Move($refresh)
    $form.add_Resize($refresh)
    $form.add_Shown($refresh)

    $full.add_Click({
        $f = $this.FindForm()
        $c = New-Object Drawing.Point (($f.Left + $f.Width / 2), ($f.Top + $f.Height / 2))
        $m = @($f.Tag.Monitors | Where-Object { $c.X -ge $_.X -and $c.X -lt $_.X + $_.Width -and $c.Y -ge $_.Y -and $c.Y -lt $_.Y + $_.Height }) | Select-Object -First 1
        if ($m) { $f.Bounds = New-Object Drawing.Rectangle ($m.X, $m.Y, $m.Width, $m.Height) }
        else { $f.Bounds = [Windows.Forms.Screen]::FromPoint($c).Bounds }
    })

    $down = {
        $f = $this.FindForm(); if (-not $f) { $f = $this }
        $p = [Windows.Forms.Control]::MousePosition
        $local = $f.PointToClient($p)
        $resize = $local.X -ge $f.ClientSize.Width - 24 -or $local.Y -ge $f.ClientSize.Height - 24
        $f.Tag.Drag = @{ Start = $p; Bounds = $f.Bounds; Resize = $resize }
    }
    $move = {
        $f = $this.FindForm(); if (-not $f) { $f = $this }
        $d = $f.Tag.Drag
        if (-not $d -or $_.Button -ne 'Left') { return }
        $p = [Windows.Forms.Control]::MousePosition
        $dx = $p.X - $d.Start.X; $dy = $p.Y - $d.Start.Y
        $b = $d.Bounds
        if ($d.Resize) { $f.Size = New-Object Drawing.Size ([math]::Max(40, $b.Width + $dx), [math]::Max(20, $b.Height + $dy)) }
        else { $f.Location = New-Object Drawing.Point ($b.X + $dx, $b.Y + $dy) }
    }
    $up = { $f = $this.FindForm(); if (-not $f) { $f = $this }; $f.Tag.Drag = $null }
    foreach ($c in $form, $label) { $c.add_MouseDown($down); $c.add_MouseMove($move); $c.add_MouseUp($up) }

    # Arrow keys would otherwise move the focus between the buttons.
    foreach ($c in $form, $full, $ok, $cancel) { $c.add_PreviewKeyDown({ if ($_.KeyCode -in 'Left', 'Right', 'Up', 'Down') { $_.IsInputKey = $true } }) }
    $form.add_KeyDown({
        $step = if ($_.Control) { 10 } else { 1 }
        $dx = 0; $dy = 0
        switch ($_.KeyCode) { 'Left' { $dx = -$step } 'Right' { $dx = $step } 'Up' { $dy = -$step } 'Down' { $dy = $step } default { return } }
        $b = $this.Bounds
        if ($_.Shift) { $this.Size = New-Object Drawing.Size ([math]::Max(40, $b.Width + $dx), [math]::Max(20, $b.Height + $dy)) }
        else { $this.Location = New-Object Drawing.Point ($b.X + $dx, $b.Y + $dy) }
        $_.Handled = $true
    })

    try {
        if ($form.ShowDialog() -ne 'OK') { return $null }
        $b = $form.Bounds
        [pscustomobject]@{ X = $b.X; Y = $b.Y; Width = $b.Width; Height = $b.Height }
    } finally { $form.Dispose() }
}

# --- wizard frame -------------------------------------------------------------------------------------------

# Page = @{ TitleKey = 'i18n key'; Build = { param($Wizard, $Panel) ... } }. Pages are built when shown and
# rebuilt after a language switch, so page state belongs in $Wizard.Values, not in controls.
# Status per page: None, WhatIf, NeedsUser, Failed, Done. Only Done (verified) is green.
function New-KitWizard {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $TitleKey,
        [Parameter(Mandatory)] [hashtable[]] $Pages,
        [bool] $DryRun = $true,
        [string[]] $Cultures = @('de-DE', 'en-US'),
        [int] $StartPage = 0
    )
    Initialize-KitForms
    $form = New-Object Windows.Forms.Form
    $form.Size = New-Object Drawing.Size (1180, 800)
    $form.MinimumSize = New-Object Drawing.Size (900, 600)
    $form.StartPosition = 'CenterScreen'
    $form.Font = New-Object Drawing.Font ('Segoe UI', 9)

    $content = New-Object Windows.Forms.Panel
    $content.Dock = 'Fill'
    $content.Padding = New-Object Windows.Forms.Padding (12)

    $list = New-Object Windows.Forms.ListBox
    $list.Dock = 'Left'
    $list.Width = 260
    $list.DrawMode = 'OwnerDrawFixed'
    $list.ItemHeight = 28
    $list.IntegralHeight = $false

    $nav = New-Object Windows.Forms.FlowLayoutPanel
    $nav.Dock = 'Bottom'
    $nav.Height = 40
    $nav.FlowDirection = 'RightToLeft'
    $next = New-Object Windows.Forms.Button
    $next.AutoSize = $true
    $back = New-Object Windows.Forms.Button
    $back.AutoSize = $true
    $nav.Controls.AddRange(@($next, $back))

    $log = New-Object Windows.Forms.TextBox
    $log.Dock = 'Bottom'
    $log.Height = 170
    $log.Multiline = $true
    $log.ReadOnly = $true
    $log.ScrollBars = 'Vertical'
    $log.Font = New-Object Drawing.Font ('Consolas', 9)

    $top = New-Object Windows.Forms.FlowLayoutPanel
    $top.Dock = 'Top'
    $top.Height = 40
    $top.Padding = New-Object Windows.Forms.Padding (6)
    $title = New-Object Windows.Forms.Label
    $title.AutoSize = $true
    $title.Font = New-Object Drawing.Font ('Segoe UI', 12, [Drawing.FontStyle]::Bold)
    $title.Margin = New-Object Windows.Forms.Padding (3, 3, 30, 3)
    $language = New-Object Windows.Forms.ComboBox
    $language.DropDownStyle = 'DropDownList'
    $language.Width = 90
    foreach ($c in $Cultures) { $null = $language.Items.Add($c) }
    $dry = New-Object Windows.Forms.CheckBox
    $dry.AutoSize = $true
    $dry.Checked = $DryRun
    $dry.Margin = New-Object Windows.Forms.Padding (20, 5, 3, 3)
    $top.Controls.AddRange(@($title, $language, $dry))

    # Docking runs from the last added control to the first: top, log, nav, list, then content fills the rest.
    $form.Controls.AddRange(@($content, $list, $nav, $log, $top))

    $wizard = [pscustomobject]@{
        PSTypeName = 'RetroCabinetKit.Wizard'
        Form = $form; Content = $content; List = $list; Log = $log; Back = $back; Next = $next
        Title = $title; Language = $language; DryRunBox = $dry; TitleKey = $TitleKey
        Pages = $Pages; Status = @{}; Values = @{}; Index = -1
    }
    foreach ($c in $form, $list, $back, $next, $language, $dry) { $c.Tag = $wizard }

    $list.add_DrawItem({
        if ($_.Index -lt 0) { return }
        $w = $this.Tag
        $status = if ($w.Status.ContainsKey($_.Index)) { $w.Status[$_.Index] } else { 'None' }
        $mark, $color = switch ($status) {
            'Done'      { [char]0x2714, [Drawing.Color]::ForestGreen }
            'Failed'    { [char]0x2716, [Drawing.Color]::Firebrick }
            'NeedsUser' { '!', [Drawing.Color]::DarkOrange }
            'WhatIf'    { '~', [Drawing.Color]::SteelBlue }
            default     { [char]0x2022, [Drawing.Color]::Gray }
        }
        $_.DrawBackground()
        $selected = ($_.State -band [Windows.Forms.DrawItemState]::Selected) -ne 0
        $textColor = if ($selected) { [Drawing.SystemColors]::HighlightText } else { [Drawing.SystemColors]::ControlText }
        $markBrush = New-Object Drawing.SolidBrush ($(if ($selected) { $textColor } else { $color }))
        $textBrush = New-Object Drawing.SolidBrush $textColor
        $y = $_.Bounds.Y + 5
        $_.Graphics.DrawString([string]$mark, $this.Font, $markBrush, ($_.Bounds.X + 6), $y)
        $_.Graphics.DrawString([string]$this.Items[$_.Index], $this.Font, $textBrush, ($_.Bounds.X + 26), $y)
        $markBrush.Dispose(); $textBrush.Dispose()
    })
    $list.add_SelectedIndexChanged({ $w = $this.Tag; if ($this.SelectedIndex -ge 0 -and $this.SelectedIndex -ne $w.Index) { Show-KitWizardPage -Wizard $w -Index $this.SelectedIndex } })
    $back.add_Click({ $w = $this.Tag; if ($w.Index -gt 0) { Show-KitWizardPage -Wizard $w -Index ($w.Index - 1) } })
    $next.add_Click({ $w = $this.Tag; if ($w.Index -lt $w.Pages.Count - 1) { Show-KitWizardPage -Wizard $w -Index ($w.Index + 1) } })
    $language.add_SelectedIndexChanged({
        $w = $this.Tag
        if ([string]$this.SelectedItem -eq (Get-KitCulture)) { return }
        Set-KitCulture -Culture ([string]$this.SelectedItem)
        Update-KitWizardText -Wizard $w
        Show-KitWizardPage -Wizard $w -Index $w.Index -Force
    })

    $current = Get-KitCulture
    $language.SelectedItem = if ($Cultures -contains $current) { $current } else { 'en-US' }
    Update-KitWizardText -Wizard $wizard
    if ($StartPage -ge 0) { Show-KitWizardPage -Wizard $wizard -Index $StartPage } # -1: caller shows a page later
    $wizard
}

function Test-KitWizardDryRun {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Wizard)
    $Wizard.DryRunBox.Checked
}

function Update-KitWizardText {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Wizard)
    $Wizard.Form.Text = Get-KitText $Wizard.TitleKey
    $Wizard.Title.Text = Get-KitText $Wizard.TitleKey
    $Wizard.DryRunBox.Text = Get-KitText 'Ui.DryRun'
    $Wizard.Back.Text = Get-KitText 'Ui.Back'
    $Wizard.Next.Text = Get-KitText 'Ui.Next'
    $selected = $Wizard.Index
    $Wizard.List.BeginUpdate()
    $Wizard.List.Items.Clear()
    for ($i = 0; $i -lt $Wizard.Pages.Count; $i++) { $null = $Wizard.List.Items.Add((Get-KitText $Wizard.Pages[$i].TitleKey)) }
    $Wizard.List.EndUpdate()
    if ($selected -ge 0) { $Wizard.List.SelectedIndex = $selected }
}

function Show-KitWizardPage {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Wizard, [Parameter(Mandatory)] [int] $Index, [switch] $Force)
    if ($Index -eq $Wizard.Index -and -not $Force) { return }
    $Wizard.Index = $Index
    foreach ($old in @($Wizard.Content.Controls)) { $Wizard.Content.Controls.Remove($old); $old.Dispose() }
    $panel = New-Object Windows.Forms.FlowLayoutPanel
    $panel.Dock = 'Fill'
    $panel.FlowDirection = 'TopDown'
    $panel.WrapContents = $false
    $panel.AutoScroll = $true
    $Wizard.Content.Controls.Add($panel)
    $page = $Wizard.Pages[$Index]
    $heading = Add-KitUiText -Panel $panel -Text (Get-KitText $page.TitleKey) -Bold
    $heading.Font = New-Object Drawing.Font ('Segoe UI', 11, [Drawing.FontStyle]::Bold)
    try { $null = & $page.Build $Wizard $panel }
    catch { Write-KitWizardLog -Wizard $Wizard -Text $_.Exception.Message -Level Error }
    if ($Wizard.List.SelectedIndex -ne $Index) { $Wizard.List.SelectedIndex = $Index }
    $Wizard.Back.Enabled = $Index -gt 0
    $Wizard.Next.Enabled = $Index -lt $Wizard.Pages.Count - 1
}

function Set-KitWizardStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $Wizard,
        [Parameter(Mandatory)] [int] $Index,
        [Parameter(Mandatory)] [ValidateSet('None', 'WhatIf', 'NeedsUser', 'Failed', 'Done')] [string] $Status
    )
    $Wizard.Status[$Index] = $Status
    $Wizard.List.Invalidate()
}

# One summary line per step result (changes, backups, duration) plus the backup paths, from the structured result.
function Write-KitWizardStepSummary {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Wizard, [AllowEmptyCollection()] [object[]] $Result = @())
    foreach ($r in $Result) {
        if (-not $r -or -not $r.PSObject.Properties['Duration']) { continue } # placeholder rows (an exception in the wizard)
        Write-KitWizardLog -Wizard $Wizard -Text (Get-KitText 'Ui.StepSummary' -f $r.Name, @($r.Changes).Count, @($r.Backups).Count, $r.Duration.TotalSeconds)
        foreach ($b in @($r.Backups)) { Write-KitWizardLog -Wizard $Wizard -Text (Get-KitText 'Ui.StepBackup' -f $b) }
    }
}

function Write-KitWizardLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [psobject] $Wizard,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text,
        [ValidateSet('Info', 'Warn', 'Error')] [string] $Level = 'Info'
    )
    $prefix = @{ Info = ''; Warn = '[!] '; Error = '[X] ' }[$Level]
    $Wizard.Log.AppendText($prefix + $Text + [Environment]::NewLine)
}
