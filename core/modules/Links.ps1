# Links: .lnk files only through WScript.Shell (the documented COM API).

function Get-KitShortcut {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $full = Resolve-FullPath $Path
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "Shortcut not found: $full" }
    $shell = New-Object -ComObject WScript.Shell
    try {
        $link = $shell.CreateShortcut($full)
        [pscustomobject]@{
            Path             = $full
            TargetPath       = $link.TargetPath
            Arguments        = $link.Arguments
            WorkingDirectory = $link.WorkingDirectory
            IconLocation     = $link.IconLocation
            Description      = $link.Description
        }
    } finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
}

function Set-KitShortcut {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [string] $TargetPath,
        [string] $Arguments,
        [string] $WorkingDirectory,
        [string] $IconLocation,
        [string] $Description
    )
    $full = Resolve-FullPath $Path
    if (-not $PSCmdlet.ShouldProcess($full, 'Write shortcut')) { return }
    $shell = New-Object -ComObject WScript.Shell
    try {
        $link = $shell.CreateShortcut($full)
        foreach ($p in 'TargetPath', 'Arguments', 'WorkingDirectory', 'IconLocation', 'Description') {
            if ($PSBoundParameters.ContainsKey($p)) { $link.$p = $PSBoundParameters[$p] }
        }
        $link.Save()
    } finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
    Get-KitShortcut -Path $full
}

# Opens a web link in the user's browser. The wizard may run elevated: "explorer.exe <url>" hands the link to
# the (unelevated) shell instead of starting the browser with administrator rights (N9). Only http(s) URLs
# without quotes; anything else is ignored and $false returned.
function Open-KitWebLink {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Url, [switch] $HttpsOnly)
    $u = $null
    $schemes = if ($HttpsOnly) { @('https') } else { @('http', 'https') }
    if (-not [Uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$u) -or $schemes -notcontains $u.Scheme -or $Url -match '["\s]') { return $false }
    $null = Start-Process -FilePath (Join-Path $env:SystemRoot 'explorer.exe') -ArgumentList ('"' + $u.AbsoluteUri + '"')
    $true
}

# $true when the shortcut's target exists. Dead targets are reported, never "repaired" by guessing.
function Test-KitShortcutTarget {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $target = (Get-KitShortcut -Path $Path).TargetPath
    [bool]($target -and (Test-Path -LiteralPath $target))
}
