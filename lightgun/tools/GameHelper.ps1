<#
.SYNOPSIS
    retro-cabinet-kit: game helper. Started by RetroBat's hook rck-game-helper.bat (game-start and game-end) at the
    user's own rights, without a task and without elevation; see lightgun\modules\GameHelper.ps1 for what it does.
    Never stops a game: every error is only written to logs\game-helper.log in the kit folder.
.PARAMETER Phase
    Start or End.
.PARAMETER Rom
    ROM path RetroBat passes to the hook.
.PARAMETER Connection
    DolphinBar or Bluetooth, fixed by step 8 when it wrote the hook.
#>
param(
    [ValidateSet('Start', 'End')] [string] $Phase = 'Start',
    [string] $Rom = '',
    [ValidateSet('DolphinBar', 'Bluetooth')] [string] $Connection = 'DolphinBar'
)
$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$log = Join-Path $kitRoot 'logs\game-helper.log'

function Write-HelperLog([string] $Message) {
    try {
        $dir = Split-Path -Parent $log
        if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        if ((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -gt 1MB) { Move-Item -LiteralPath $log -Destination "$log.1" -Force }
        Add-Content -LiteralPath $log -Value ('{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Message) -Encoding UTF8
    } catch { }
}

try {
    Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1')
    Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1')
    $plan = Get-LightgunGameHelperPlan -Phase $Phase -Rom $Rom -Connection $Connection
    Write-HelperLog ('{0} system={1} connection={2} rom={3}' -f $Phase, $plan.System, $Connection, $Rom)

    if ($plan.StopDemulShooter) {
        Get-Process -Name 'DemulShooter', 'DemulShooterX64' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-HelperLog 'DemulShooter ended'
    }
    if ($plan.DemulShooter) {
        $exe = (Get-LightgunDemulPath -RetroBatRoot $plan.RetroBatRoot).DemulShooterExe
        if (Test-Path -LiteralPath $exe -PathType Leaf) {
            Start-LightgunDemulShooter -DemulShooterExe $exe -Target $plan.DemulShooter.Target -Rom $plan.DemulShooter.Rom -Confirm:$false
            Write-HelperLog ('DemulShooter started: -target={0} -rom={1}' -f $plan.DemulShooter.Target, $plan.DemulShooter.Rom)
        } else { Write-HelperLog "DemulShooter not found: $exe" }
    } elseif ($Phase -eq 'Start' -and $plan.System -in 'naomi', 'atomiswave', 'model2') {
        Write-HelperLog 'DemulShooter not started: ROM is not a known gun game'
    }
    if ($plan.FfbNetOutputs) {
        foreach ($f in @(Set-LightgunTpNetOutput -RetroBatRoot $plan.RetroBatRoot -Confirm:$false)) { Write-HelperLog "FFBBlaster network outputs: $f" }
    }
    if ($plan.OrderCheck) {
        $arcade = Join-Path $kitRoot 'arcade\RetroCabinetKit.Arcade.psd1'
        if (-not (Test-Path -LiteralPath $arcade)) { Write-HelperLog 'player order: package arcade missing'; return }
        Import-Module $arcade
        $order = Get-ArcadeWiimoteOrder
        Write-HelperLog ('player order: {0} ({1})' -f $order.State, ((@($order.Wiimotes) | ForEach-Object { '{0}={1}' -f $_.Player, $_.Mac }) -join ', '))
        $cmd = Get-LightgunShowPlayersCommand -Order $order
        if ($cmd) {
            $sent = Send-LightgunRelayCommand -Command $cmd
            Write-HelperLog ('{0} -> {1}' -f $cmd, $(if ($sent) { 'sent to the relay' } else { 'relay not reachable (port 8000)' }))
        }
    }
} catch { Write-HelperLog "ERROR $($_.Exception.Message)" }
