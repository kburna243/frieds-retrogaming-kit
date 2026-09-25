# Model 2 & Supermodel (step 13): Sega Model 2 and Model 3 lightgun setup.
#   Model 2:           User supplies Model 2 emulator (EMULATOR.EXE / emulator_multicpu.exe, Emulator.ini).
#                      Closed-source emulator by ElSemi. DemulShooter hooks via -target=model2m (or -target=model2).
#   Supermodel:        Official releases from trzy/Supermodel (GPL-3.0). Configured for XInput crosshairs and gun inputs.
#   RetroBat settings: model2.use_guns=0, model3.use_guns=0, model2.disableautocontrollers=1, model3.disableautocontrollers=1.

$script:LightgunSupermodelReleaseUrl = 'https://github.com/trzy/Supermodel/releases'
$script:LightgunSupermodelReleasePrefix = 'https://github.com/trzy/Supermodel/releases/download/'

$script:LightgunModel2KnownRoms = @(
    'bel',
    'gunblade',
    'hotd',
    'rchase2',
    'vcop',
    'vcop2'
)

function Get-LightgunSupermodelReleaseUrl {
    [CmdletBinding()]
    param()
    $script:LightgunSupermodelReleaseUrl
}

function Get-LightgunSupermodelReleasePrefix {
    [CmdletBinding()]
    param()
    $script:LightgunSupermodelReleasePrefix
}

function Get-LightgunModel2KnownRoms {
    [CmdletBinding()]
    param()
    $script:LightgunModel2KnownRoms
}

function Get-LightgunModel2Path {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RetroBatRoot)
    $m2Dir = Join-Path $RetroBatRoot 'emulators\m2emulator'
    $smDir = Join-Path $RetroBatRoot 'emulators\supermodel'
    $smCfgDir = Join-Path $smDir 'Config'
    [pscustomobject]@{
        Model2Dir            = $m2Dir
        Model2Exe            = Join-Path $m2Dir 'EMULATOR.EXE'
        Model2MultiCpu       = Join-Path $m2Dir 'emulator_multicpu.exe'
        Model2Ini            = Join-Path $m2Dir 'Emulator.ini'
        SupermodelDir        = $smDir
        SupermodelExe        = Join-Path $smDir 'supermodel.exe'
        SupermodelConfigDir  = $smCfgDir
        SupermodelIni        = Join-Path $smCfgDir 'Supermodel.ini'
    }
}

# Checks Model 2 emulator (user supplied, closed source).
function Test-LightgunModel2Installed {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RetroBatRoot)
    $paths = Get-LightgunModel2Path -RetroBatRoot $RetroBatRoot
    $hasExe = (Test-Path -LiteralPath $paths.Model2Exe -PathType Leaf) -or
              (Test-Path -LiteralPath $paths.Model2MultiCpu -PathType Leaf)
    $hasIni = Test-Path -LiteralPath $paths.Model2Ini -PathType Leaf

    [pscustomobject]@{
        Installed = $hasExe
        HasIni    = $hasIni
        DirPath   = $paths.Model2Dir
        ExePath   = if (Test-Path -LiteralPath $paths.Model2MultiCpu -PathType Leaf) { $paths.Model2MultiCpu } else { $paths.Model2Exe }
    }
}

# Checks Supermodel (shipped by RetroBat or user).
function Test-LightgunSupermodelInstalled {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RetroBatRoot)
    $paths = Get-LightgunModel2Path -RetroBatRoot $RetroBatRoot
    $hasExe = Test-Path -LiteralPath $paths.SupermodelExe -PathType Leaf
    $hasIni = Test-Path -LiteralPath $paths.SupermodelIni -PathType Leaf

    [pscustomobject]@{
        Installed = $hasExe
        HasIni    = $hasIni
        DirPath   = $paths.SupermodelDir
        ExePath   = $paths.SupermodelExe
        IniPath   = $paths.SupermodelIni
    }
}

# Strict validation of Model 2 ROM names against allowlist.
function Test-LightgunModel2RomName {
    [CmdletBinding()]
    param(
        [string] $Rom,
        [string[]] $Allowlist = $script:LightgunModel2KnownRoms
    )
    if ([string]::IsNullOrWhiteSpace($Rom)) { return $false }
    $trimmed = $Rom.Trim()
    if ($trimmed.Length -gt 64) { return $false }
    if ($trimmed -notmatch '^[A-Za-z0-9_\-]{1,64}$') { return $false }
    $lower = $trimmed.ToLowerInvariant()
    [bool](@($Allowlist | Where-Object { $_.ToLowerInvariant() -eq $lower }).Count)
}

function Assert-LightgunModel2RomName {
    [CmdletBinding()]
    param(
        [string] $Rom,
        [string[]] $Allowlist = $script:LightgunModel2KnownRoms
    )
    if (-not (Test-LightgunModel2RomName -Rom $Rom -Allowlist $Allowlist)) {
        throw (Get-KitText 'Lightgun.Model2.BadRom' -f $Rom)
    }
}

