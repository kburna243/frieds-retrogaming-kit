# Library adapter plugins: one <Name>.ps1 per tool in library\adapters\, same five-function shape as
# the lightgun/arcade adapters (Test / Get-Info / Install / Configure / Shield), but library adapters
# are detected by frontend installations and supported systems.

function Get-LibraryAdapterCatalog {
    [CmdletBinding()]
    param([string] $Dir = (Get-LibraryAdapterDir))
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { return @() }
    foreach ($f in @(Get-ChildItem -LiteralPath $Dir -Filter '*.ps1' -File | Sort-Object Name)) {
        if ($f.Name -like '_*') { continue }
        $name = $f.BaseName
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref] $tokens, [ref] $errors)
        $funcs = @(if ($ast) { foreach ($d in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) { $d.Name } })
        [pscustomobject]@{
            Name         = $name
            Path         = $f.FullName
            HasParseErrors = (@($errors).Count -gt 0)
            HasTest      = [bool]($funcs -contains "Test-${name}Frontend")
            HasInfo      = [bool]($funcs -contains "Get-${name}FrontendInfo")
            HasInstall   = [bool]($funcs -contains "Install-${name}Frontend")
            HasConfigure = [bool]($funcs -contains "Configure-${name}Frontend")
            HasShield    = [bool]($funcs -contains "Set-${name}InterferenceShield")
        }
    }
}

function Invoke-LibraryAdapterFunction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Function,
        [string] $Dir = (Get-LibraryAdapterDir),
        [hashtable] $Parameters = @{}
    )
    if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$') { throw (Get-KitText 'Library.Adapter.NotFound' -f $Name) }
    $file = Join-Path $Dir "$Name.ps1"
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw (Get-KitText 'Library.Adapter.NotFound' -f $Name) }
    . $file
    if (-not (Get-Command $Function -ErrorAction SilentlyContinue)) { throw (Get-KitText 'Library.Adapter.MissingFunction' -f $Name, $Function) }
    & $Function @Parameters
}

function Get-LibraryAdapterValue($Info, [string] $Key) { if ($Info -and $Info.Contains($Key)) { $Info[$Key] } }

# Base snapshot of the machine a library adapter probe may read. Without -Snapshot the real system answers:
# Frontend installations, RetroBat root, PinballY root, and common paths.
# Tests inject their own hashtable so nothing on the machine is touched.
function Get-LibraryBaseSnapshot {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [string] $PinballYRoot = ''
    )
    @{
        RetroBatRoot   = $RetroBatRoot
        PinballYRoot   = $PinballYRoot
        CommonPaths    = Get-LibraryCommonPaths
        Frontends      = Get-LibraryInstalledFrontends -RetroBatRoot $RetroBatRoot -PinballYRoot $PinballYRoot
    }
}

function Get-LibraryCommonPaths {
    [CmdletBinding()]
    param()
    @{
        ROMsRoot       = Join-Path $env:USERPROFILE 'RetroCabinet\ROMs'
        MediaRoot      = Join-Path $env:USERPROFILE 'RetroCabinet\Media'
        PlaylistsRoot  = Join-Path $env:USERPROFILE 'RetroCabinet\Playlists'
        CabinetsRoot   = Join-Path $env:USERPROFILE 'RetroCabinet\Cabinets'
    }
}

function Get-LibraryInstalledFrontends {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [string] $PinballYRoot = ''
    )
    $frontends = @()
    
    # Check for RetroBat
    if ($RetroBatRoot -and (Test-Path -LiteralPath $RetroBatRoot -PathType Container)) {
        $frontends += @{
            Name = 'RetroBat'
            Root = $RetroBatRoot
            Type = 'Emulator'
        }
    }
    
    # Check for PinballY
    if ($PinballYRoot -and (Test-Path -LiteralPath $PinballYRoot -PathType Container)) {
        $frontends += @{
            Name = 'PinballY'
            Root = $PinballYRoot
            Type = 'Pinball'
        }
    }
    
    # Add detection for other frontends here as needed
    # Playnite, LaunchBox, etc.
    
    return $frontends
}

