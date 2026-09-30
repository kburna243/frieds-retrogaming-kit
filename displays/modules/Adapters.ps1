# Display adapter plugins: one <Name>.ps1 per tool in displays\adapters\, same five-function shape as
# the lightgun/arcade adapters (Test / Get-Info / Install / Configure / Shield), but display adapters are
# detected by PROCESS, PORT, EDID and supported boards — and it is explicitly MULTI: a cabinet can
# run multiple display tools simultaneously for different outputs (monitor, DMD, backglass, topper).

function Get-DisplaysAdapterCatalog {
    [CmdletBinding()]
    param([string] $Dir = (Get-DisplaysAdapterDir))
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

function Invoke-DisplaysAdapterFunction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Function,
        [string] $Dir = (Get-DisplaysAdapterDir),
        [hashtable] $Parameters = @{}
    )
    if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$') { throw (Get-KitText 'Displays.Adapter.NotFound' -f $Name) }
    $file = Join-Path $Dir "$Name.ps1"
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw (Get-KitText 'Displays.Adapter.NotFound' -f $Name) }
    . $file
    if (-not (Get-Command $Function -ErrorAction SilentlyContinue)) { throw (Get-KitText 'Displays.Adapter.MissingFunction' -f $Name, $Function) }
    & $Function @Parameters
}

function Get-DisplaysAdapterValue($Info, [string] $Key) { if ($Info -and $Info.Contains($Key)) { $Info[$Key] } }

# Snapshot of the machine a display adapter probe may read. Without -Snapshot the real system answers:
# running process names, listening TCP ports, present PnP devices, RetroBat tools folder, monitor EDID.
# Tests inject their own hashtable so nothing on the machine is touched.
function Get-DisplaysSystemSnapshot {
    [CmdletBinding()]
    param([string] $RetroBatRoot = '')
    @{
        Processes = @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $_.Name.ToLowerInvariant() })
        Ports     = @(try { @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | ForEach-Object { [int]$_.LocalPort }) } catch { @() })
        Devices   = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue)
        Monitors  = @(Get-DisplayMonitorEdid)
        Root      = $RetroBatRoot
    }
}

# Detect ALL display adapters in use (multi), plus the structured conflicts:
# EDIDConflict (duplicate monitor signatures) and PortConflict (a wanted port is already held by someone else).
function Get-DisplaysDetectedAdapters {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [hashtable] $Snapshot,
        [string] $Dir = (Get-DisplaysAdapterDir),
        [switch] $Quiet
    )
    if (-not $PSBoundParameters.ContainsKey('Snapshot')) { $Snapshot = Get-DisplaysSystemSnapshot -RetroBatRoot $RetroBatRoot }
    $errors = New-Object Collections.Generic.List[string]
    $scanned = New-Object Collections.Generic.List[string]
    $detected = New-Object Collections.Generic.List[object]
    foreach ($a in (Get-DisplaysAdapterCatalog -Dir $Dir)) {
        if ($a.HasParseErrors -or -not ($a.HasTest -and $a.HasInfo)) {
            $reason = if ($a.HasParseErrors) { 'syntax' } elseif (-not $a.HasTest) { "Test-$($a.Name)Hardware" } else { "Get-$($a.Name)AdapterInfo" }
            $errors.Add((Get-KitText 'Displays.Adapter.Incomplete' -f $a.Name, $reason))
            if (-not $Quiet) { Write-KitLog (Get-KitText 'Displays.Adapter.Incomplete' -f $a.Name, $reason) -Level Warn }
            continue
        }
        $scanned.Add($a.Name)
        try {
            $present = [bool](Invoke-DisplaysAdapterFunction -Name $a.Name -Function "Test-$($a.Name)Hardware" -Parameters @{ RetroBatRoot = $RetroBatRoot; Snapshot = $Snapshot })
            if (-not $present) { continue }
            $info = Invoke-DisplaysAdapterFunction -Name $a.Name -Function "Get-$($a.Name)AdapterInfo"
            $detected.Add([pscustomobject]@{
                Name       = $a.Name
                AdapterType = [string](Get-DisplaysAdapterValue $info 'AdapterType'))  # e.g., Monitor, DMD, Backglass, Topper
                EdidSignature = [string](Get-DisplaysAdapterValue $info 'EdidSignature'))  # Manufacturer+ProductCode+SerialNumber hash
                Ports      = @(Get-DisplaysAdapterValue $info 'DetectPorts')
            })
        } catch {
            $errors.Add((Get-KitText 'Displays.Adapter.Error' -f $a.Name, $_.Exception.Message))
            if (-not $Quiet) { Write-KitLog (Get-KitText 'Displays.Adapter.Error' -f $a.Name, $_.Exception.Message) -Level Error }
        }
    }
    $conflicts = New-Object Collections.Generic.List[object]
    $signatures = @($detected | ForEach-Object { $_.EdidSignature } | Where-Object { $_ } | Group-Object)
    foreach ($group in $signatures) {
        if ($group.Count -gt 1) {
            $conflicts.Add([pscustomobject]@{ Kind = 'EdidConflict'; Detail = (Get-KitText 'Displays.Conflict.Edid' -f ($group.Group | ForEach-Object { $_.Name }) -join '+', $group.Name) })
        }
    }
    foreach ($p in @($detected | ForEach-Object { $_.Ports } | Where-Object { $_ } | Select-Object -Unique)) {
        # Two detected adapters claiming the same TCP port: whoever binds first steals the events.
        $sharing = @($detected | Where-Object { $_.Ports -contains $p })
        if ($sharing.Count -gt 1) {
            $conflicts.Add([pscustomobject]@{ Kind = 'PortConflict'; Detail = (Get-KitText 'Displays.Conflict.Port' -f (($sharing | ForEach-Object { $_.Name }) -join '+'), $p) })
        }
    }
    $names = @($detected | ForEach-Object { $_.Name })
    # @($list) on a List[object] throws "argument types do not match" under PS 5.1 (List[string] is
    # fine) — object lists therefore go through ToArray().
    [pscustomobject]@{
        Success          = ($names.Count -gt 0)
        DetectedAdapters = $names
        DetectedDetails  = $detected.ToArray()
        Conflicts        = $conflicts.ToArray()
        ScannedAdapters  = ($scanned -join ',')
        Errors           = @($errors)
        NextStep         = $(if ($names.Count) { "Set-DisplaysAdapterConfiguration -Names ($($names -join ', '))" } else { '' })
    }
}

