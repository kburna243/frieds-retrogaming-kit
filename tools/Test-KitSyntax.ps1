<#
.SYNOPSIS
    Static checks for every PowerShell file git would publish; exits with 1 on any problem.
.DESCRIPTION
    - every *.ps1, *.psm1 and *.psd1 parses without errors
    - every file with non-ASCII characters starts with a UTF-8 BOM (Windows PowerShell 5.1 reads files
      without BOM as ANSI, so umlauts, dashes and emoji would be garbled or break string parsing)
    - every *.psd1 loads as data (Import-LocalizedData, like the kit loads its texts; Import-PowerShellDataFile
      refuses large files such as the i18n tables)
    - network APIs appear only in core/modules/Download.ps1 (no telemetry, no hidden downloads)
    - every *.xaml (gui views and themes) is well-formed XML
    - the module manifests (core, pinball, lightgun, gui, api) carry the version from the VERSION file
    Runs on Windows PowerShell 5.1 and on PowerShell 7.
.PARAMETER Root
    Repository root. Default: the parent folder of this script's folder.
.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File tools\Test-KitSyntax.ps1
#>
[CmdletBinding()]
param([string] $Root)

$ErrorActionPreference = 'Stop'
if (-not $Root) { $Root = Split-Path -Parent $PSScriptRoot }
$Root = (Resolve-Path -LiteralPath $Root).Path
$problems = New-Object System.Collections.Generic.List[string]

$files = $null
if ((Get-Command git -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath (Join-Path $Root '.git'))) {
    $files = @(& git -C $Root ls-files --cached --others --exclude-standard -- '*.ps1' '*.psm1' '*.psd1')
    if ($LASTEXITCODE -ne 0) { $files = $null }
}
if ($null -eq $files) {
    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1' | ForEach-Object {
        $_.FullName.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/'
    } | Where-Object { $_ -notmatch '(^|/)(\.git|node_modules)(/|$)' })
}

$checked = 0
foreach ($rel in $files | Sort-Object -Unique) {
    $full = Join-Path $Root $rel
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
    $checked++

    $bytes = [IO.File]::ReadAllBytes($full)
    $hasBom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    if (-not $hasBom) {
        foreach ($b in $bytes) {
            if ($b -gt 0x7F) { $problems.Add("${rel}: non-ASCII characters without UTF-8 BOM"); break }
        }
    }

    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($full, [ref] $tokens, [ref] $errors)
    foreach ($e in $errors) {
        $problems.Add(('{0}:{1}: parse error: {2}' -f $rel, $e.Extent.StartLineNumber, $e.Message))
    }

    if ($rel -like '*.psd1' -and -not $errors) {
        try {
            $data = $null
            Import-LocalizedData -BindingVariable data -BaseDirectory (Split-Path -Parent $full) -FileName (Split-Path -Leaf $full) -UICulture 'en-US' -ErrorAction Stop
        }
        catch { $problems.Add("${rel}: not a valid data file: $($_.Exception.Message)") }
    }
}

# --- local only: network access exists in exactly one place ---------------------------------------------------
# The kit has no telemetry. Downloads go through core/modules/Download.ps1 (HTTPS, allowlisted hosts, signature
# and hash checks); any other network API in the shipped engine is a finding.
$networkApi = '\b(Invoke-WebRequest|Invoke-RestMethod|Start-BitsTransfer|Send-MailMessage|Net\.WebClient|Net\.WebRequest|Net\.HttpWebRequest|Net\.Http\.HttpClient|Net\.Sockets\.|Net\.Mail\.|iwr|irm|wget|curl)\b'
$networkAllowed = @('core/modules/Download.ps1')
foreach ($rel in $files | Sort-Object -Unique) {
    if ($rel -notmatch '^(core|pinball|lightgun|gui|api)/.+\.ps(m?)1$' -or $networkAllowed -contains $rel) { continue }
    $full = Join-Path $Root $rel
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
    $tokens = $null; $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($full, [ref] $tokens, [ref] $errors)
    # Tokens, not text: comments and strings (e.g. a URL shown to the user) are not network calls.
    foreach ($t in $tokens) {
        if ($t.Kind.ToString() -in 'Comment', 'StringLiteral', 'StringExpandable', 'HereStringLiteral', 'HereStringExpandable') { continue }
        if ($t.Text -match $networkApi) {
            $problems.Add(('{0}:{1}: network API "{2}" outside {3}' -f $rel, $t.Extent.StartLineNumber, $t.Text, ($networkAllowed -join ', ')))
        }
    }
}

# --- XAML: every view and theme is well-formed XML ------------------------------------------------------------
$xamlFiles = $null
if ((Get-Command git -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath (Join-Path $Root '.git'))) {
    $xamlFiles = @(& git -C $Root ls-files --cached --others --exclude-standard -- '*.xaml')
}
if ($null -eq $xamlFiles) { $xamlFiles = @(Get-ChildItem -LiteralPath $Root -Recurse -File -Filter '*.xaml' | ForEach-Object { $_.FullName.Substring($Root.Length).TrimStart('\', '/') -replace '\\', '/' }) }
foreach ($rel in $xamlFiles | Where-Object { $_ -notmatch '(^|/)node_modules/' }) {
    $full = Join-Path $Root $rel
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
    try { $doc = New-Object Xml.XmlDocument; $doc.Load($full) }
    catch { $problems.Add("${rel}: not well-formed XML: $($_.Exception.Message)") }
}

# --- version consistency --------------------------------------------------------------------------------------
$versionFile = Join-Path $Root 'VERSION'
if (Test-Path -LiteralPath $versionFile) {
    $version = ([IO.File]::ReadAllText($versionFile)).Trim()
    if ($version -notmatch '^(\d+\.\d+\.\d+)(-[0-9A-Za-z.-]+)?$') {
        $problems.Add("VERSION: invalid version '$version'")
    } else {
        $moduleVersion = $Matches[1]
        foreach ($m in 'core/RetroCabinetKit.Core.psd1', 'pinball/RetroCabinetKit.Pinball.psd1', 'lightgun/RetroCabinetKit.Lightgun.psd1', 'gui/RetroCabinetKit.Gui.psd1', 'api/RetroCabinetKit.Api.psd1') {
            $data = Import-PowerShellDataFile -LiteralPath (Join-Path $Root $m)
            if ($data.ModuleVersion -ne $moduleVersion) { $problems.Add("${m}: ModuleVersion $($data.ModuleVersion) differs from VERSION $moduleVersion") }
        }
    }
} else {
    $problems.Add('VERSION file missing')
}

foreach ($p in $problems) { Write-Output $p }
Write-Output ('Syntax check: {0} PowerShell files, {1} problem(s).' -f $checked, $problems.Count)
if ($problems.Count) { exit 1 }
exit 0
