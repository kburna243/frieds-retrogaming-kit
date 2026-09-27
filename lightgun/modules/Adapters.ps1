# Adapters (step 15): USB lightgun systems as a second route beside the Wiimote/DolphinBar path
# (Gun4IR, OpenFIRE, AimTrak, Retro Shooter). A community adapter is one file in lightgun\adapters\<Name>.ps1
# following the contract of _Template.ps1:
#   Test-<Name>Hardware -RetroBatRoot <string> [-Devices <object[]>]   read-only detection, must work standalone
#   Get-<Name>AdapterInfo                                            data table (VIDs, ini values, links)
#   Install-<Name>Software / Configure-<Name>Profile / Set-<Name>InterferenceShield   use this module's helpers
# Files starting with '_' are templates and are never executed. Discovery and configuration only ever run
# functions of the file they just loaded; nothing is downloaded from hosts outside the core allow-list.

function Get-LightgunAdapterDir {
    [CmdletBinding()]
    param()
    Join-Path $script:LightgunDir 'adapters'
}

# The adapter folder as data, without executing anything: the parser lists the functions of every file.
function Get-LightgunAdapterCatalog {
    [CmdletBinding()]
    param([string] $Dir)
    if (-not $PSBoundParameters.ContainsKey('Dir')) { $Dir = Get-LightgunAdapterDir }
    foreach ($f in @(Get-ChildItem -LiteralPath $Dir -Filter '*.ps1' -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -notlike '_*' } | Sort-Object Name)) {
        $name = $f.BaseName
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref] $tokens, [ref] $errors)
        $funcs = @(if ($ast) { foreach ($d in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) { $d.Name } })
        [pscustomobject]@{
            Name     = $name
            Path     = $f.FullName
            HasParseErrors = (@($errors).Count -gt 0)
            HasTest  = [bool]($funcs -contains "Test-${name}Hardware")
            HasInfo  = [bool]($funcs -contains "Get-${name}AdapterInfo")
            HasInstall = [bool]($funcs -contains "Install-${name}Software")
            HasConfigure = [bool]($funcs -contains "Configure-${name}Profile")
            HasShield = [bool]($funcs -contains "Set-${name}InterferenceShield")
        }
    }
}

# Loads one adapter file into the module scope and calls one of its functions. Only the file name derived
# from -Name (a catalog entry) is executed, never a caller-supplied path.
function Invoke-LightgunAdapterFunction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Function,
        [string] $Dir,
        [hashtable] $Parameters = @{}
    )
    if (-not $PSBoundParameters.ContainsKey('Dir')) { $Dir = Get-LightgunAdapterDir }
    if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$') { throw (Get-KitText 'Lightgun.Adapter.NotFound' -f $Name) }
    $file = Join-Path $Dir "$Name.ps1"
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw (Get-KitText 'Lightgun.Adapter.NotFound' -f $Name) }
    . $file
    if (-not (Get-Command $Function -ErrorAction SilentlyContinue)) { throw (Get-KitText 'Lightgun.Adapter.MissingFunction' -f $Name, $Function) }
    & $Function @Parameters
}

# Instance id of a PnP/CIM device object or a plain string (adapters and tests use both).
function Get-LightgunDeviceId($Device) {
    if ($Device -is [string]) { return $Device }
    if ($Device.PSObject.Properties['InstanceId']) { return [string]$Device.InstanceId }
    if ($Device.PSObject.Properties['DeviceID']) { return [string]$Device.DeviceID }
    [string]$Device
}

function Get-LightgunDeviceName($Device) {
    if ($Device -is [string]) { return '' }
    foreach ($prop in 'FriendlyName', 'Name') {
        if ($Device.PSObject.Properties[$prop] -and [string]$Device.($prop)) { return [string]$Device.($prop) }
    }
    ''
}

# First instance id whose pattern matches one of -Patterns ('*x*' or plain substring; case-insensitive).
function Get-LightgunDeviceMatch {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [object[]] $Devices, [Parameter(Mandatory)] [string[]] $Patterns)
    foreach ($d in $Devices) {
        $id = Get-LightgunDeviceId $d
        foreach ($p in $Patterns) {
            if ($p -and ($id -like $p -or $id -like "*$p*")) { return $id }
        }
    }
    ''
}

