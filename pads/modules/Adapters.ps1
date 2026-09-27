# Pads adapters: one <Name>.ps1 per GAMEPAD FAMILY in pads\adapters\, discovered by parsing (never
# executing) the files, matched by tight VID/PID signatures, configured through lightgun's audited INI
# writer. Same plugin pattern as arcade\, different device class: pads are MULTI (up to four players at
# once), so the scan collects every match instead of stopping at the first one.
#
# --- DEVICE CLASS RULE (the heart of this file) ------------------------------------------------------
# Exclusion order is **lightgun > arcade > pads**. A device that a lightgun or an arcade adapter claims
# is never re-claimed as a gamepad, because the interesting USB ids are shared:
#   045E:028E  Xbox 360 pad  ==  GP2040-CE stick  ==  8BitDo in X-mode
#   045E:0719  Xbox wireless receiver  ==  Xbox 360 Racing Wheel (arcade's Xbox360Wheel)
#   0738:4718  Mad Catz FightPad  ==  Mad Catz Arcade Stick (arcade claims the id)
#   0079:0011  generic PS2 pad on a Zero Delay encoder (arcade)
#   D209:*     Ultimarc: AimTrak guns (lightgun) and I-PAC encoders (arcade)
#   2E8A:000A  GP2040 bootloader (lightgun's OpenFIRE route)
# Without that order one stick in the cabinet would silently become "player 3".
# Every exclusion is logged ONCE per device (Pad.Excluded) - an exclusion nobody can see is a bug.
#
# Lightgun is matched by signature (its adapters carry no NameHints key), arcade by signature OR name
# hint, because arcade's GP2040-CE adapter has no signature at all and is exactly the 045E:028E case.
#
# --- Steam: pads NEVER touch it ---------------------------------------------------------------------
# The arcade/lightgun suites blacklist their vendor VIDs in Steam's controller_blacklist. Pads do the
# opposite on purpose (key Pad.NoBlacklist): Steam is the thing that still needs a working navigation
# device, and a blacklisted pad would take the gamepad away from exactly the UI where the user has to
# opt in. This contradicts the delivered community design doc (which masks pads through HidHide); it is
# an architectural decision of this kit, not an oversight. There is therefore no -SteamConfigVdf
# parameter anywhere in this package: a parameter that could point at config.vdf would be a door we
# promise never to open.

function Get-PadAdapterCatalog {
    [CmdletBinding()]
    param([string] $Dir = (Get-PadAdapterDir))
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { return @() }
    $result = @()
    foreach ($file in (Get-ChildItem -LiteralPath $Dir -Filter '*.ps1' -File | Sort-Object Name)) {
        if ($file.Name -like '_*') { continue }
        $name = [IO.Path]::GetFileNameWithoutExtension($file.Name)
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        $funcs = @(if ($ast) { foreach ($d in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) { $d.Name } })
        $result += [pscustomobject]@{
            Name           = $name
            Path           = $file.FullName
            HasParseErrors = (@($errors).Count -gt 0)
            HasTest        = [bool]($funcs -contains "Test-${name}Hardware")
            HasInfo        = [bool]($funcs -contains "Get-${name}AdapterInfo")
            HasInstall     = [bool]($funcs -contains "Install-${name}Software")
            HasConfigure   = [bool]($funcs -contains "Configure-${name}Profile")
            HasShield      = [bool]($funcs -contains "Set-${name}InterferenceShield")
        }
    }
    $result
}

# Run one function out of one adapter file, by validated name (same guard as lightgun/arcade: the
# caller can never steer this to an arbitrary path or invoke something that is not an adapter part).
function Invoke-PadAdapterFunction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Function,
        [string] $Dir = (Get-PadAdapterDir),
        [hashtable] $Parameters = @{}
    )
    if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$') { throw (Get-KitText 'Pad.Adapter.NotFound' -f $Name) }
    $file = Join-Path $Dir "$Name.ps1"
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw (Get-KitText 'Pad.Adapter.NotFound' -f $Name) }
    . $file
    if (-not (Get-Command $Function -ErrorAction SilentlyContinue)) { throw (Get-KitText 'Pad.Adapter.MissingFunction' -f $Name, $Function) }
    & $Function @Parameters
}

