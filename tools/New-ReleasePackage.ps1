<#
.SYNOPSIS
    Builds the release zip of Fried's Retrogaming Kit and writes SHA256SUMS.txt next to it.
.DESCRIPTION
    The version comes from the VERSION file in the repository root (single source of truth); the module
    manifests (core, pinball, lightgun) must carry the same ModuleVersion or the build stops.
    Only files git tracks are packaged, so local runtime output (logs, install-state.json, backups, real test
    fixtures) can never end up in a release. Without git, the folders are copied and runtime output is removed.
    The zip holds one top folder "frieds-retrogaming-kit\" and uses "/" as entry separator.
    Runs on Windows PowerShell 5.1 and on PowerShell 7.
.PARAMETER Version
    Override the version (e.g. for a test build). Default: the content of VERSION.
.PARAMETER DestinationDir
    Output folder. Default: the user's Downloads folder.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\New-ReleasePackage.ps1 -DestinationDir dist
#>
[CmdletBinding()]
param(
    [string] $Version,
    [string] $DestinationDir
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot

# --- version --------------------------------------------------------------------------------------------------
$versionFile = Join-Path $repoRoot 'VERSION'
if (-not $Version) {
    if (-not (Test-Path -LiteralPath $versionFile)) { throw "VERSION file not found: $versionFile" }
    $Version = ([IO.File]::ReadAllText($versionFile)).Trim()
}
if ($Version -notmatch '^(\d+\.\d+\.\d+)(-[0-9A-Za-z.-]+)?$') { throw "Invalid version '$Version' (expected e.g. 0.2.0 or 0.2.0-rc.1)." }
$moduleVersion = $Matches[1]
foreach ($manifest in 'core\RetroCabinetKit.Core.psd1', 'pinball\RetroCabinetKit.Pinball.psd1', 'lightgun\RetroCabinetKit.Lightgun.psd1', 'gui\RetroCabinetKit.Gui.psd1') {
    $path = Join-Path $repoRoot $manifest
    $data = Import-PowerShellDataFile -LiteralPath $path
    if ($data.ModuleVersion -ne $moduleVersion) {
        throw "$manifest has ModuleVersion $($data.ModuleVersion), VERSION says $moduleVersion. Keep them in sync."
    }
}

if (-not $DestinationDir) { $DestinationDir = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads' }
if (-not (Test-Path -LiteralPath $DestinationDir)) { New-Item -ItemType Directory -Force -Path $DestinationDir | Out-Null }
$DestinationDir = (Resolve-Path -LiteralPath $DestinationDir).Path

$zipName = "frieds-retrogaming-kit-v$Version.zip"
$zipPath = Join-Path $DestinationDir $zipName
$sumsPath = Join-Path $DestinationDir 'SHA256SUMS.txt'
$topFolder = 'frieds-retrogaming-kit'

# --- file list ------------------------------------------------------------------------------------------------
$rootFiles = @(
    'Start-Kit.cmd', 'Start-Pinball.cmd', 'Start-Lightgun.cmd',
    'README.md', 'README.de.md', 'LICENSE', 'SECURITY.md', 'CREDITS.md', 'CONTRIBUTING.md',
    'CHANGELOG.md', 'ARCHITECTURE.md', 'VERSION'
)
$subDirs = @('core', 'pinball', 'lightgun', 'gui', 'i18n', 'docs', 'tools')
# Never shipped, even if tracked by mistake or copied without git.
$excluded = '(^|/)(\.git[^/]*|logs|backups|fixtures-local|node_modules|desktop\.ini)(/|$)|\.(log|tmp|partial)$|\.bak_|(^|/)install-state\.json$'

$files = $null
if ((Get-Command git -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath (Join-Path $repoRoot '.git'))) {
    $tracked = @(& git -C $repoRoot ls-files)
    if ($LASTEXITCODE -eq 0) {
        $files = @($tracked | Where-Object {
            $f = $_
            ($rootFiles -contains $f) -or ($subDirs | Where-Object { $f.StartsWith("$_/") })
        })
    }
}
if ($null -eq $files) {
    Write-Warning 'git not available: packaging the working tree (runtime output is filtered).'
    $files = @($rootFiles | Where-Object { Test-Path -LiteralPath (Join-Path $repoRoot $_) -PathType Leaf })
    foreach ($dir in $subDirs) {
        $full = Join-Path $repoRoot $dir
        if (-not (Test-Path -LiteralPath $full)) { continue }
        $files += @(Get-ChildItem -LiteralPath $full -Recurse -File -Force | ForEach-Object {
            $_.FullName.Substring($repoRoot.Length).TrimStart('\', '/') -replace '\\', '/'
        })
    }
}
$files = @($files | Where-Object { $_ -notmatch $excluded } | Sort-Object -Unique)
foreach ($required in $rootFiles) {
    if ($files -notcontains $required) { Write-Warning "Root file missing from package: $required" }
}

# --- zip ------------------------------------------------------------------------------------------------------
Write-Host "Creating $zipName ($($files.Count) files) from $repoRoot ..." -ForegroundColor Cyan
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
$zip = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
try {
    foreach ($rel in $files) {
        $src = Join-Path $repoRoot ($rel -replace '/', [IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path -LiteralPath $src -PathType Leaf)) { continue } # deleted but still in the index
        [void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $zip, $src, "$topFolder/$rel", [IO.Compression.CompressionLevel]::Optimal)
    }
} finally {
    $zip.Dispose()
}

# --- checksums ------------------------------------------------------------------------------------------------
$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
# GNU coreutils format ("<hash>  <name>"), so "sha256sum -c SHA256SUMS.txt" works as well.
[IO.File]::WriteAllText($sumsPath, "$hash  $zipName`n", (New-Object Text.UTF8Encoding $false))

$zipItem = Get-Item -LiteralPath $zipPath
$sizeMb = [math]::Round($zipItem.Length / 1MB, 2)
Write-Host "Created $zipPath ($sizeMb MB)" -ForegroundColor Green
Write-Host "SHA-256 $hash" -ForegroundColor Green

[pscustomobject]@{
    Version   = $Version
    Name      = $zipItem.Name
    FullName  = $zipItem.FullName
    SizeMB    = $sizeMb
    Sha256    = $hash
    SumsFile  = $sumsPath
    FileCount = $files.Count
}
