# Output middleware plugins: one <Name>.ps1 per tool in output\adapters\, same five-function shape as
# the lightgun/arcade adapters (Test / Get-Info / Install / Configure / Shield), but middleware is
# detected by PROCESS, PORT, OWN FILES and supported boards — and it is explicitly MULTI: a cabinet can
# run Hook of the Reaper for the gun solenoid AND MAMEHooker for the lights at the same time. Only the
# mame.ini key "output" is exclusive: windows (MAMEHooker, HotR) vs network (qMamehook); a detected
# conflict is reported as a structured object and never resolved by force.

function Get-OutputAdapterCatalog {
    [CmdletBinding()]
    param([string] $Dir = (Get-OutputAdapterDir))
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

function Invoke-OutputAdapterFunction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Function,
        [string] $Dir = (Get-OutputAdapterDir),
        [hashtable] $Parameters = @{}
    )
    if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$') { throw (Get-KitText 'Output.Adapter.NotFound' -f $Name) }
    $file = Join-Path $Dir "$Name.ps1"
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw (Get-KitText 'Output.Adapter.NotFound' -f $Name) }
    . $file
    if (-not (Get-Command $Function -ErrorAction SilentlyContinue)) { throw (Get-KitText 'Output.Adapter.MissingFunction' -f $Name, $Function) }
    & $Function @Parameters
}

function Get-OutputAdapterValue($Info, [string] $Key) { if ($Info -and $Info.Contains($Key)) { $Info[$Key] } }

# Snapshot of the machine a middleware probe may read. Without -Snapshot the real system answers:
# running process names, listening TCP ports, present PnP devices, RetroBat tools folder.
# Tests inject their own hashtable so nothing on the machine is touched.
function Get-OutputSystemSnapshot {
    [CmdletBinding()]
    param([string] $RetroBatRoot = '')
    @{
        Processes = @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $_.Name.ToLowerInvariant() })
        Ports     = @(try { @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | ForEach-Object { [int]$_.LocalPort }) } catch { @() })
        Devices   = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue)
        Root      = $RetroBatRoot
    }
}

