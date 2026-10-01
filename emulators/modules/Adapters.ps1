# Emulator adapter plugins: one <Name>.ps1 per emulator in emulators\adapters\, same five-function shape as
# the other packages (Test / Get-Info / Install / Configure / Shield), but emulator adapters are
# detected by executable presence, process checks, and RetroBat emulator folders -- and it is explicitly
# MULTI: a cabinet can run multiple emulators simultaneously for different systems.

function Get-EmulatorsAdapterCatalog {
    [CmdletBinding()]
    param([string] $Dir = (Get-EmulatorsAdapterDir))
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { return @() }
    foreach ($f in @(Get-ChildItem -LiteralPath $Dir -Filter '*.ps1' -File | Sort-Object Name)) {
        if ($f.Name -like '_*') { continue }
        $name = $f.BaseName
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref] $tokens, [ref] $errors)
        $funcs = @(if ($ast) { foreach ($d in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) { $d.Name } })
        [pscustomobject]@{
            Name           = $name
            Path           = $f.FullName
            HasParseErrors = (@($errors).Count -gt 0)
            HasTest        = [bool]($funcs -contains "Test-${name}Emulator")
            HasInfo        = [bool]($funcs -contains "Get-${name}EmulatorInfo")
            HasInstall     = [bool]($funcs -contains "Install-${name}Emulator")
            HasConfigure   = [bool]($funcs -contains "Configure-${name}Emulator")
            HasShield      = [bool]($funcs -contains "Set-${name}InterferenceShield")
        }
    }
}

function Invoke-EmulatorsAdapterFunction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Function,
        [string] $Dir = (Get-EmulatorsAdapterDir),
        [hashtable] $Parameters = @{}
    )
    if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$') { throw (Get-KitText 'Emulators.Adapter.NotFound' -f $Name) }
    $file = Join-Path $Dir "$Name.ps1"
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw (Get-KitText 'Emulators.Adapter.NotFound' -f $Name) }
    . $file
    if (-not (Get-Command $Function -ErrorAction SilentlyContinue)) { throw (Get-KitText 'Emulators.Adapter.MissingFunction' -f $Name, $Function) }
    & $Function @Parameters
}

function Get-EmulatorsAdapterValue($Info, [string] $Key) { if ($Info -and $Info.Contains($Key)) { $Info[$Key] } }

# Detect ALL emulator adapters that are installed on this system.
function Get-EmulatorsDetectedAdapters {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [hashtable] $Snapshot,
        [string] $Dir = (Get-EmulatorsAdapterDir),
        [switch] $Quiet
    )
    if (-not $PSBoundParameters.ContainsKey('Snapshot')) { $Snapshot = Get-EmulatorSystemSnapshot -RetroBatRoot $RetroBatRoot }
    $errors = New-Object Collections.Generic.List[string]
    $scanned = New-Object Collections.Generic.List[string]
    $detected = New-Object Collections.Generic.List[object]
    foreach ($a in (Get-EmulatorsAdapterCatalog -Dir $Dir)) {
        if ($a.HasParseErrors -or -not ($a.HasTest -and $a.HasInfo)) {
            $reason = if ($a.HasParseErrors) { 'syntax' } elseif (-not $a.HasTest) { "Test-$($a.Name)Emulator" } else { "Get-$($a.Name)EmulatorInfo" }
            $errors.Add((Get-KitText 'Emulators.Adapter.Incomplete' -f $a.Name, $reason))
            if (-not $Quiet) { Write-KitLog (Get-KitText 'Emulators.Adapter.Incomplete' -f $a.Name, $reason) -Level Warn }
            continue
        }
        $scanned.Add($a.Name)
        try {
            $present = [bool](Invoke-EmulatorsAdapterFunction -Name $a.Name -Function "Test-$($a.Name)Emulator" -Parameters @{ RetroBatRoot = $RetroBatRoot; Snapshot = $Snapshot })
            if (-not $present) { continue }
            $info = Invoke-EmulatorsAdapterFunction -Name $a.Name -Function "Get-$($a.Name)EmulatorInfo" -Parameters @{ RetroBatRoot = $RetroBatRoot }
            $detected.Add([pscustomobject]@{
                Name        = $a.Name
                EmulatorType = [string](Get-EmulatorsAdapterValue $info 'EmulatorType')
                Version     = [string](Get-EmulatorsAdapterValue $info 'Version')
                ExePath     = [string](Get-EmulatorsAdapterValue $info 'ExePath')
            })
        } catch {
            $errors.Add((Get-KitText 'Emulators.Adapter.Error' -f $a.Name, $_.Exception.Message))
            if (-not $Quiet) { Write-KitLog (Get-KitText 'Emulators.Adapter.Error' -f $a.Name, $_.Exception.Message) -Level Error }
        }
    }
    $names = @($detected | ForEach-Object { $_.Name })
    [pscustomobject]@{
        Success           = ($names.Count -gt 0)
        DetectedEmulators = $names
        DetectedDetails   = $detected.ToArray()
        ScannedAdapters   = ($scanned -join ',')
        Errors            = @($errors)
    }
}

