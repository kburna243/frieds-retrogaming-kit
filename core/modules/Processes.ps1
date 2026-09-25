# Processes: the kit never ends a process. It only reports running ones and asks the user.

function Test-KitProcessesClosed {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string[]] $Names)
    foreach ($n in $Names) {
        $bare = $n -replace '\.exe$', ''
        Get-Process -Name $bare -ErrorAction SilentlyContinue |
            ForEach-Object { [pscustomobject]@{ Name = $_.ProcessName; Id = $_.Id } }
    }
}

# Returns $true once all are closed, $false on timeout (TimeoutSeconds 0 = wait forever).
function Wait-KitProcessesClosed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]] $Names,
        [int] $TimeoutSeconds = 0,
        [ValidateRange(1, 60)] [int] $PollSeconds = 2
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $asked = $null
    while ($true) {
        $running = @(Test-KitProcessesClosed -Names $Names)
        if (-not $running) { return $true }
        $list = ($running | ForEach-Object { $_.Name } | Sort-Object -Unique) -join ', '
        if ($list -ne $asked) { Write-KitLog (Get-KitText 'Process.PleaseClose' -f $list) -Level Warn; $asked = $list }
        if ($TimeoutSeconds -gt 0 -and (Get-Date) -ge $deadline) { return $false }
        Start-Sleep -Seconds $PollSeconds
    }
}
