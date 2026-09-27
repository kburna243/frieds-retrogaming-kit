# Arcade adapters: the same plugin pattern the lightgun suite proved — one <Name>.ps1 per device in
# arcade\adapters\, discovered by parsing (never executing) the files, matched by tight VID/PID
# signatures, configured exclusively through lightgun's audited writers (backup, encoding kept,
# process guard, WhatIf, Steam controller_blacklist instead of any process kill).
#
# Class coexistence rule from the input-orchestrator design: lightgun wins. A device the lightgun
# catalog already claims is never re-claimed here, so an OpenFIRE board on 2E8A/000A can never be
# mistaken for a GP2040 or DIY wheel even if a future adapter lists that signature.

function Get-ArcadeAdapterCatalog {
    [CmdletBinding()]
    param([string] $Dir = (Get-ArcadeAdapterDir))
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { return @() }
    $result = @()
    foreach ($file in (Get-ChildItem -LiteralPath $Dir -Filter '*.ps1' -File | Sort-Object Name)) {
        if ($file.Name -like '_*') { continue }
        $name = [IO.Path]::GetFileNameWithoutExtension($file.Name)
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        $funcs = @(if ($ast) { foreach ($d in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) { $d.Name } })
        $result += [pscustomobject]@{
            Name            = $name
            Path            = $file.FullName
            HasParseErrors  = (@($errors).Count -gt 0)
            HasTest         = [bool]($funcs -contains "Test-${name}Hardware")
            HasInfo         = [bool]($funcs -contains "Get-${name}AdapterInfo")
            HasInstall      = [bool]($funcs -contains "Install-${name}Software")
            HasConfigure    = [bool]($funcs -contains "Configure-${name}Profile")
            HasShield       = [bool]($funcs -contains "Set-${name}InterferenceShield")
        }
    }
    $result
}

# Run one function out of one adapter file, by validated name. Same guard as lightgun: no path
# traversal, no arbitrary invocation.
function Invoke-ArcadeAdapterFunction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Function,
        [string] $Dir = (Get-ArcadeAdapterDir),
        [hashtable] $Parameters = @{}
    )
    if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$') { throw (Get-KitText 'Arcade.Adapter.NotFound' -f $Name) }
    $file = Join-Path $Dir "$Name.ps1"
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw (Get-KitText 'Arcade.Adapter.NotFound' -f $Name) }
    . $file
    if (-not (Get-Command $Function -ErrorAction SilentlyContinue)) { throw (Get-KitText 'Arcade.Adapter.MissingFunction' -f $Name, $Function) }
    & $Function @Parameters
}

function Get-ArcadeDeviceId($Device) {
    if ($null -eq $Device) { return '' }
    if ($Device -is [string]) { return $Device }
    if ($Device.PSObject.Properties['InstanceId']) { return [string]$Device.InstanceId }
    if ($Device.PSObject.Properties['DeviceID'])   { return [string]$Device.DeviceID }
    ''
}

function Get-ArcadeDeviceName($Device) {
    if ($null -eq $Device -or $Device -is [string]) { return '' }
    foreach ($p in 'FriendlyName', 'Name', 'Caption') {
        if ($Device.PSObject.Properties[$p]) { return [string]$Device.$p }
    }
    ''
}

# Signature match on the InstanceId: every entry in MatchIds is a full "USB\VID_xxx&PID_yyy*" pattern.
# NameHints are ONLY a fallback for adapters that deliberately carry no MatchIds (GP2040-CE reports the
# same 045E/028E as every XInput pad) — a name like '*TE*' or '*Ultimarc*' must never claim a device on
# its own while real VID/PID signatures exist, or 'USB Com**te*** Device' would match '*te*'.
function Get-ArcadeDeviceMatch {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Device, [string[]] $MatchIds = @(), [string[]] $NameHints = @())
    $id = (Get-ArcadeDeviceId $Device).ToUpperInvariant()
    $nm = (Get-ArcadeDeviceName $Device)
    if (@($MatchIds).Count) {
        foreach ($m in $MatchIds) { if ($id -like $m.ToUpperInvariant()) { return $true } }
        return $false
    }
    foreach ($h in $NameHints) { if ($nm -and $nm -like $h) { return $true } }
    $false
}

