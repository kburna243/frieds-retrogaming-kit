# Demul & DemulShooter (step 12): Naomi & Atomiswave lightgun support.
#   Demul 0.7a:          User supplies Demul 0.7a (demul.exe, nvram folder, BIOS files). Closed-source emulator.
#   DemulShooter:        Guided download from official GitHub releases (argonlefou/DemulShooter).
#                        Configures HID raw input mode for Gunmote Xbox pads (left stick axes 0x30/0x31,
#                        triggers 2/1, action 3, outputs enabled).
#   RetroBat settings:   naomi.emulator=demul, atomiswave.emulator=demul, use_guns=0, use_demulshooter=0,
#                        disableautocontrollers=1 in es_settings.cfg.
#   gamelist overrides:  Checks roms\naomi\gamelist.xml and roms\atomiswave\gamelist.xml for hardwired <emulator>
#                        (flycast/libretro) on gun games and removes them so demul is used.
#   Secure ROM launch:   DemulShooter runs asInvoker (un-elevated) matching Demul integrity; ROM names strictly
#                        validated against ^[A-Za-z0-9_\-]{1,64}$ and an allowlist of known Naomi/Atomiswave gun ROMs.

$script:LightgunDemulReleaseUrl = 'https://github.com/argonlefou/DemulShooter/releases'

# Known lightgun ROMs for Demul (Naomi and Atomiswave) supported by DemulShooter -target=demul07a.
$script:LightgunDemulKnownRoms = @(
    # Naomi
    'braveff',
    'confmiss',
    'deathcrm',
    'hotd2',
    'hotd2o',
    'hotd2p',
    'lupinsho',
    'manicpnc',
    'mok',
    'ninjaslt',
    'ninjaslta',
    'ninjasltj',
    'ninjasltu',
    'pokasuka',
    'rangrnge',
    'shootgo',
    'sportsm',
    # Atomiswave
    'claychal',
    'rangero',
    'seawolf',
    'xtrmhunt',
    'xtrmhnt2'
)

function Get-LightgunDemulShooterReleaseUrl {
    [CmdletBinding()]
    param()
    $script:LightgunDemulReleaseUrl
}

function Get-LightgunDemulKnownRoms {
    [CmdletBinding()]
    param()
    $script:LightgunDemulKnownRoms
}

# Resolves paths for Demul, DemulShooter and Naomi/Atomiswave gamelists.
function Get-LightgunDemulPath {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RetroBatRoot)
    $demulDir = Join-Path $RetroBatRoot 'emulators\demul'
    $dsDir = Join-Path $RetroBatRoot 'system\tools\demulshooter'
    [pscustomobject]@{
        DemulDir            = $demulDir
        DemulExe            = Join-Path $demulDir 'demul.exe'
        DemulIni            = Join-Path $demulDir 'Demul.ini'
        NvramDir            = Join-Path $demulDir 'nvram'
        DemulShooterDir     = $dsDir
        DemulShooterExe     = Join-Path $dsDir 'DemulShooter.exe'
        DemulShooterConfig  = Join-Path $dsDir 'config.ini'
        DemulShooterLog     = Join-Path $dsDir 'ChangeLog.txt'
        NaomiGamelist       = Join-Path $RetroBatRoot 'roms\naomi\gamelist.xml'
        AtomiswaveGamelist  = Join-Path $RetroBatRoot 'roms\atomiswave\gamelist.xml'
    }
}

# Checks user-supplied Demul 0.7a installation.
function Test-LightgunDemulInstalled {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RetroBatRoot)
    $paths = Get-LightgunDemulPath -RetroBatRoot $RetroBatRoot
    $hasExe = Test-Path -LiteralPath $paths.DemulExe -PathType Leaf
    $hasNvram = Test-Path -LiteralPath $paths.NvramDir -PathType Container

    # Check BIOS presence in roms\naomi, roms\atomiswave or bios folder
    $biosFiles = @('naomi.zip', 'awbios.zip')
    $biosDirs = @(
        (Join-Path $RetroBatRoot 'roms\naomi'),
        (Join-Path $RetroBatRoot 'roms\atomiswave'),
        (Join-Path $RetroBatRoot 'bios'),
        $paths.DemulDir
    )
    $foundBios = @(foreach ($b in $biosFiles) {
        $found = $false
        foreach ($d in $biosDirs) {
            if (Test-Path -LiteralPath (Join-Path $d $b) -PathType Leaf) { $found = $true; break }
        }
        if ($found) { $b }
    })

    [pscustomobject]@{
        Installed = $hasExe -and $hasNvram
        HasExe    = $hasExe
        HasNvram  = $hasNvram
        HasBios   = $foundBios.Count -eq $biosFiles.Count
        FoundBios = $foundBios
        Path      = $paths.DemulDir
    }
}

