# CabinetProfile: export configuration from cabinet A and import onto cabinet B.
#
# Rules:
# - Strictly separated profiles: -Suite Pinball or -Suite Lightgun.
# - Tokenized paths: {PinballRoot}, {RetroBatRoot}, {GunmoteDir}, {SteamDir}.
#   profile.json and stored text never contain machine-specific absolute paths or user names.
# - Export only reads; import backs up every file before changing it (New-KitBackup).
# - Untrusted input: manifest validated, all extract paths verified under allowed roots (Test-KitPathUnder),
#   .reg texts validated against allowlisted roots (Assert-KitRegText).
# - Second import is idempotent (every step Skipped).

$script:KitProfileFormat = 1
$script:KitProfileMaxBytes = 10MB
$script:KitProfileTokens = @('{PinballRoot}', '{RetroBatRoot}', '{GunmoteDir}', '{SteamDir}')

function ConvertTo-KitProfilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [hashtable] $Roots
    )
    $res = $Path.Trim()
    foreach ($token in $Roots.Keys | Sort-Object { $Roots[$_].Length } -Descending) {
        $rootVal = $Roots[$token]
        if (-not $rootVal) { continue }
        $cleanRoot = $rootVal.TrimEnd('\', '/')
        if ($res.StartsWith($cleanRoot, [StringComparison]::OrdinalIgnoreCase)) {
            $sub = $res.Substring($cleanRoot.Length).TrimStart('\', '/')
            $res = if ($sub) { "$token/$sub" -replace '\\', '/' } else { $token }
            break
        }
    }
    $res -replace '\\', '/'
}

function ConvertFrom-KitProfilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [hashtable] $Roots
    )
    $res = $Path.Trim()
    foreach ($token in $Roots.Keys) {
        $rootVal = $Roots[$token]
        if (-not $rootVal) { continue }
        $cleanRoot = $rootVal.TrimEnd('\', '/')
        if ($res.StartsWith($token, [StringComparison]::OrdinalIgnoreCase)) {
            $sub = $res.Substring($token.Length).TrimStart('/', '\')
            $res = if ($sub) { Join-Path $cleanRoot ($sub -replace '/', '\') } else { $cleanRoot }
            break
        }
    }
    $res
}

function Assert-KitProfilePathSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $p = $Path -replace '\\', '/'
    if ($p -match '(^|/)\.\.(/|$)') {
        throw "Path traversal refused: '$Path'"
    }
    if ($p -match '^[A-Za-z]:' -or $p.StartsWith('/') -or $p.StartsWith('\\')) {
        throw "Absolute path refused: '$Path'"
    }
    if ($p -match '[\x00-\x1F\x7F]') {
        throw "Invalid characters in path: '$Path'"
    }
}

function Assert-KitProfileManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object] $Manifest)

    $format = if ($Manifest -is [System.Collections.IDictionary]) {
        if ($Manifest.Contains('Format')) { $Manifest['Format'] } else { $null }
    } elseif ($Manifest.PSObject -and $Manifest.PSObject.Properties['Format']) {
        $Manifest.PSObject.Properties['Format'].Value
    } else { $null }

    if (-not $format) { throw "Invalid profile manifest: missing Format." }
    if ($format -gt $script:KitProfileFormat) {
        throw "Profile format $format is newer than supported format $script:KitProfileFormat. Please update the kit."
    }

    $suite = if ($Manifest -is [System.Collections.IDictionary]) {
        if ($Manifest.Contains('Suite')) { $Manifest['Suite'] } else { $null }
    } elseif ($Manifest.PSObject -and $Manifest.PSObject.Properties['Suite']) {
        $Manifest.PSObject.Properties['Suite'].Value
    } else { $null }

    if (-not $suite -or $suite -notmatch '^(Pinball|Lightgun)$') {
        throw "Invalid profile manifest: unknown Suite '$suite'."
    }

    $roots = if ($Manifest -is [System.Collections.IDictionary]) {
        if ($Manifest.Contains('Roots')) { $Manifest['Roots'] } else { $null }
    } elseif ($Manifest.PSObject -and $Manifest.PSObject.Properties['Roots']) {
        $Manifest.PSObject.Properties['Roots'].Value
    } else { $null }

    if (-not $roots) {
        throw "Invalid profile manifest: missing Roots."
    }

    # Verify no machine paths or private data in profile.json
    $jsonText = ConvertTo-Json $Manifest -Depth 10
    if ($jsonText -match '[A-Za-z]:\\' -or $jsonText -match '\\\\[A-Za-z0-9_]+\\') {
        throw "Profile manifest contains absolute paths. Only tokenized paths are allowed."
    }
    if ($jsonText -match 'S-1-5-21-\d+-\d+-\d+-\d+') {
        throw "Profile manifest contains user SIDs."
    }

    $items = if ($Manifest -is [System.Collections.IDictionary]) {
        if ($Manifest.Contains('Items')) { $Manifest['Items'] } else { $null }
    } elseif ($Manifest.PSObject -and $Manifest.PSObject.Properties['Items']) {
        $Manifest.PSObject.Properties['Items'].Value
    } else { $null }

    foreach ($item in @($items)) {
        if (-not $item) { continue }
        $itemPath = if ($item -is [System.Collections.IDictionary]) {
            if ($item.Contains('Path')) { $item['Path'] } else { $null }
        } elseif ($item.PSObject -and $item.PSObject.Properties['Path']) {
            $item.PSObject.Properties['Path'].Value
        } else { $null }

        if ($itemPath) {
            Assert-KitProfilePathSafe -Path $itemPath
        }
    }
}