# One hardware scan across arcade\adapters\. $Devices replaces the live PnP list (tests, agents);
# -Quiet keeps warnings out of the log. Lightgun devices are excluded up front.
function Get-ArcadeDetectedAdapter {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [object[]] $Devices,
        [string] $Dir = (Get-ArcadeAdapterDir),
        [switch] $Quiet
    )
    if (-not $PSBoundParameters.ContainsKey('Devices')) {
        $Devices = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue)
    }
    $Devices = @($Devices | Where-Object { $_ })
    $claimed = @()
    $gun = Get-LightgunDetectedAdapter -Devices $Devices -Quiet
    if ($gun.DetectedDeviceId) { $claimed += , $gun.DetectedDeviceId.ToUpperInvariant() }

    $errors = New-Object Collections.Generic.List[string]
    $scanned = New-Object Collections.Generic.List[string]
    $detected = $null; $detectedId = ''; $detectedClass = ''; $quirks = @()
    foreach ($a in (Get-ArcadeAdapterCatalog -Dir $Dir)) {
        if ($a.HasParseErrors) {
            $errors.Add((Get-KitText 'Arcade.Adapter.Incomplete' -f $a.Name, 'syntax'))
            if (-not $Quiet) { Write-KitLog (Get-KitText 'Arcade.Adapter.Incomplete' -f $a.Name, 'syntax') -Level Warn }
            continue
        }
        if (-not ($a.HasTest -and $a.HasInfo)) {
            $errors.Add((Get-KitText 'Arcade.Adapter.Incomplete' -f $a.Name, $(if (-not $a.HasTest) { "Test-$($a.Name)Hardware" } else { "Get-$($a.Name)AdapterInfo" })))
            if (-not $Quiet) { Write-KitLog (Get-KitText 'Arcade.Adapter.Incomplete' -f $a.Name, 'function') -Level Warn }
            continue
        }
        $scanned.Add($a.Name)
        $hit = $null
        try {
            if (-not $a.HasTest) { continue }
            $info = Invoke-ArcadeAdapterFunction -Name $a.Name -Function "Get-$($a.Name)AdapterInfo"
            foreach ($d in $Devices) {
                $id = (Get-ArcadeDeviceId $d).ToUpperInvariant()
                if ($id -and $claimed -contains $id) { continue }
                if (Get-ArcadeDeviceMatch -Device $d -MatchIds @(Get-ArcadeAdapterValue $info 'MatchIds') -NameHints @(Get-ArcadeAdapterValue $info 'NameHints')) { $hit = $d; break }
            }
            if ($null -eq $hit) { continue }
            $detected = $a.Name
            $detectedId = Get-ArcadeDeviceId $hit
            $detectedClass = [string](Get-ArcadeAdapterValue $info 'Class')
            $quirks = @(Get-ArcadeAdapterValue $info 'Quirks')
            # Quirk diagnostics read device properties, never localized strings (Code 43 survives any UI language).
            if ($quirks -contains 'usb-descriptor-failed') {
                $code43 = @($Devices | Where-Object { (Get-ArcadeDeviceId $_) -and
                    ($_.PSObject.Properties['ConfigManagerErrorCode'] -and [int]$_.ConfigManagerErrorCode -eq 43) }).Count
                if ($code43) { Write-KitLog (Get-KitText 'Arcade.Quirk.Code43') -Level Warn }
            }
            break
        } catch {
            $errors.Add((Get-KitText 'Arcade.Adapter.Error' -f $a.Name, $_.Exception.Message))
            if (-not $Quiet) { Write-KitLog (Get-KitText 'Arcade.Adapter.Error' -f $a.Name, $_.Exception.Message) -Level Error }
        }
    }
    [pscustomobject]@{
        Success           = [bool]$detected
        DetectedAdapter   = $detected
        DetectedClass     = $detectedClass
        DetectedDeviceId  = $detectedId
        ScannedAdapters   = ($scanned -join ',')
        Quirks            = $quirks
        Errors            = @($errors)
        NextStep          = $(if ($detected) { "Install-$detected`Software" } else { '' })
    }
}

