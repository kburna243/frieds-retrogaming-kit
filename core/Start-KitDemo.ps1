<#
.SYNOPSIS
    Core demo: unblock kit files, start the log, show the language, run one example step with -WhatIf.
.PARAMETER Culture
    Override the UI language (e.g. de-DE, en-US). Default: the Windows display language.
#>
[CmdletBinding()]
param([string] $Culture)

$ErrorActionPreference = 'Stop'
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
