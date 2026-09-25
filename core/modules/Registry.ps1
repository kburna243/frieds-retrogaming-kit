# Registry: read, search (value data AND value names, recursive), set, export as .reg.
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

function Import-KitRegistryFile {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [string] $Path)
    $file = Resolve-FullPath $Path
    if (-not $PSCmdlet.ShouldProcess($file, 'reg.exe import (merges, never deletes)')) { return }
    $ErrorActionPreference = 'Continue'
    $output = & reg.exe import $file 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "reg.exe import '$file' failed ($LASTEXITCODE): $($output.Trim())" }
}