# Read one optional key from an adapter's info hashtable (StrictMode 2.0: a missing key must not throw).
function Get-PadAdapterValue($Info, [string] $Key) { if ($Info -and $Info.Contains($Key)) { $Info[$Key] } }

# Name of one DetectedPads entry. StrictMode 2.0 throws on a missing PROPERTY, so reading $_.Name of a
# hashtable that came back from Get-KitStateValue / JSON would break an adapter. One tolerant accessor.
function Get-PadDetectedName($Entry) {
    if ($null -eq $Entry) { return '' }
    if ($Entry -is [string]) { return $Entry }
    if ($Entry -is [System.Collections.IDictionary]) {
        foreach ($k in 'Name', 'Adapter', 'DetectedAdapter') { if ($Entry.Contains($k)) { return [string]$Entry[$k] } }
        return ''
    }
    if ($Entry.PSObject.Properties['Name']) { return [string]$Entry.Name }
    ''
}

# --- device access ------------------------------------------------------------------
# Get-PnpDevice and Win32_PnPEntity expose InstanceId as a property; the tests inject hashtables.
# One normalization step keeps every matcher (ours AND the lightgun/arcade ones we delegate to) working
# on both shapes - those modules read PSObject properties and would silently see nothing in a hashtable.
function ConvertTo-PadDeviceObject($Device) {
    if ($Device -is [System.Collections.IDictionary]) { return [pscustomobject]$Device }
    $Device
}

function Get-PadDeviceId($Device) {
    if ($null -eq $Device) { return '' }
    if ($Device -is [string]) { return $Device }
    if ($Device -is [System.Collections.IDictionary]) {
        foreach ($k in 'InstanceId', 'DeviceID') { if ($Device.Contains($k)) { return [string]$Device[$k] } }
        return ''
    }
    if ($Device.PSObject.Properties['InstanceId']) { return [string]$Device.InstanceId }
    if ($Device.PSObject.Properties['DeviceID'])   { return [string]$Device.DeviceID }
    ''
}

function Get-PadDeviceName($Device) {
    if ($null -eq $Device -or $Device -is [string]) { return '' }
    if ($Device -is [System.Collections.IDictionary]) {
        foreach ($k in 'FriendlyName', 'Name', 'Caption') { if ($Device.Contains($k) -and [string]$Device[$k]) { return [string]$Device[$k] } }
        return ''
    }
    foreach ($p in 'FriendlyName', 'Name', 'Caption') {
        if ($Device.PSObject.Properties[$p]) { return [string]$Device.$p }
    }
    ''
}

# Every declared MatchId yields the pattern set it can appear as. A signature is either a full instance
# prefix ('USB\VID_045E&PID_028E*') or a bare core ('VID_045E&PID_028E'); both also exist in the
# Bluetooth-classic spelling, where BTHENUM does not use 'VID_xxxx&PID_yyyy' but
# 'VID&0002xxxx_PID&yyyy' (little-endian class prefix 0002, 4-digit VID, '_PID&' + 4 hex digits).
# Without this step a DualShock 4 that is paired over Bluetooth is simply invisible to the kit.
# The VID+PID pair is always also tried as a substring: the same controller enumerates as USB parent,
# HID child ('HID\VID_x&PID_y&MI_00\...'), XUSB or BTHENUM node, and a pad is a pad on every one of
# them. A bare VID would be over-broad (see adapters\README.md), a full pair is not.
function Get-PadSignaturePatterns([string] $MatchId) {
    $m = ([string]$MatchId).Trim().ToUpperInvariant()
    if (-not $m) { return @() }
    $out = New-Object Collections.Generic.List[string]
    [void]$out.Add($m)
    if ($m -match 'VID_([0-9A-F]{4})&PID_([0-9A-F]{4})') {
        $core = "VID_$($Matches[1])&PID_$($Matches[2])"
        [void]$out.Add("*$core*")
        $bt = "VID&0002$($Matches[1])_PID&$($Matches[2])"
        [void]$out.Add($bt)
        [void]$out.Add("*$bt*")
    } elseif ($m -notmatch '[*?]') {
        [void]$out.Add("*$m*")
    }
    $out.ToArray()
}