# Checks DemulShooter installation and parses version from ChangeLog or file version.
function Test-LightgunDemulShooterInstalled {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $RetroBatRoot,
        [string] $CustomPath
    )
    $paths = Get-LightgunDemulPath -RetroBatRoot $RetroBatRoot
    $dsExe = if ($CustomPath) {
        if (Test-Path -LiteralPath $CustomPath -PathType Leaf) { $CustomPath } else { Join-Path $CustomPath 'DemulShooter.exe' }
    } else { $paths.DemulShooterExe }

    $installed = Test-Path -LiteralPath $dsExe -PathType Leaf
    $version = $null
    if ($installed) {
        $dsDir = Split-Path -Parent $dsExe
        $logFile = Join-Path $dsDir 'ChangeLog.txt'
        if (Test-Path -LiteralPath $logFile -PathType Leaf) {
            $first = Get-Content -LiteralPath $logFile -ErrorAction SilentlyContinue | Where-Object { $_ -match '##\s*\[([0-9\.]+)\]' } | Select-Object -First 1
            if ($first -and $first -match '##\s*\[([0-9\.]+)\]') { $version = $Matches[1] }
        }
        if (-not $version) {
            try {
                $vi = [Diagnostics.FileVersionInfo]::GetVersionInfo($dsExe)
                if ($vi.ProductVersion) { $version = $vi.ProductVersion } elseif ($vi.FileVersion) { $version = $vi.FileVersion }
            } catch { }
        }
    }

    [pscustomobject]@{
        Installed = $installed
        Version   = $version
        ExePath   = $dsExe
        DirPath   = if ($installed) { Split-Path -Parent $dsExe } else { $paths.DemulShooterDir }
    }
}

# Target keys for DemulShooter config.ini in HID / raw input mode for Gunmote pads.
$script:LightgunDemulShooterTarget = [ordered]@{
    'P1Mode'                    = 'RAWINPUT'
    'P1HidAxisX'                = '0x30'
    'P1InvertAxisX'             = 'False'
    'P1HidAxisY'                = '0x31'
    'P1InvertAxisY'             = 'False'
    'P1HidBtnOnscreenTrigger'   = '2'
    'P1HidBtnAction'            = '3'
    'P1HidBtnOffscreenTrigger'  = '1'
    'P2Mode'                    = 'RAWINPUT'
    'P2HidAxisX'                = '0x30'
    'P2InvertAxisX'             = 'False'
    'P2HidAxisY'                = '0x31'
    'P2InvertAxisY'             = 'False'
    'P2HidBtnOnscreenTrigger'   = '2'
    'P2HidBtnAction'            = '3'
    'P2HidBtnOffscreenTrigger'  = '1'
    'OutputEnabled'             = 'True'
    'WM_OutputsEnabled'         = 'True'
}

# Plans DemulShooter configuration differences.
function Get-LightgunDemulShooterConfigPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $ConfigPath)
    $current = @{}
    if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
        foreach ($line in [IO.File]::ReadAllLines($ConfigPath)) {
            $trimmed = $line.Trim()
            if (-not $trimmed -or $trimmed.StartsWith(';') -or $trimmed.StartsWith('#')) { continue }
            $eq = $trimmed.IndexOf('=')
            if ($eq -gt 0) {
                $k = $trimmed.Substring(0, $eq).Trim()
                $v = $trimmed.Substring($eq + 1).Trim()
                $current[$k] = $v
            }
        }
    }
    $changes = New-Object Collections.Generic.List[object]
    foreach ($k in $script:LightgunDemulShooterTarget.Keys) {
        $want = $script:LightgunDemulShooterTarget[$k]
        if (-not $current.ContainsKey($k)) {
            $changes.Add([pscustomobject]@{ Key = $k; Old = $null; New = $want; Action = 'Add' })
        } elseif ($current[$k] -ne $want) {
            $changes.Add([pscustomobject]@{ Key = $k; Old = $current[$k]; New = $want; Action = 'Change' })
        }
    }
    $changes.ToArray()
}