# Public route into a display adapter's Install-<Name>Software (link only, or local ZIP with -Approved).
function Install-DisplaysAdapter {
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
    Invoke-DisplaysAdapterFunction -Name $Name -Function "Install-$($Name)Software" -Parameters $params
}

# Apply all detected display adapters. Configuration files are touched only where they already exist;
# safety values (backlight limits, DMD frame timing) are enforced with the same backup/WhatIf path as everything else.
function Set-DisplaysAdapterConfiguration {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string[]] $Names,
        [Parameter(Mandatory)] [string] $RetroBatRoot
    )
    if (-not $PSCmdlet.ShouldProcess(($Names -join ', '), 'configure display adapters')) { return 0 }
    $changes = 0
    foreach ($n in $Names) {
        $info = Invoke-DisplaysAdapterFunction -Name $n -Function "Get-$($n)AdapterInfo"
        $toolDir = [string](Get-DisplaysAdapterValue $info 'ToolDir')
        foreach ($t in @(Get-DisplaysAdapterValue $info 'SettingsTargets')) {
            $path = if ($t.Contains('Path')) { [string]$t.Path } else { Join-Path $RetroBatRoot ('tools\' + $toolDir + '\' + [string]$t.File) }
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                Write-KitLog (Get-KitText 'Displays.Adapter.NoSettings' -f $path) -Level Warn
                continue
            }
            $values = @{}
            if ($t.Contains('Safety')) { foreach ($k in $t.Safety.Keys) { $values[$k] = $t.Safety[$k] } }
            if ($t.Contains('Values')) { foreach ($k in $t.Values.Keys) { $values[$k] = $t.Values[$k] } }
            if ($values.Count) { $changes += Set-DisplaysIniValue -Path $path -Section $([string]$(if ($t.Contains('Section')) { $t.Section } else { '' })) -Values $values -Confirm:$false }
        }
    }
    Write-KitLog (Get-KitText 'Displays.Adapter.Changes' -f ($Names -join '+'), $changes)
    $changes
}

# True when every detected display adapter finds its own settings already in place.
function Test-DisplaysAdapterConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string[]] $Names, [Parameter(Mandatory)] [string] $RetroBatRoot)
    foreach ($n in $Names) {
        $info = Invoke-DisplaysAdapterFunction -Name $n -Function "Get-$($n)AdapterInfo"
        $toolDir = [string](Get-DisplaysAdapterValue $info 'ToolDir')
        foreach ($t in @(Get-DisplaysAdapterValue $info 'SettingsTargets')) {
            $path = if ($t.Contains('Path')) { [string]$t.Path } else { Join-Path $RetroBatRoot ('tools\' + $toolDir + '\' + [string]$t.File) }
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }   # tool active but no settings file: safety unproven, stay red
            $values = @{}
            if ($t.Contains('Safety')) { foreach ($k in $t.Safety.Keys) { $values[$k] = $t.Safety[$k] } }
            if ($t.Contains('Values')) { foreach ($k in $t.Values.Keys) { $values[$k] = $t.Values[$k] } }
            if ($values.Count -and @(Get-DisplaysIniPlan -Path $path -Section $([string]$(if ($t.Contains('Section')) { $t.Section } else { '' })) -Values $values).Count) { return $false }
        }
    }
    $true
}