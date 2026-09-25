# tools/New-ReleasePackage.ps1
# Creates a clean release zip package for Fried's Retrogaming Kit.

param(
    [string]$Version = "0.1",
    [string]$DestinationDir = "C:\Users\Fried\Downloads"
)

$ErrorActionPreference = "Stop"

$repoRoot = (Get-Item $PSScriptRoot).Parent.FullName
$zipName = "frieds-retrogaming-kit-v$Version.zip"
$zipPath = Join-Path $DestinationDir $zipName

Write-Host "Creating release package $zipName from $repoRoot..." -ForegroundColor Cyan

# Create a temporary staging directory
$stageDir = Join-Path $env:TEMP ("frgk-stage-" + [guid]::NewGuid().ToString("N"))
$packageRoot = Join-Path $stageDir "frieds-retrogaming-kit"
New-Item -ItemType Directory -Force -Path $packageRoot | Out-Null

try {
    # 1. Root files
    $rootFiles = @(
        "Start-Kit.cmd",
        "Start-Pinball.cmd",
        "Start-Lightgun.cmd",
        "README.md",
        "README.de.md",
        "LICENSE",
        "SECURITY.md",
        "CREDITS.md",
        "CONTRIBUTING.md"
    )

    foreach ($file in $rootFiles) {
        $src = Join-Path $repoRoot $file
        if (Test-Path $src) {
            Copy-Item -Path $src -Destination $packageRoot -Force
        } else {
            Write-Warning "File not found: $file"
        }
    }

    # 2. Subdirectories
    $subDirs = @(
        "core",
        "pinball",
        "lightgun",
        "i18n",
        "docs",
        "tools"
    )

    foreach ($dir in $subDirs) {
        $src = Join-Path $repoRoot $dir
        if (Test-Path $src) {
            $dest = Join-Path $packageRoot $dir
            Copy-Item -Path $src -Destination $dest -Recurse -Force
        }
    }

    # Clean any unwanted files from packageRoot
    Get-ChildItem -Path $packageRoot -Include "*.tmp", "*.log", ".git*", "desktop.ini" -Recurse -Force | Remove-Item -Force

    # Ensure output directory exists
    if (-not (Test-Path $DestinationDir)) {
        New-Item -ItemType Directory -Force -Path $DestinationDir | Out-Null
    }

    # Remove existing zip if present
    if (Test-Path $zipPath) {
        Remove-Item -Path $zipPath -Force
    }

    # Create zip
    Write-Host "Compressing to $zipPath..." -ForegroundColor Cyan
    Compress-Archive -Path (Join-Path $stageDir "*") -DestinationPath $zipPath -CompressionLevel Optimal

    $zipItem = Get-Item $zipPath
    $sizeMb = [math]::Round($zipItem.Length / 1MB, 2)
    Write-Host "Successfully created release package: $zipPath ($sizeMb MB)" -ForegroundColor Green

    # Output file details
    [PSCustomObject]@{
        Name = $zipItem.Name
        FullName = $zipItem.FullName
        SizeMB = $sizeMb
        CreatedAt = $zipItem.CreationTime
    }
}
finally {
    if (Test-Path $stageDir) {
        Remove-Item -Path $stageDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}