# Scans the adapter folder and asks every adapter (read-only) whether its hardware is present.
# Result (stable field names, agent-friendly): Success, DetectedAdapter, DetectedDeviceId,
# ScannedAdapters, Errors, NextStep. The first adapter that matches wins; multi-gun wiring lives in the
# adapter's own Configure step.
function Get-LightgunDetectedAdapter {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [object[]] $Devices,
        [string] $Dir,
        [switch] $Quiet
    )
    if (-not $PSBoundParameters.ContainsKey('Devices')) { $Devices = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue) }
    if (-not $PSBoundParameters.ContainsKey('Dir')) { $Dir = Get-LightgunAdapterDir }
    $detected = $null; $detectedId = ''; $scanned = @(); $errors = @()
    foreach ($a in @(Get-LightgunAdapterCatalog -Dir $Dir)) {
        $test = "Test-$($a.Name)Hardware"
        if ($a.HasParseErrors -or -not $a.HasTest) {
            $msg = Get-KitText 'Lightgun.Adapter.Incomplete' -f $a.Name, $test
            if (-not $Quiet) { Write-KitLog $msg -Level Warn }
            $errors += $msg
            continue
        }
        $scanned += $a.Name
        if (-not $Quiet) { Write-KitLog (Get-KitText 'Lightgun.Adapter.Scanning' -f $a.Name) }
        try {
            $params = @{ Devices = $Devices }
            if ($RetroBatRoot) { $params.RetroBatRoot = $RetroBatRoot }
            $hit = Invoke-LightgunAdapterFunction -Name $a.Name -Function $test -Dir $Dir -Parameters $params
        } catch {
            $msg = Get-KitText 'Lightgun.Adapter.Error' -f $a.Name, $_.Exception.Message
            if (-not $Quiet) { Write-KitLog $msg -Level Warn }
            $errors += $msg
            continue
        }
        if ($hit) {
            $detected = $a.Name
            try {
                $info = Invoke-LightgunAdapterFunction -Name $a.Name -Function "Get-$($a.Name)AdapterInfo" -Dir $Dir
                $ids = if ($info -and $info.Contains('MatchIds')) { @($info['MatchIds']) } else { @() }
                $detectedId = if ($ids.Count) { Get-LightgunDeviceMatch -Devices $Devices -Patterns $ids } else { '' }
            } catch { $detectedId = '' }
            break
        }
    }
    if ($detected) {
        if (-not $Quiet) { Write-KitLog (Get-KitText 'Lightgun.Adapter.Detected' -f $detected) }
    } elseif (-not $Quiet) {
        Write-KitLog (Get-KitText 'Lightgun.Adapter.None') -Level Warn
    }
    [pscustomobject]@{
        Success          = [bool]$detected
        DetectedAdapter  = $detected
        DetectedDeviceId = $detectedId
        ScannedAdapters  = $scanned
        Errors           = $errors
        NextStep         = if ($detected) { "Install-$($detected)Software" } else { '' }
    }
}

# --- mame.ini: MAME's own option file uses "name<whitespace>value", no '=' -------------------------------

# Plan (Name, Pad, Old, New, Action) for the space-separated MAME values.
function Get-LightgunMameIniPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [Collections.IDictionary] $Values)
    $found = @{}
    foreach ($l in @(Read-LightgunIniLine $Path)) {
        if ($l -match '^\s*([A-Za-z][A-Za-z0-9_]*)(\s+)(\S.*?)\s*$') {
            if (-not $found.ContainsKey($Matches[1])) { $found[$Matches[1]] = @{ Pad = $Matches[2]; Value = $Matches[3] } }
        }
    }
    foreach ($k in $Values.Keys) {
        $old = if ($found.ContainsKey($k)) { $found[$k].Value } else { $null }
        if ($old -cne [string]$Values[$k]) {
            [pscustomobject]@{ File = $Path; Name = $k; Pad = $(if ($null -eq $old) { ' ' } else { $found[$k].Pad }); Old = $old; New = [string]$Values[$k]; Action = $(if ($null -eq $old) { 'Add' } else { 'Change' }) }
        }
    }
}

