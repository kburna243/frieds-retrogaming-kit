<#
.SYNOPSIS
    Checks a release zip built by New-ReleasePackage.ps1 and exits with 1 on any problem.
.DESCRIPTION
    - the SHA-256 of the zip matches SHA256SUMS.txt (when present next to the zip or given)
    - every entry sits below "frieds-retrogaming-kit/", no absolute paths, no "..", no backslashes
    - required files are present (launchers, module manifests, i18n, VERSION)
    - no runtime output or private files (logs, install-state.json, backups, .git, real fixtures, *.tmp, ...)
    - VERSION inside the zip matches the version in the zip name
    - the extracted content passes tools/Test-Depersonalized.ps1 (0 findings)
    Runs on Windows PowerShell 5.1 and on PowerShell 7.
.PARAMETER ZipPath
    The release zip.
.PARAMETER SumsPath
    SHA256SUMS.txt. Default: SHA256SUMS.txt next to the zip; skipped with a warning when missing.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-ReleasePackage.ps1 -ZipPath dist\frieds-retrogaming-kit-v0.1.0.zip
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $ZipPath,
    [string] $SumsPath
)

$ErrorActionPreference = 'Stop'
$problems = New-Object System.Collections.Generic.List[string]
$ZipPath = (Resolve-Path -LiteralPath $ZipPath).Path
$zipName = Split-Path -Leaf $ZipPath
$topFolder = 'frieds-retrogaming-kit'

# --- checksum -------------------------------------------------------------------------------------------------
if (-not $SumsPath) { $SumsPath = Join-Path (Split-Path -Parent $ZipPath) 'SHA256SUMS.txt' }
if (Test-Path -LiteralPath $SumsPath) {
    $actual = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $pattern = "^\s*([0-9a-fA-F]{64})\s+\*?$([regex]::Escape($zipName))\s*$"
    $line = @(Get-Content -LiteralPath $SumsPath | Where-Object { $_ -match $pattern })
    if ($line.Count -ne 1) {
        $problems.Add("SHA256SUMS: no single entry for $zipName")
    } else {
        $listed = ([regex]::Match($line[0], $pattern)).Groups[1].Value.ToLowerInvariant()
        if ($listed -ne $actual) { $problems.Add("SHA256SUMS: hash mismatch for $zipName (file $actual, list $listed)") }
    }
} else {
    Write-Warning "No checksum list found ($SumsPath); hash check skipped."
}

# --- entries --------------------------------------------------------------------------------------------------
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$required = @(
    'Start-Kit.cmd', 'Start-Pinball.cmd', 'Start-Lightgun.cmd', 'LICENSE', 'README.md', 'README.de.md', 'VERSION',
    'core/RetroCabinetKit.Core.psd1', 'core/RetroCabinetKit.Core.psm1',
    'pinball/RetroCabinetKit.Pinball.psd1', 'pinball/RetroCabinetKit.Pinball.psm1',
    'lightgun/RetroCabinetKit.Lightgun.psd1', 'lightgun/RetroCabinetKit.Lightgun.psm1',
    'gui/RetroCabinetKit.Gui.psd1', 'gui/RetroCabinetKit.Gui.psm1', 'gui/Start-KitGui.ps1', 'gui/Views/MainWindow.xaml', 'gui/Themes/Brand.xaml',
    'i18n/en-US.psd1', 'i18n/de-DE.psd1'
)
$forbidden = '(^|/)(\.git[^/]*|logs|backups|fixtures-local|node_modules|_intern|_bestand|references|\.claude)(/|$)|\.(log|tmp|partial|bak)$|\.bak_|(^|/)(install-state\.json|PLAN\.md|desktop\.ini)$'

$zip = [IO.Compression.ZipFile]::OpenRead($ZipPath)
$extractDir = Join-Path ([IO.Path]::GetTempPath()) ('frgk-verify-' + [guid]::NewGuid().ToString('N'))
try {
    $names = @($zip.Entries | ForEach-Object { $_.FullName })
    if ($names.Count -eq 0) { $problems.Add('The zip is empty.') }
    $relative = New-Object System.Collections.Generic.List[string]
    foreach ($n in $names) {
        if ($n.Contains('\')) { $problems.Add("Entry uses a backslash: $n"); continue }
        if ($n -match '(^|/)\.\.(/|$)' -or $n.StartsWith('/') -or $n -match '^[A-Za-z]:') { $problems.Add("Unsafe entry path: $n"); continue }
        if (-not $n.StartsWith("$topFolder/")) { $problems.Add("Entry outside $topFolder/: $n"); continue }
        $rel = $n.Substring($topFolder.Length + 1)
        if ($rel -match $forbidden) { $problems.Add("Forbidden file in package: $rel") }
        $relative.Add($rel)
    }
    foreach ($r in $required) {
        if (-not $relative.Contains($r)) { $problems.Add("Required file missing: $r") }
    }

    # --- version ------------------------------------------------------------------------------------------------
    $versionEntry = $zip.GetEntry("$topFolder/VERSION")
    if ($versionEntry) {
        $reader = New-Object IO.StreamReader($versionEntry.Open())
        try { $inside = $reader.ReadToEnd().Trim() } finally { $reader.Dispose() }
        if ($zipName -notmatch '^frieds-retrogaming-kit-v(.+)\.zip$') {
            $problems.Add("Unexpected zip name: $zipName")
        } elseif ($Matches[1] -ne $inside) {
            $problems.Add("Zip name says v$($Matches[1]), VERSION inside says $inside")
        }
    }

    # --- depersonalization of the shipped content -----------------------------------------------------------------
    if ($problems.Count -eq 0) {
        [IO.Compression.ZipFileExtensions]::ExtractToDirectory($zip, $extractDir)
        $scanner = Join-Path $PSScriptRoot 'Test-Depersonalized.ps1'
        $scanOutput = & $scanner -Root (Join-Path $extractDir $topFolder) -AllowlistPath (Join-Path $PSScriptRoot 'depersonalized-allowlist.psd1')
        $scanOutput | ForEach-Object { Write-Host "  $_" }
        if ($LASTEXITCODE -ne 0) { $problems.Add('Depersonalization scan of the extracted package reported findings.') }
    }
} finally {
    $zip.Dispose()
    if (Test-Path -LiteralPath $extractDir) { Remove-Item -LiteralPath $extractDir -Recurse -Force -ErrorAction SilentlyContinue }
}

foreach ($p in $problems) { Write-Output "FAIL: $p" }
Write-Output ('Release package check: {0}, {1} entries, {2} problem(s).' -f $zipName, $names.Count, $problems.Count)
if ($problems.Count) { exit 1 }
exit 0