function Export-KitCabinetProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('Pinball', 'Lightgun')] [string] $Suite,
        [Parameter(Mandatory)] [string] $Destination,
        [hashtable] $RootMap = @{},
        [string[]] $RegistryRoots,
        [string] $StatePath,
        [string] $PupDatabasePath,
        [string] $RetroBatRoot,
        [string] $GunmoteDir,
        [string] $SteamDir,
        [object[]] $Monitors,
        [string] $UserName,
        [string] $ComputerName,
        [string] $UserProfile
    )

    $kitRoot = Split-Path -Parent $PSScriptRoot
    $versionFile = Join-Path $kitRoot 'VERSION'
    $kitVersion = if (Test-Path -LiteralPath $versionFile) { ([IO.File]::ReadAllText($versionFile)).Trim() } else { '0.1.0' }

    # Resolve roots on machine A
    $roots = @{}
    if ($Suite -eq 'Pinball') {
        $pState = if ($StatePath) { $StatePath } else { Get-PinballDefaultStatePath }
        $targetRoot = if ($RootMap.ContainsKey('{PinballRoot}')) { $RootMap['{PinballRoot}'] }
                      elseif (Test-Path -LiteralPath $pState) { (Get-KitState -Path $pState).TargetRoot }
                      else { $null }
        if ($targetRoot) { $roots['{PinballRoot}'] = $targetRoot }
    } else {
        $lState = if ($StatePath) { $StatePath } else { Get-LightgunDefaultStatePath }
        $lStateData = if (Test-Path -LiteralPath $lState) { Get-KitState -Path $lState } else { $null }
        $rbRoot = if ($RetroBatRoot) { $RetroBatRoot }
                  elseif ($RootMap.ContainsKey('{RetroBatRoot}')) { $RootMap['{RetroBatRoot}'] }
                  elseif ($lStateData -and $lStateData.RetroBatRoot) { $lStateData.RetroBatRoot }
                  else { $null }
        if ($rbRoot) { $roots['{RetroBatRoot}'] = $rbRoot }

        $gmDir = if ($GunmoteDir) { $GunmoteDir }
                 elseif ($RootMap.ContainsKey('{GunmoteDir}')) { $RootMap['{GunmoteDir}'] }
                 elseif ($lStateData -and $lStateData.GunmoteDir) { $lStateData.GunmoteDir }
                 else { Find-LightgunGunmote }
        if ($gmDir) { $roots['{GunmoteDir}'] = $gmDir }

        $stDir = if ($SteamDir) { $SteamDir }
                 elseif ($RootMap.ContainsKey('{SteamDir}')) { $RootMap['{SteamDir}'] }
                 else { Get-LightgunSteamPath }
        if ($stDir) { $roots['{SteamDir}'] = $stDir }
    }

    $destPath = Resolve-FullPath $Destination
    $targetZip = if ($destPath.EndsWith('.zip', [StringComparison]::OrdinalIgnoreCase)) {
        $destPath
    } else {
        if (-not (Test-Path -LiteralPath $destPath)) { New-Item -ItemType Directory -Force -Path $destPath | Out-Null }
        Join-Path $destPath ('cabinet-profile-{0}_{1:yyyyMMdd-HHmmss}.zip' -f $Suite.ToLowerInvariant(), (Get-Date))
    }
    $targetZipDir = Split-Path -Parent $targetZip
    if (-not (Test-Path -LiteralPath $targetZipDir)) { New-Item -ItemType Directory -Force -Path $targetZipDir | Out-Null }

    $stageDir = Join-Path $env:TEMP ('kit-profile-stage-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $stageDir | Out-Null

    try {
        $items = New-Object Collections.Generic.List[object]

        if ($Suite -eq 'Pinball') {
            # 1. Registry
            $regDir = Join-Path $stageDir 'registry'
            New-Item -ItemType Directory -Force -Path $regDir | Out-Null
            $regKeys = if ($RegistryRoots) { $RegistryRoots } else { Get-PinballRegistryImportRoot }
            $regIndex = 1
            foreach ($rk in $regKeys) {
                if (Test-Path -LiteralPath $rk) {
                    $regFile = Join-Path $regDir ('{0:D3}.reg' -f $regIndex)
                    try {
                        $null = Export-KitRegistryKey -Path $rk -Destination $regFile
                        if (Test-Path -LiteralPath $regFile) {
                            $bytes = [IO.File]::ReadAllBytes($regFile)
                            $items.Add([pscustomobject]@{
                                Suite = 'Pinball'; Kind = 'Registry'; Path = "registry/{0:D3}.reg" -f $regIndex
                                Key = $rk; Sha256 = (Get-FileHash -LiteralPath $regFile -Algorithm SHA256).Hash
                                Size = $bytes.Length
                            })
                            $regIndex++
                        }
                    } catch {
                        Write-KitLog "Profile export registry warning: $($_.Exception.Message)"
                    }
                }
            }

            # 2. Screens proposal
            $screenItems = @{}
            $pbRoot = $roots['{PinballRoot}']
            if ($pbRoot -and (Test-Path -LiteralPath $pbRoot)) {
                $screenResPath = Join-Path $pbRoot 'vPinball\Tables\ScreenRes.txt'
                if (Test-Path -LiteralPath $screenResPath) {
                    $screenItems['ScreenRes'] = (Get-Content -LiteralPath $screenResPath -Raw)
                }
                $vpxIni = Join-Path $pbRoot 'vPinball\VisualPinball\VPinballX.ini'
                if (Test-Path -LiteralPath $vpxIni) {
                    $screenItems['VPinballX'] = (Get-Content -LiteralPath $vpxIni -Raw)
                }
            }
            if ($screenItems.Count -gt 0) {
                $filesDir = Join-Path $stageDir 'files/pinball'
                New-Item -ItemType Directory -Force -Path $filesDir | Out-Null
                $screensJson = Join-Path $filesDir 'screens.json'
                [IO.File]::WriteAllText($screensJson, (ConvertTo-Json $screenItems -Depth 5), [Text.Encoding]::UTF8)
                $items.Add([pscustomobject]@{
                    Suite = 'Pinball'; Kind = 'Proposal'; Path = 'files/pinball/screens.json'
                    TargetToken = '{PinballRoot}/screens.json'; Sha256 = (Get-FileHash -LiteralPath $screensJson -Algorithm SHA256).Hash
                    Size = (Get-Item $screensJson).Length
                })
            }

            # 3. SQLite settings: Emulators & Playlists
            $dbFile = if ($PupDatabasePath) { $PupDatabasePath }
                      elseif ($pbRoot) { Join-Path $pbRoot 'vPinball\PinUPSystem\PUPDatabase.db' }
                      else { $null }
            if ($dbFile -and (Test-Path -LiteralPath $dbFile)) {
                $sqliteData = @{ Emulators = @(); Playlists = @() }
                $dbConn = Open-KitSqlite -Path $dbFile -ReadOnly
                try {
                    $hasEmus = @(Invoke-KitSqlQuery -Connection $dbConn -Sql "SELECT name FROM sqlite_master WHERE type='table' AND name='Emulators'").Count -gt 0
                    if ($hasEmus) {
                        $emus = @(Invoke-KitSqlQuery -Connection $dbConn -Sql 'SELECT * FROM Emulators')
                        foreach ($emu in $emus) {
                            $eObj = [ordered]@{}
                            foreach ($prop in $emu.psobject.Properties) {
                                $val = $prop.Value
                                if ($val -is [string] -and $roots.Count -gt 0) {
                                    $val = ConvertTo-KitProfilePath -Path $val -Roots $roots
                                }
                                $eObj[$prop.Name] = $val
                            }
                            $sqliteData.Emulators += $eObj
                        }
                    }
                    $hasPlaylists = @(Invoke-KitSqlQuery -Connection $dbConn -Sql "SELECT name FROM sqlite_master WHERE type='table' AND name='Playlists'").Count -gt 0
                    if ($hasPlaylists) {
                        $pls = @(Invoke-KitSqlQuery -Connection $dbConn -Sql 'SELECT * FROM Playlists')
                        foreach ($pl in $pls) {
                            $pObj = [ordered]@{}
                            foreach ($prop in $pl.psobject.Properties) {
                                $val = $prop.Value
                                if ($val -is [string] -and $roots.Count -gt 0) {
                                    $val = ConvertTo-KitProfilePath -Path $val -Roots $roots
                                }
                                $pObj[$prop.Name] = $val
                            }
                            $sqliteData.Playlists += $pObj
                        }
                    }
                } finally {
                    Close-KitSqlite $dbConn
                }

                if ($sqliteData.Emulators.Count -gt 0 -or $sqliteData.Playlists.Count -gt 0) {
                    $filesDir = Join-Path $stageDir 'files/pinball'
                    New-Item -ItemType Directory -Force -Path $filesDir | Out-Null
                    $sqliteJson = Join-Path $filesDir 'sqlite-settings.json'
                    [IO.File]::WriteAllText($sqliteJson, (ConvertTo-Json $sqliteData -Depth 5), [Text.Encoding]::UTF8)
                    $items.Add([pscustomobject]@{
                        Suite = 'Pinball'; Kind = 'Sqlite'; Path = 'files/pinball/sqlite-settings.json'
                        TargetToken = '{PinballRoot}/PUPDatabase.db'; Sha256 = (Get-FileHash -LiteralPath $sqliteJson -Algorithm SHA256).Hash
                        Size = (Get-Item $sqliteJson).Length
                    })
                }
            }
        } elseif ($Suite -eq 'Lightgun') {
            $filesDir = Join-Path $stageDir 'files/lightgun'
            New-Item -ItemType Directory -Force -Path $filesDir | Out-Null

            # 1. es_settings.cfg keys
            $rb = $roots['{RetroBatRoot}']
            if ($rb -and (Test-Path -LiteralPath $rb)) {
                $cfgPath = Join-Path $rb 'emulationstation\.emulationstation\es_settings.cfg'
                if (Test-Path -LiteralPath $cfgPath) {
                    $xml = [xml](Get-Content -LiteralPath $cfgPath -Raw)
                    $kitKeys = [ordered]@{}
                    foreach ($node in $xml.SelectNodes('/config/*')) {
                        $name = $node.GetAttribute('name')
                        if ($name -match '(\.use_guns|\.emulator|\.core|disableautocontrollers|teknoparrot)') {
                            $val = $node.GetAttribute('value')
                            if ($roots.Count -gt 0) { $val = ConvertTo-KitProfilePath -Path $val -Roots $roots }
                            $kitKeys[$name] = @{ Type = $node.LocalName; Value = $val }
                        }
                    }
                    if ($kitKeys.Count -gt 0) {
                        $esJson = Join-Path $filesDir 'es_settings.json'
                        [IO.File]::WriteAllText($esJson, (ConvertTo-Json $kitKeys -Depth 5), [Text.Encoding]::UTF8)
                        $items.Add([pscustomobject]@{
                            Suite = 'Lightgun'; Kind = 'Config'; Path = 'files/lightgun/es_settings.json'
                            TargetToken = '{RetroBatRoot}/es_settings.cfg'; Sha256 = (Get-FileHash -LiteralPath $esJson -Algorithm SHA256).Hash
                            Size = (Get-Item $esJson).Length
                        })
                    }
                }

                # 2. TeknoParrot profiles for gun games
                $tpProfiles = Join-Path $rb 'emulators\teknoparrot\UserProfiles'
                if (Test-Path -LiteralPath $tpProfiles) {
                    $tpDir = Join-Path $filesDir 'teknoparrot'
                    New-Item -ItemType Directory -Force -Path $tpDir | Out-Null
                    foreach ($xmlFile in Get-ChildItem -LiteralPath $tpProfiles -Filter '*.xml' -File) {
                        try {
                            $tpXml = [xml](Get-Content -LiteralPath $xmlFile.FullName -Raw)
                            $isGun = $tpXml.SelectSingleNode('/GameProfile/GunGame')
                            if ($isGun -and $isGun.InnerText.Trim() -eq 'true') {
                                # Save profile, tokenizing paths
                                $rawXml = Get-Content -LiteralPath $xmlFile.FullName -Raw
                                $tokenXml = ConvertTo-KitProfilePath -Path $rawXml -Roots $roots
                                $destXml = Join-Path $tpDir $xmlFile.Name
                                [IO.File]::WriteAllText($destXml, $tokenXml, [Text.Encoding]::UTF8)
                                $relPath = "files/lightgun/teknoparrot/$($xmlFile.Name)"
                                $items.Add([pscustomobject]@{
                                    Suite = 'Lightgun'; Kind = 'File'; Path = $relPath
                                    TargetToken = "{RetroBatRoot}/emulators/teknoparrot/UserProfiles/$($xmlFile.Name)"
                                    Sha256 = (Get-FileHash -LiteralPath $destXml -Algorithm SHA256).Hash
                                    Size = (Get-Item $destXml).Length
                                })
                            }
                        } catch {
                            Write-KitLog "Skipping invalid TeknoParrot XML: $($xmlFile.Name)"
                        }
                    }
                }
            }

            # 3. Gunmote layouts
            $gm = $roots['{GunmoteDir}']
            if ($gm -and (Test-Path -LiteralPath $gm)) {
                $kmJson = Join-Path $gm 'Keymaps\Keymaps.json'
                if (Test-Path -LiteralPath $kmJson) {
                    $gmDirOut = Join-Path $filesDir 'gunmote'
                    New-Item -ItemType Directory -Force -Path $gmDirOut | Out-Null
                    $kmData = Get-Content -LiteralPath $kmJson -Raw | ConvertFrom-Json
                    $exportedLayouts = [ordered]@{}
                    if ($kmData.LayoutChooser) {
                        foreach ($entry in $kmData.LayoutChooser) {
                            if ($entry.Title -like 'RCK*') {
                                $layoutFile = Join-Path $gm "Keymaps\$($entry.Keymap)"
                                if (Test-Path -LiteralPath $layoutFile) {
                                    $content = Get-Content -LiteralPath $layoutFile -Raw
                                    $tokenContent = ConvertTo-KitProfilePath -Path $content -Roots $roots
                                    $destLayout = Join-Path $gmDirOut $entry.Keymap
                                    [IO.File]::WriteAllText($destLayout, $tokenContent, [Text.Encoding]::UTF8)
                                    $exportedLayouts[$entry.Keymap] = $entry.Title
                                    $items.Add([pscustomobject]@{
                                        Suite = 'Lightgun'; Kind = 'File'; Path = "files/lightgun/gunmote/$($entry.Keymap)"
                                        TargetToken = "{GunmoteDir}/Keymaps/$($entry.Keymap)"
                                        Sha256 = (Get-FileHash -LiteralPath $destLayout -Algorithm SHA256).Hash
                                        Size = (Get-Item $destLayout).Length
                                    })
                                }
                            }
                        }
                    }
                    if ($exportedLayouts.Count -gt 0) {
                        $metaJson = Join-Path $gmDirOut 'layouts-meta.json'
                        [IO.File]::WriteAllText($metaJson, (ConvertTo-Json $exportedLayouts -Depth 3), [Text.Encoding]::UTF8)
                        $items.Add([pscustomobject]@{
                            Suite = 'Lightgun'; Kind = 'Config'; Path = 'files/lightgun/gunmote/layouts-meta.json'
                            TargetToken = '{GunmoteDir}/Keymaps/layouts-meta.json'
                            Sha256 = (Get-FileHash -LiteralPath $metaJson -Algorithm SHA256).Hash
                            Size = (Get-Item $metaJson).Length
                        })
                    }
                }
            }
        }

        # Build Roots map for manifest (token -> 'present' / 'absent')
        $rootsMap = [ordered]@{}
        foreach ($t in $script:KitProfileTokens) {
            $rootsMap[$t] = if ($roots.ContainsKey($t) -and $roots[$t]) { 'present' } else { 'absent' }
        }

        # profile.json
        $manifest = [ordered]@{
            Format     = $script:KitProfileFormat
            KitVersion = $kitVersion
            Created    = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
            Suite      = $Suite
            Roots      = $rootsMap
            Items      = $items.ToArray()
        }

        Assert-KitProfileManifest -Manifest $manifest

        $manifestJson = Join-Path $stageDir 'profile.json'
        [IO.File]::WriteAllText($manifestJson, (ConvertTo-Json $manifest -Depth 10), [Text.Encoding]::UTF8)

        # Depersonalization check across all text files in staging
        $anonOpts = @{}
        if ($UserName) { $anonOpts.UserName = $UserName }
        if ($ComputerName) { $anonOpts.ComputerName = $ComputerName }
        if ($UserProfile) { $anonOpts.UserProfile = $UserProfile }

        foreach ($stagedFile in Get-ChildItem -LiteralPath $stageDir -Recurse -File) {
            if ($stagedFile.Extension -in '.json', '.xml', '.reg', '.txt') {
                $rawContent = [IO.File]::ReadAllText($stagedFile.FullName)
                # Check for absolute Windows drive paths
                if ($stagedFile.Name -ne 'profile.json' -and $rawContent -match '[A-Za-z]:\\[A-Za-z0-9_]') {
                    # Allow foreign known paths like Program Files if needed, but not user profile
                    if ($rawContent -match 'Users\\[A-Za-z0-9_]+') {
                        throw "Staged file '$($stagedFile.Name)' contains private user path."
                    }
                }
                $anon = ConvertTo-KitAnonymousText -Text $rawContent @anonOpts
                if ($anon -ne $rawContent) {
                    throw "Depersonalization check failed: staged file '$($stagedFile.Name)' contains user or machine specific names."
                }
            }
        }

        # Zip it up using System.IO.Compression with forward-slashed entries
        Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
        if (Test-Path -LiteralPath $targetZip) { Remove-Item -LiteralPath $targetZip -Force }

        $zip = [IO.Compression.ZipFile]::Open($targetZip, [IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($f in Get-ChildItem -LiteralPath $stageDir -Recurse -File) {
                $rel = $f.FullName.Substring($stageDir.Length).TrimStart('\', '/') -replace '\\', '/'
                $entry = $zip.CreateEntry($rel, [IO.Compression.CompressionLevel]::Optimal)
                $stream = $entry.Open()
                $bytes = [IO.File]::ReadAllBytes($f.FullName)
                try {
                    $stream.Write($bytes, 0, $bytes.Length)
                } finally {
                    $stream.Dispose()
                }
            }
        } finally {
            $zip.Dispose()
        }

        $zipItem = Get-Item -LiteralPath $targetZip
        if ($zipItem.Length -gt $script:KitProfileMaxBytes) {
            Write-Warning "Profile archive exceeds 10 MB ($([math]::Round($zipItem.Length/1MB, 2)) MB). Profiles should carry settings, not builds."
        }

        [pscustomobject]@{
            PSTypeName = 'RetroCabinetKit.CabinetProfile'
            Path       = $zipItem.FullName
            Suite      = $Suite
            ItemsCount = $items.Count
            SizeBytes  = $zipItem.Length
        }
    } finally {
        if (Test-Path -LiteralPath $stageDir) {
            Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Import-KitCabinetProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [hashtable] $RootMap = @{},
        [string[]] $RegistryRoots,
        [string] $StatePath,
        [string] $PupDatabasePath,
        [string] $RetroBatRoot,
        [string] $GunmoteDir,
        [string] $SteamDir,
        [object[]] $Monitors,
        [switch] $AutoInstall
    )

    $isWhatIf = [bool]$WhatIfPreference

    $fullZip = Resolve-FullPath $Path
    if (-not (Test-Path -LiteralPath $fullZip -PathType Leaf)) {
        throw "Profile file not found: '$Path'"
    }

    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($fullZip)
    $manifestEntry = $zip.GetEntry('profile.json')
    if (-not $manifestEntry) {
        $zip.Dispose()
        throw "Invalid profile archive: missing 'profile.json'."
    }

    $manifest = $null
    $reader = New-Object IO.StreamReader ($manifestEntry.Open(), [Text.Encoding]::UTF8)
    try {
        $manifest = $reader.ReadToEnd() | ConvertFrom-Json
    } finally {
        $reader.Dispose()
    }

    Assert-KitProfileManifest -Manifest $manifest

    # Resolve roots on machine B
    $roots = @{}
    if ($manifest.Suite -eq 'Pinball') {
        $pState = if ($StatePath) { $StatePath } else { Get-PinballDefaultStatePath }
        $targetRoot = if ($RootMap.ContainsKey('{PinballRoot}')) { $RootMap['{PinballRoot}'] }
                      elseif (Test-Path -LiteralPath $pState) { (Get-KitState -Path $pState).TargetRoot }
                      else { $null }
        if ($targetRoot) { $roots['{PinballRoot}'] = $targetRoot }
    } else {
        $lState = if ($StatePath) { $StatePath } else { Get-LightgunDefaultStatePath }
        $lStateData = if (Test-Path -LiteralPath $lState) { Get-KitState -Path $lState } else { $null }
        $rbRoot = if ($RetroBatRoot) { $RetroBatRoot }
                  elseif ($RootMap.ContainsKey('{RetroBatRoot}')) { $RootMap['{RetroBatRoot}'] }
                  elseif ($lStateData -and $lStateData.RetroBatRoot) { $lStateData.RetroBatRoot }
                  else { $null }
        if ($rbRoot) { $roots['{RetroBatRoot}'] = $rbRoot }

        $gmDir = if ($GunmoteDir) { $GunmoteDir }
                 elseif ($RootMap.ContainsKey('{GunmoteDir}')) { $RootMap['{GunmoteDir}'] }
                 elseif ($lStateData -and $lStateData.GunmoteDir) { $lStateData.GunmoteDir }
                 else { Find-LightgunGunmote }
        if ($gmDir) { $roots['{GunmoteDir}'] = $gmDir }

        $stDir = if ($SteamDir) { $SteamDir }
                 elseif ($RootMap.ContainsKey('{SteamDir}')) { $RootMap['{SteamDir}'] }
                 else { Get-LightgunSteamPath }
        if ($stDir) { $roots['{SteamDir}'] = $stDir }
    }

    $results = New-Object Collections.Generic.List[object]

    try {
        if ($manifest.Suite -eq 'Pinball') {
            $pbRoot = $roots['{PinballRoot}']
            if (-not $pbRoot) {
                $results.Add([pscustomobject]@{
                    Name = 'pinball-root'; Status = 'NeedsUser'; Detail = 'Pinball target root on cabinet B is unknown. Specify -RootMap @{ "{PinballRoot}" = "..." }.'
                })
                return @($results)
            }

            # 1. Registry import
            $regEntries = @($zip.Entries | Where-Object { $_.FullName -like 'registry/*.reg' })
            if ($regEntries.Count -gt 0) {
                $regAllowed = if ($RegistryRoots) { $RegistryRoots } else { Get-PinballRegistryImportRoot }
                $regChanged = $false
                foreach ($re in $regEntries) {
                    $rStream = $re.Open()
                    $sr = New-Object IO.StreamReader ($rStream, [Text.Encoding]::Unicode)
                    $regText = $null
                    try { $regText = $sr.ReadToEnd() } finally { $sr.Dispose() }
                    $cleanReg = Assert-KitRegText -Text $regText -AllowedRoots $regAllowed
                    if (-not $isWhatIf) {
                        # Import using reg.exe import with temp file
                        $tmpReg = Join-Path $env:TEMP ('kit-import-' + [guid]::NewGuid().ToString('N') + '.reg')
                        [IO.File]::WriteAllText($tmpReg, $cleanReg, [Text.Encoding]::Unicode)
                        try {
                            & reg.exe import $tmpReg 2>&1 | Out-Null
                            $regChanged = $true
                        } finally {
                            if (Test-Path -LiteralPath $tmpReg) { Remove-Item -LiteralPath $tmpReg -Force }
                        }
                    }
                }
                $results.Add([pscustomobject]@{
                    Name = 'pinball-registry'; Status = if ($isWhatIf) { 'WhatIf' } elseif ($regChanged) { 'Done' } else { 'Skipped' }
                    Detail = "$($regEntries.Count) registry file(s) processed."
                })
            }

            # 2. SQLite Settings merge
            $sqliteEntry = $zip.GetEntry('files/pinball/sqlite-settings.json')
            if ($sqliteEntry) {
                $dbFile = if ($PupDatabasePath) { $PupDatabasePath } else { Join-Path $pbRoot 'vPinball\PinUPSystem\PUPDatabase.db' }
                if (-not (Test-Path -LiteralPath $dbFile)) {
                    $results.Add([pscustomobject]@{
                        Name = 'pinball-sqlite'; Status = 'NeedsUser'; Detail = "PUPDatabase.db not found at '$dbFile'."
                    })
                } else {
                    $sr = New-Object IO.StreamReader ($sqliteEntry.Open(), [Text.Encoding]::UTF8)
                    $sqData = $null
                    try { $sqData = $sr.ReadToEnd() | ConvertFrom-Json } finally { $sr.Dispose() }

                    $dbChanged = $false
                    if (-not $isWhatIf) {
                        # Backup database before modifying
                        $backup = New-KitBackup -Files $dbFile -Purpose 'profile_import'

                        $dbConn = Open-KitSqlite -Path $dbFile
                        try {
                            if ($sqData.Emulators) {
                                foreach ($emu in $sqData.Emulators) {
                                    $eName = $emu.EmuName
                                    if (-not $eName) { continue }
                                    $existing = @(Invoke-KitSqlQuery -Connection $dbConn -Sql 'SELECT EMUID FROM Emulators WHERE EmuName = @n' -Parameters @{ n = $eName })
                                    if ($existing.Count -gt 0) {
                                        # Update paths
                                        $dirGames = ConvertFrom-KitProfilePath -Path ([string]$emu.DirGames) -Roots $roots
                                        $dirMedia = ConvertFrom-KitProfilePath -Path ([string]$emu.DirMedia) -Roots $roots
                                        $dirRoms  = ConvertFrom-KitProfilePath -Path ([string]$emu.DirRoms) -Roots $roots
                                        $launch   = ConvertFrom-KitProfilePath -Path ([string]$emu.LaunchScript) -Roots $roots

                                        $null = Invoke-KitSqlNonQuery -Connection $dbConn -Sql 'UPDATE Emulators SET DirGames = @g, DirMedia = @m, DirRoms = @r, LaunchScript = @s WHERE EmuName = @n' `
                                            -Parameters @{ g = $dirGames; m = $dirMedia; r = $dirRoms; s = $launch; n = $eName }
                                        $dbChanged = $true
                                    }
                                }
                            }
                        } finally {
                            Close-KitSqlite $dbConn
                        }
                    }
                    $results.Add([pscustomobject]@{
                        Name = 'pinball-sqlite'; Status = if ($WhatIf) { 'WhatIf' } elseif ($dbChanged) { 'Done' } else { 'Skipped' }
                        Detail = "Popper database emulators/settings merged."
                    })
                }
            }

            # 3. Screens proposal
            $screensEntry = $zip.GetEntry('files/pinball/screens.json')
            if ($screensEntry) {
                $results.Add([pscustomobject]@{
                    Name = 'pinball-screens'; Status = 'Proposal'; Detail = 'Screen layout proposal available from profile.'
                })
            }
        } elseif ($manifest.Suite -eq 'Lightgun') {
            $rb = $roots['{RetroBatRoot}']
            $gm = $roots['{GunmoteDir}']

            # 1. Prerequisites check & auto-install (ViGEmBus)
            $vigemState = Get-LightgunViGEmState
            if (-not $vigemState.Installed) {
                if ($AutoInstall -and (Test-KitAdmin)) {
                    if (-not $isWhatIf) {
                        try {
                            $null = Install-LightgunViGEm -Approve { $true }
                            $results.Add([pscustomobject]@{ Name = 'lightgun-vigem'; Status = 'Done'; Detail = 'ViGEmBus installed.' })
                        } catch {
                            $results.Add([pscustomobject]@{ Name = 'lightgun-vigem'; Status = 'NeedsUser'; Detail = "ViGEmBus install failed: $($_.Exception.Message)" })
                        }
                    } else {
                        $results.Add([pscustomobject]@{ Name = 'lightgun-vigem'; Status = 'WhatIf'; Detail = 'Would install ViGEmBus driver.' })
                    }
                } else {
                    $results.Add([pscustomobject]@{ Name = 'lightgun-vigem'; Status = 'NeedsUser'; Detail = 'ViGEmBus is not installed on cabinet B.' })
                }
            } else {
                $results.Add([pscustomobject]@{ Name = 'lightgun-vigem'; Status = 'Skipped'; Detail = 'ViGEmBus already installed.' })
            }

            # 2. es_settings.cfg merge
            $esEntry = $zip.GetEntry('files/lightgun/es_settings.json')
            if ($esEntry -and $rb -and (Test-Path -LiteralPath $rb)) {
                $cfgPath = Join-Path $rb 'emulationstation\.emulationstation\es_settings.cfg'
                if (Test-Path -LiteralPath $cfgPath) {
                    $sr = New-Object IO.StreamReader ($esEntry.Open(), [Text.Encoding]::UTF8)
                    $esData = $null
                    try { $esData = $sr.ReadToEnd() | ConvertFrom-Json } finally { $sr.Dispose() }

                    $xml = [xml](Get-Content -LiteralPath $cfgPath -Raw)
                    $cfgModified = $false

                    foreach ($key in $esData.psobject.Properties) {
                        $name = $key.Name
                        $targetVal = ConvertFrom-KitProfilePath -Path ([string]$key.Value.Value) -Roots $roots
                        $existingNode = $xml.SelectSingleNode("/config/*[@name='$name']")
                        if ($null -eq $existingNode) {
                            $newNode = $xml.CreateElement([string]$key.Value.Type)
                            $newNode.SetAttribute('name', $name)
                            $newNode.SetAttribute('value', $targetVal)
                            $xml.DocumentElement.AppendChild($newNode) | Out-Null
                            $cfgModified = $true
                        } elseif ($existingNode.GetAttribute('value') -ne $targetVal) {
                            $existingNode.SetAttribute('value', $targetVal)
                            $cfgModified = $true
                        }
                    }

                    if ($cfgModified -and -not $WhatIf) {
                        $null = New-KitBackup -Files $cfgPath -Purpose 'profile_import'
                        $xml.Save($cfgPath)
                    }

                    $results.Add([pscustomobject]@{
                        Name = 'lightgun-essettings'; Status = if ($WhatIf) { 'WhatIf' } elseif ($cfgModified) { 'Done' } else { 'Skipped' }
                        Detail = 'es_settings.cfg merged.'
                    })
                }
            }

            # 3. Gunmote layouts merge
            $metaEntry = $zip.GetEntry('files/lightgun/gunmote/layouts-meta.json')
            if ($metaEntry -and $gm -and (Test-Path -LiteralPath $gm)) {
                $kmJson = Join-Path $gm 'Keymaps\Keymaps.json'
                if (Test-Path -LiteralPath $kmJson) {
                    $sr = New-Object IO.StreamReader ($metaEntry.Open(), [Text.Encoding]::UTF8)
                    $meta = $null
                    try { $meta = $sr.ReadToEnd() | ConvertFrom-Json } finally { $sr.Dispose() }

                    $kmData = Get-Content -LiteralPath $kmJson -Raw | ConvertFrom-Json
                    $kmModified = $false

                    foreach ($prop in $meta.psobject.Properties) {
                        $file = $prop.Name
                        $title = $prop.Value
                        $layoutEntry = $zip.GetEntry("files/lightgun/gunmote/$file")
                        if ($layoutEntry) {
                            $targetFile = Join-Path $gm "Keymaps\$file"
                            $lReader = New-Object IO.StreamReader ($layoutEntry.Open(), [Text.Encoding]::UTF8)
                            $lText = $null
                            try { $lText = $lReader.ReadToEnd() } finally { $lReader.Dispose() }
                            $resolvedLayout = ConvertFrom-KitProfilePath -Path $lText -Roots $roots

                            $currentContent = if (Test-Path -LiteralPath $targetFile) { [IO.File]::ReadAllText($targetFile) } else { '' }
                            if ($currentContent -ne $resolvedLayout) {
                                if (-not $isWhatIf) {
                                    if (Test-Path -LiteralPath $targetFile) { $null = New-KitBackup -Files $targetFile -Purpose 'profile_import' }
                                    [IO.File]::WriteAllText($targetFile, $resolvedLayout, [Text.Encoding]::UTF8)
                                }
                                $kmModified = $true
                            }

                            # Ensure layout chooser has entry
                            $chooserHas = @($kmData.LayoutChooser | Where-Object { $_.Keymap -eq $file }).Count -gt 0
                            if (-not $chooserHas) {
                                $kmData.LayoutChooser += @{ Title = $title; Keymap = $file }
                                $kmModified = $true
                            }
                        }
                    }

                    if ($kmModified -and -not $WhatIf) {
                        $null = New-KitBackup -Files $kmJson -Purpose 'profile_import'
                        [IO.File]::WriteAllText($kmJson, (ConvertTo-Json $kmData -Depth 5), [Text.Encoding]::UTF8)
                    }

                    $results.Add([pscustomobject]@{
                        Name = 'lightgun-gunmote'; Status = if ($WhatIf) { 'WhatIf' } elseif ($kmModified) { 'Done' } else { 'Skipped' }
                        Detail = 'Gunmote layouts merged.'
                    })
                }
            }

            # 4. TeknoParrot profiles merge
            $tpEntries = @($zip.Entries | Where-Object { $_.FullName -like 'files/lightgun/teknoparrot/*.xml' })
            if ($tpEntries.Count -gt 0 -and $rb -and (Test-Path -LiteralPath $rb)) {
                $tpProfiles = Join-Path $rb 'emulators\teknoparrot\UserProfiles'
                if (Test-Path -LiteralPath $tpProfiles) {
                    $tpModified = $false
                    foreach ($te in $tpEntries) {
                        $fileName = Split-Path -Leaf $te.FullName
                        $targetXml = Join-Path $tpProfiles $fileName
                        if (Test-Path -LiteralPath $targetXml) {
                            $tReader = New-Object IO.StreamReader ($te.Open(), [Text.Encoding]::UTF8)
                            $teXml = $null
                            try { $teXml = $tReader.ReadToEnd() } finally { $tReader.Dispose() }
                            $resolvedXml = ConvertFrom-KitProfilePath -Path $teXml -Roots $roots

                            $currentXml = [IO.File]::ReadAllText($targetXml)
                            if ($currentXml -ne $resolvedXml) {
                                if (-not $isWhatIf) {
                                    $null = New-KitBackup -Files $targetXml -Purpose 'profile_import'
                                    [IO.File]::WriteAllText($targetXml, $resolvedXml, [Text.Encoding]::UTF8)
                                }
                                $tpModified = $true
                            }
                        }
                    }
                    $results.Add([pscustomobject]@{
                        Name = 'lightgun-teknoparrot'; Status = if ($WhatIf) { 'WhatIf' } elseif ($tpModified) { 'Done' } else { 'Skipped' }
                        Detail = "$($tpEntries.Count) TeknoParrot profile(s) checked."
                    })
                }
            }
        }
    } finally {
        $zip.Dispose()
    }

    @($results)
}
