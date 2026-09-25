# Registry: read, search (value data AND value names, recursive), set, export as .reg, checked import.
# Some Windows keys (e.g. AppCompatFlags\Layers) store the path in the value NAME, so a search
# that only looks at data would miss them.

function ConvertTo-RegExeKey([string] $Path) {
    $key = $Path -replace '^Microsoft\.PowerShell\.Core\\Registry::', '' -replace '^Registry::', ''
    $key = $key -replace '^HKCU:\\?', 'HKCU\' -replace '^HKLM:\\?', 'HKLM\'
    $key.TrimEnd('\')
}

function Get-KitRegistryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Name
    )
    $key = Get-Item -LiteralPath $Path -ErrorAction SilentlyContinue
    if ($key) { $key.GetValue($Name, $null, 'DoNotExpandEnvironmentNames') }
}

function Find-KitRegistryValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Pattern,
        [switch] $Recurse
    )
    $keys = @(Get-Item -LiteralPath $Path -ErrorAction Stop)
    if ($Recurse) { $keys += @(Get-ChildItem -LiteralPath $Path -Recurse -ErrorAction SilentlyContinue) }
    $cmp = [StringComparison]::OrdinalIgnoreCase
    foreach ($key in $keys) {
        foreach ($name in $key.GetValueNames()) {
            $data = $key.GetValue($name, $null, 'DoNotExpandEnvironmentNames')
            $hit  = [pscustomobject]@{ Key = $key.Name; PSPath = "Registry::$($key.Name)"; Name = $name; Data = $data; MatchIn = $null }
            if ($name.IndexOf($Pattern, $cmp) -ge 0) { $hit.MatchIn = 'Name'; $hit }
            $texts = @(if ($data -is [string]) { $data } elseif ($data -is [string[]]) { $data })
            if (@($texts | Where-Object { $_.IndexOf($Pattern, $cmp) -ge 0 }).Count) {
                $hit = $hit.PSObject.Copy(); $hit.MatchIn = 'Data'; $hit
            }
        }
    }
}

# New-ItemProperty is used on purpose: reg.exe /d "" swallows the empty argument.
function Set-KitRegistryValue {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Name,
        [Parameter(Mandatory)] [AllowEmptyString()] [AllowNull()] [object] $Value,
        [ValidateSet('String', 'ExpandString', 'DWord', 'QWord', 'MultiString', 'Binary')] [string] $Type = 'String'
    )
    if (-not $PSCmdlet.ShouldProcess("$Path\$Name", 'Set registry value')) { return }
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }
    New-ItemProperty -LiteralPath $Path -Name $Name -Value $Value -PropertyType $Type -Force | Out-Null
}

function Export-KitRegistryKey {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Destination
    )
    $ErrorActionPreference = 'Continue' # reg.exe writes to stderr; judge by exit code only
    $key  = ConvertTo-RegExeKey $Path
    $dest = Resolve-FullPath $Destination
    $output = & reg.exe export $key $dest /y 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "reg.exe export '$key' failed ($LASTEXITCODE): $($output.Trim())" }
    Get-Item -LiteralPath $dest
}