# Detect ALL middlewares in use (multi), plus the structured conflicts the docs asked for:
# OutputModeConflict (mame "output" cannot be windows AND network at once) and
# PortConflict (a wanted port is already held by someone else).
function Get-OutputDetectedMiddleware {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [hashtable] $Snapshot,
        [string] $Dir = (Get-OutputAdapterDir),
        [switch] $Quiet
    )
    if (-not $PSBoundParameters.ContainsKey('Snapshot')) { $Snapshot = Get-OutputSystemSnapshot -RetroBatRoot $RetroBatRoot }
    $errors = New-Object Collections.Generic.List[string]
    $scanned = New-Object Collections.Generic.List[string]
    $detected = New-Object Collections.Generic.List[object]
    foreach ($a in (Get-OutputAdapterCatalog -Dir $Dir)) {
        if ($a.HasParseErrors -or -not ($a.HasTest -and $a.HasInfo)) {
            $reason = if ($a.HasParseErrors) { 'syntax' } elseif (-not $a.HasTest) { "Test-$($a.Name)Hardware" } else { "Get-$($a.Name)AdapterInfo" }
            $errors.Add((Get-KitText 'Output.Adapter.Incomplete' -f $a.Name, $reason))
            if (-not $Quiet) { Write-KitLog (Get-KitText 'Output.Adapter.Incomplete' -f $a.Name, $reason) -Level Warn }
            continue
        }
        $scanned.Add($a.Name)
        try {
            $present = [bool](Invoke-OutputAdapterFunction -Name $a.Name -Function "Test-$($a.Name)Hardware" -Parameters @{ RetroBatRoot = $RetroBatRoot; Snapshot = $Snapshot })
            if (-not $present) { continue }
            $info = Invoke-OutputAdapterFunction -Name $a.Name -Function "Get-$($a.Name)AdapterInfo"
            $detected.Add([pscustomobject]@{
                Name       = $a.Name
                OutputMode = [string](Get-OutputAdapterValue $info 'MameOutput')
                Ports      = @(Get-OutputAdapterValue $info 'DetectPorts')
            })
        } catch {
            $errors.Add((Get-KitText 'Output.Adapter.Error' -f $a.Name, $_.Exception.Message))
            if (-not $Quiet) { Write-KitLog (Get-KitText 'Output.Adapter.Error' -f $a.Name, $_.Exception.Message) -Level Error }
        }
    }
    $conflicts = New-Object Collections.Generic.List[object]
    $modes = @($detected | Where-Object { $_.OutputMode } | ForEach-Object { $_.OutputMode } | Select-Object -Unique)
    if ($modes.Count -gt 1) {
        $who = (@($detected | ForEach-Object { "$($_.Name)=$($_.OutputMode)" }) -join ', ')
        $conflicts.Add([pscustomobject]@{ Kind = 'OutputModeConflict'; Detail = (Get-KitText 'Output.Conflict.OutputMode' -f $who) })
    }
    foreach ($p in @($detected | ForEach-Object { $_.Ports } | Where-Object { $_ } | Select-Object -Unique)) {
        # Two detected middlewares claiming the same TCP port: whoever binds first steals the events.
        $sharing = @($detected | Where-Object { $_.Ports -contains $p })
        if ($sharing.Count -gt 1) {
            $conflicts.Add([pscustomobject]@{ Kind = 'PortConflict'; Detail = (Get-KitText 'Output.Conflict.Port' -f (($sharing | ForEach-Object { $_.Name }) -join '+'), $p) })
        }
    }
    $names = @($detected | ForEach-Object { $_.Name })
    # @($list) on a List[object] throws "argument types do not match" under PS 5.1 (List[string] is
    # fine) — object lists therefore go through ToArray().
    [pscustomobject]@{
        Success          = ($names.Count -gt 0)
        DetectedOutputs  = $names
        DetectedAdapters = $detected.ToArray()
        OutputMode       = $(if ($modes.Count -eq 1) { $modes[0] } else { '' })
        Conflicts        = $conflicts.ToArray()
        ScannedAdapters  = ($scanned -join ',')
        Errors           = @($errors)
        NextStep         = $(if ($names.Count) { "Set-OutputMiddlewareConfiguration -Names ($($names -join ', '))" } else { '' })
    }
}

# Public route into a middleware's Install-<Name>Software (link only, or local ZIP with -Approved).
function Install-OutputMiddleware {
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
    Invoke-OutputAdapterFunction -Name $Name -Function "Install-$($Name)Software" -Parameters $params
}