function Get-ArcadeAdapterValue($Info, [string] $Key) { if ($Info -and $Info.Contains($Key)) { $Info[$Key] } }

# Supermodel [Global] diff for arbitrary keys (lightgun's planner only knows its own target set).
function Get-ArcadeSupermodelPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [Collections.IDictionary] $Values)
    $current = @{}
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $inGlobal = $false
        foreach ($line in [IO.File]::ReadAllLines($Path)) {
            $t = $line.Trim()
            if ($t -match '^\[\s*Global\s*\]') { $inGlobal = $true; continue }
            if ($t -match '^\[') { $inGlobal = $false; continue }
            if ($inGlobal -and $t -and -not $t.StartsWith(';') -and -not $t.StartsWith('#')) {
                $eq = $t.IndexOf('='); if ($eq -gt 0) { $current[$t.Substring(0, $eq).Trim()] = $t.Substring($eq + 1).Trim() }
            }
        }
    }
    $plan = @()
    foreach ($k in $Values.Keys) {
        $old = if ($current.ContainsKey($k)) { $current[$k] } else { $null }
        if ($old -cne [string]$Values[$k]) { $plan += [pscustomobject]@{ Section = 'Global'; Key = $k; Old = $old; New = [string]$Values[$k] } }
    }
    $plan
}

# Public route into an adapter's Install-<Name>Software.
function Install-ArcadeAdapter {
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
    Invoke-ArcadeAdapterFunction -Name $Name -Function "Install-$($Name)Software" -Parameters $params
}

# Apply everything the adapter's Info table wants, file by file, existing files only.
# Returns the total number of changes. Steam semantics equal to lightgun: a bound empty
# -SteamConfigVdf means "skip Steam on purpose"; only an unbound call falls back to the found Steam.
function Set-ArcadeAdapterConfiguration {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $RetroBatRoot,
        [string] $DetectedDeviceId = '',
        [string] $SteamConfigVdf
    )
    if (-not $PSCmdlet.ShouldProcess($Name, 'configure')) { return 0 }
    $info = Invoke-ArcadeAdapterFunction -Name $Name -Function "Get-$($Name)AdapterInfo"
    $f = Get-ArcadeAdapterFiles -RetroBatRoot $RetroBatRoot
    $changes = 0

    $mv = Get-ArcadeAdapterValue $info 'MameValues'
    if ($mv -and @($mv.Keys).Count) {
        if ($f.MameIni) { $changes += Set-LightgunMameIniValue -Path $f.MameIni -Values $mv -Confirm:$false }
        else { Write-KitLog (Get-KitText 'Arcade.Adapter.NoMameIni' -f $RetroBatRoot) -Level Warn }
    }
    $cv = Get-ArcadeAdapterValue $info 'ControllersValues'
    if ($cv -and @($cv.Keys).Count) {
        if ($f.RetroBatIni) { $changes += Set-LightgunIniValue -Path $f.RetroBatIni -Section 'Controllers' -Values $cv -Confirm:$false }
        else { Write-KitLog (Get-KitText 'Arcade.Adapter.NoRetroBatIni' -f $RetroBatRoot) -Level Warn }
    }
    $m2 = Get-ArcadeAdapterValue $info 'Model2Values'
    if ($m2 -and @($m2.Keys).Count -and $f.Model2Ini) {
        $changes += Set-LightgunIniValue -Path $f.Model2Ini -Section '' -Values $m2 -Confirm:$false
    }
    $sv = Get-ArcadeAdapterValue $info 'SupermodelValues'
    if ($sv -and @($sv.Keys).Count -and $f.SupermodelIni) {
        $plan = @(Get-ArcadeSupermodelPlan -Path $f.SupermodelIni -Values $sv)
        if ($plan.Count) { $changes += Set-LightgunSupermodelConfig -ConfigPath $f.SupermodelIni -Plan $plan -Confirm:$false }
    }
    $se = @(Get-ArcadeAdapterValue $info 'SteamEntries')
    if (-not $PSBoundParameters.ContainsKey('SteamConfigVdf') -and $se.Count) {
        $steam = Get-LightgunSteamPath
        $SteamConfigVdf = if ($steam) { Join-Path $steam 'config\config.vdf' } else { '' }
    }
    if ($se.Count -and $SteamConfigVdf -and (Test-Path -LiteralPath $SteamConfigVdf -PathType Leaf)) {
        $changes += Set-LightgunSteamBlacklist -ConfigVdf $SteamConfigVdf -ExtraEntries $se -Confirm:$false
    }
    Write-KitLog (Get-KitText 'Arcade.Adapter.Changes' -f $Name, $changes)
    $changes
}