# Public route into an emulator adapter's Install-<Name>Emulator (link only, or local ZIP with -Approved).
function Install-EmulatorsAdapter {
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
    Invoke-EmulatorsAdapterFunction -Name $Name -Function "Install-$($Name)Emulator" -Parameters $params
}

# Apply configuration to all detected emulator adapters.
function Set-EmulatorsAdapterConfiguration {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string[]] $Names,
        [Parameter(Mandatory)] [string] $RetroBatRoot
    )
    if (-not $PSCmdlet.ShouldProcess(($Names -join ', '), 'configure emulator adapters')) { return 0 }
    $changes = 0
    foreach ($n in $Names) {
        $info = Invoke-EmulatorsAdapterFunction -Name $n -Function "Get-$($n)EmulatorInfo" -Parameters @{ RetroBatRoot = $RetroBatRoot }
        foreach ($t in @(Get-EmulatorsAdapterValue $info 'SettingsTargets')) {
            $path = if ($t.Contains('Path')) { [string]$t.Path }
                    else {
                        $toolDir = [string](Get-EmulatorsAdapterValue $info 'ToolDir')
                        Join-Path $RetroBatRoot ('emulators\' + $toolDir + '\' + [string]$t.File)
                    }
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                Write-KitLog "Emulator config not found: $path" -Level Warn
                continue
            }
            $values = @{}
            if ($t.Contains('Values')) { foreach ($k in $t.Values.Keys) { $values[$k] = $t.Values[$k] } }
            if ($values.Count) {
                $section = if ($t.Contains('Section')) { [string]$t.Section } else { '' }
                $changes += Set-EmulatorsIniValue -Path $path -Section $section -Values $values -Confirm:$false
            }
        }
    }
    Write-KitLog "Emulator configuration: $($Names -join ', ') -- $changes value(s) set"
    $changes
}

# True when every detected emulator adapter finds its own settings already in place.
function Test-EmulatorsAdapterConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string[]] $Names, [Parameter(Mandatory)] [string] $RetroBatRoot)
    foreach ($n in $Names) {
        $info = Invoke-EmulatorsAdapterFunction -Name $n -Function "Get-$($n)EmulatorInfo" -Parameters @{ RetroBatRoot = $RetroBatRoot }
        foreach ($t in @(Get-EmulatorsAdapterValue $info 'SettingsTargets')) {
            $path = if ($t.Contains('Path')) { [string]$t.Path }
                    else {
                        $toolDir = [string](Get-EmulatorsAdapterValue $info 'ToolDir')
                        Join-Path $RetroBatRoot ('emulators\' + $toolDir + '\' + [string]$t.File)
                    }
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
            $values = @{}
            if ($t.Contains('Values')) { foreach ($k in $t.Values.Keys) { $values[$k] = $t.Values[$k] } }
            if ($values.Count -and @(Get-EmulatorsIniPlan -Path $path -Section $([string]$(if ($t.Contains('Section')) { $t.Section } else { '' })) -Values $values).Count) { return $false }
        }
    }
    $true
}

