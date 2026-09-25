<#
.SYNOPSIS
    Scans the repository for personal or machine-specific data and exits with 1 when it finds any.
.DESCRIPTION
    Checks every file git would publish (tracked plus untracked, not ignored; without git: every file below
    the root except .git, node_modules and dist) for:
      PrivateIp  private and CGNAT IPv4 addresses (10/8, 172.16/12, 192.168/16, 100.64/10, 169.254/16)
      HostName   UNC host names, Tailscale names (*.ts.net), *.local/*.lan/*.fritz.box/*.home.arpa names,
                 Windows default computer names (DESKTOP-/WIN- plus random letters), ssh logins
      DrivePath  paths that start with a drive letter
      Email      e-mail addresses
      Secret     typical secret patterns (private keys, GitHub/OpenAI/Anthropic/AWS/Slack/Google tokens, JWTs,
                 "password = ..." assignments)
    Legitimate examples are listed in the allowlist (tools/depersonalized-allowlist.psd1), each with a reason.
    Runs on Windows PowerShell 5.1 and on PowerShell 7 (Windows, Linux, macOS).
.PARAMETER Root
    Repository root. Default: the parent folder of this script's folder.
.PARAMETER AllowlistPath
    Allowlist file. Default: depersonalized-allowlist.psd1 next to this script.
.EXAMPLE
    pwsh -NoProfile -File tools/Test-Depersonalized.ps1
#>
[CmdletBinding()]
param(
    [string] $Root,
    [string] $AllowlistPath
)
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
if (-not $AllowlistPath) { $AllowlistPath = Join-Path $PSScriptRoot 'depersonalized-allowlist.psd1' }
$Root = (Resolve-Path -LiteralPath $Root).Path

# --- rules ----------------------------------------------------------------------------------------------------
$octet = '(?:25[0-5]|2[0-4]\d|1?\d?\d)'
$rules = @(
    @{ Kind = 'PrivateIp'; Pattern = "(?<![\d.])(?:10\.$octet|172\.(?:1[6-9]|2\d|3[01])|192\.168|169\.254)\.$octet\.$octet(?![\d.])" }
    @{ Kind = 'PrivateIp'; Pattern = "(?<![\d.])100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7])\.$octet\.$octet(?![\d.])" }
    @{ Kind = 'HostName';  Pattern = '(?<![\w\\])\\\\[A-Za-z0-9][A-Za-z0-9-]{0,62}\\[^\\\s"''<>|]+' }
    @{ Kind = 'HostName';  Pattern = '\b[a-z0-9-]+(?:\.[a-z0-9-]+)*\.ts\.net\b' }
    @{ Kind = 'HostName';  Pattern = '\b[a-z0-9][a-z0-9-]*\.(?:local|lan|fritz\.box|home\.arpa)\b(?!\.)' }
    @{ Kind = 'HostName';  Pattern = '\b(?:DESKTOP-[A-Z0-9]{7}|WIN-[A-Z0-9]{11})\b' }
    @{ Kind = 'HostName';  Pattern = '\bssh\s+(?:-\S+\s+)*[A-Za-z0-9._-]+@[A-Za-z0-9._-]+' }
    @{ Kind = 'DrivePath'; Pattern = '(?<![A-Za-z0-9\\])[A-Za-z]:[\\/](?![\\/])[^\s"''`<>|*?)\]}]*' }
    @{ Kind = 'Email';     Pattern = '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}\b' }
    @{ Kind = 'Secret';    Pattern = '-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----' }
    @{ Kind = 'Secret';    Pattern = '\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}\b|\bgithub_pat_[A-Za-z0-9_]{40,}' }
    @{ Kind = 'Secret';    Pattern = '\bsk-(?:ant-|proj-)?[A-Za-z0-9_-]{20,}' }
    @{ Kind = 'Secret';    Pattern = '\b(?:AKIA|ASIA)[A-Z0-9]{16}\b' }
    @{ Kind = 'Secret';    Pattern = '\bxox[abprs]-[A-Za-z0-9-]{10,}' }
    @{ Kind = 'Secret';    Pattern = '\bAIza[0-9A-Za-z_-]{35}\b' }
    @{ Kind = 'Secret';    Pattern = '\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}' }
    @{ Kind = 'Secret';    Pattern = '(?i)\b(?:password|passwd|pwd|secret|api[_-]?key|token)\b\s*[:=]\s*["''][^"''\s$]{6,}["'']' }
)

# --- allowlist ------------------------------------------------------------------------------------------------
$allow = @()
if (Test-Path -LiteralPath $AllowlistPath) { $allow = @((Import-PowerShellDataFile -LiteralPath $AllowlistPath).Entries) }
foreach ($a in $allow) {
    if (-not $a.Path -or -not $a.Reason) { throw "Allowlist entry without Path or Reason: $($a | Out-String)" }
}

function Test-Allowed([string] $File, [string] $Kind, [string] $Text) {
    foreach ($a in $allow) {
        if ($File -notlike $a.Path) { continue }
        if ($a.Kind -and $a.Kind -ne $Kind) { continue }
        if ($a.Match -and $Text -notmatch $a.Match) { continue }
        return $true
    }
    $false
}

# --- files ----------------------------------------------------------------------------------------------------
$files = $null
if ((Get-Command git -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath (Join-Path $Root '.git'))) {
    $files = @(& git -C $Root ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) { $files = $null }
}
if ($null -eq $files) {
    $skip = '(^|/)(\.git|node_modules|dist)(/|$)'
    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Force | ForEach-Object {
        $_.FullName.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/'
    } | Where-Object { $_ -notmatch $skip })
}
$binary = '\.(png|jpe?g|gif|ico|webp|woff2?|ttf|otf|zip|exe|dll|db|sqlite|pdf)$'

# --- scan -----------------------------------------------------------------------------------------------------
$findings = New-Object System.Collections.Generic.List[object]
$scanned = 0
foreach ($rel in $files | Sort-Object -Unique) {
    if ($rel -match $binary) { continue }
    $full = Join-Path $Root $rel
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue } # deleted but still in the index
    $scanned++
    $lines = [IO.File]::ReadAllLines($full)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        foreach ($r in $rules) {
            foreach ($m in [regex]::Matches($lines[$i], $r.Pattern)) {
                if (Test-Allowed $rel $r.Kind $m.Value) { continue }
                $findings.Add([pscustomobject]@{ File = $rel; Line = $i + 1; Kind = $r.Kind; Text = $m.Value })
            }
        }
    }
}

foreach ($f in $findings) { Write-Output ('{0}:{1}: {2}: {3}' -f $f.File, $f.Line, $f.Kind, $f.Text) }
Write-Output ('Depersonalization scan: {0} files, {1} finding(s), {2} allowlist entries.' -f $scanned, $findings.Count, $allow.Count)
if ($findings.Count) { exit 1 }
exit 0