# True when every value the adapter wants is already in place (Steam included).
function Test-ArcadeAdapterConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Name, [Parameter(Mandatory)] [string] $RetroBatRoot, [string] $DetectedDeviceId = '', [string] $SteamConfigVdf)
    $info = Invoke-ArcadeAdapterFunction -Name $Name -Function "Get-$($Name)AdapterInfo"
    $f = Get-ArcadeAdapterFiles -RetroBatRoot $RetroBatRoot
    $mv = Get-ArcadeAdapterValue $info 'MameValues'
    if ($mv -and @($mv.Keys).Count) {
        if (-not $f.MameIni) { return $false }
        if (@(Get-LightgunMameIniPlan -Path $f.MameIni -Values $mv).Count) { return $false }
    }
    $cv = Get-ArcadeAdapterValue $info 'ControllersValues'
    if ($cv -and @($cv.Keys).Count) {
        if (-not $f.RetroBatIni) { return $false }
        if (@(Get-LightgunIniPlan -Path $f.RetroBatIni -Section 'Controllers' -Values $cv).Count) { return $false }
    }
    # Model 2 and Supermodel are optional emulators: absent files are skipped here exactly like
    # Set-ArcadeAdapterConfiguration skips them (mame.ini/retrobat.ini stay mandatory — RetroBat owns them).
    $m2 = Get-ArcadeAdapterValue $info 'Model2Values'
    if ($m2 -and @($m2.Keys).Count -and $f.Model2Ini) {
        if (@(Get-LightgunIniPlan -Path $f.Model2Ini -Section '' -Values $m2).Count) { return $false }
    }
    $sv = Get-ArcadeAdapterValue $info 'SupermodelValues'
    if ($sv -and @($sv.Keys).Count -and $f.SupermodelIni) {
        if (@(Get-ArcadeSupermodelPlan -Path $f.SupermodelIni -Values $sv).Count) { return $false }
    }
    $se = @(Get-ArcadeAdapterValue $info 'SteamEntries')
    if (-not $PSBoundParameters.ContainsKey('SteamConfigVdf') -and $se.Count) {
        $steam = Get-LightgunSteamPath
        $SteamConfigVdf = if ($steam) { Join-Path $steam 'config\config.vdf' } else { '' }
    }
    if ($se.Count -and $SteamConfigVdf -and (Test-Path -LiteralPath $SteamConfigVdf -PathType Leaf)) {
        if (-not (Test-LightgunSteamBlacklist -ConfigVdf $SteamConfigVdf -ExtraEntries $se)) { return $false }
    }
    $true
}