# Detect ALL library adapters in use (multi), plus the structured conflicts:
# We check for frontend installations and report which adapters are present and functional.
function Get-LibraryDetectedAdapters {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [string] $PinballYRoot = '',
        [hashtable] $Snapshot,
        [string] $Dir = (Get-LibraryAdapterDir),
        [switch] $Quiet
    )
    if (-not $PSBoundParameters.ContainsKey('Snapshot')) { $Snapshot = Get-LibrarySystemSnapshot -RetroBatRoot $RetroBatRoot -PinballYRoot $PinballYRoot }
    $errors = New-Object Collections.Generic.List[string]
    $scanned = New-Object Collections.Generic.List[string]
    $detected = New-Object Collections.Generic.List[object]
    foreach ($a in (Get-LibraryAdapterCatalog -Dir $Dir)) {
        if ($a.HasParseErrors -or -not ($a.HasTest -and $a.HasInfo)) {
            $reason = if ($a.HasParseErrors) { 'syntax' } elseif (-not $a.HasTest) { "Test-$($a.Name)Frontend" } else { "Get-$($a.Name)FrontendInfo" }
            $errors.Add((Get-KitText 'Library.Adapter.Incomplete' -f $a.Name, $reason))
            if (-not $Quiet) { Write-KitLog (Get-KitText 'Library.Adapter.Incomplete' -f $a.Name, $reason) -Level Warn }
            continue
        }
        $scanned.Add($a.Name)
        try {
            $present = [bool](Invoke-LibraryAdapterFunction -Name $a.Name -Function "Test-$($a.Name)Frontend" -Parameters @{ RetroBatRoot = $RetroBatRoot; PinballYRoot = $PinballYRoot; Snapshot = $Snapshot })
            if (-not $present) { continue }
            $info = Invoke-LibraryAdapterFunction -Name $a.Name -Function "Get-$($a.Name)FrontendInfo"
            $detected.Add([pscustomobject]@{
                Name       = $a.Name
                FrontendType = [string](Get-LibraryAdapterValue $info 'FrontendType')
            })
        } catch {
            $errors.Add((Get-KitText 'Library.Adapter.Error' -f $a.Name, $_.Exception.Message))
            if (-not $Quiet) { Write-KitLog (Get-KitText 'Library.Adapter.Error' -f $a.Name, $_.Exception.Message) -Level Error }
        }
    }
    $names = @($detected | ForEach-Object { $_.Name })
    [pscustomobject]@{
        Success          = ($names.Count -gt 0)
        DetectedAdapters = $names
        DetectedDetails  = $detected.ToArray()
        ScannedAdapters  = ($scanned -join ',')
        Errors           = @($errors)
        NextStep         = $(if ($names.Count) { "Set-LibraryAdapterConfiguration -Names ($($names -join ', '))" } else { '' })
    }
}

# Public route into a library adapter's Install-<Name>Frontend (link only, or local ZIP with -Approved).
function Install-LibraryAdapter {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $RetroBatRoot,
        [Parameter(Mandatory)] [string] $PinballYRoot,
        [string] $PackagePath,
        [switch] $Approved
    )
    $params = @{ RetroBatRoot = $RetroBatRoot; PinballYRoot = $PinballYRoot }
    if ($PackagePath) { $params.PackagePath = $PackagePath }
    if ($Approved.IsPresent) { $params.Approved = $true }
    Invoke-LibraryAdapterFunction -Name $Name -Function "Install-$($Name)Frontend" -Parameters $params
}