# The pads matcher. Deliberate arcade rules kept: InstanceId is compared upper-cased, and NameHints are
# ONLY consulted when the adapter declared no MatchIds at all - a friendly name like '*Xbox*' must
# never outvote a real signature, it is a fallback for devices with nothing better (GP2040-CE).
function Get-PadDeviceMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Device,
        [string[]] $MatchIds = @(),
        [string[]] $NameHints = @()
    )
    $ids = @($MatchIds | Where-Object { $_ })
    if ($ids.Count) {
        $instance = (Get-PadDeviceId $Device).ToUpperInvariant()
        if (-not $instance) { return $false }
        foreach ($m in $ids) {
            foreach ($p in (Get-PadSignaturePatterns $m)) { if ($instance -like $p) { return $true } }
        }
        return $false
    }
    $name = Get-PadDeviceName $Device
    if (-not $name) { return $false }
    foreach ($h in @($NameHints | Where-Object { $_ })) { if ($name -like $h) { return $true } }
    $false
}

# --- class coexistence: who claims this device before pads may look at it? --------------------------------

# One pass per foreign class, results cached as flat pattern lists: pads must not dot-source the other
# packages' adapter files once per device (that is O(devices x adapters) file loads on a real cabinet).
function Get-PadForeignClaimPatterns {
    [CmdletBinding()]
    param([switch] $Quiet)
    $gun   = New-Object Collections.Generic.List[string]
    $stick = New-Object Collections.Generic.List[object]
    foreach ($a in @(Get-LightgunAdapterCatalog)) {
        if ($a.HasParseErrors -or -not $a.HasInfo) {
            # An unreadable gun adapter is a hole in the exclusion, so it must be heard, not swallowed.
            $msg = Get-KitText 'Pad.Adapter.Incomplete' -f "lightgun\$($a.Name)", 'AdapterInfo'
            if (-not $Quiet) { Write-KitLog $msg -Level Warn }
            continue
        }
        try {
            $info = Invoke-LightgunAdapterFunction -Name $a.Name -Function "Get-$($a.Name)AdapterInfo"
            foreach ($id in @(Get-LightgunAdapterValue $info 'MatchIds')) { if ($id) { [void]$gun.Add([string]$id) } }
        } catch {
            $msg = Get-KitText 'Pad.Adapter.Error' -f "lightgun\$($a.Name)", $_.Exception.Message
            if (-not $Quiet) { Write-KitLog $msg -Level Warn }
        }
    }
    foreach ($a in @(Get-ArcadeAdapterCatalog)) {
        if ($a.HasParseErrors -or -not ($a.HasTest -and $a.HasInfo)) {
            $msg = Get-KitText 'Pad.Adapter.Incomplete' -f "arcade\$($a.Name)", 'Test+AdapterInfo'
            if (-not $Quiet) { Write-KitLog $msg -Level Warn }
            continue
        }
        try {
            $info = Invoke-ArcadeAdapterFunction -Name $a.Name -Function "Get-$($a.Name)AdapterInfo"
            [void]$stick.Add([pscustomobject]@{
                MatchIds  = @(Get-ArcadeAdapterValue $info 'MatchIds')
                NameHints = @(Get-ArcadeAdapterValue $info 'NameHints')
            })
        } catch {
            $msg = Get-KitText 'Pad.Adapter.Error' -f "arcade\$($a.Name)", $_.Exception.Message
            if (-not $Quiet) { Write-KitLog $msg -Level Warn }
        }
    }
    [pscustomobject]@{ Lightgun = $gun.ToArray(); Arcade = $stick.ToArray() }
}

