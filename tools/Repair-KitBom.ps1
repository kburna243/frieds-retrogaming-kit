<#
.SYNOPSIS
    Adds the UTF-8 BOM to PowerShell files that contain non-ASCII characters and have none.
.DESCRIPTION
    Windows PowerShell 5.1 reads a file without BOM as ANSI: umlauts and dashes turn into garbage or break the
    parser. Editors and agents often save UTF-8 without BOM, so this repairs it instead of failing on it. Only
    files that are valid UTF-8 are changed (an ANSI file would need a real conversion, it is reported instead).
    Runs automatically in tests\Run-Tests.ps1 and in the git pre-commit hook (.githooks); CI does not repair,
    tools\Test-KitSyntax.ps1 still fails there.
    Output: the repository-relative paths that were changed.
.PARAMETER Path
    Files to check (relative to -Root or absolute). Default: every *.ps1, *.psm1, *.psd1 git knows or would add.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\Repair-KitBom.ps1
#>
[CmdletBinding()]
param([string[]] $Path, [string] $Root)
$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
if ($Path) { $Path = @($Path | ForEach-Object { $_ -split ',' } | Where-Object { $_ }) } # powershell -File passes "a,b" as one string
else {
    $Path = @(& git -C $Root ls-files --cached --others --exclude-standard -- '*.ps1' '*.psm1' '*.psd1')
    if ($LASTEXITCODE -ne 0) { throw 'git ls-files failed; pass -Path' }
}
$strict = New-Object Text.UTF8Encoding ($false, $true) # throws on invalid UTF-8
foreach ($rel in $Path) {
    $full = if ([IO.Path]::IsPathRooted($rel)) { $rel } else { Join-Path $Root $rel }
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
    $bytes = [IO.File]::ReadAllBytes($full)
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { continue }
    $ascii = $true
    foreach ($b in $bytes) { if ($b -gt 0x7F) { $ascii = $false; break } }
    if ($ascii) { continue }
    try { $null = $strict.GetString($bytes) } catch { Write-Warning "${rel}: not valid UTF-8 (ANSI?), convert it by hand"; continue }
    [IO.File]::WriteAllBytes($full, [byte[]](0xEF, 0xBB, 0xBF) + $bytes)
    Write-Output $rel
}
