# Loopback: one line of text to a program on this computer, e.g. the hotwm relay on 127.0.0.1:8000. The address is
# fixed and not a parameter, so this file can never reach another machine; that is why the syntax check
# (tools\Test-KitSyntax.ps1) allows a socket here next to Download.ps1, the kit's only way to the internet.

# $true when the line was delivered; $false when nothing listens on the port or it does not answer in time.
function Send-KitLoopbackLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateRange(1, 65535)] [int] $Port,
        [Parameter(Mandatory)] [string] $Line,
        [ValidateRange(100, 30000)] [int] $TimeoutMs = 2000
    )
    $client = New-Object Net.Sockets.TcpClient
    try {
        if (-not $client.ConnectAsync([Net.IPAddress]::Loopback, $Port).Wait($TimeoutMs)) { return $false }
        $bytes = [Text.Encoding]::ASCII.GetBytes($Line + "`r`n")
        $client.GetStream().Write($bytes, 0, $bytes.Length)
        # Give the receiver a moment before the connection closes (the relay reads line by line).
        Start-Sleep -Milliseconds 300
        $true
    } catch { $false } finally { $client.Dispose() }
}
