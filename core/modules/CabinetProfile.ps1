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
            if ($sub) { return "$token/$sub" -replace '\\', '/' }
            return $token
        }
    }
    $res
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

function ConvertTo-KitProfileText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text,
        [Parameter(Mandatory)] [hashtable] $Roots
    )
    $res = $Text
    foreach ($token in $Roots.Keys | Sort-Object { $Roots[$_].Length } -Descending) {
        $rootVal = $Roots[$token]
        if (-not $rootVal) { continue }
        $cleanRoot = $rootVal.TrimEnd('\', '/')
        $rootDbl = $cleanRoot.Replace('\', '\\')   # .reg files double every backslash
        $rootFwd = $cleanRoot.Replace('\', '/')
        $res = [regex]::Replace($res, [regex]::Escape($rootDbl), $token, 'IgnoreCase')
        $res = [regex]::Replace($res, [regex]::Escape($cleanRoot), $token, 'IgnoreCase')
        $res = [regex]::Replace($res, [regex]::Escape($rootFwd), $token, 'IgnoreCase')
    }
    $res
}

function ConvertFrom-KitProfileText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text,
        [Parameter(Mandatory)] [hashtable] $Roots,
        [switch] $DoubleBackslash
    )
    $res = $Text
    foreach ($token in $Roots.Keys | Sort-Object { $_.Length } -Descending) {
        $rootVal = $Roots[$token]
        if (-not $rootVal) { continue }
        $cleanRoot = $rootVal.TrimEnd('\', '/')
        if ($DoubleBackslash) { $cleanRoot = $cleanRoot.Replace('\', '\\') }
        $repl = $cleanRoot.Replace('$', '$$')      # keep '$' literal in the replacement
        $res = [regex]::Replace($res, [regex]::Escape($token), $repl, 'IgnoreCase')
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
    if ($jsonText -match '(?<![A-Za-z0-9_])[A-Za-z]:\\\\' -or $jsonText -match '\\\\\\\\[A-Za-z0-9_]+') {
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
                            # Tokenize in place: a .reg carries its paths with doubled backslashes
                            # (REG_SZ escaping), so no absolute machine path may survive into the zip.
                            if ($roots.Count -gt 0) {
                                $regRaw = [IO.File]::ReadAllText($regFile) # detects the UTF-16LE BOM of reg export
                                $regTok = ConvertTo-KitProfileText -Text $regRaw -Roots $roots
                                [IO.File]::WriteAllText($regFile, $regTok, [Text.Encoding]::Unicode)
                            }
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
                    $screenItems['ScreenRes'] = ConvertTo-KitProfileText -Text (Get-Content -LiteralPath $screenResPath -Raw) -Roots $roots
                }
                $vpxIni = Join-Path $pbRoot 'vPinball\VisualPinball\VPinballX.ini'
                if (Test-Path -LiteralPath $vpxIni) {
                    $screenItems['VPinballX'] = ConvertTo-KitProfileText -Text (Get-Content -LiteralPath $vpxIni -Raw) -Roots $roots
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
                                    # Text form: embedded paths inside LaunchScript get tokenized too
                                    $val = ConvertTo-KitProfileText -Text $val -Roots $roots
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
                                    # Text form: embedded paths inside LaunchScript get tokenized too
                                    $val = ConvertTo-KitProfileText -Text $val -Roots $roots
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
                                $tokenXml = ConvertTo-KitProfileText -Text $rawXml -Roots $roots
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
                                    $tokenContent = ConvertTo-KitProfileText -Text $content -Roots $roots
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
                if ($stagedFile.Name -ne 'profile.json' -and $rawContent -match '(?<![A-Za-z0-9_])[A-Za-z]:\\[A-Za-z0-9_]') {
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

function Backup-ProfileFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [string] $Purpose = 'profile'
    )
    $backup = '{0}.bak_{1}_{2:yyyyMMdd-HHmmss-fff}' -f $Path, $Purpose, (Get-Date)
    Copy-Item -LiteralPath $Path -Destination $backup
    Write-KitLog "Profile import backup: $backup"
    $backup
}

# Long form inside a .reg back to a provider path: HKEY_CURRENT_USER\X -> HKCU:\X.
function ConvertFrom-RegFileKey([string] $Key) {
    $k = $Key.Trim()
    if ($k.StartsWith('[') -and $k.EndsWith(']')) { $k = $k.Substring(1, $k.Length - 2) }
    ($k -replace '^HKEY_CURRENT_USER(?=\\|$)', 'HKCU:\' -replace '^HKEY_LOCAL_MACHINE(?=\\|$)', 'HKLM:\' `
        -replace '^HKEY_USERS(?=\\|$)', 'HKU:\' -replace '^HKEY_CLASSES_ROOT(?=\\|$)', 'HKCR:\')
}

# Verify-first for a checked .reg text (output of Assert-KitRegText): true only when every REG_SZ/REG_DWORD
# value it would write is already present with the same data. Hex forms (EXPAND_SZ, MULTI_SZ, BINARY) and
# continued lines cannot be proven -> false, so the merge runs again (merging the same data is harmless).
function Test-KitRegTextApplied {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Text)
    $cur = $null
    foreach ($line in ($Text -split '\r?\n')) {
        $t = $line.Trim()
        if (-not $t -or $t.StartsWith(';')) { continue }
        if ($t.StartsWith('[')) { $cur = ConvertFrom-RegFileKey $t; continue }
        if (-not $cur) { continue }
        if ($t -match '^(?:"((?:[^"\\]|\\.)*)"|@)\s*=\s*(.*)$') {
            if ($Matches[2].EndsWith('\')) { return $false } # continuation line, not provable
            $name = if ($Matches[1]) { [regex]::Replace($Matches[1], '\\(.)', '$1') } else { '' }
            $keyObj = Get-Item -LiteralPath $cur -ErrorAction SilentlyContinue
            if (-not $keyObj) { return $false }
            $existing = $keyObj.GetValue($name, $null, 'DoNotExpandEnvironmentNames')
            if ($null -eq $existing) { return $false }
            $d = $Matches[2].Trim()
            if ($d.StartsWith('"') -and $d.EndsWith('"')) {
                $want = [regex]::Replace($d.Substring(1, $d.Length - 2), '\\(.)', '$1')
                if ($existing -isnot [string] -or $existing -ne $want) { return $false }
            } elseif ($d -match '^dword:([0-9a-fA-F]{8})$') {
                if ([long]$existing -ne [long]('0x' + $Matches[1])) { return $false }
            } else {
                return $false
            }
        }
    }
    $true
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

    if ($manifest.PSObject.Properties['KitVersion'] -and $manifest.KitVersion) {
        $versionFileB = Join-Path (Split-Path -Parent $PSScriptRoot) 'VERSION'
        $localVersion = if (Test-Path -LiteralPath $versionFileB) { ([IO.File]::ReadAllText($versionFileB)).Trim() } else { '0.1.0' }
        if ($manifest.KitVersion -ne $localVersion) {
            Write-Warning "Profile was created with kit version $($manifest.KitVersion); this kit is $localVersion."
        }
    }

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
                $out = New-Object object[] $results.Count
                [void]$results.CopyTo($out)
                return $out
            }

            # 1. Registry import: remap A's key roots onto B's roots, validate, merge - and verify first,
            #    so a second import stays idle (Skipped).
            $regEntries = @($zip.Entries | Where-Object { $_.FullName -like 'registry/*.reg' } | Sort-Object FullName)
            if ($regEntries.Count -gt 0) {
                # @() around the if-assignment: a single-element string[] unwraps to String otherwise,
                # and StrictMode 2.0 refuses .Count on it.
                $regAllowed = @(if ($RegistryRoots) { $RegistryRoots } else { Get-PinballRegistryImportRoot })
                $regItems = @($manifest.Items | Where-Object { $_.Kind -eq 'Registry' } | Sort-Object Path)
                $regHandled = $true
                $regImported = $false
                for ($i = 0; $i -lt $regEntries.Count; $i++) {
                    $re = $regEntries[$i]
                    $sourceKey = if ($i -lt $regItems.Count -and $regItems[$i].PSObject.Properties['Key']) { [string]$regItems[$i].Key } else { $null }
                    # Target root: identity when A's root is also allowed on B, else positional pairing
                    # with -RegistryRoots (the list the operator maintains on both cabinets).
                    $targetKey = $null
                    if ($sourceKey) {
                        $srcLong = ConvertTo-RegFileKey $sourceKey
                        $same = @($regAllowed | Where-Object { (ConvertTo-RegFileKey $_) -ieq $srcLong } | Select-Object -First 1)
                        if ($same.Count -gt 0) { $targetKey = [string]$same[0] }
                        elseif ($i -lt $regAllowed.Count) { $targetKey = [string]$regAllowed[$i] }
                    } elseif ($i -lt $regAllowed.Count) { $targetKey = [string]$regAllowed[$i] }
                    if (-not $targetKey) {
                        $results.Add([pscustomobject]@{
                            Name = 'pinball-registry'; Status = 'NeedsUser'
                            Detail = "No target registry root for '$($re.FullName)'. Pass -RegistryRoots with one root per exported key."
                        })
                        $regHandled = $false
                        break
                    }
                    $rStream = $re.Open()
                    $sr = New-Object IO.StreamReader ($rStream, [Text.Encoding]::Unicode)
                    try { $regText = $sr.ReadToEnd() } finally { $sr.Dispose() }
                    $mapped = ConvertFrom-KitProfileText -Text $regText -Roots $roots -DoubleBackslash
                    if ($sourceKey) {
                        $srcLong = ConvertTo-RegFileKey $sourceKey
                        $dstLong = ConvertTo-RegFileKey $targetKey
                        $rep = $dstLong.Replace('$', '$$')
                        $mapped = [regex]::Replace($mapped, '(?m)^\[' + [regex]::Escape($srcLong) + '(?=\\|\])', ('[' + $rep), 'IgnoreCase')
                    }
                    $checked = Assert-KitRegText -Text $mapped -AllowedRoots $regAllowed
                    if ($isWhatIf) { continue }
                    if (-not (Test-KitRegTextApplied -Text $checked)) {
                        $tmpReg = Join-Path $env:TEMP ('kit-import-' + [guid]::NewGuid().ToString('N') + '.reg')
                        try {
                            [IO.File]::WriteAllText($tmpReg, $checked, [Text.Encoding]::Unicode)
                            Import-KitRegistryFile -Path $tmpReg -AllowedRoots $regAllowed
                            $regImported = $true
                        } finally {
                            if (Test-Path -LiteralPath $tmpReg) { Remove-Item -LiteralPath $tmpReg -Force }
                        }
                    }
                }
                if ($regHandled) {
                    $results.Add([pscustomobject]@{
                        Name = 'pinball-registry'; Status = if ($isWhatIf) { 'WhatIf' } elseif ($regImported) { 'Done' } else { 'Skipped' }
                        Detail = "$($regEntries.Count) registry file(s) processed."
                    })
                }
            }

            # 2. SQLite Settings merge: existing rows only, existing columns only (the real Popper schema
            #    varies by version - never guess, read PRAGMA), backup before the first write.
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

                    $updates = New-Object Collections.Generic.List[object]
                    $dbConn = Open-KitSqlite -Path $dbFile -ReadOnly
                    try {
                        foreach ($tablePair in @(@('Emulators', 'EmuName', $sqData.Emulators), @('Playlists', 'Name', $sqData.Playlists))) {
                            $table = $tablePair[0]; $nameCol = $tablePair[1]; $rows = @($tablePair[2])
                            if ($rows.Count -eq 0 -or -not $rows[0]) { continue }
                            $hasTable = @(Invoke-KitSqlQuery -Connection $dbConn -Sql "SELECT name FROM sqlite_master WHERE type='table' AND name='$table'").Count -gt 0
                            if (-not $hasTable) { continue }
                            $cols = @(Invoke-KitSqlQuery -Connection $dbConn -Sql "PRAGMA table_info($table)") | ForEach-Object { $_.name }
                            if ($cols -notcontains $nameCol) {
                                if ($table -eq 'Playlists' -and $cols -contains 'PlaylistName') { $nameCol = 'PlaylistName' } else { continue }
                            }
                            foreach ($row in $rows) {
                                $rowName = if ($row.PSObject.Properties[$nameCol]) { [string]$row.$nameCol } else { $null }
                                if (-not $rowName) { continue }
                                $existing = @(Invoke-KitSqlQuery -Connection $dbConn -Sql "SELECT * FROM $table WHERE $nameCol = @n" -Parameters @{ n = $rowName })
                                if ($existing.Count -eq 0) { continue }
                                $cur = $existing[0]
                                $set = [ordered]@{}
                                foreach ($p in $row.PSObject.Properties) {
                                    if ($p.Name -eq $nameCol) { continue }
                                    if ($p.Value -isnot [string]) { continue }
                                    if ($cols -notcontains $p.Name) { continue }
                                    $resolved = ConvertFrom-KitProfileText -Text ([string]$p.Value) -Roots $roots
                                    $curVal = if ($cur.PSObject.Properties[$p.Name]) { [string]$cur.($p.Name) } else { $null }
                                    if ($curVal -ne $resolved) { $set[$p.Name] = $resolved }
                                }
                                if ($set.Count -gt 0) {
                                    $updates.Add([pscustomobject]@{ Table = $table; NameCol = $nameCol; Name = $rowName; Set = $set })
                                }
                            }
                        }
                    } finally {
                        Close-KitSqlite $dbConn
                    }

                    $dbChanged = $false
                    if ($updates.Count -gt 0 -and -not $isWhatIf) {
                        # Backup database before modifying
                        $backupZip = Join-Path (Split-Path -Parent $dbFile) ('PUPDatabase_backup_{0:yyyyMMdd-HHmmss}.zip' -f (Get-Date))
                        $null = New-KitBackup -Files @($dbFile) -Destination $backupZip

                        $dbConn = Open-KitSqlite -Path $dbFile
                        try {
                            foreach ($u in $updates) {
                                $assignments = foreach ($colName in $u.Set.Keys) { "[$colName] = @$colName" }
                                $sql = 'UPDATE [{0}] SET {1} WHERE [{2}] = @n' -f $u.Table, ($assignments -join ', '), $u.NameCol
                                $params = @{ n = $u.Name }
                                foreach ($colName in $u.Set.Keys) { $params[$colName] = $u.Set[$colName] }
                                $null = Invoke-KitSqlNonQuery -Connection $dbConn -Sql $sql -Parameters $params
                            }
                            $dbChanged = $true
                        } finally {
                            Close-KitSqlite $dbConn
                        }
                    }
                    $results.Add([pscustomobject]@{
                        Name = 'pinball-sqlite'; Status = if ($isWhatIf) { 'WhatIf' } elseif ($dbChanged) { 'Done' } else { 'Skipped' }
                        Detail = "$($updates.Count) emulator/playlist row(s) differ from cabinet B."
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
            if ($esEntry) {
                $cfgPath = if ($rb -and (Test-Path -LiteralPath $rb)) { Join-Path $rb 'emulationstation\.emulationstation\es_settings.cfg' } else { $null }
                if (-not $cfgPath -or -not (Test-Path -LiteralPath $cfgPath)) {
                    $results.Add([pscustomobject]@{
                        Name = 'lightgun-essettings'; Status = 'NeedsUser'
                        Detail = 'RetroBat with es_settings.cfg not found on cabinet B. Finish the RetroBat install (lightgun steps 1-2), then import again.'
                    })
                } else {
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

                    if ($cfgModified -and -not $isWhatIf) {
                        $null = Backup-ProfileFile -Path $cfgPath -Purpose 'profile'
                        $xml.Save($cfgPath)
                    }

                    $results.Add([pscustomobject]@{
                        Name = 'lightgun-essettings'; Status = if ($isWhatIf) { 'WhatIf' } elseif ($cfgModified) { 'Done' } else { 'Skipped' }
                        Detail = 'es_settings.cfg merged.'
                    })
                }
            }

            # 3. Gunmote layouts merge
            $metaEntry = $zip.GetEntry('files/lightgun/gunmote/layouts-meta.json')
            if ($metaEntry) {
                $kmJson = if ($gm -and (Test-Path -LiteralPath $gm)) { Join-Path $gm 'Keymaps\Keymaps.json' } else { $null }
                if (-not $kmJson -or -not (Test-Path -LiteralPath $kmJson)) {
                    $results.Add([pscustomobject]@{
                        Name = 'lightgun-gunmote'; Status = 'NeedsUser'
                        Detail = 'Gunmote with Keymaps\Keymaps.json not found on cabinet B. Run lightgun step 4, then import again.'
                    })
                } else {
                    $sr = New-Object IO.StreamReader ($metaEntry.Open(), [Text.Encoding]::UTF8)
                    $meta = $null
                    try { $meta = $sr.ReadToEnd() | ConvertFrom-Json } finally { $sr.Dispose() }

                    $kmData = Get-Content -LiteralPath $kmJson -Raw | ConvertFrom-Json
                    $kmModified = $false
                    $gmRefused = $false

                    foreach ($prop in $meta.psobject.Properties) {
                        $file = $prop.Name
                        $title = [string]$prop.Value
                        # The meta file is untrusted: refuse traversal and anything outside Gunmote\Keymaps.
                        Assert-KitProfilePathSafe -Path $file
                        $targetFile = Join-Path $gm "Keymaps\$file"
                        if (-not (Test-KitPathUnder -Path $targetFile -Root @((Join-Path $gm 'Keymaps')))) {
                            $results.Add([pscustomobject]@{
                                Name = 'lightgun-gunmote'; Status = 'NeedsUser'
                                Detail = "Refused layout '$file' outside the Gunmote Keymaps folder."
                            })
                            $gmRefused = $true
                            break
                        }
                        $layoutEntry = $zip.GetEntry("files/lightgun/gunmote/$file")
                        if ($layoutEntry) {
                            $lReader = New-Object IO.StreamReader ($layoutEntry.Open(), [Text.Encoding]::UTF8)
                            $lText = $null
                            try { $lText = $lReader.ReadToEnd() } finally { $lReader.Dispose() }
                            $resolvedLayout = ConvertFrom-KitProfileText -Text $lText -Roots $roots

                            $currentContent = if (Test-Path -LiteralPath $targetFile) { [IO.File]::ReadAllText($targetFile) } else { '' }
                            if ($currentContent -ne $resolvedLayout) {
                                if (-not $isWhatIf) {
                                    if (Test-Path -LiteralPath $targetFile) { $null = Backup-ProfileFile -Path $targetFile -Purpose 'profile' }
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

                    if (-not $gmRefused) {
                        if ($kmModified -and -not $isWhatIf) {
                            $null = Backup-ProfileFile -Path $kmJson -Purpose 'profile'
                            [IO.File]::WriteAllText($kmJson, (ConvertTo-Json $kmData -Depth 5), [Text.Encoding]::UTF8)
                        }

                        $results.Add([pscustomobject]@{
                            Name = 'lightgun-gunmote'; Status = if ($isWhatIf) { 'WhatIf' } elseif ($kmModified) { 'Done' } else { 'Skipped' }
                            Detail = 'Gunmote layouts merged.'
                        })
                    }
                }
            }

            # 4. TeknoParrot profiles merge
            $tpEntries = @($zip.Entries | Where-Object { $_.FullName -like 'files/lightgun/teknoparrot/*.xml' } | Sort-Object FullName)
            if ($tpEntries.Count -gt 0) {
                $tpProfiles = if ($rb -and (Test-Path -LiteralPath $rb)) { Join-Path $rb 'emulators\teknoparrot\UserProfiles' } else { $null }
                if (-not $tpProfiles -or -not (Test-Path -LiteralPath $tpProfiles)) {
                    $results.Add([pscustomobject]@{
                        Name = 'lightgun-teknoparrot'; Status = 'NeedsUser'
                        Detail = "TeknoParrot UserProfiles not found under '$rb'. Run lightgun step 10 for the games you want, then import again."
                    })
                } else {
                    $tpModified = $false
                    foreach ($te in $tpEntries) {
                        $fileName = Split-Path -Leaf $te.FullName
                        Assert-KitProfilePathSafe -Path $te.FullName
                        $targetXml = Join-Path $tpProfiles $fileName
                        if (-not (Test-KitPathUnder -Path $targetXml -Root @($tpProfiles))) {
                            $results.Add([pscustomobject]@{
                                Name = 'lightgun-teknoparrot'; Status = 'NeedsUser'
                                Detail = "Refused profile '$fileName' outside the TeknoParrot UserProfiles folder."
                            })
                            $tpModified = $null
                            break
                        }
                        if (Test-Path -LiteralPath $targetXml) {
                            $tReader = New-Object IO.StreamReader ($te.Open(), [Text.Encoding]::UTF8)
                            $teXml = $null
                            try { $teXml = $tReader.ReadToEnd() } finally { $tReader.Dispose() }
                            $resolvedXml = ConvertFrom-KitProfileText -Text $teXml -Roots $roots

                            $currentXml = [IO.File]::ReadAllText($targetXml)
                            if ($currentXml -ne $resolvedXml) {
                                if (-not $isWhatIf) {
                                    $null = Backup-ProfileFile -Path $targetXml -Purpose 'profile'
                                    [IO.File]::WriteAllText($targetXml, $resolvedXml, [Text.Encoding]::UTF8)
                                }
                                $tpModified = $true
                            }
                        }
                    }
                    if ($null -ne $tpModified) {
                        $results.Add([pscustomobject]@{
                            Name = 'lightgun-teknoparrot'; Status = if ($isWhatIf) { 'WhatIf' } elseif ($tpModified) { 'Done' } else { 'Skipped' }
                            Detail = "$($tpEntries.Count) TeknoParrot profile(s) checked."
                        })
                    }
                }
            }
        }
    } finally {
        $zip.Dispose()
    }

    # List[object] -> object[]: a plain cast keeps PS 5.1 from tripping its dynamic array binder.
    $out = New-Object object[] $results.Count
    [void]$results.CopyTo($out)
    $out
}
