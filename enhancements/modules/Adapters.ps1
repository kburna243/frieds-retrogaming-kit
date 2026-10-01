# Enhancement adapter plugins: one <Name>.ps1 per tool in enhancements\adapters\, same five-function shape as
# the lightgun/arcade adapters (Test / Get-Info / Install / Configure / Shield), but enhancement adapters are
# detected by GPU, audio, MPO support, and supported boards — and it is explicitly MULTI: a cabinet can
# run multiple enhancement tools simultaneously for different aspects (shader, upscaling, latency, etc.).

function Get-EnhancementsAdapterCatalog {
    [CmdletBinding()]
    param([string] $Dir = (Get-EnhancementsAdapterDir))
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
            HasTest      = [bool]($funcs -contains "Test-${name}Hardware")
            HasInfo      = [bool]($funcs -contains "Get-${name}AdapterInfo")
            HasInstall   = [bool]($funcs -contains "Install-${name}Software")
            HasConfigure = [bool]($funcs -contains "Configure-${name}Profile")
            HasShield    = [bool]($funcs -contains "Set-${name}InterferenceShield")
        }
    }
}

function Invoke-EnhancementsAdapterFunction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Function,
        [string] $Dir = (Get-EnhancementsAdapterDir),
        [hashtable] $Parameters = @{}
    )
    if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$') { throw (Get-KitText 'Enhancements.Adapter.NotFound' -f $Name) }
    $file = Join-Path $Dir "$Name.ps1"
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw (Get-KitText 'Enhancements.Adapter.NotFound' -f $Name) }
    . $file
    if (-not (Get-Command $Function -ErrorAction SilentlyContinue)) { throw (Get-KitText 'Enhancements.Adapter.MissingFunction' -f $Name, $Function) }
    & $Function @Parameters
}

function Get-EnhancementsAdapterValue($Info, [string] $Key) { if ($Info -and $Info.Contains($Key)) { $Info[$Key] } }

# Snapshot of the machine an enhancement adapter probe may read. Without -Snapshot the real system answers:
# GPU info, audio devices, MPO support, and RetroBat root.
# Tests inject their own hashtable so nothing on the machine is touched.
function Get-EnhancementsSystemSnapshot {
    [CmdletBinding()]
    param([string] $RetroBatRoot = '')
    @{
        GpuInfo      = Get-EnhancementGpuInfo
        AudioDevices = Get-EnhancementAudioDevices
        MpoSupported = Test-EnhancementMpoSupport
        Root         = $RetroBatRoot
    }
}

# Detect ALL enhancement adapters in use (multi), plus the structured conflicts:
# We don't have EDID or port conflicts for enhancements, but we can check for conflicting GPU settings?
# For now, we just detect which adapters are present and functional.
function Get-EnhancementsDetectedAdapters {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [hashtable] $Snapshot,
        [string] $Dir = (Get-EnhancementsAdapterDir),
        [switch] $Quiet
    )
    if (-not $PSBoundParameters.ContainsKey('Snapshot')) { $Snapshot = Get-EnhancementsSystemSnapshot -RetroBatRoot $RetroBatRoot }
    $errors = New-Object Collections.Generic.List[string]
    $scanned = New-Object Collections.Generic.List[string]
    $detected = New-Object Collections.Generic.List[object]
    foreach ($a in (Get-EnhancementsAdapterCatalog -Dir $Dir)) {
        if ($a.HasParseErrors -or -not ($a.HasTest -and $a.HasInfo)) {
            $reason = if ($a.HasParseErrors) { 'syntax' } elseif (-not $a.HasTest) { "Test-$($a.Name)Hardware" } else { "Get-$($a.Name)AdapterInfo" }
            $errors.Add((Get-KitText 'Enhancements.Adapter.Incomplete' -f $a.Name, $reason))
            if (-not $Quiet) { Write-KitLog (Get-KitText 'Enhancements.Adapter.Incomplete' -f $a.Name, $reason) -Level Warn }
            continue
        }
        $scanned.Add($a.Name)
        try {
            $present = [bool](Invoke-EnhancementsAdapterFunction -Name $a.Name -Function "Test-$($a.Name)Hardware" -Parameters @{ RetroBatRoot = $RetroBatRoot; Snapshot = $Snapshot })
            if (-not $present) { continue }
            $info = Invoke-EnhancementsAdapterFunction -Name $a.Name -Function "Get-$($a.Name)AdapterInfo"
            $detected.Add([pscustomobject]@{
                Name       = $a.Name
                AdapterType = [string](Get-EnhancementsAdapterValue $info 'AdapterType')
            })
        } catch {
            $errors.Add((Get-KitText 'Enhancements.Adapter.Error' -f $a.Name, $_.Exception.Message))
            if (-not $Quiet) { Write-KitLog (Get-KitText 'Enhancements.Adapter.Error' -f $a.Name, $_.Exception.Message) -Level Error }
        }
    }
    $names = @($detected | ForEach-Object { $_.Name })
    [pscustomobject]@{
        Success          = ($names.Count -gt 0)
        DetectedAdapters = $names
        DetectedDetails  = $detected.ToArray()
        ScannedAdapters  = ($scanned -join ',')
        Errors           = @($errors)
        NextStep         = $(if ($names.Count) { "Set-EnhancementsAdapterConfiguration -Names ($($names -join ', '))" } else { '' })
    }
}