# Writes the plan (backup first, encoding and line ends stay). Missing keys are appended aligned to the
# column the file already uses (26 by default). Returns the number of changes.
function Set-LightgunMameIniValue {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [Collections.IDictionary] $Values)
    $plan = @(Get-LightgunMameIniPlan -Path $Path -Values $Values)
    if (-not $plan) { return 0 }
    if (-not $PSCmdlet.ShouldProcess($Path, "$($plan.Count) MAME value(s)")) { return 0 }
    $exists = Test-Path -LiteralPath $Path -PathType Leaf
    $info = if ($exists) { Get-KitFileEncoding -Path $Path } else { [pscustomobject]@{ CodePage = 65001; BomLength = 0 } }
    $bytes = if ($exists) { [IO.File]::ReadAllBytes($Path) } else { [byte[]]@() }
    $nl = if ($exists -and [Text.Encoding]::GetEncoding($info.CodePage).GetString($bytes).Contains("`r`n")) { "`r`n" } else { "`n" }
    $lines = New-Object Collections.Generic.List[string]
    foreach ($l in @(Read-LightgunIniLine $Path)) { $lines.Add($l) }
    if ($lines.Count -and $lines[$lines.Count - 1] -eq '') { $lines.RemoveAt($lines.Count - 1) }
    # The column the file writes its values at (shortest observed name+pad, default 26 like MAME's own ini).
    $column = 26
    foreach ($l in $lines) {
        if ($l -match '^\s*([A-Za-z][A-Za-z0-9_]*)(\s+)(\S.*?)\s*$') {
            $col = $Matches[1].Length + $Matches[2].Length
            if ($col -ge 2 -and $col -lt $column) { $column = $col }
        }
    }
    $map = @{}; foreach ($c in $plan) { $map[$c.Name] = $c }
    $done = New-Object Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*([A-Za-z][A-Za-z0-9_]*)(\s+)(\S.*?)\s*$' -and $map.ContainsKey($Matches[1])) {
            $c = $map[$Matches[1]]
            $lines[$i] = '{0}{1}{2}' -f $Matches[1], $Matches[2], $c.New
            $null = $done.Add($Matches[1])
        }
    }
    foreach ($c in $plan) {
        if ($done.Contains($c.Name)) { continue }
        $pad = ' ' * [Math]::Max(1, $column - $c.Name.Length)
        $lines.Add(('{0}{1}{2}' -f $c.Name, $pad, $c.New))
    }
    if ($exists) { Assert-LightgunProcessesClosed; $null = Backup-LightgunFile -Path $Path }
    $body = [Text.Encoding]::GetEncoding($info.CodePage).GetBytes((($lines -join $nl) + $nl))
    $out = [byte[]](@($bytes | Select-Object -First $info.BomLength) + $body)
    $tmp = "$Path.tmp"
    [IO.File]::WriteAllBytes($tmp, $out)
    if ($exists) { [IO.File]::Replace($tmp, $Path, [NullString]::Value) } else { Move-Item -LiteralPath $tmp -Destination $Path }
    $plan.Count
}

# Public route into an adapter's Install-<Name>Software (those functions are module-private by contract).
function Install-LightgunAdapter {
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
    Invoke-LightgunAdapterFunction -Name $Name -Function "Install-$($Name)Software" -Parameters $params
}

# --- applying one adapter's data ---------------------------------------------------------------------------

# Read one optional key from an adapter's info hashtable (a missing key must not trip StrictMode).
function Get-LightgunAdapterValue($Info, [string] $Key) { if ($Info -and $Info.Contains($Key)) { $Info[$Key] } }

# All files an adapter touches (existence checks decide what happens; missing files only get a hint).
function Get-LightgunAdapterFiles {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $RetroBatRoot)
    [pscustomobject]@{
        MameIni       = Join-Path $RetroBatRoot 'emulators\mame\mame.ini'
        RetroBatIni   = Join-Path $RetroBatRoot 'retrobat.ini'
        DemulShooter  = Join-Path $RetroBatRoot 'system\demulshooter\DemulShooter.ini'
    }
}

# Changes the adapter would write (same shapes as Get-LightgunIniPlan): for -WhatIf output and tests.
function Get-LightgunAdapterPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Name, [Parameter(Mandatory)] [string] $RetroBatRoot, [string] $DetectedDeviceId = '')
    $info = Invoke-LightgunAdapterFunction -Name $Name -Function "Get-$($Name)AdapterInfo"
    $f = Get-LightgunAdapterFiles -RetroBatRoot $RetroBatRoot
    $mv = Get-LightgunAdapterValue $info 'MameValues'
    $gv = Get-LightgunAdapterValue $info 'GunsValues'
    $se = @(Get-LightgunAdapterValue $info 'SteamEntries')
    if ($mv -and @($mv.Keys).Count -and (Test-Path -LiteralPath $f.MameIni -PathType Leaf)) {
        Get-LightgunMameIniPlan -Path $f.MameIni -Values $mv
    }
    if ($gv -and @($gv.Keys).Count -and (Test-Path -LiteralPath $f.RetroBatIni -PathType Leaf)) {
        Get-LightgunIniPlan -Path $f.RetroBatIni -Section 'Guns' -Values $gv
    }
    if ((Get-LightgunAdapterValue $info 'DemulDevice') -and $DetectedDeviceId -and (Test-Path -LiteralPath $f.DemulShooter -PathType Leaf)) {
        Get-LightgunIniPlan -Path $f.DemulShooter -Section 'Player1' -Values @{ Device = $DetectedDeviceId }
    }
}