# Apply all detected middlewares. mame.ini "output" is written only when the detected tools agree on
# one mode; otherwise the conflict stays in the report and the key is left alone (NeedsUser, not force).
# Settings files are touched only where they already exist; safety values (solenoid current limits)
# are enforced with the same backup/WhatIf path as everything else.
function Set-OutputMiddlewareConfiguration {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string[]] $Names,
        [Parameter(Mandatory)] [string] $RetroBatRoot
    )
    if (-not $PSCmdlet.ShouldProcess(($Names -join ', '), 'configure output middleware')) { return 0 }
    # Get-LightgunAdapterFiles only joins paths — middleware lives or dies with the real files:
    # mame.ini and every settings file is touched strictly when it exists (no phantom installs).
    $mameIni = Join-Path $RetroBatRoot 'emulators\mame\mame.ini'
    $changes = 0
    $modes = @(); $settingsTargets = @()
    foreach ($n in $Names) {
        $info = Invoke-OutputAdapterFunction -Name $n -Function "Get-$($n)AdapterInfo"
        if ((Get-OutputAdapterValue $info 'MameOutput')) { $modes += [string](Get-OutputAdapterValue $info 'MameOutput') }
        $tool = [string](Get-OutputAdapterValue $info 'ToolDir')
        foreach ($t in @(Get-OutputAdapterValue $info 'SettingsTargets')) { $settingsTargets += , @{ T = $t; Tool = $tool } }
    }
    $uniqueModes = @($modes | Select-Object -Unique)
    if ($uniqueModes.Count -eq 1) {
        if (Test-Path -LiteralPath $mameIni -PathType Leaf) {
            $changes += Set-LightgunMameIniValue -Path $mameIni -Values @{ output = $uniqueModes[0] } -Confirm:$false
        } else {
            Write-KitLog (Get-KitText 'Output.Adapter.NoSettings' -f $mameIni) -Level Warn
        }
    } elseif ($uniqueModes.Count -gt 1) {
        Write-KitLog (Get-KitText 'Output.Conflict.SkipMame' -f ($uniqueModes -join '/')) -Level Warn
    }
    foreach ($e in $settingsTargets) {
        $t = $e.T
        $path = if ($t.Contains('Path')) { [string]$t.Path } else { Join-Path $RetroBatRoot ('tools\' + $e.Tool + '\' + [string]$t.File) }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            Write-KitLog (Get-KitText 'Output.Adapter.NoSettings' -f $path) -Level Warn
            continue
        }
        $values = @{}
        if ($t.Contains('Safety')) { foreach ($k in $t.Safety.Keys) { $values[$k] = $t.Safety[$k] } }
        if ($t.Contains('Values')) { foreach ($k in $t.Values.Keys) { $values[$k] = $t.Values[$k] } }
        if ($values.Count) { $changes += Set-LightgunIniValue -Path $path -Section $([string]$(if ($t.Contains('Section')) { $t.Section } else { '' })) -Values $values -Confirm:$false }
    }
    Write-KitLog (Get-KitText 'Output.Adapter.Changes' -f ($Names -join '+'), $changes)
    $changes
}

# True when every detected middleware finds its own settings already in place.
function Test-OutputMiddlewareConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string[]] $Names, [Parameter(Mandatory)] [string] $RetroBatRoot)
    $mameIni = Join-Path $RetroBatRoot 'emulators\mame\mame.ini'
    $modes = @()
    $tools = @{}
    foreach ($n in $Names) {
        $info = Invoke-OutputAdapterFunction -Name $n -Function "Get-$($n)AdapterInfo"
        if ((Get-OutputAdapterValue $info 'MameOutput')) { $modes += [string](Get-OutputAdapterValue $info 'MameOutput') }
        $tools[$n] = $info
    }
    $uniqueModes = @($modes | Select-Object -Unique)
    if ($uniqueModes.Count -gt 1) { return $false }
    if ($uniqueModes.Count -eq 1 -and (Test-Path -LiteralPath $mameIni -PathType Leaf)) {
        if (@(Get-LightgunMameIniPlan -Path $mameIni -Values @{ output = $uniqueModes[0] }).Count) { return $false }
    }
    foreach ($n in $Names) {
        $info = $tools[$n]
        $tool = [string](Get-OutputAdapterValue $info 'ToolDir')
        foreach ($t in @(Get-OutputAdapterValue $info 'SettingsTargets')) {
            $path = if ($t.Contains('Path')) { [string]$t.Path } else { Join-Path $RetroBatRoot ('tools\' + $tool + '\' + [string]$t.File) }
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }   # tool active but no settings file: safety unproven, stay red
            $values = @{}
            if ($t.Contains('Safety')) { foreach ($k in $t.Safety.Keys) { $values[$k] = $t.Safety[$k] } }
            if ($t.Contains('Values')) { foreach ($k in $t.Values.Keys) { $values[$k] = $t.Values[$k] } }
            if ($values.Count -and @(Get-LightgunIniPlan -Path $path -Section $([string]$(if ($t.Contains('Section')) { $t.Section } else { '' })) -Values $values).Count) { return $false }
        }
    }
    $true
}
