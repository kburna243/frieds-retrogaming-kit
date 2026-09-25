<#
.SYNOPSIS
    retro-cabinet-kit: Gunmote profile automation. Started by the scheduled tasks
    "RetroCabinetKit Gunmote Profile <Name>" with highest rights (Gunmote's pipe only accepts administrators);
    RetroBat's game-start/game-end hooks only run "schtasks /run". This file lives in the kit folder below
    ProgramData that only administrators can change.

    Gunmote falls back to its Default layout on every window change to a program it does not list, so one
    command does not last: the layout is sent at the start and again after every window change away from
    RetroBat, until RetroBat stays in front. -Once sends a single time (back in the menu). A newer run ends an
    older one. Log: logs\profile.log next to this file.
.PARAMETER Layout
    Title of the layout in Gunmote's layout chooser (Keymaps.json, LayoutChooser).
.PARAMETER Once
    Send once and end (menu).
.PARAMETER Seconds
    Longest watch time.
#>
param(
    [Parameter(Mandatory)] [ValidatePattern('^[\p{L}\p{N} _\-\.:,\(\)\+]{1,64}$')] [string] $Layout,
    [switch] $Once,
    [ValidateRange(10, 3600)] [int] $Seconds = 180
)
$ErrorActionPreference = 'Stop'
$logDir = Join-Path $PSScriptRoot 'logs'
$log = Join-Path $logDir 'profile.log'
$current = Join-Path $logDir 'current.txt'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

function Write-ProfileLog([string] $Message) {
    if ((Test-Path -LiteralPath $log) -and (Get-Item -LiteralPath $log).Length -gt 1MB) { Move-Item -LiteralPath $log -Destination "$log.1" -Force }
    Add-Content -LiteralPath $log -Value ('{0:yyyy-MM-dd HH:mm:ss} {1}' -f (Get-Date), $Message) -Encoding UTF8
}

function Send-Layout([string] $Why) {
    try {
        $pipe = New-Object IO.Pipes.NamedPipeClientStream ('.', 'Gunmote', [IO.Pipes.PipeDirection]::Out)
        $pipe.Connect(2000)
        $writer = New-Object IO.StreamWriter ($pipe)
        $writer.AutoFlush = $true
        $writer.WriteLine('keymap' + [char]31 + $Layout)
        $writer.Dispose()
        Write-ProfileLog "SENT layout='$Layout' ($Why)"
    } catch { Write-ProfileLog "ERROR pipe: $($_.Exception.Message)" }
}

function Get-ForegroundProcessName {
    $id = 0
    [void][RetroCabinetKit.ProfileNative]::GetWindowThreadProcessId([RetroCabinetKit.ProfileNative]::GetForegroundWindow(), [ref]$id)
    if ($id) { (Get-Process -Id $id -ErrorAction SilentlyContinue).ProcessName }
}

if (-not ('RetroCabinetKit.ProfileNative' -as [type])) {
    Add-Type -Namespace RetroCabinetKit -Name ProfileNative -MemberDefinition @'
[DllImport("user32.dll")] public static extern System.IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(System.IntPtr window, out uint processId);
'@
}

$run = [guid]::NewGuid().ToString()
Set-Content -LiteralPath $current -Value $run -Encoding ASCII # a running older watcher sees this and ends
Write-ProfileLog "START layout='$Layout' once=$([bool]$Once)"
if (-not (Get-Process -Name 'Gunmote' -ErrorAction SilentlyContinue)) { Write-ProfileLog 'END Gunmote is not running'; return }
if ($Once) { Send-Layout 'once'; Write-ProfileLog 'END once'; return }

# Windows that come and go around a start (this script's own console, the task scheduler, Dolphin which
# takes the Wiimotes over itself) do not count as leaving RetroBat.
$ignore = 'powershell', 'conhost', 'schtasks', 'WindowsTerminal', 'Dolphin', 'DolphinNoGUI'
$start = Get-Date
$lastName = $null
$left = $false
Start-Sleep -Milliseconds 800
Send-Layout 'start'
$reason = 'time limit'
while (((Get-Date) - $start).TotalSeconds -lt $Seconds) {
    if ((Get-Content -LiteralPath $current -ErrorAction SilentlyContinue | Select-Object -First 1) -ne $run) { $reason = 'newer run'; break }
    if (-not (Get-Process -Name 'Gunmote' -ErrorAction SilentlyContinue)) { $reason = 'Gunmote ended'; break }
    $name = Get-ForegroundProcessName
    if ($name -and $name -ne $lastName) {
        $lastName = $name
        if ($ignore -contains $name) { }
        elseif ($name -eq 'emulationstation') {
            if ($left) {
                # RetroBat flickers to the front while an emulator starts: only a second look decides.
                Start-Sleep -Milliseconds 1200
                if ((Get-ForegroundProcessName) -eq 'emulationstation') { $reason = 'RetroBat in front again'; break }
            }
        } else {
            $left = $true
            Start-Sleep -Milliseconds 900
            Send-Layout "window change to $name"
        }
    }
    Start-Sleep -Milliseconds 300
}
Write-ProfileLog "END $reason"