# 'Lightgun' | 'Arcade' | '' - the class a device belongs to before pads gets a say.
#
# Deliberately LOOSER than arcade's own matcher: the foreign id lists go through pads' signature
# expansion, because a GP2040 stick enumerates as 'USB\VID_045E&PID_028E\...' (which arcade sees) AND
# as 'HID\VID_045E&PID_028E&MI_00\...' (which arcade's USB-pinned pattern does not see) - and that HID
# child must not become "player 3". Over-exclusion costs one Info line, under-exclusion steals a device.
# The name-hint rule stays exactly arcade's: hints only count when the adapter has no ids at all, so
# GP2040-CE - the adapter without any signature - still wins against our 045E:028E line.
function Get-PadDeviceClassClaim {
    [CmdletBinding()]
    param([Parameter(Mandatory)] $Device, [Parameter(Mandatory)] $Claims)
    $id = Get-PadDeviceId $Device
    if ($id) {
        $upper = $id.ToUpperInvariant()
        foreach ($p in @($Claims.Lightgun)) {
            # lightgun stores loose cores ('VID_D209&PID_1602'); its own matcher accepts substring hits.
            if ($p -and ($upper -like "*$($p.ToUpperInvariant())*")) { return 'Lightgun' }
        }
    }
    foreach ($a in @($Claims.Arcade)) {
        if (Get-PadDeviceMatch -Device $Device -MatchIds $a.MatchIds -NameHints $a.NameHints) { return 'Arcade' }
    }
    ''
}

# --- detection (MULTI) ---------------------------------------------------------------------------------

# Scans the pad catalog and returns EVERY pad that is present and not claimed by a stronger class.
# Result (stable field names, agent-friendly): Success, DetectedPads, Excluded, ScannedAdapters,
# Errors, NextStep. Arrays are built with .ToArray() on purpose: PS 5.1 refuses
# @([Collections.Generic.List[object]]) with a ArgumentException ("Cannot convert ... List`1").
function Get-PadDetectedGamepad {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [object[]] $Devices,
        [string] $Dir = (Get-PadAdapterDir),
        [switch] $Quiet
    )
    # Rule: never scan the live machine on our own initiative. Callers (steps, agents, tests) bind
    # -Devices; only a genuinely unbound call reads PnP. Tests always bind, so they never touch hardware.
    $devicesBound = $PSBoundParameters.ContainsKey('Devices')
    if (-not $devicesBound) { $Devices = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue) }
    $devices = @(foreach ($d in @($Devices)) { if ($d) { ConvertTo-PadDeviceObject $d } })

    $errors   = New-Object Collections.Generic.List[string]
    $scanned  = New-Object Collections.Generic.List[string]
    $excluded = New-Object Collections.Generic.List[object]
    $detected = New-Object Collections.Generic.List[object]
    $codes    = New-Object Collections.Generic.List[string]
    $claims   = Get-PadForeignClaimPatterns -Quiet:$Quiet

    # Pass 1: hand every device to the stronger classes. Exactly one log line per excluded device.
    $pads = New-Object Collections.Generic.List[object]
    foreach ($d in $devices) {
        $class = Get-PadDeviceClassClaim -Device $d -Claims $claims
        if ($class) {
            $deviceId = Get-PadDeviceId $d
            $msg = Get-KitText 'Pad.Excluded' -f $deviceId, $class
            if (-not $Quiet) { Write-KitLog $msg -Level Info }
            [void]$excluded.Add([pscustomobject]@{ DeviceId = $deviceId; Class = $class; Message = $msg })
            continue
        }
        [void]$pads.Add($d)
    }

    # Pass 2: the pad families. Multi by nature - no break, and one device is claimed only once
    # (catalog order decides, which is alphabetical and therefore reproducible). The claim set is what
    # keeps two overlapping signatures from turning one physical pad into "player 2 and player 3".
    #
    # NOTE on the adapter's Test-<Name>Hardware: this scan deliberately does NOT call it. Those
    # functions delegate back here (see adapters\_Template.ps1) so that a per-family check cannot skip
    # the class rule - calling them from inside would recurse. The catalog still requires the function
    # to exist, and agents reach it through Invoke-PadAdapterFunction.
    $claimed = New-Object Collections.Generic.HashSet[string] ([StringComparer]::OrdinalIgnoreCase)
    foreach ($a in @(Get-PadAdapterCatalog -Dir $Dir)) {
        if ($a.HasParseErrors) {
            $msg = Get-KitText 'Pad.Adapter.Incomplete' -f $a.Name, 'syntax'
            if (-not $Quiet) { Write-KitLog $msg -Level Warn }
            [void]$errors.Add($msg)
            continue
        }
        if (-not ($a.HasTest -and $a.HasInfo)) {
            $msg = Get-KitText 'Pad.Adapter.Incomplete' -f $a.Name, 'Test+AdapterInfo'
            if (-not $Quiet) { Write-KitLog $msg -Level Warn }
            [void]$errors.Add($msg)
            continue
        }
        [void]$scanned.Add($a.Name)
        if (-not $Quiet) { Write-KitLog (Get-KitText 'Pad.Adapter.Scanning' -f $a.Name) }
        try {
            $info = Invoke-PadAdapterFunction -Name $a.Name -Function "Get-$($a.Name)AdapterInfo" -Dir $Dir
            $ids   = @(Get-PadAdapterValue $info 'MatchIds')
            $hints = @(Get-PadAdapterValue $info 'NameHints')
            $class = [string](Get-PadAdapterValue $info 'Class')
            $quirks = @(Get-PadAdapterValue $info 'Quirks')
        } catch {
            $msg = Get-KitText 'Pad.Adapter.Error' -f $a.Name, $_.Exception.Message
            if (-not $Quiet) { Write-KitLog $msg -Level Warn }
            [void]$errors.Add($msg)
            continue
        }
        foreach ($d in $pads) {
            if (-not (Get-PadDeviceMatch -Device $d -MatchIds $ids -NameHints $hints)) { continue }
            $deviceId = Get-PadDeviceId $d
            if (-not $deviceId) { continue }          # nothing to name in the result -> not a pad entry
            if (-not $claimed.Add($deviceId)) { continue }   # an earlier family already took this device
            [void]$detected.Add([pscustomobject]@{
                Name         = $a.Name
                Class        = $class
                DeviceId     = $deviceId
                FriendlyName = (Get-PadDeviceName $d)
            })
            # Quirks travel as CODES in the result, in prose through the adapter's -InterferenceShield:
            # only that file knows which mode masquerades as which vendor id. Reporting, never repairing.
            foreach ($q in $quirks) { if ($q) { [void]$codes.Add([string]$q) } }
        }
    }

    $names = @($detected.ToArray() | ForEach-Object { $_.Name } | Select-Object -Unique)
    $success = ($errors.Count -eq 0)
    if (-not $detected.Count -and -not $Quiet) {
        # No pad is a normal cabinet state (guns and sticks only) - a note, never a failure by itself.
        Write-KitLog (Get-KitText 'Pad.Adapter.None')
    }
    # -RetroBatRoot is part of the documented signature; detection itself needs no path (PnP only).
    # Where the parameter earns its keep is NextStep: the hint is a command an agent can paste as it
    # stands, per family - so a cabinet with three pads reads as three real calls, not as a template
    # with a placeholder that does not exist as a parameter (-Names would be one).
    $tail = $(if ($RetroBatRoot) { " -RetroBatRoot '$RetroBatRoot'" } else { '' })
    $next = (@($names | ForEach-Object { "Set-PadGamepadConfiguration -Name '$_'$tail" }) -join '; ')
    [pscustomobject]@{
        Success         = $success
        DetectedPads    = $detected.ToArray()
        Excluded        = $excluded.ToArray()
        ScannedAdapters = $scanned.ToArray()
        Errors          = $errors.ToArray()
        Quirks          = @($codes.ToArray() | Select-Object -Unique)
        NextStep        = $next
    }
}