# Writes DemulShooter config.ini with backup, preserving other keys and comments.
function Set-LightgunDemulShooterConfig {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $ConfigPath,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Plan
    )
    if (-not $Plan -or $Plan.Count -eq 0) { return 0 }
    if (-not $PSCmdlet.ShouldProcess($ConfigPath, "Set $($Plan.Count) DemulShooter setting(s)")) { return 0 }

    $lines = New-Object Collections.Generic.List[string]
    $seen = New-Object Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
    $planMap = @{}
    foreach ($p in $Plan) { $planMap[$p.Key] = $p.New }

    if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
        $null = Backup-LightgunFile -Path $ConfigPath
        foreach ($line in [IO.File]::ReadAllLines($ConfigPath)) {
            $trimmed = $line.Trim()
            $eq = $trimmed.IndexOf('=')
            if ($trimmed -and -not $trimmed.StartsWith(';') -and -not $trimmed.StartsWith('#') -and $eq -gt 0) {
                $k = $trimmed.Substring(0, $eq).Trim()
                $null = $seen.Add($k)
                if ($planMap.ContainsKey($k)) {
                    $lines.Add("$k = $($planMap[$k])")
                    continue
                }
            }
            $lines.Add($line)
        }
    } else {
        $parent = Split-Path -Parent $ConfigPath
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    }

    # Add any missing keys
    foreach ($k in $script:LightgunDemulShooterTarget.Keys) {
        if (-not $seen.Contains($k)) {
            $lines.Add("$k = $($script:LightgunDemulShooterTarget[$k])")
        }
    }

    $utf8 = New-Object Text.UTF8Encoding $false
    [IO.File]::WriteAllText($ConfigPath, (($lines -join "`r`n") + "`r`n"), $utf8)
    Write-KitLog (Get-KitText 'Lightgun.Demul.ConfigSaved' -f $ConfigPath, $Plan.Count)
    $Plan.Count
}

# Strict validation of ROM name: must match ^[A-Za-z0-9_\-]{1,64}$ AND be on the allowlist.
function Test-LightgunDemulRomName {
    [CmdletBinding()]
    param(
        [string] $Rom,
        [string[]] $Allowlist = $script:LightgunDemulKnownRoms
    )
    if ([string]::IsNullOrWhiteSpace($Rom)) { return $false }
    $trimmed = $Rom.Trim()
    if ($trimmed.Length -gt 64) { return $false }
    if ($trimmed -notmatch '^[A-Za-z0-9_\-]{1,64}$') { return $false }
    $lower = $trimmed.ToLowerInvariant()
    [bool](@($Allowlist | Where-Object { $_.ToLowerInvariant() -eq $lower }).Count)
}

function Assert-LightgunDemulRomName {
    [CmdletBinding()]
    param(
        [string] $Rom,
        [string[]] $Allowlist = $script:LightgunDemulKnownRoms
    )
    if (-not (Test-LightgunDemulRomName -Rom $Rom -Allowlist $Allowlist)) {
        throw (Get-KitText 'Lightgun.Demul.BadRom' -f $Rom)
    }
}

# Launches DemulShooter safely: validates target and ROM, discrete argument array, no shell execution.
function Start-LightgunDemulShooter {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $DemulShooterExe,
        [Parameter(Mandatory)] [ValidateSet('demul07a', 'model2m', 'model2')] [string] $Target,
        [Parameter(Mandatory)] [string] $Rom,
        [string[]] $Allowlist = $script:LightgunDemulKnownRoms
    )
    Assert-LightgunDemulRomName -Rom $Rom -Allowlist $Allowlist
    if (-not (Test-Path -LiteralPath $DemulShooterExe -PathType Leaf)) {
        throw (Get-KitText 'Lightgun.Demul.DsNotFound' -f $DemulShooterExe)
    }

    # Stop any existing DemulShooter process
    Get-Process -Name 'DemulShooter', 'DemulShooterX64' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

    $args = @("-target=$Target", "-rom=$Rom")
    if ($PSCmdlet.ShouldProcess($DemulShooterExe, "Start DemulShooter $($args -join ' ')")) {
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = $DemulShooterExe
        $psi.Arguments = $args -join ' '
        $psi.WorkingDirectory = Split-Path -Parent $DemulShooterExe
        $psi.UseShellExecute = $false
        [Diagnostics.Process]::Start($psi) | Out-Null
        Write-KitLog (Get-KitText 'Lightgun.Demul.DsStarted' -f $Target, $Rom)
    }
}

