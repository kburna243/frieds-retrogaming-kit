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

# A .reg text may only MERGE values below -AllowedRoots: no key deletion ([-...]), no value deletion ("x"=-,
# @=-), no key outside the roots, no line reg.exe could read as something else. Text from reg export
# (UTF-16LE with BOM) must be decoded with BOM detection; a leftover BOM character is ignored.
# Throws with line number and line; returns nothing when the text is fine.
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
        $t = $lines[$i].Trim()
        $n = $i + 1
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
            if ($Matches[2].Trim() -eq '-') { throw (Get-KitText 'Registry.Refused.DeleteValue' -f $n, $t) }
            $continued = $Matches[2].EndsWith('\'); continue
        }
        throw (Get-KitText 'Registry.Refused.Syntax' -f $n, $t)
    }
    if (-not $header) { throw (Get-KitText 'Registry.Refused.Header') }
}

# Every import goes through Assert-KitRegText; reg.exe imports a private copy of the checked text, not the
# file that could still change after the check. Only then is "merges, never deletes" true.
function Import-KitRegistryFile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $AllowedRoots
    )
    $file = Resolve-FullPath $Path
    $text = [IO.File]::ReadAllText($file) # detects the UTF-16LE BOM of reg export
    Assert-KitRegText -Text $text -AllowedRoots $AllowedRoots
    if (-not $PSCmdlet.ShouldProcess($file, 'reg.exe import (merges, never deletes)')) { return }
    $tmp = Join-Path $env:TEMP ("rck-import-{0}.reg" -f [guid]::NewGuid())
    $ErrorActionPreference = 'Continue'
    try {
        [IO.File]::WriteAllText($tmp, $text.TrimStart([char]0xFEFF), [Text.Encoding]::Unicode)
        $output = & reg.exe import $tmp 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) { throw "reg.exe import '$file' failed ($LASTEXITCODE): $($output.Trim())" }
    } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
}