# Public route into an enhancement adapter's Install-<Name>Software (link only, or local ZIP with -Approved).
function Install-EnhancementsAdapter {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $RetroBatRoot,
        [string] $PackagePath,
        [switch] $Approved
    )
    $params = @{ RetroBatRoot = $RetroBatRoot }
    if ($PackagePath) { $params.PackagePath = $PackagePath }
    if ($Approved.IsPresent) { $params.Approved = $true }
    Invoke-EnhancementsAdapterFunction -Name $Name -Function "Install-$($Name)Software" -Parameters $params
}

# Apply all detected enhancement adapters. Configuration files are touched only where they already exist;
# safety values (backlight limits, DMD frame timing) are enforced with the same backup/WhatIf path as everything else.
function Set-EnhancementsAdapterConfiguration {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string[]] $Names,
        [Parameter(Mandatory)] [string] $RetroBatRoot
    )
    if (-not $PSCmdlet.ShouldProcess(($Names -join ', '), 'configure enhancement adapters')) { return 0 }
    $changes = 0
    foreach ($n in $Names) {
        $info = Invoke-EnhancementsAdapterFunction -Name $n -Function "Get-$($n)AdapterInfo"
        $toolDir = [string](Get-EnhancementsAdapterValue $info 'ToolDir')
        foreach ($t in @(Get-EnhancementsAdapterValue $info 'SettingsTargets')) {
            $path = if ($t.Contains('Path')) { [string]$t.Path } else { Join-Path $RetroBatRoot ('tools\' + $toolDir + '\' + [string]$t.File) }
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                Write-KitLog (Get-KitText 'Enhancements.Adapter.NoSettings' -f $path) -Level Warn
                continue
            }
            $values = @{}
            if ($t.Contains('Safety')) { foreach ($k in $t.Safety.Keys) { $values[$k] = $t.Safety[$k] } }
            if ($t.Contains('Values')) { foreach ($k in $t.Values.Keys) { $values[$k] = $t.Values[$k] } }
            if ($values.Count) { $changes += Set-EnhancementsIniValue -Path $path -Section $([string]$(if ($t.Contains('Section')) { $t.Section } else { '' })) -Values $values -Confirm:$false }
        }
    }
    Write-KitLog (Get-KitText 'Enhancements.Adapter.Changes' -f ($Names -join '+'), $changes)
    $changes
}

# True when every detected enhancement adapter finds its own settings already in place.
function Test-EnhancementsAdapterConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string[]] $Names, [Parameter(Mandatory)] [string] $RetroBatRoot)
    foreach ($n in $Names) {
        $info = Invoke-EnhancementsAdapterFunction -Name $n -Function "Get-$($n)AdapterInfo"
        $toolDir = [string](Get-EnhancementsAdapterValue $info 'ToolDir')
        foreach ($t in @(Get-EnhancementsAdapterValue $info 'SettingsTargets')) {
            $path = if ($t.Contains('Path')) { [string]$t.Path } else { Join-Path $RetroBatRoot ('tools\' + $toolDir + '\' + [string]$t.File) }
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }   # tool active but no settings file: safety unproven, stay red
            $values = @{}
            if ($t.Contains('Safety')) { foreach ($k in $t.Safety.Keys) { $values[$k] = $t.Safety[$k] } }
            if ($t.Contains('Values')) { foreach ($k in $t.Values.Keys) { $values[$k] = $t.Values[$k] } }
            if ($values.Count -and @(Get-EnhancementsIniPlan -Path $path -Section $([string]$(if ($t.Contains('Section')) { $t.Section } else { '' })) -Values $values).Count) { return $false }
        }
    }
    $true
}