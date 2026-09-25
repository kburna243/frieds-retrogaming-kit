# tools/Assemble-LaunchPack.ps1
param(
    [string]$PackDir = "C:\Users\Fried\Downloads\Frieds-Retrogaming-Kit-Launch-Pack"
)

$ErrorActionPreference = "Stop"

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
Copy-Item "C:\Users\Fried\Downloads\Facebook_Posts_Lunatics_EN.md" (Join-Path $sub01 "Facebook_Posts_Lunatics_EN.md") -Force
Copy-Item "C:\Users\Fried\Downloads\Facebook_Posts_Lunatics.md" (Join-Path $sub01 "Facebook_Posts_Lunatics_DE.md") -Force

# 2. Optimized graphics
$graphics = @(
    "frieds-rgk-3pillars.webp", "frieds-rgk-3pillars.png",
    "frieds-rgk-pinball.webp", "frieds-rgk-pinball.png",
    "frieds-rgk-wiimote.webp", "frieds-rgk-wiimote.png",
    "frieds-rgk-core.webp", "frieds-rgk-core.png"
)
foreach ($g in $graphics) {
    $src = Join-Path "C:\Users\Fried\Downloads" $g
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination (Join-Path $sub02 $g) -Force
    }
}

# Mascots
$mascotFiles = Get-ChildItem "I:\claude-system\data\projects\retro-cabinet-kit\docs\images\character-*.svg"
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
    $src = Join-Path "C:\Users\Fried\Downloads" $doc
    if (Test-Path $src) {
        Copy-Item -Path $src -Destination (Join-Path $sub03 $doc) -Force
    }
}

# 4. Release package
$zipSrc = "C:\Users\Fried\Downloads\frieds-retrogaming-kit-v0.1.zip"
if (Test-Path $zipSrc) {
    Copy-Item -Path $zipSrc -Destination (Join-Path $sub04 "frieds-retrogaming-kit-v0.1.zip") -Force
}

# 5. Summary Readme
$readmeContent = @"
# Fried's Retrogaming Kit — Launch Pack v0.1

This folder contains all essential marketing, social, visual, and documentation assets for the v0.1 launch.

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
  - `frieds-retrogaming-kit-v0.1.zip`: Standalone release build v0.1.0 ready for distribution.

## 🔗 Important Links
- **GitHub Repository**: https://github.com/kburna243/frieds-retrogaming-kit
- **GitHub Release v0.1.0**: https://github.com/kburna243/frieds-retrogaming-kit/releases/tag/v0.1.0
- **Live Documentation & Website**: https://kburna243.github.io/frieds-retrogaming-kit/
"@

Set-Content -Path (Join-Path $PackDir "README_LAUNCH_PACK.md") -Value $readmeContent -Encoding UTF8

Write-Host "Launch pack assembled successfully at: $PackDir" -ForegroundColor Green