# Long form as used inside .reg files: HKCU:\X, Registry::HKEY_CURRENT_USER\X -> HKEY_CURRENT_USER\X.
function ConvertTo-RegFileKey([string] $Path) {
    (ConvertTo-RegExeKey $Path) -replace '^HKCU(?=\\|$)', 'HKEY_CURRENT_USER' -replace '^HKLM(?=\\|$)', 'HKEY_LOCAL_MACHINE' `
        -replace '^HKU(?=\\|$)', 'HKEY_USERS' -replace '^HKCR(?=\\|$)', 'HKEY_CLASSES_ROOT'
}

# Control characters a .reg line must not contain (tab excepted; a CR left after splitting at CRLF/LF is a lone
# CR). U+2028/U+2029 are added as [char] so the source file itself carries no line separator characters.
$script:RegControlPattern = '[\x00-\x08\x0B-\x1F\x7F\x85' + [char]0x2028 + [char]0x2029 + ']'

# A .reg text may only MERGE values below -AllowedRoots: no key deletion ([-...]), no value deletion (data
# starting with -), no key outside the roots, no line reg.exe could read as something else: control characters
# (NUL, NEL, U+2028/9, a CR without LF ...) are refused, they could end a line for reg.exe but not for this
# check. Text from reg export (UTF-16LE with BOM) must be decoded with BOM detection; a leftover BOM character
# is ignored. Throws with line number and line; returns the checked lines joined with CRLF, the only text
# that may be imported.
function Assert-KitRegText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $AllowedRoots
    )
    $roots = @($AllowedRoots | Where-Object { $_ } | ForEach-Object { (ConvertTo-RegFileKey $_) + '\' })
    $lines = $Text.TrimStart([char]0xFEFF) -split '\r?\n'
    $header = $false; $inKey = $false; $continued = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $n = $i + 1
        if ($lines[$i] -match $script:RegControlPattern) { throw (Get-KitText 'Registry.Refused.Control' -f $n) }
        $t = $lines[$i].Trim()
        if ($continued) {
            if ($t -notmatch '^[0-9A-Fa-f,\s]*\\?$') { throw (Get-KitText 'Registry.Refused.Syntax' -f $n, $t) }
            $continued = $t.EndsWith('\'); continue
        }
        if (-not $t -or $t.StartsWith(';')) { continue }
        if (-not $header) {
            if ($t -notmatch '^(Windows Registry Editor Version 5\.00|REGEDIT4)$') { throw (Get-KitText 'Registry.Refused.Header') }
            $header = $true; continue
        }
        if ($t.StartsWith('[')) {
            if ($t -notmatch '^\[(.+)\]$') { throw (Get-KitText 'Registry.Refused.Syntax' -f $n, $t) }
            $key = $Matches[1]
            if ($key.StartsWith('-')) { throw (Get-KitText 'Registry.Refused.DeleteKey' -f $n, $t) }
            if (-not @($roots | Where-Object { ($key + '\').StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }).Count) {
                throw (Get-KitText 'Registry.Refused.Outside' -f $n, $t, ($AllowedRoots -join '; '))
            }
            $inKey = $true; continue
        }
        if ($inKey -and $t -match '^(@|"(?:[^"\\]|\\.)*")\s*=\s*(.*)$') {
            if ($Matches[2].StartsWith('-')) { throw (Get-KitText 'Registry.Refused.DeleteValue' -f $n, $t) }
            $continued = $Matches[2].EndsWith('\'); continue
        }
        throw (Get-KitText 'Registry.Refused.Syntax' -f $n, $t)
    }
    if (-not $header) { throw (Get-KitText 'Registry.Refused.Header') }
    $lines -join "`r`n"
}

# Writes the text as UTF-16LE .reg into TEMP and reopens it read-only with FileShare.Read: while the handle is
# held nobody can change or replace the file; reg.exe (read access) still can open it. Returns the stream.
function Open-CheckedRegFile([string] $Path, [string] $Text) {
    $bytes = [byte[]]([Text.Encoding]::Unicode.GetPreamble() + [Text.Encoding]::Unicode.GetBytes($Text))
    $w = [IO.File]::Open($Path, 'CreateNew', 'Write', 'None')
    try { $w.Write($bytes, 0, $bytes.Length) } finally { $w.Dispose() }
    $r = [IO.File]::Open($Path, 'Open', 'Read', 'Read')
    $copy = New-Object byte[] $r.Length
    $read = 0
    while ($read -lt $copy.Length) { $n = $r.Read($copy, $read, $copy.Length - $read); if ($n -le 0) { break }; $read += $n }
    if ([Convert]::ToBase64String($copy) -ne [Convert]::ToBase64String($bytes)) { $r.Dispose(); throw (Get-KitText 'Plan.Changed' -f $Path) }
    $r
}

# Every import goes through Assert-KitRegText; reg.exe imports a private copy of the checked and rebuilt text,
# not the file that could still change after the check, and the copy is held open read-only (FileShare.Read)
# while reg.exe runs. Only then is "merges, never deletes" true.
function Import-KitRegistryFile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $AllowedRoots
    )
    $file = Resolve-FullPath $Path
    $text = [IO.File]::ReadAllText($file) # detects the UTF-16LE BOM of reg export
    $checked = Assert-KitRegText -Text $text -AllowedRoots $AllowedRoots
    if (-not $PSCmdlet.ShouldProcess($file, 'reg.exe import (merges, never deletes)')) { return }
    $tmp = Join-Path $env:TEMP ("rck-import-{0}.reg" -f [guid]::NewGuid())
    $ErrorActionPreference = 'Continue'
    $handle = $null
    try {
        $handle = Open-CheckedRegFile $tmp $checked
        $output = & reg.exe import $tmp 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "reg.exe import '$file' failed ($LASTEXITCODE): $($output.Trim())" }
    } finally {
        if ($handle) { $handle.Dispose() }
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}
