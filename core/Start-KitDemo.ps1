<#
.SYNOPSIS
    Entry of Start-Kit.cmd. Without switches it opens the dashboard (gui\Start-KitGui.ps1, WPF).
    -Doctor, -Backups, -SupportBundle, -ExportProfile or -ImportProfile run that tool on the command line
    (core\Start-KitTools.ps1);
    -Demo runs the core demo (unblock kit files, start the log, one example step with -WhatIf).
.PARAMETER Culture
    Override the UI language (e.g. de-DE, en-US). Default: the Windows display language.
.PARAMETER Doctor
    Read-only health check of system, pinball and lightgun.
.PARAMETER Backups
    Lists the kit's backups.
.PARAMETER SupportBundle
    Creates an anonymized support bundle in the logs folder.
.PARAMETER Demo
    Runs the core demo instead of opening the dashboard.
.PARAMETER ExportProfile
    Cabinet A: writes the cabinet profile of -Suite (Pinball, Lightgun) as a zip (-ProfileDestination: folder or
    zip path; default: Downloads).
.PARAMETER ImportProfile
    Cabinet B: imports this profile zip. Use -WhatIf first: it checks everything and changes nothing.
    -AutoInstall installs missing drivers after showing their plan and asking.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $Culture,
    [switch] $Doctor,
    [switch] $Backups,
    [switch] $SupportBundle,
    [switch] $Demo,
    [switch] $ExportProfile,
    [string] $Suite,
    [string] $ProfileDestination,
    [string] $ImportProfile,
    [switch] $AutoInstall
)

$ErrorActionPreference = 'Stop'
if ($Doctor -or $Backups -or $SupportBundle -or $ExportProfile -or $ImportProfile) {
    & (Join-Path $PSScriptRoot 'Start-KitTools.ps1') @PSBoundParameters
    exit $LASTEXITCODE
}
if (-not $Demo) {
    $gui = @{}
    if ($Culture) { $gui.Culture = $Culture }
    & (Join-Path (Split-Path -Parent $PSScriptRoot) 'gui\Start-KitGui.ps1') @gui
    exit 0
}
$kitRoot = Split-Path -Parent $PSScriptRoot

# Files downloaded as ZIP carry a Zone.Identifier; remove it from the kit's own files only.
Get-ChildItem -LiteralPath (Join-Path $kitRoot 'core'), (Join-Path $kitRoot 'i18n') -Recurse -File | Unblock-File
Get-ChildItem -LiteralPath $kitRoot -Filter '*.cmd' -File | Unblock-File

Import-Module (Join-Path $PSScriptRoot 'RetroCabinetKit.Core.psd1') -Force
if ($Culture) { Set-KitCulture -Culture $Culture }

$log = Join-Path $kitRoot ('logs\demo_{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))
Start-KitLog -Path $log
try {
    Write-KitLog (Get-KitText 'Demo.Welcome')
    Write-KitLog (Get-KitText 'Culture.Current' -f (Get-KitCulture))
    Write-KitLog (Get-KitText $(if (Test-KitAdmin) { 'Admin.Yes' } else { 'Admin.No' }))

    $marker = Join-Path $env:TEMP 'retro-cabinet-kit-demo.txt'
    $step = New-KitStep -Name 'demo-marker-file' `
        -Test   { Test-Path -LiteralPath $env:TEMP } `
        -Invoke { Set-Content -LiteralPath $marker -Value 'demo' } `
        -Verify { Test-Path -LiteralPath $marker }
    $result = Invoke-KitStep -Step $step -WhatIf
    Write-KitLog ('{0}: {1}' -f $result.Name, $result.Status)
    Write-KitLog (Get-KitText 'Demo.Done' -f $log)
} finally {
    Stop-KitLog
}
