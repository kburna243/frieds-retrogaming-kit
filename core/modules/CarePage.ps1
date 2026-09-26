# Maintenance page for the wizards: doctor, backups and support bundle in one place. The page is plain data
# (New-KitCarePage); the wizard only passes what differs per suite:
#   -Checks       { ... }  returns the doctor checks (e.g. Get-KitSystemCheck plus the suite's checks)
#   -BackupRoots  { ... }  returns the folders to look for backups in
#   -Guard        { ... }  throws when programs that hold the files are running (called before a restore)
#   -StatePath / -LogDir   what the support bundle collects
# Handlers find the wizard through the button's Tag and the page's settings through $wizard.Pages[$wizard.Index].
# The doctor and the support bundle only read (they also run in the dry run); a restore follows the dry-run
# switch and asks first; deleting a backup always asks.

function New-KitCarePage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [scriptblock] $Checks,
        [Parameter(Mandatory)] [scriptblock] $BackupRoots,
        [scriptblock] $Guard = {},
        [string[]] $StatePath = @(),
        [string] $LogDir
    )
    @{
        TitleKey = 'Ui.Care.Page'
        Care     = @{ Checks = $Checks; BackupRoots = $BackupRoots; Guard = $Guard; StatePath = $StatePath; LogDir = $LogDir }
        Build    = { param($w, $p) Add-CarePageControls -Wizard $w -Panel $p }
    }
}

function Get-CareSettings($Wizard) { $Wizard.Pages[$Wizard.Index].Care }

# The selected backup row or a warning in the log.
function Get-CareSelection($Wizard) {
    $list = $Wizard.Values['CareList']
    $rows = @($Wizard.Values['CareRows'])
    if (-not $list -or $list.SelectedIndex -lt 0 -or $list.SelectedIndex -ge $rows.Count) {
        Write-KitWizardLog -Wizard $Wizard -Text (Get-KitText 'Ui.Care.SelectFirst') -Level Warn
        return $null
    }
    $rows[$list.SelectedIndex]
}

# Runs the doctor, writes the report into the log box, returns the rows.
function Invoke-KitCareDoctor {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Wizard)
    $cfg = Get-CareSettings $Wizard
    $rows = @(Invoke-KitDoctor -Check @(& $cfg.Checks))
    foreach ($line in Format-KitDoctorReport -Result $rows) {
        $level = if ($line -match '^\[ERROR\]') { 'Error' } elseif ($line -match '^\[WARN\]') { 'Warn' } else { 'Info' }
        Write-KitWizardLog -Wizard $Wizard -Text $line -Level $level
    }
    $rows
}

# Fills the backup list; returns the rows.
function Update-KitCareBackupList {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Wizard)
    $cfg = Get-CareSettings $Wizard
    $roots = @(& $cfg.BackupRoots | Where-Object { $_ })
    $rows = @(Get-KitBackup -Path $roots)
    $Wizard.Values['CareRows'] = $rows
    $list = $Wizard.Values['CareList']
    if ($list) {
        $list.BeginUpdate()
        $list.Items.Clear()
        foreach ($b in $rows) {
            $detail = if ($b.Kind -eq 'Zip') { '{0} - {1}' -f (Get-KitText 'Recovery.ZipDetail' -f $b.Files, $b.Registry), $b.Path } else { $b.Path }
            $null = $list.Items.Add((Get-KitText 'Recovery.Row' -f $b.Created, $b.Kind, $b.Purpose, $detail))
        }
        $list.EndUpdate()
    }
    if (-not $rows.Count) { Write-KitWizardLog -Wizard $Wizard -Text (Get-KitText 'Recovery.None' -f ($roots -join '; ')) }
    $rows
}

# Restores the selected file copy. Zip backups are restored from the command line (they need the allowed roots).
function Invoke-KitCareRestore {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Wizard, [scriptblock] $Confirm = { param($text) Confirm-KitAction -Text $text })
    $b = Get-CareSelection $Wizard
    if (-not $b) { return }
    if ($b.Kind -ne 'File') { Write-KitWizardLog -Wizard $Wizard -Text (Get-KitText 'Ui.Care.ZipOnCommandLine') -Level Warn; return }
    $dry = Test-KitWizardDryRun -Wizard $Wizard
    if (-not $dry -and -not (& $Confirm (Get-KitText 'Ui.Care.ConfirmRestore' -f $b.Original, $b.Path))) { return }
    try {
        & (Get-CareSettings $Wizard).Guard
        $r = Restore-KitFileBackup -Path $b.Path -WhatIf:$dry -Confirm:$false
        if ($r.Action -eq 'WhatIf') { Write-KitWizardLog -Wizard $Wizard -Text (Get-KitText 'Ui.Care.RestorePlan' -f $r.Target, $r.Source) }
        else { Write-KitWizardLog -Wizard $Wizard -Text (Get-KitText 'Recovery.Restored' -f $r.Target, $r.Source) }
        $r
    } catch { Write-KitWizardLog -Wizard $Wizard -Text $_.Exception.Message -Level Error }
}

function Invoke-KitCareCheck {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Wizard)
    $b = Get-CareSelection $Wizard
    if (-not $b) { return }
    try {
        $r = Test-KitBackup -Path $b.Path
        if ($r.Ok) { Write-KitWizardLog -Wizard $Wizard -Text (Get-KitText 'Recovery.CheckOk' -f $r.Path) }
        else {
            Write-KitWizardLog -Wizard $Wizard -Text (Get-KitText 'Recovery.CheckBad' -f $r.Path) -Level Error
            foreach ($p in $r.Problems) { Write-KitWizardLog -Wizard $Wizard -Text "  $p" -Level Error }
        }
        $r
    } catch { Write-KitWizardLog -Wizard $Wizard -Text $_.Exception.Message -Level Error }
}

