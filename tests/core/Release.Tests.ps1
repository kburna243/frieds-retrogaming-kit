$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tools = Join-Path $kitRoot 'tools'
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

# Release engineering: one version source, reproducible package, integrity check that catches tampering.
Describe 'Release package' {
    $version = ([IO.File]::ReadAllText((Join-Path $kitRoot 'VERSION'))).Trim()
    $dist = Join-Path $TestDrive 'dist'
    $zipName = "frieds-retrogaming-kit-v$version.zip"

    It 'VERSION is a semantic version and matches the module manifests' {
        $version | Should Match '^\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?$'
        $moduleVersion = ($version -split '-')[0]
        foreach ($m in 'core\RetroCabinetKit.Core.psd1', 'pinball\RetroCabinetKit.Pinball.psd1', 'lightgun\RetroCabinetKit.Lightgun.psd1', 'gui\RetroCabinetKit.Gui.psd1', 'api\RetroCabinetKit.Api.psd1') {
            (Import-PowerShellDataFile -LiteralPath (Join-Path $kitRoot $m)).ModuleVersion | Should Be $moduleVersion
        }
    }

    It 'the website shows the same version (site\src\config.ts)' {
        $config = [IO.File]::ReadAllText((Join-Path $kitRoot 'site\src\config.ts'))
        $config | Should Match ('KIT_VERSION = "{0}"' -f [regex]::Escape($version))
    }

    It 'builds the zip named after VERSION with a matching SHA256SUMS.txt' {
        $result = & (Join-Path $tools 'New-ReleasePackage.ps1') -DestinationDir $dist 6>$null
        $result.Name | Should BeExactly $zipName
        Join-Path $dist $zipName | Should Exist
        $sums = [IO.File]::ReadAllText((Join-Path $dist 'SHA256SUMS.txt'))
        $hash = (Get-FileHash -LiteralPath (Join-Path $dist $zipName) -Algorithm SHA256).Hash.ToLowerInvariant()
        $sums | Should BeExactly "$hash  $zipName`n"
    }

    It 'the built zip passes the integrity check' {
        $null = & (Join-Path $tools 'Test-ReleasePackage.ps1') -ZipPath (Join-Path $dist $zipName) 6>$null
        $LASTEXITCODE | Should Be 0
    }

    It 'a changed checksum list fails the check' {
        $bad = Join-Path $TestDrive 'tampered'
        New-Item -ItemType Directory -Path $bad -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $dist $zipName) -Destination $bad
        [IO.File]::WriteAllText((Join-Path $bad 'SHA256SUMS.txt'), ('f' * 64) + "  $zipName`n")
        $out = & (Join-Path $tools 'Test-ReleasePackage.ps1') -ZipPath (Join-Path $bad $zipName) 6>$null
        $LASTEXITCODE | Should Be 1
        ($out -join "`n") | Should Match 'hash mismatch'
    }

    It 'runtime output and unsafe paths in the zip fail the check' {
        $bad = Join-Path $TestDrive 'runtime'
        New-Item -ItemType Directory -Path $bad -Force | Out-Null
        $zipPath = Join-Path $bad $zipName
        Copy-Item -LiteralPath (Join-Path $dist $zipName) -Destination $zipPath
        $zip = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Update)
        try {
            foreach ($entry in 'frieds-retrogaming-kit/lightgun/install-state.json', 'frieds-retrogaming-kit/logs/kit.log', '../outside.txt') {
                $writer = New-Object IO.StreamWriter($zip.CreateEntry($entry).Open())
                try { $writer.Write('x') } finally { $writer.Dispose() }
            }
        } finally {
            $zip.Dispose()
        }
        $out = & (Join-Path $tools 'Test-ReleasePackage.ps1') -ZipPath $zipPath 6>$null 3>$null
        $LASTEXITCODE | Should Be 1
        $text = $out -join "`n"
        $text | Should Match 'Forbidden file in package: lightgun/install-state\.json'
        $text | Should Match 'Forbidden file in package: logs/kit\.log'
        $text | Should Match 'Unsafe entry path: \.\./outside\.txt'
    }
}
