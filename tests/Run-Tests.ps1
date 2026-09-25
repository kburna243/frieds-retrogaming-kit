<#
.SYNOPSIS
    Runs the Pester tests with the Pester 3.x that ships with Windows. Exit code 1 on any failure,
    skip or pending test.
.PARAMETER Path
    Test files or folders. Default: tests\core and tests\pinball.
.PARAMETER Local
    Runs tests\local instead: tests against real (non-synthetic) files in tests\fixtures-local\,
    which only exist on the developer's machine and are never committed.
#>
[CmdletBinding()]
param(
    [string[]] $Path,
    [switch] $Local
)

$ErrorActionPreference = 'Stop'
$testsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Path) {
    $Path = if ($Local) { @(Join-Path $testsDir 'local') } else { @((Join-Path $testsDir 'core'), (Join-Path $testsDir 'pinball')) }
}
Import-Module Pester -MaximumVersion 3.99
$result = Invoke-Pester -Script $Path -PassThru
Write-Host ''
Write-Host ('Passed: {0}  Failed: {1}  Skipped: {2}  Pending: {3}  Total: {4}' -f `
    $result.PassedCount, $result.FailedCount, $result.SkippedCount, $result.PendingCount, $result.TotalCount)
if ($result.FailedCount -gt 0 -or $result.SkippedCount -gt 0 -or $result.PendingCount -gt 0 -or $result.TotalCount -eq 0) { exit 1 }
exit 0