# Scans roms\naomi\gamelist.xml and roms\atomiswave\gamelist.xml for hardwired <emulator> (flycast/libretro) on gun games.
function Get-LightgunDemulGamelistOverride {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RetroBatRoot)
    $results = New-Object Collections.Generic.List[object]
    $paths = Get-LightgunDemulPath -RetroBatRoot $RetroBatRoot
    $lists = @(
        @{ System = 'naomi'; File = $paths.NaomiGamelist },
        @{ System = 'atomiswave'; File = $paths.AtomiswaveGamelist }
    )

    foreach ($entry in $lists) {
        if (-not (Test-Path -LiteralPath $entry.File -PathType Leaf)) { continue }
        try { $doc = Read-LightgunXml $entry.File } catch { continue }
        foreach ($gameNode in @($doc.SelectNodes('/gameList/game'))) {
            $pathNode = $gameNode.SelectSingleNode('path')
            if (-not $pathNode) { continue }
            $gamePath = $pathNode.InnerText
            $baseName = [IO.Path]::GetFileNameWithoutExtension($gamePath)
            if ($baseName.StartsWith('./') -or $baseName.StartsWith('.\')) { $baseName = $baseName.Substring(2) }

            if ($script:LightgunDemulKnownRoms -contains $baseName.ToLowerInvariant()) {
                $emuNode = $gameNode.SelectSingleNode('emulator')
                $coreNode = $gameNode.SelectSingleNode('core')
                if ($emuNode -or $coreNode) {
                    $emu = if ($emuNode) { $emuNode.InnerText } else { '' }
                    $core = if ($coreNode) { $coreNode.InnerText } else { '' }
                    # demul / naomi or demul / atomiswave is the kit's target, others are overrides
                    $isKitTarget = ($emu -eq 'demul') -and ($core -in 'naomi', 'atomiswave', '')
                    if (-not $isKitTarget) {
                        $results.Add([pscustomobject]@{
                            System   = $entry.System
                            File     = $entry.File
                            Game     = $baseName
                            Path     = $gamePath
                            Emulator = $emu
                            Core     = $core
                        })
                    }
                }
            }
        }
    }
    $results.ToArray()
}

# Removes hardwired emulator and core nodes from gun games in naomi/atomiswave gamelist.xml.
function Remove-LightgunDemulGamelistOverride {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $RetroBatRoot,
        [object[]] $Overrides
    )
    if (-not $Overrides -or $Overrides.Count -eq 0) { return 0 }
    $byFile = $Overrides | Group-Object -Property File
    $totalRemoved = 0

    foreach ($group in $byFile) {
        $file = $group.Name
        if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { continue }
        $doc = Read-LightgunXml $file
        $gamesToRemove = @($group.Group | ForEach-Object { $_.Path })
        $fileChanged = $false

        foreach ($gameNode in @($doc.SelectNodes('/gameList/game'))) {
            $pathNode = $gameNode.SelectSingleNode('path')
            if (-not $pathNode -or ($gamesToRemove -notcontains $pathNode.InnerText)) { continue }

            $emuNode = $gameNode.SelectSingleNode('emulator')
            $coreNode = $gameNode.SelectSingleNode('core')
            if ($emuNode) { $null = $gameNode.RemoveChild($emuNode); $fileChanged = $true; $totalRemoved++ }
            if ($coreNode) { $null = $gameNode.RemoveChild($coreNode); $fileChanged = $true }
        }

        if ($fileChanged -and $PSCmdlet.ShouldProcess($file, 'Remove hardwired emulator tags for gun games')) {
            $null = Backup-LightgunFile -Path $file
            Save-LightgunXml $doc $file
            Write-KitLog (Get-KitText 'Lightgun.Demul.GamelistCleaned' -f $file, $group.Group.Count)
        }
    }
    $totalRemoved
}