# Supermodel target settings under [ Global ] for XInput gun play with crosshairs.
$script:LightgunSupermodelTarget = [ordered]@{
    'Crosshairs'         = '1'
    'InputGunX'          = '"JOY1_XAXIS,MOUSE_XAXIS"'
    'InputGunY'          = '"JOY1_YAXIS,MOUSE_YAXIS"'
    'InputTrigger'       = '"JOY1_BUTTON1,MOUSE_LEFT_BUTTON"'
    'InputOffscreen'     = '"JOY1_BUTTON5,MOUSE_RIGHT_BUTTON"'
    'InputAutoTrigger'   = '1'
    'InputGunX2'         = '"JOY2_XAXIS,MOUSE_XAXIS"'
    'InputGunY2'         = '"JOY2_YAXIS,MOUSE_YAXIS"'
    'InputTrigger2'      = '"JOY2_BUTTON1"'
    'InputOffscreen2'    = '"JOY2_BUTTON5"'
    'InputAutoTrigger2'  = '1'
}

# Plans Supermodel.ini settings under [ Global ].
function Get-LightgunSupermodelConfigPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $ConfigPath)
    $current = @{}
    $inGlobal = $false
    if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
        foreach ($line in [IO.File]::ReadAllLines($ConfigPath)) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^\[\s*Global\s*\]') { $inGlobal = $true; continue }
            if ($trimmed -match '^\[') { $inGlobal = $false; continue }
            if ($inGlobal -and $trimmed -and -not $trimmed.StartsWith(';') -and -not $trimmed.StartsWith('#')) {
                $eq = $trimmed.IndexOf('=')
                if ($eq -gt 0) {
                    $k = $trimmed.Substring(0, $eq).Trim()
                    $v = $trimmed.Substring($eq + 1).Trim()
                    $current[$k] = $v
                }
            }
        }
    }

    $changes = New-Object Collections.Generic.List[object]
    foreach ($k in $script:LightgunSupermodelTarget.Keys) {
        $want = $script:LightgunSupermodelTarget[$k]
        if (-not $current.ContainsKey($k)) {
            $changes.Add([pscustomobject]@{ Section = 'Global'; Key = $k; Old = $null; New = $want; Action = 'Add' })
        } elseif ($current[$k] -ne $want) {
            $changes.Add([pscustomobject]@{ Section = 'Global'; Key = $k; Old = $current[$k]; New = $want; Action = 'Change' })
        }
    }
    $changes.ToArray()
}

# Writes Supermodel.ini settings under [ Global ], preserving other sections and comments.
function Set-LightgunSupermodelConfig {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $ConfigPath,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [object[]] $Plan
    )
    if (-not $Plan -or $Plan.Count -eq 0) { return 0 }
    if (-not $PSCmdlet.ShouldProcess($ConfigPath, "Set $($Plan.Count) Supermodel setting(s)")) { return 0 }

    $lines = New-Object Collections.Generic.List[string]
    $seen = New-Object Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
    $planMap = @{}
    foreach ($p in $Plan) { $planMap[$p.Key] = $p.New }

    $hasGlobalSection = $false
    $inGlobal = $false

    if (Test-Path -LiteralPath $ConfigPath -PathType Leaf) {
        $null = Backup-LightgunFile -Path $ConfigPath
        foreach ($line in [IO.File]::ReadAllLines($ConfigPath)) {
            $trimmed = $line.Trim()
            if ($trimmed -match '^\[\s*Global\s*\]') {
                $hasGlobalSection = $true
                $inGlobal = $true
                $lines.Add($line)
                continue
            }
            if ($trimmed -match '^\[') {
                if ($inGlobal) {
                    # Add any unwritten target keys before leaving [ Global ]
                    foreach ($k in $script:LightgunSupermodelTarget.Keys) {
                        if (-not $seen.Contains($k)) {
                            $lines.Add("$k = $($script:LightgunSupermodelTarget[$k])")
                            $null = $seen.Add($k)
                        }
                    }
                    $inGlobal = $false
                }
                $lines.Add($line)
                continue
            }

            if ($inGlobal -and $trimmed -and -not $trimmed.StartsWith(';') -and -not $trimmed.StartsWith('#')) {
                $eq = $trimmed.IndexOf('=')
                if ($eq -gt 0) {
                    $k = $trimmed.Substring(0, $eq).Trim()
                    $null = $seen.Add($k)
                    if ($planMap.ContainsKey($k)) {
                        $lines.Add("$k = $($planMap[$k])")
                        continue
                    }
                }
            }
            $lines.Add($line)
        }
    } else {
        $parent = Split-Path -Parent $ConfigPath
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    }

    if ($inGlobal) {
        foreach ($k in $script:LightgunSupermodelTarget.Keys) {
            if (-not $seen.Contains($k)) {
                $lines.Add("$k = $($script:LightgunSupermodelTarget[$k])")
                $null = $seen.Add($k)
            }
        }
    } elseif (-not $hasGlobalSection) {
        $lines.Add('[ Global ]')
        foreach ($k in $script:LightgunSupermodelTarget.Keys) {
            $lines.Add("$k = $($script:LightgunSupermodelTarget[$k])")
        }
    }

    $utf8 = New-Object Text.UTF8Encoding $false
    [IO.File]::WriteAllText($ConfigPath, (($lines -join "`r`n") + "`r`n"), $utf8)
    Write-KitLog (Get-KitText 'Lightgun.Supermodel.ConfigSaved' -f $ConfigPath, $Plan.Count)
    $Plan.Count
}
