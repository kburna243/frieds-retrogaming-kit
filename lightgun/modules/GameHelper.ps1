# Game helper (step 8): what RetroBat's game-start/game-end hook rck-game-helper.bat asks of the kit, at the user's
# own rights (tools\GameHelper.ps1, started without a task and without elevation):
#   Naomi, Atomiswave, Model 2  DemulShooter for the ROM (Demul.ps1: name checked against the known gun ROMs, started
#                               un-elevated), ended when the game ends
#   TeknoParrot                 every FFBBlaster.ini of a game with "FFB Blaster" on gets network outputs on port 8002,
#                               where the hotwm relay fetches them; FFBBlaster writes its INI on a game's first start,
#                               so this runs at every start and end of a TeknoParrot game
#   Bluetooth                   Wiimote player order: when Gunmote numbered the Wiimotes the other way round than the
#                               saved binding, the relay makes each wrong Wiimote rumble and blink the LED of the
#                               player it should be (SHOW_PLAYERS). Over the DolphinBar there is no Bluetooth address
#                               per Wiimote, so nothing is checked.
# Ported from the cabinet's hand-made bridge (gunmote-profil: pad43.ps1, ffbblaster-netoutputs.ps1, order-check.py),
# without its admin tasks: none of this needs administrator rights.

$script:LightgunDemulShooterTargets = @{ naomi = 'demul07a'; atomiswave = 'demul07a'; model2 = 'model2m' }
$script:LightgunFfbNetPort = 8002
$script:LightgunRelayPort = 8000

# What the helper does for one hook call: System and RetroBatRoot (from the ROM path), DemulShooter (Target, Rom or
# $null), StopDemulShooter, FfbNetOutputs, OrderCheck.
function Get-LightgunGameHelperPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateSet('Start', 'End')] [string] $Phase,
        [AllowEmptyString()] [string] $Rom = '',
        [ValidateSet('DolphinBar', 'Bluetooth')] [string] $Connection = 'DolphinBar'
    )
    $system = ''
    $root = ''
    if ($Rom -match '^(.+?)\\roms\\([^\\]+)\\') { $root = $Matches[1]; $system = $Matches[2].ToLowerInvariant() }
    $ds = $null
    $dsSystem = $script:LightgunDemulShooterTargets.ContainsKey($system)
    if ($Phase -eq 'Start' -and $dsSystem) {
        $name = [IO.Path]::GetFileNameWithoutExtension($Rom)
        $target = $script:LightgunDemulShooterTargets[$system]
        $allow = if ($target -eq 'model2m') { $script:LightgunModel2KnownRoms } else { $script:LightgunDemulKnownRoms }
        if (Test-LightgunDemulRomName -Rom $name -Allowlist $allow) { $ds = [pscustomobject]@{ Target = $target; Rom = $name } }
    }
    [pscustomobject]@{
        Phase            = $Phase
        System           = $system
        RetroBatRoot     = $root
        DemulShooter     = $ds
        StopDemulShooter = $Phase -eq 'End' -and $dsSystem
        FfbNetOutputs    = [bool]$root -and $system -eq 'teknoparrot'
        OrderCheck       = $Phase -eq 'Start' -and $Connection -eq 'Bluetooth' -and (Get-LightgunSystemProfile -Connection $Connection).Contains($system)
    }
}

# Switches the FFBBlaster.ini of every TeknoParrot game with "FFB Blaster" on to network outputs (OutputsSystem=1,
# NetOutputsTCPPort=-Port). Only INIs below the game's own folder in roms\teknoparrot, none in a "_FFB" backup folder;
# the first change keeps a copy <ini>.bak_netoutputs. Returns the changed INI paths.
function Set-LightgunTpNetOutput {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [string] $RetroBatRoot, [int] $Port = $script:LightgunFfbNetPort)
    $tp = Get-LightgunTpPath -Root $RetroBatRoot
    foreach ($x in Get-LightgunTpProfileFile $tp.UserProfiles) {
        try { $doc = Read-LightgunXml $x.FullName } catch { continue }
        $on = @($doc.SelectNodes('//FieldInformation') | Where-Object {
            [string]$_.CategoryName -eq 'FFB Blaster' -and [string]$_.FieldName -eq 'Enable' -and [string]$_.FieldValue -eq '1' })
        if (-not $on.Count) { continue }
        $gamePath = [string]$doc.SelectSingleNode('/GameProfile/GamePath').InnerText
        $folder = Get-LightgunTpRomFolder -GamePath $gamePath -RomsDir $tp.Roms
        if (-not $folder) { continue }
        $dir = Join-Path $tp.Roms $folder
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { continue }
        foreach ($ini in Get-ChildItem -LiteralPath $dir -Recurse -Filter 'FFBBlaster.ini' -File -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\_FFB' }) {
            $lines = [IO.File]::ReadAllLines($ini.FullName)
            $new = @($lines -replace '^OutputsSystem=.*', 'OutputsSystem=1' -replace '^NetOutputsTCPPort=.*', "NetOutputsTCPPort=$Port")
            if (-not (Compare-Object $lines $new -SyncWindow 0)) { continue }
            if (-not $PSCmdlet.ShouldProcess($ini.FullName, "FFBBlaster network outputs on port $Port")) { continue }
            $bak = "$($ini.FullName).bak_netoutputs"
            if (-not (Test-Path -LiteralPath $bak)) { Copy-Item -LiteralPath $ini.FullName -Destination $bak }
            [IO.File]::WriteAllLines($ini.FullName, $new)
            $ini.FullName
        }
    }
}

# The relay command that shows each wrongly numbered Wiimote its player, or $null when nothing is to show (order
# right, unclear, unbound). -Order: result of Get-ArcadeWiimoteOrder (State, Wiimotes with Player and Expected).
function Get-LightgunShowPlayersCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Order)
    if ([string]$Order.State -ne 'Swapped') { return $null }
    $wrong = @($Order.Wiimotes | Where-Object { $null -ne $_.Expected -and [int]$_.Expected -ne [int]$_.Player } |
        ForEach-Object { '{0}={1}' -f [int]$_.Player, [int]$_.Expected })
    if (-not $wrong.Count) { return $null }
    'SHOW_PLAYERS ' + ($wrong -join ' ')
}

# Sends one line to the hotwm relay on this computer (core Loopback.ps1). $true when it was delivered.
function Send-LightgunRelayCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Command, [int] $Port = $script:LightgunRelayPort, [int] $TimeoutMs = 2000)
    Send-KitLoopbackLine -Port $Port -Line $Command -TimeoutMs $TimeoutMs
}
