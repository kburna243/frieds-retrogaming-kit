<#
.SYNOPSIS
    Kit tools: doctor (health check), backups (recovery) and support bundle.
.DESCRIPTION
    -Doctor          read-only health check of system, pinball and lightgun; exit code 1 when an error is found
    -Backups         lists the kit's backups (zip backups and <file>.bak_* copies) of both suites, newest first
    -CheckBackup     checks one backup against its checksums (zip) or its original (file copy)
    -RestoreBackup   puts one backup back. A file copy replaces its original (the current file is saved first
                     as <file>.bak_recovery_<time>); a zip backup needs -AllowedRoot and restores files only.
                     Supports -WhatIf. Guarded programs (RetroBat, emulators, Popper, VPX, ...) must be closed.
    -ExportBackup    copies one backup to -Destination and records its SHA-256 in SHA256SUMS.txt there
    -RemoveBackup    deletes one backup (asks first)
    -SupportBundle   anonymized zip with doctor report, environment, step states and the newest logs
    Start-Kit.cmd forwards -Doctor, -Backups and -SupportBundle, e.g. "Start-Kit.cmd -Doctor".
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File core\Start-KitTools.ps1 -RestoreBackup "<file>.bak_lightgun_20260101-120000-000" -WhatIf
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Doctor')]
param(
    [Parameter(ParameterSetName = 'Doctor')] [switch] $Doctor,
    [Parameter(ParameterSetName = 'Backups', Mandatory)] [switch] $Backups,
    [Parameter(ParameterSetName = 'Backups')] [string[]] $BackupRoot,
    [Parameter(ParameterSetName = 'Check', Mandatory)] [string] $CheckBackup,
    [Parameter(ParameterSetName = 'Restore', Mandatory)] [string] $RestoreBackup,
    [Parameter(ParameterSetName = 'Restore')] [string[]] $AllowedRoot,
    [Parameter(ParameterSetName = 'Export', Mandatory)] [string] $ExportBackup,
    [Parameter(ParameterSetName = 'Export', Mandatory)] [Parameter(ParameterSetName = 'Support')] [string] $Destination,
    [Parameter(ParameterSetName = 'Remove', Mandatory)] [string] $RemoveBackup,
    [Parameter(ParameterSetName = 'Support', Mandatory)] [switch] $SupportBundle,
    [Parameter(ParameterSetName = 'ExportProfile', Mandatory)] [switch] $ExportProfile,
    [Parameter(ParameterSetName = 'ExportProfile', Mandatory)] [ValidateSet('Pinball', 'Lightgun')] [string] $Suite,
    [Parameter(ParameterSetName = 'ExportProfile')] [string] $ProfileDestination,
    [Parameter(ParameterSetName = 'ImportProfile', Mandatory)] [string] $ImportProfile,
    [Parameter(ParameterSetName = 'ImportProfile')] [hashtable] $RootMap,
    [Parameter(ParameterSetName = 'ImportProfile')] [switch] $AutoInstall,
    [string] $Culture
)

$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $PSScriptRoot 'RetroCabinetKit.Core.psd1')
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1')
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1')
if ($Culture) { Set-KitCulture -Culture $Culture }

$pinballState = Get-PinballDefaultStatePath
$lightgunState = Get-LightgunDefaultStatePath
$logDir = Join-Path $kitRoot 'logs'

function Invoke-AllChecks {
    Invoke-KitDoctor -Check @(@(Get-KitSystemCheck) + @(Get-PinballDoctorCheck -StatePath $pinballState) + @(Get-LightgunDoctorCheck -StatePath $lightgunState))
}

function Write-Report([object[]] $Result) {
    $color = @{ '[OK]' = 'Green'; '[INFO]' = 'Gray'; '[WARN]' = 'Yellow'; '[ERROR]' = 'Red' }
    foreach ($line in Format-KitDoctorReport -Result $Result) {
        $tag = if ($line -match '^(\[[A-Z]+\])') { $Matches[1] } else { '' }
        if ($tag -and $color.ContainsKey($tag)) { Write-Host $line -ForegroundColor $color[$tag] } else { Write-Host $line }
    }
}