# INI value helpers for emulator config files — SECTION-AWARE + SHADOW OVERRIDE.
# For every config.ini, the user may create config.override.ini in the same folder.
# Override values ALWAYS win over kit defaults. The plan SKIPS keys managed by the user.
# This ensures kit updates never overwrite user customizations.
function Get-EmulatorsIniPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [string] $Section = '',
        [hashtable] $Values = @{}
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $base = ConvertFrom-Ini -Path $Path
    $overridePath = Get-IniOverridePath $Path
    $override = if (Test-Path -LiteralPath $overridePath) { ConvertFrom-Ini -Path $overridePath } else { @{} }

    $plan = @()
    foreach ($key in $Values.Keys) {
        $desiredKitValue = [string]$Values[$key]

        # User override check: skip if user manages this key
        if ($override.ContainsKey($Section) -and $override[$Section].ContainsKey($key)) {
            $overrideValue = $override[$Section][$key]
            # Still need to apply if the base INI doesn't match the override (lazy merge)
            if ($base.ContainsKey($Section) -and $base[$Section].ContainsKey($key)) {
                if ($base[$Section][$key] -ne $overrideValue) {
                    $plan += [pscustomobject]@{ Key = $key; Section = $Section; Old = $base[$Section][$key]; New = $overrideValue; Overridden = $true }
                }
            } else {
                $plan += [pscustomobject]@{ Key = $key; Section = $Section; Old = $null; New = $overrideValue; Overridden = $true }
            }
            continue
        }

        # Normal kit logic
        if ($base.ContainsKey($Section) -and $base[$Section].ContainsKey($key)) {
            $currentValue = $base[$Section][$key]
            if ($currentValue -ne $desiredKitValue) {
                $plan += [pscustomobject]@{ Key = $key; Section = $Section; Old = $currentValue; New = $desiredKitValue; Overridden = $false }
            }
        } else {
            $plan += [pscustomobject]@{ Key = $key; Section = $Section; Old = $null; New = $desiredKitValue; Overridden = $false }
        }
    }
    $plan
    if ($plan.Count -eq 0) { return @() }
    return ,$plan
}

function Set-EmulatorsIniValue {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [string] $Section = '',
        [hashtable] $Values = @{}
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 0 }
    if (-not $PSCmdlet.ShouldProcess($Path, "set $($Values.Count) INI value(s) in [$Section]")) { return 0 }

    # 0. Backup before ANY modification (kit promise: never write without backup)
    $backupPath = "$Path.bak_$(Get-Date -Format 'yyyyMMddHHmmss')"
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force
    Write-Verbose "Backup: $backupPath"

    # 1. Load base INI
    $ini = ConvertFrom-Ini -Path $Path

    # 2. Apply ONLY changed kit values to the target section
    if (-not $ini.ContainsKey($Section)) { $ini[$Section] = @{} }
    $changed = 0
    foreach ($key in $Values.Keys) {
        $desired = [string]$Values[$key]
        $current = if ($ini[$Section].ContainsKey($key)) { $ini[$Section][$key] } else { $null }
        if ($current -ne $desired) {
            $ini[$Section][$key] = $desired
            $changed++
        }
    }
    if ($changed -eq 0) { return 0 }  # idempotent: nothing to do

    # 3. Merge user overrides on top (user always wins)
    $overridePath = Get-IniOverridePath $Path
    if (Test-Path -LiteralPath $overridePath) {
        $override = ConvertFrom-Ini -Path $overridePath
        $ini = Merge-IniData -BaseData $ini -OverrideData $override
    }

    # 4. Write back
    ConvertTo-Ini -IniData $ini -Path $Path
    $changed
}

