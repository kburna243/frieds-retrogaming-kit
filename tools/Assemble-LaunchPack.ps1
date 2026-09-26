# tools/Assemble-LaunchPack.ps1
# Collects social posts, graphics, manuals and the release zip into one launch folder.
# The version comes from the VERSION file (same source as tools/New-ReleasePackage.ps1).
param(
    [string]$PackDir = "",
    [string]$Version = ""
)

$ErrorActionPreference = "Stop"

$downloadsDir = Join-Path ([Environment]::GetFolderPath("UserProfile")) "Downloads"
if (-not $PackDir) {
    $PackDir = Join-Path $downloadsDir "Frieds-Retrogaming-Kit-Launch-Pack"
}

$repoRoot = (Get-Item $PSScriptRoot).Parent.FullName
if (-not $Version) {
    $Version = ([IO.File]::ReadAllText((Join-Path $repoRoot "VERSION"))).Trim()
}
$zipName = "frieds-retrogaming-kit-v$Version.zip"

Write-Host "Creating launch pack at $PackDir..." -ForegroundColor Cyan

$sub01 = Join-Path $PackDir "01_Social_Posts"
$sub02 = Join-Path $PackDir "02_Optimized_Graphics"
$sub02Mascots = Join-Path $sub02 "mascots"
$sub03 = Join-Path $PackDir "03_Product_Manuals"
$sub04 = Join-Path $PackDir "04_Release_Package"

New-Item -ItemType Directory -Force -Path $sub01 | Out-Null
New-Item -ItemType Directory -Force -Path $sub02 | Out-Null
New-Item -ItemType Directory -Force -Path $sub02Mascots | Out-Null
New-Item -ItemType Directory -Force -Path $sub03 | Out-Null
New-Item -ItemType Directory -Force -Path $sub04 | Out-Null

# 1. Social posts
$postEn = Join-Path $downloadsDir "Facebook_Posts_Lunatics_EN.md"
$postDe = Join-Path $downloadsDir "Facebook_Posts_Lunatics.md"

if (Test-Path $postEn) {
    Copy-Item $postEn (Join-Path $sub01 "Facebook_Posts_Lunatics_EN.md") -Force
}
if (Test-Path $postDe) {
    Copy-Item $postDe (Join-Path $sub01 "Facebook_Posts_Lunatics_DE.md") -Force
}

# 2. Optimized graphics
$graphics = @(
    "frieds-rgk-3pillars.webp", "frieds-rgk-3pillars.png",
    "frieds-rgk-pinball.webp", "frieds-rgk-pinball.png",
    "frieds-rgk-wiimote.webp", "frieds-rgk-wiimote.png",
    "frieds-rgk-core.webp", "frieds-rgk-core.png"
)
foreach ($g in $graphics) {
    $src = Join-Path $downloadsDir $g
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination (Join-Path $sub02 $g) -Force
    }
}

# Mascots
$mascotFiles = Get-ChildItem (Join-Path $repoRoot "docs\images\character-*.svg")
foreach ($m in $mascotFiles) {
    Copy-Item -Path $m.FullName -Destination $sub02Mascots -Force
}

# 3. Product manuals
$manuals = @(
    "01_Virtual_Pinball_Suite.md",
    "02_Wiimote_Lightgun_Suite.md",
    "03_Core_Platform_und_Tools.md"
)
foreach ($doc in $manuals) {
    $src = Join-Path $downloadsDir $doc
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination (Join-Path $sub03 $doc) -Force
    }
}

# 4. Release package
$zipSrc = Join-Path $downloadsDir $zipName
if (Test-Path $zipSrc) {
    Copy-Item -Path $zipSrc -Destination (Join-Path $sub04 $zipName) -Force
} else {
    Write-Warning "Release zip not found: $zipSrc (run tools\New-ReleasePackage.ps1 first)"
}
$sumsSrc = Join-Path $downloadsDir "SHA256SUMS.txt"
if (Test-Path $sumsSrc) {
    Copy-Item -Path $sumsSrc -Destination (Join-Path $sub04 "SHA256SUMS.txt") -Force
}

# 5. Summary Readme
# Literal here-string: backticks are markdown code spans here, not PowerShell escapes.
$readmeContent = @'
# Fried's Retrogaming Kit — Launch Pack v{{VERSION}}

This folder contains all essential marketing, social, visual, and documentation assets for the v{{VERSION}} launch.

## 📂 Folder Overview

- **01_Social_Posts/**
  - `Facebook_Posts_Lunatics_EN.md`: English post templates for Light Gun Lunatics, Pinball Lunatics, and general community.
  - `Facebook_Posts_Lunatics_DE.md`: Deutsche Post-Vorlagen für die deutschsprachigen Communitys.

- **02_Optimized_Graphics/**
  - `frieds-rgk-3pillars.webp` & `.png`: 3-Pillars ecosystem graphic.
  - `frieds-rgk-pinball.webp` & `.png`: Virtual Pinball Suite overview & flow.
  - `frieds-rgk-wiimote.webp` & `.png`: Light Gun Suite / Wiimote turnkey pipeline.
  - `frieds-rgk-core.webp` & `.png`: Core platform, backup & diagnostic architecture.
  - `mascots/`: 9 vector mascot expressions & poses (SVG).

- **03_Product_Manuals/**
  - `01_Virtual_Pinball_Suite.md`: Detailed module guide & setup instructions.
  - `02_Wiimote_Lightgun_Suite.md`: Detailed lightgun guide & emulator settings.
  - `03_Core_Platform_und_Tools.md`: Core system, backup/rollback, and wizard guide.

- **04_Release_Package/**
  - `{{ZIP}}`: Standalone release build v{{VERSION}} ready for distribution.
  - `SHA256SUMS.txt`: SHA-256 checksum of the zip (verify with `Get-FileHash` or `sha256sum -c`).

## 🔗 Important Links
- **GitHub Repository**: https://github.com/kburna243/frieds-retrogaming-kit
- **GitHub Release v{{VERSION}}**: https://github.com/kburna243/frieds-retrogaming-kit/releases/tag/v{{VERSION}}
- **Live Documentation & Website**: https://kburna243.github.io/frieds-retrogaming-kit/
'@
$readmeContent = $readmeContent.Replace('{{VERSION}}', $Version).Replace('{{ZIP}}', $zipName)

Set-Content -Path (Join-Path $PackDir "README_LAUNCH_PACK.md") -Value $readmeContent -Encoding UTF8

Write-Host "Launch pack assembled successfully at: $PackDir" -ForegroundColor Green