# Folders that hold the kit's backups: each suite knows its own.
function Get-BackupRoots {
    @(@(Get-PinballBackupRoot -StatePath $pinballState) + @(Get-LightgunBackupRoot -StatePath $lightgunState) | Sort-Object -Unique)
}

switch ($PSCmdlet.ParameterSetName) {
    'Doctor' {
        $result = @(Invoke-AllChecks)
        Write-Report $result
        if ((Get-KitDoctorSummary -Result $result).Error) { exit 1 }
        exit 0
    }
    'Backups' {
        $roots = @(if ($BackupRoot) { $BackupRoot } else { Get-BackupRoots })
        $list = @(Get-KitBackup -Path $roots)
        Write-Host (Get-KitText 'Recovery.Title')
        if (-not $list.Count) { Write-Host (Get-KitText 'Recovery.None' -f ($roots -join '; ')); exit 0 }
        foreach ($b in $list) {
            $detail = if ($b.Kind -eq 'Zip') { '{0} - {1}' -f (Get-KitText 'Recovery.ZipDetail' -f $b.Files, $b.Registry), $b.Path } else { $b.Path }
            Write-Host (Get-KitText 'Recovery.Row' -f $b.Created, $b.Kind, $b.Purpose, $detail)
        }
        exit 0
    }
    'Check' {
        $r = Test-KitBackup -Path $CheckBackup
        if ($r.Ok) { Write-Host (Get-KitText 'Recovery.CheckOk' -f $r.Path) -ForegroundColor Green; exit 0 }
        Write-Host (Get-KitText 'Recovery.CheckBad' -f $r.Path) -ForegroundColor Red
        $r.Problems | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
        exit 1
    }
    'Restore' {
        Start-KitLog -Path (Join-Path $logDir ('tools-restore_{0:yyyyMMdd-HHmmss}.log' -f (Get-Date)))
        try {
            Assert-PinballProcessesClosed
            Assert-LightgunProcessesClosed
            if (ConvertFrom-KitFileBackupName -Path $RestoreBackup) {
                Restore-KitFileBackup -Path $RestoreBackup -WhatIf:$WhatIfPreference -Confirm:$false
            } else {
                if (-not $AllowedRoot) { throw (Get-KitText 'Recovery.ZipRestoreRoots') }
                $check = Test-KitBackup -Path $RestoreBackup
                if (-not $check.Ok) { throw (Get-KitText 'Recovery.CheckBad' -f $check.Path) }
                Restore-KitBackup -Path $RestoreBackup -AllowedRoots $AllowedRoot -SkipRegistry -WhatIf:$WhatIfPreference -Confirm:$false
            }
        } finally { Stop-KitLog }
    }
    'Export' { Export-KitBackup -Path $ExportBackup -Destination $Destination }
    'Remove' { Remove-KitBackup -Path $RemoveBackup }
    'Support' {
        $result = @(Invoke-AllChecks)
        if (-not $Destination) { $Destination = Join-Path $logDir ('support-bundle_{0:yyyyMMdd-HHmmss}.zip' -f (Get-Date)) }
        $zip = Export-KitSupportBundle -Destination $Destination -DoctorResult $result -StatePath $pinballState, $lightgunState -LogDir $logDir
        Write-Host (Get-KitText 'Support.Hint')
        $zip
    }
    'ExportProfile' {
        $dest = if ($ProfileDestination) { $ProfileDestination } else { Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads' }
        $res = Export-KitCabinetProfile -Suite $Suite -Destination $dest
        Write-Host (Get-KitText 'Profile.Exported' -f $res.Path) -ForegroundColor Green
        $res
    }
    'ImportProfile' {
        $rMap = if ($RootMap) { $RootMap } else { @{} }
        $results = Import-KitCabinetProfile -Path $ImportProfile -RootMap $rMap -WhatIf:$WhatIfPreference -AutoInstall:$AutoInstall
        foreach ($r in $results) {
            $color = switch ($r.Status) { 'Done' { 'Green' } 'Skipped' { 'DarkGray' } 'WhatIf' { 'Cyan' } 'NeedsUser' { 'Yellow' } default { 'White' } }
            Write-Host ("[{0}] {1}: {2}" -f $r.Status, $r.Name, $r.Detail) -ForegroundColor $color
        }
    }
}

exit 0