# Apply all detected library adapter configurations. Configuration files are touched only where they already exist;
# safety values (backlight limits, DMD frame timing) are enforced with the same backup/WhatIf path as everything else.
function Set-LibraryAdapterConfiguration {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string[]] $Names,
        [Parameter(Mandatory)] [string] $RetroBatRoot,
        [Parameter(Mandatory)] [string] $PinballYRoot
    )
    if (-not $PSCmdlet.ShouldProcess(($Names -join ', '), 'configure library adapters')) { return 0 }
    $changes = 0
    foreach ($n in $Names) {
        $info = Invoke-LibraryAdapterFunction -Name $n -Function "Get-$($n)FrontendInfo"
        $toolDir = [string](Get-LibraryAdapterValue $info 'ToolDir')
        foreach ($t in @(Get-LibraryAdapterValue $info 'SettingsTargets')) {
            $path = if ($t.Contains('Path')) { [string]$t.Path } else { Join-Path $RetroBatRoot ('tools\' + $toolDir + '\' + [string]$t.File) }
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                Write-KitLog (Get-KitText 'Library.Adapter.NoSettings' -f $path) -Level Warn
                continue
            }
            $values = @{}
            if ($t.Contains('Safety')) { foreach ($k in $t.Safety.Keys) { $values[$k] = $t.Safety[$k] } }
            if ($t.Contains('Values')) { foreach ($k in $t.Values.Keys) { $values[$k] = $t.Values[$k] } }
            if ($values.Count) { $changes += Set-LibraryIniValue -Path $path -Section $([string]$(if ($t.Contains('Section')) { $t.Section } else { '' })) -Values $values -Confirm:$false }
        }
    }
    Write-KitLog (Get-KitText 'Library.Adapter.Changes' -f ($Names -join '+'), $changes)
    $changes
}

# True when every detected library adapter finds its own settings already in place.
function Test-LibraryAdapterConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string[]] $Names, [Parameter(Mandatory)] [string] $RetroBatRoot, [Parameter(Mandatory)] [string] $PinballYRoot)
    foreach ($n in $Names) {
        $info = Invoke-LibraryAdapterFunction -Name $n -Function "Get-$($n)FrontendInfo"
        $toolDir = [string](Get-LibraryAdapterValue $info 'ToolDir')
        foreach ($t in @(Get-LibraryAdapterValue $info 'SettingsTargets')) {
            $path = if ($t.Contains('Path')) { [string]$t.Path } else { Join-Path $RetroBatRoot ('tools\' + $toolDir + '\' + [string]$t.File) }
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }   # tool active but no settings file: safety unproven, stay red
            $values = @{}
            if ($t.Contains('Safety')) { foreach ($k in $t.Safety.Keys) { $values[$k] = $t.Safety[$k] } }
            if ($t.Contains('Values')) { foreach ($k in $t.Values.Keys) { $values[$k] = $t.Values[$k] } }
            if ($values.Count -and @(Get-LibraryIniPlan -Path $path -Section $([string]$(if ($t.Contains('Section')) { $t.Section } else { '' })) -Values $values).Count) { return $false }
        }
    }
    $true
}

# Get a comprehensive snapshot of the library system including ROMs, frontends, etc.
function Get-LibrarySystemSnapshot {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [string] $PinballYRoot = ''
    )
    
    # Get base snapshot
    $snapshot = Get-LibraryBaseSnapshot -RetroBatRoot $RetroBatRoot -PinballYRoot $PinballYRoot
    
    # Add library-specific information
    $snapshot | Add-Member -NotePropertyName LibraryDir -NotePropertyValue (Get-LibraryAdapterDir)
    $snapshot | Add-Member -NotePropertyName AdaptersCatalog -NotePropertyValue (Get-LibraryAdapterCatalog)
    $snapshot | Add-Member -NotePropertyName DetectedAdapters -NotePropertyValue (Get-LibraryDetectedAdapters -RetroBatRoot $RetroBatRoot -PinballYRoot $PinballYRoot -Snapshot $snapshot)
    
    return $snapshot
}