function Invoke-KitCareExport {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Wizard, [string] $Destination)
    $b = Get-CareSelection $Wizard
    if (-not $b) { return }
    if (-not $Destination) {
        $dialog = New-Object Windows.Forms.FolderBrowserDialog
        try { if ($dialog.ShowDialog() -ne 'OK') { return }; $Destination = $dialog.SelectedPath } finally { $dialog.Dispose() }
    }
    try {
        $item = Export-KitBackup -Path $b.Path -Destination $Destination
        Write-KitWizardLog -Wizard $Wizard -Text (Get-KitText 'Recovery.Exported' -f $item.FullName)
        $item
    } catch { Write-KitWizardLog -Wizard $Wizard -Text $_.Exception.Message -Level Error }
}

function Invoke-KitCareRemove {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Wizard, [scriptblock] $Confirm = { param($text) Confirm-KitAction -Text $text })
    $b = Get-CareSelection $Wizard
    if (-not $b) { return }
    if (-not (& $Confirm (Get-KitText 'Ui.Care.ConfirmDelete' -f $b.Path))) { return }
    try {
        Remove-KitBackup -Path $b.Path -Confirm:$false
        Write-KitWizardLog -Wizard $Wizard -Text (Get-KitText 'Recovery.Deleted' -f $b.Path)
        $null = Update-KitCareBackupList -Wizard $Wizard
    } catch { Write-KitWizardLog -Wizard $Wizard -Text $_.Exception.Message -Level Error }
}

# Runs the doctor and writes the anonymized bundle into the log folder; returns the zip.
function Invoke-KitCareSupportBundle {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Wizard)
    $cfg = Get-CareSettings $Wizard
    try {
        $rows = @(Invoke-KitDoctor -Check @(& $cfg.Checks))
        $dir = if ($cfg.LogDir) { $cfg.LogDir } else { Join-Path $script:KitRoot 'logs' }
        $zip = Export-KitSupportBundle -Destination (Join-Path $dir ('support-bundle_{0:yyyyMMdd-HHmmss}.zip' -f (Get-Date))) -DoctorResult $rows -StatePath $cfg.StatePath -LogDir $dir
        Write-KitWizardLog -Wizard $Wizard -Text (Get-KitText 'Support.Created' -f $zip.FullName)
        Write-KitWizardLog -Wizard $Wizard -Text (Get-KitText 'Support.Hint')
        $zip
    } catch { Write-KitWizardLog -Wizard $Wizard -Text $_.Exception.Message -Level Error }
}

function Add-CarePageControls($Wizard, $Panel) {
    $null = Add-KitUiText $Panel (Get-KitText 'Ui.Care.Intro')

    $null = Add-KitUiText $Panel (Get-KitText 'Ui.Care.DoctorHead') -Bold
    $null = Add-KitUiText $Panel (Get-KitText 'Ui.Care.DoctorDesc')
    $null = Add-KitUiButton $Panel (Get-KitText 'Ui.Care.RunDoctor') -Tag $Wizard { $null = Invoke-KitCareDoctor -Wizard $this.Tag }

    $null = Add-KitUiText $Panel (Get-KitText 'Ui.Care.BackupsHead') -Bold
    $null = Add-KitUiText $Panel (Get-KitText 'Ui.Care.BackupsDesc')
    $list = New-Object Windows.Forms.ListBox
    $list.Width = Get-PanelInnerWidth $Panel
    $list.Height = 150
    $list.HorizontalScrollbar = $true
    $list.Font = New-Object Drawing.Font ('Consolas', 9)
    $Panel.Controls.Add($list)
    $Wizard.Values['CareList'] = $list
    $Wizard.Values['CareRows'] = @()
    $buttons = New-Object Windows.Forms.FlowLayoutPanel
    $buttons.AutoSize = $true
    $buttons.WrapContents = $true
    $buttons.MaximumSize = New-Object Drawing.Size ((Get-PanelInnerWidth $Panel), 0)
    $Panel.Controls.Add($buttons)
    $null = Add-KitUiButton $buttons (Get-KitText 'Ui.Care.ListBackups') -Tag $Wizard { $null = Update-KitCareBackupList -Wizard $this.Tag }
    $null = Add-KitUiButton $buttons (Get-KitText 'Ui.Care.Check') -Tag $Wizard { $null = Invoke-KitCareCheck -Wizard $this.Tag }
    $null = Add-KitUiButton $buttons (Get-KitText 'Ui.Care.Restore') -Tag $Wizard { $null = Invoke-KitCareRestore -Wizard $this.Tag }
    $null = Add-KitUiButton $buttons (Get-KitText 'Ui.Care.Export') -Tag $Wizard { $null = Invoke-KitCareExport -Wizard $this.Tag }
    $null = Add-KitUiButton $buttons (Get-KitText 'Ui.Care.Delete') -Tag $Wizard { $null = Invoke-KitCareRemove -Wizard $this.Tag }
    $null = Add-KitUiText $Panel (Get-KitText 'Ui.Care.ZipOnCommandLine') -Color 'DimGray'

    $null = Add-KitUiText $Panel (Get-KitText 'Ui.Care.SupportHead') -Bold
    $null = Add-KitUiText $Panel (Get-KitText 'Ui.Care.SupportDesc')
    $null = Add-KitUiButton $Panel (Get-KitText 'Ui.Care.CreateBundle') -Tag $Wizard { $null = Invoke-KitCareSupportBundle -Wizard $this.Tag }
}
