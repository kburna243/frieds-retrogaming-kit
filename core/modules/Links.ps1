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

# $true when the shortcut's target exists. Dead targets are reported, never "repaired" by guessing.
function Test-KitShortcutTarget {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $target = (Get-KitShortcut -Path $Path).TargetPath
    [bool]($target -and (Test-Path -LiteralPath $target))
}
