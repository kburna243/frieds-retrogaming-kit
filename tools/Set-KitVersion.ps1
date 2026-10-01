<#
.SYNOPSIS
    Sets the kit version everywhere it is written down, in one go, and checks the result.
.DESCRIPTION
    VERSION, every module manifest (ModuleVersion), the website (config.ts KIT_VERSION, the "v<version>." in
    index.html and both i18n descriptions), the "Status: v<version>" line of both READMEs and CHANGELOG.md
    (the [Unreleased] entries become the new section, compare links updated). Then runs Test-KitSyntax.
    Nothing is committed or tagged: the script prints the git commands, so the tag always lands on the
    commit that carries the new VERSION (the release workflow refuses any other).
.PARAMETER Version
    The new version, X.Y.Z (optionally -suffix for a pre-release).
.PARAMETER Date
    Release date for the CHANGELOG heading. Default: today.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\Set-KitVersion.ps1 -Version 0.4.2
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)] [ValidatePattern('^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$')] [string] $Version,
    [string] $Date = (Get-Date -Format 'yyyy-MM-dd'),
    [string] $Root
)
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$old = ([IO.File]::ReadAllText((Join-Path $Root 'VERSION'))).Trim()
if ($old -eq $Version) { throw "VERSION is already $Version" }
$repo = 'https://github.com/kburna243/frieds-retrogaming-kit'
$moduleVersion = ($Version -split '-')[0]

# Rewrites one file; keeps its BOM and line endings. Every replacement must hit, or nothing is written.
function Update-KitFile([string] $Rel, [object[]] $Pairs) {
    $path = Join-Path $Root $Rel
    $bytes = [IO.File]::ReadAllBytes($path)
    $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    $text = (New-Object Text.UTF8Encoding $false).GetString($bytes, $(if ($bom) { 3 } else { 0 }), $bytes.Length - $(if ($bom) { 3 } else { 0 }))
    foreach ($p in $Pairs) {
        if (-not [regex]::IsMatch($text, $p[0])) { throw "${Rel}: '$($p[0])' not found" }
        $text = [regex]::Replace($text, $p[0], $p[1])
    }
    if ($PSCmdlet.ShouldProcess($Rel, "set version $Version")) {
        [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding $bom))
        Write-Output "  $Rel"
    }
}

$o = [regex]::Escape($old)
$nl = if ([IO.File]::ReadAllText((Join-Path $Root 'CHANGELOG.md')).Contains("`r`n")) { "`r`n" } else { "`n" }
Update-KitFile 'VERSION' @(, @("^$o", $Version))
foreach ($m in Get-ChildItem -Path (Join-Path $Root '*\RetroCabinetKit.*.psd1')) {
    Update-KitFile (Join-Path (Split-Path -Leaf $m.DirectoryName) $m.Name) @(, @("(ModuleVersion\s*=\s*')[^']+'", "`${1}$moduleVersion'"))
}
Update-KitFile 'site\src\config.ts' @(, @("KIT_VERSION = `"$o`"", "KIT_VERSION = `"$Version`""))
foreach ($f in 'site\index.html', 'site\src\i18n\de.ts', 'site\src\i18n\en.ts') { Update-KitFile $f @(, @(" v$o\.", " v$Version.")) }
foreach ($f in 'README.md', 'README.de.md') { Update-KitFile $f @(, @("\*\*Status: v$o\*\*", "**Status: v$Version**")) }
Update-KitFile 'CHANGELOG.md' @(
    @("(?m)^## \[Unreleased\]\r?\n", "## [Unreleased]$nl$nl## [$Version] - $Date$nl"),
    @("(?m)^\[Unreleased\]: \S+", "[Unreleased]: $repo/compare/v$Version...HEAD$nl[$Version]: $repo/compare/v$old...v$Version")
)

if (-not $WhatIfPreference) {
    & (Join-Path $PSScriptRoot 'Test-KitSyntax.ps1') -Root $Root | Select-Object -Last 1
    if ($LASTEXITCODE) { exit $LASTEXITCODE }
    Write-Output ''
    Write-Output 'Next: check the CHANGELOG section, then'
    Write-Output '  git add VERSION CHANGELOG.md README.md README.de.md site */RetroCabinetKit.*.psd1'
    Write-Output "  git commit -m `"release: v$Version`"   (commit first, the tag must point at this commit)"
    Write-Output "  git tag -a v$Version -m `"v$Version`""
    Write-Output "  git push origin main v$Version"
}
