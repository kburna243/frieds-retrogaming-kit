# Wiimote player order. Gunmote numbers the Wiimotes in the order they connect (first connected = player 1, measured
# on a cabinet in both directions: whichever Wiimote was switched on first rumbled as "wii 1"). Windows keeps that
# order as each Wiimote's LastArrivalDate, and the Bluetooth address sits in the instance id of the HID entry's parent
# (BTHENUM\...&<12 hex digits>_C00000000). So the kit can tell which Wiimote is player 1 right now, without asking
# Gunmote, and compare it with the binding the person saved (wiimotes.json next to the input profiles).
# Limit: a Wiimote that drops out and reconnects gets its old Gunmote number back but a new arrival time. Arrivals far
# apart, or before Gunmote started, therefore give "Unclear" instead of a guess.

$script:WiimoteLedgerPath = Join-Path $env:USERPROFILE 'RetroCabinet\wiimotes.json'
$script:WiimoteArrivalWindow = 60   # seconds; ponytail: a fixed window, make it a setting if cabinets need more

# Connected Wiimotes over Bluetooth: Mac, Model (RVL-CNT-01 / RVL-CNT-01-TR), Arrived.
function Get-ArcadeWiimoteDevice {
    [CmdletBinding()]
    param()
    foreach ($d in @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue | Where-Object { $_.InstanceId -match '^HID\\\{00001124-[^}]+\}_VID&0002057E_PID&03(06|30)' })) {
        $parent = [string](Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName DEVPKEY_Device_Parent -ErrorAction SilentlyContinue).Data
        $arrived = (Get-PnpDeviceProperty -InstanceId $d.InstanceId -KeyName DEVPKEY_Device_LastArrivalDate -ErrorAction SilentlyContinue).Data
        [pscustomobject]@{
            Mac     = if ($parent -match '&([0-9A-Fa-f]{12})_C[0-9A-Fa-f]+$') { $Matches[1].ToUpperInvariant() } else { $null }
            Model   = if ($d.InstanceId -match 'PID&0330') { 'RVL-CNT-01-TR' } else { 'RVL-CNT-01' }
            Arrived = $arrived
        }
    }
}

function Get-ArcadeWiimoteLedger {
    [CmdletBinding()]
    param([string] $Path = $script:WiimoteLedgerPath)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    @((Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json).Wiimotes | Where-Object { $_ })
}

# The order as Gunmote has it now and how it compares with the saved binding.
# State: NoWiimote | NoGunmote | Unclear (arrivals before Gunmote or far apart) | Unbound (nothing saved) | Ok | Swapped
# Wiimotes: Player (by arrival), Mac, Model, Arrived, Expected (player in the binding or $null).
# -Device, -GunmoteStart and -Ledger are for tests; by default they are read from this machine.
function Get-ArcadeWiimoteOrder {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()] [object[]] $Device = @(Get-ArcadeWiimoteDevice),
        [object] $GunmoteStart = $(try { (Get-Process -Name Gunmote -ErrorAction Stop | Select-Object -First 1).StartTime } catch { $null }),
        [AllowEmptyCollection()] [object[]] $Ledger = @(Get-ArcadeWiimoteLedger),
        [int] $ArrivalWindow = $script:WiimoteArrivalWindow
    )
    $sorted = @($Device | Where-Object { $_ -and $_.Mac } | Sort-Object Arrived)
    $n = 0
    $rows = @(foreach ($w in $sorted) {
        $n++
        $bound = @($Ledger | Where-Object { $_.Mac -eq $w.Mac }) | Select-Object -First 1
        [pscustomobject]@{ Player = $n; Mac = $w.Mac; Model = $w.Model; Arrived = $w.Arrived; Expected = $(if ($bound) { [int]$bound.Player } else { $null }) }
    })
    $state = if (-not $rows.Count) { 'NoWiimote' }
             elseif (-not $GunmoteStart) { 'NoGunmote' }
             elseif (@($rows | Where-Object { -not $_.Arrived -or $_.Arrived -lt $GunmoteStart }).Count) { 'Unclear' }
             elseif ($rows.Count -gt 1 -and ($rows[-1].Arrived - $rows[0].Arrived).TotalSeconds -gt $ArrivalWindow) { 'Unclear' }
             elseif (-not @($rows | Where-Object { $null -ne $_.Expected }).Count) { 'Unbound' }
             elseif (@($rows | Where-Object { $null -ne $_.Expected -and $_.Expected -ne $_.Player }).Count) { 'Swapped' }
             else { 'Ok' }
    # The order to switch them on in, from the binding: player 1 first.
    $fix = @($rows | Where-Object { $null -ne $_.Expected } | Sort-Object Expected | ForEach-Object { '{0} ({1})' -f $_.Mac, $_.Model })
    [pscustomobject]@{ State = $state; Wiimotes = $rows; GunmoteStart = $GunmoteStart; SwitchOnOrder = $fix }
}

# Saves the current order as the binding (player = position now); an existing file is copied to .bak_<time> first.
# Returns the binding; with -WhatIf it writes nothing.
function Save-ArcadeWiimoteLedger {
    [CmdletBinding(SupportsShouldProcess)]
    param([AllowEmptyCollection()] [object[]] $Wiimotes = @((Get-ArcadeWiimoteOrder).Wiimotes), [string] $Path = $script:WiimoteLedgerPath)
    if (-not @($Wiimotes).Count) { throw 'No Wiimote connected: switch them on in the order you want (player 1 first), then save.' }
    $entries = @($Wiimotes | Sort-Object Player | ForEach-Object { [ordered]@{ Player = [int]$_.Player; Mac = $_.Mac; Model = $_.Model } })
    if ($PSCmdlet.ShouldProcess($Path, 'save Wiimote player binding')) {
        $dir = Split-Path -Parent $Path
        if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
        if (Test-Path -LiteralPath $Path -PathType Leaf) { Copy-Item -LiteralPath $Path -Destination ('{0}.bak_{1:yyyyMMdd-HHmmss}' -f $Path, (Get-Date)) }
        $json = [ordered]@{ Note = 'Wiimote -> player, saved by the kit. Gunmote numbers the Wiimotes in the order they connect.'; Wiimotes = $entries } | ConvertTo-Json -Depth 4
        [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding $false))
    }
    $entries | ForEach-Object { [pscustomobject]$_ }
}
