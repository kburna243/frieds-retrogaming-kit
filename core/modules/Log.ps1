# Log: console + log file, optional PowerShell transcript.

$script:KitLogFile    = $null
$script:KitTranscript = $false

function Start-KitLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [switch] $NoTranscript
    )
    $full = Resolve-FullPath $Path
    $dir  = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $script:KitLogFile = $full
    if (-not $NoTranscript) {
        $transcript = [IO.Path]::ChangeExtension($full, '.transcript.log')
        Start-Transcript -LiteralPath $transcript -Append | Out-Null
        $script:KitTranscript = $true
    }
    Write-KitLog (Get-KitText 'Log.Started' -f $full)
}

function Stop-KitLog {
    [CmdletBinding()]
    param()
    if ($script:KitTranscript) {
        try { Stop-Transcript | Out-Null } catch { Write-Verbose $_.Exception.Message }
        $script:KitTranscript = $false
    }
    $script:KitLogFile = $null
}

function Write-KitLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)] [AllowEmptyString()] [string] $Message,
        [ValidateSet('Info', 'Warn', 'Error')] [string] $Level = 'Info'
    )
    $line  = '{0:yyyy-MM-dd HH:mm:ss} [{1}] {2}' -f (Get-Date), $Level.ToUpperInvariant(), $Message
    $color = @{ Info = 'Gray'; Warn = 'Yellow'; Error = 'Red' }[$Level]
    Write-Host $line -ForegroundColor $color
    if ($script:KitLogFile) {
        [IO.File]::AppendAllText($script:KitLogFile, $line + [Environment]::NewLine, (New-Object Text.UTF8Encoding $true))
    }
}