# Applies the adapter's data: mame.ini, retrobat.ini [Guns], DemulShooter [Player1] Device (when a device
# id was detected), and the gun VIDs in Steam's controller_blacklist (the kit's shield: Steam Input is
# blocked from grabbing the gun, no process is ever killed). Returns the number of file changes.
function Set-LightgunAdapterConfiguration {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $RetroBatRoot,
        [string] $DetectedDeviceId = '',
        [string] $SteamConfigVdf
    )
    if (-not $PSCmdlet.ShouldProcess($Name, 'configure adapter')) { return 0 }
    $info = Invoke-LightgunAdapterFunction -Name $Name -Function "Get-$($Name)AdapterInfo"
    $f = Get-LightgunAdapterFiles -RetroBatRoot $RetroBatRoot
    $mv = Get-LightgunAdapterValue $info 'MameValues'
    $gv = Get-LightgunAdapterValue $info 'GunsValues'
    $se = @(Get-LightgunAdapterValue $info 'SteamEntries')
    $changes = 0
    if ($mv -and @($mv.Keys).Count) {
        if (Test-Path -LiteralPath $f.MameIni -PathType Leaf) { $changes += Set-LightgunMameIniValue -Path $f.MameIni -Values $mv }
        else { Write-KitLog (Get-KitText 'Lightgun.Adapter.NoMameIni' -f $f.MameIni) -Level Warn }
    }
    if ($gv -and @($gv.Keys).Count) {
        if (Test-Path -LiteralPath $f.RetroBatIni -PathType Leaf) { $changes += Set-LightgunIniValue -Path $f.RetroBatIni -Section 'Guns' -Values $gv }
        else { Write-KitLog (Get-KitText 'Lightgun.Adapter.NoRetroBatIni' -f $f.RetroBatIni) -Level Warn }
    }
    if ((Get-LightgunAdapterValue $info 'DemulDevice') -and $DetectedDeviceId) {
        if (Test-Path -LiteralPath $f.DemulShooter -PathType Leaf) { $changes += Set-LightgunIniValue -Path $f.DemulShooter -Section 'Player1' -Values @{ Device = $DetectedDeviceId } }
    }
    if (-not $PSBoundParameters.ContainsKey('SteamConfigVdf') -and $se.Count) {
        $steam = Get-LightgunSteamPath
        $SteamConfigVdf = if ($steam) { Join-Path $steam 'config\config.vdf' } else { '' }
    }
    if ($se.Count -and $SteamConfigVdf -and (Test-Path -LiteralPath $SteamConfigVdf -PathType Leaf)) {
        $changes += Set-LightgunSteamBlacklist -ConfigVdf $SteamConfigVdf -ExtraEntries $se
    }
    Write-KitLog (Get-KitText 'Lightgun.Adapter.Changes' -f $Name, $changes)
    $changes
}

# True when every value the adapter wants is already in place (Steam included).
function Test-LightgunAdapterConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Name, [Parameter(Mandatory)] [string] $RetroBatRoot, [string] $DetectedDeviceId = '', [string] $SteamConfigVdf)
    $info = Invoke-LightgunAdapterFunction -Name $Name -Function "Get-$($Name)AdapterInfo"
    $f = Get-LightgunAdapterFiles -RetroBatRoot $RetroBatRoot
    $mv = Get-LightgunAdapterValue $info 'MameValues'
    $gv = Get-LightgunAdapterValue $info 'GunsValues'
    $se = @(Get-LightgunAdapterValue $info 'SteamEntries')
    if ($mv -and @($mv.Keys).Count) {
        if (-not (Test-Path -LiteralPath $f.MameIni -PathType Leaf)) { return $false }
        if (@(Get-LightgunMameIniPlan -Path $f.MameIni -Values $mv).Count) { return $false }
    }
    if ($gv -and @($gv.Keys).Count) {
        if (-not (Test-Path -LiteralPath $f.RetroBatIni -PathType Leaf)) { return $false }
        if (@(Get-LightgunIniPlan -Path $f.RetroBatIni -Section 'Guns' -Values $gv).Count) { return $false }
    }
    if ((Get-LightgunAdapterValue $info 'DemulDevice') -and $DetectedDeviceId -and (Test-Path -LiteralPath $f.DemulShooter -PathType Leaf)) {
        if (@(Get-LightgunIniPlan -Path $f.DemulShooter -Section 'Player1' -Values @{ Device = $DetectedDeviceId }).Count) { return $false }
    }
    if (-not $PSBoundParameters.ContainsKey('SteamConfigVdf') -and $se.Count) {
        $steam = Get-LightgunSteamPath
        $SteamConfigVdf = if ($steam) { Join-Path $steam 'config\config.vdf' } else { '' }
    }
    if ($se.Count -and $SteamConfigVdf -and (Test-Path -LiteralPath $SteamConfigVdf -PathType Leaf)) {
        if (-not (Test-LightgunSteamBlacklist -ConfigVdf $SteamConfigVdf -ExtraEntries $se)) { return $false }
    }
    $true
}