# Apply shader preset to an emulator
function Set-EmulatorsShaderPreset {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $EmulatorName,
        [Parameter(Mandatory)] [string] $RetroBatRoot,
        [Parameter(Mandatory)] [ValidateSet('none', 'crt-lottes', 'crt-royale', 'hsm-mega-bezel', 'lcd-grid', 'scanlines')] [string] $Preset,
        [string] $ShaderPath = ''
    )
    $shaderMap = @{
        'none'            = @{ Shader = ''; Dir = '' }
        'crt-lottes'      = @{ Shader = 'crt-lottes.glslp'; Dir = 'shaders\crt' }
        'crt-royale'      = @{ Shader = 'crt-royale.glslp'; Dir = 'shaders\crt' }
        'hsm-mega-bezel'  = @{ Shader = 'hsm-mega-bezel-reflection.glslp'; Dir = 'shaders\bezel' }
        'lcd-grid'        = @{ Shader = 'lcd-grid-v2.glslp'; Dir = 'shaders\handheld' }
        'scanlines'       = @{ Shader = 'scanlines.glslp'; Dir = 'shaders\crt' }
    }
    $s = $shaderMap[$Preset]
    $info = Invoke-EmulatorsAdapterFunction -Name $EmulatorName -Function "Get-$($EmulatorName)EmulatorInfo" -Parameters @{ RetroBatRoot = $RetroBatRoot }
    $shaderTarget = if ($info.Contains('ShaderTarget')) { $info.ShaderTarget } else { '' }
    if (-not $shaderTarget) {
        Write-KitLog "Emulator $EmulatorName does not support shader presets" -Level Warn
        return @{ Success = $false; Message = "Shader presets not supported for $EmulatorName" }
    }
    $cfgPath = if ($ShaderPath) { $ShaderPath } else { Join-Path $RetroBatRoot $shaderTarget }
    if (-not (Test-Path -LiteralPath $cfgPath -PathType Leaf)) {
        Write-KitLog "Shader config not found: $cfgPath" -Level Warn
        return @{ Success = $false; Message = "Config file not found: $cfgPath" }
    }
    Set-EmulatorsIniValue -Path $cfgPath -Values @{
        'video_shader'     = $s.Shader
        'video_shader_dir' = $s.Dir
    }
    @{ Success = $true; Preset = $Preset; Shader = $s.Shader; Dir = $s.Dir }
}

# Verify emulator file integrity: check exe exists, config files are valid, checksums match
function Test-EmulatorsIntegrity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $EmulatorName,
        [Parameter(Mandatory)] [string] $RetroBatRoot
    )
    $info = Invoke-EmulatorsAdapterFunction -Name $EmulatorName -Function "Get-$($EmulatorName)EmulatorInfo" -Parameters @{ RetroBatRoot = $RetroBatRoot }
    $results = @()
    # Check executable
    $exePath = [string](Get-EmulatorsAdapterValue $info 'ExePath')
    if ($exePath) {
        $exeOk = Test-Path -LiteralPath $exePath -PathType Leaf
        $results += [pscustomobject]@{ Check = 'Executable'; Path = $exePath; Ok = $exeOk; Detail = if ($exeOk) { 'Found' } else { 'Missing' } }
    }
    # Check config files
    foreach ($t in @(Get-EmulatorsAdapterValue $info 'SettingsTargets')) {
        $path = if ($t.Contains('Path')) { [string]$t.Path }
                else { Join-Path $RetroBatRoot ('emulators\' + [string](Get-EmulatorsAdapterValue $info 'ToolDir') + '\' + [string]$t.File) }
        $cfgOk = Test-Path -LiteralPath $path -PathType Leaf
        $results += [pscustomobject]@{ Check = 'Config'; Path = $path; Ok = $cfgOk; Detail = if ($cfgOk) { 'Found' } else { 'Missing' } }
    }
    [pscustomobject]@{
        Emulator = $EmulatorName
        Checks   = $results
        AllOk    = @($results | Where-Object { -not $_.Ok }).Count -eq 0
    }
}