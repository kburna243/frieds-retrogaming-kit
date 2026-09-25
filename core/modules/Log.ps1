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

function Get-KitLogFile {
    [CmdletBinding()]
    param()
    $script:KitLogFile
}

# Placeholders for what identifies the person or the machine: profile path, user name, computer name and
# account SIDs (S-1-5-21-...). Names only count as whole words, so a short user name does not eat text.
function ConvertTo-KitAnonymousText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text,
        [string] $UserName = $env:USERNAME,
        [string] $ComputerName = $env:COMPUTERNAME,
        [string] $UserProfile = $env:USERPROFILE
    )
    $t = [regex]::Replace($Text, 'S-1-5-21(?:-\d+){3,4}', '<SID>')
    if ($UserProfile) { $t = [regex]::Replace($t, [regex]::Escape($UserProfile.TrimEnd('\')), '<USERPROFILE>', 'IgnoreCase') }
    foreach ($pair in @(@($UserName, '<USER>'), @($ComputerName, '<COMPUTER>'))) {
        if ($pair[0]) { $t = [regex]::Replace($t, '(?<![\p{L}\p{N}_])' + [regex]::Escape($pair[0]) + '(?![\p{L}\p{N}_])', $pair[1], 'IgnoreCase') }
    }
    $t
}

# "Export log for support": one anonymized UTF-8 file from the given logs (missing ones are left out).
# Files still open for writing (transcript) are read with FileShare.ReadWrite.
function Export-KitSupportLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]] $Path,
        [Parameter(Mandatory)] [string] $Destination
    )
    $parts = foreach ($p in $Path) {
        $full = Resolve-FullPath $p
        if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
        $stream = [IO.File]::Open($full, 'Open', 'Read', 'ReadWrite')
        try { $reader = New-Object IO.StreamReader ($stream, [Text.Encoding]::UTF8, $true); $text = $reader.ReadToEnd() } finally { $stream.Dispose() }
        "===== $(Split-Path -Leaf $full) =====" + [Environment]::NewLine + (ConvertTo-KitAnonymousText -Text $text)
    }
    $dest = Resolve-FullPath $Destination
    [IO.File]::WriteAllText($dest, (@($parts) -join [Environment]::NewLine), (New-Object Text.UTF8Encoding $true))
    Write-KitLog (Get-KitText 'Log.SupportExported' -f $dest)
    Get-Item -LiteralPath $dest
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