# --- applying one adapter's data ------------------------------------------------------------------------

# retrobat.ini [Controllers] is the ONLY thing pads writes. Everything else about a gamepad (Steam
# input, RetroArch autoconfig per device, driver/middleware like DsHidMini or BetterJoy, HidHide) is
# either deliberately untouched or hand work - the adapter's Quirks/Links say what, see adapters\README.md.
function Set-PadGamepadConfiguration {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $RetroBatRoot
    )
    if (-not $PSCmdlet.ShouldProcess($Name, 'configure gamepad')) { return 0 }
    $info  = Invoke-PadAdapterFunction -Name $Name -Function "Get-$($Name)AdapterInfo"
    $cv    = Get-PadAdapterValue $info 'ControllersValues'
    $se    = @(Get-PadAdapterValue $info 'SteamEntries')
    $changes = 0
    if ($se.Count) {
        # A pad adapter that declares Steam entries breaks the class decision above. Not written, loud.
        Write-KitLog (Get-KitText 'Pad.NoBlacklist') -Level Warn
    }
    if ($cv -and @($cv.Keys).Count) {
        $f = Get-PadAdapterFiles -RetroBatRoot $RetroBatRoot
        if ($f.RetroBatIni) {
            $changes += Set-LightgunIniValue -Path $f.RetroBatIni -Section 'Controllers' -Values $cv -Confirm:$false
        } else {
            # Missing retrobat.ini: warn and change nothing. The kit does not create RetroBat's own file
            # from a pad package - starting RetroBat once does that, with the real defaults.
            Write-KitLog (Get-KitText 'Pad.Adapter.NoRetroBatIni' -f $RetroBatRoot) -Level Warn
        }
    }
    Write-KitLog (Get-KitText 'Pad.Adapter.Changes' -f $Name, $changes)
    $changes
}

# Mirror image of Set-PadGamepadConfiguration, for the step's Verify and for -WhatIf previews.
# A missing retrobat.ini counts as verified: there is nothing to verify and nothing was written, which
# is exactly how arcade treats its optional emulator files. Reporting false here would make the step
# "Failed" for a cabinet state that is not an error.
function Test-PadGamepadConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $RetroBatRoot
    )
    $info = Invoke-PadAdapterFunction -Name $Name -Function "Get-$($Name)AdapterInfo"
    $cv = Get-PadAdapterValue $info 'ControllersValues'
    if ($cv -and @($cv.Keys).Count) {
        $f = Get-PadAdapterFiles -RetroBatRoot $RetroBatRoot
        if ($f.RetroBatIni -and @(Get-LightgunIniPlan -Path $f.RetroBatIni -Section 'Controllers' -Values $cv).Count) { return $false }
    }
    $true
}

# Public route into an adapter's Install-<Name>Software (those functions are module-private by contract).
function Install-PadAdapter {
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
    Invoke-PadAdapterFunction -Name $Name -Function "Install-$($Name)Software" -Parameters $params
}

# The one audited package route every adapter's Install-<Name>Software calls (arcade copies this block
# into each file; pads keeps a single audited path so no adapter can drift into a second write rule).
# Rules: local ZIP only, -Approved required, no network, no service, no silent overwrite - the target
# folder is created, the archive unpacked, and the SHA256 of what was fed in is logged.
function Install-PadAdapterPackage {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $RetroBatRoot,
        [string] $PackagePath,
        [switch] $Approved,
        [string] $Dir = (Get-PadAdapterDir)
    )
    $info = Invoke-PadAdapterFunction -Name $Name -Function "Get-$($Name)AdapterInfo" -Dir $Dir
    $tool = [string](Get-PadAdapterValue $info 'ToolDir')
    $links = Get-PadAdapterValue $info 'Links'
    if (-not $PackagePath) {
        # Nothing to install without a package: name the official sources and stop. This is the whole
        # "no download" rule made visible - the person fetches, the kit only ever unpacks.
        foreach ($k in @($links.Keys)) { Write-KitLog (Get-KitText 'Pad.Adapter.SoftwareLink' -f $k, ([string]$links[$k])) }
        return $false
    }
    if (-not $Approved.IsPresent) { Write-KitLog (Get-KitText 'Pad.Adapter.NeedsApproval') -Level Warn; return $false }
    if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) { Write-KitLog (Get-KitText 'Pad.Adapter.PackageMissing' -f $PackagePath) -Level Warn; return $false }
    if (-not $tool) {
        # This family declares no tool folder: nothing belongs into tools\. Same honest ending as the
        # no-package case - name the source instead of pretending that something was installed.
        foreach ($k in @($links.Keys)) { Write-KitLog (Get-KitText 'Pad.Adapter.SoftwareLink' -f $k, ([string]$links[$k])) }
        return $false
    }
    $target = Join-Path $RetroBatRoot "tools\$tool"
    if (-not $PSCmdlet.ShouldProcess($target, 'unpack pad package')) { return $false }
    $null = New-Item -ItemType Directory -Path $target -Force
    Write-KitLog (Get-KitText 'Pad.Adapter.PackageHash' -f (Split-Path -Leaf $PackagePath), (Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash)
    Expand-Archive -LiteralPath $PackagePath -DestinationPath $target -Force
    Write-KitLog (Get-KitText 'Pad.Adapter.SoftwareInstalled' -f $tool, $target)
    $true
}
