# Library Common Helpers
# Unified JSON catalog format: neutral intermediate representation for all frontend databases.

function Get-LibraryAdapterDir { Join-Path $script:LibraryDir 'adapters' }

function New-LibraryCatalog {
    [CmdletBinding()]
    param()
    [pscustomobject]@{
        Version = '1.0'
        Generated = (Get-Date -Format 'o')
        Systems = @()
        TotalRoms = 0
    }
}

function Add-LibrarySystemEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] $Catalog,
        [Parameter(Mandatory)] [string] $System,
        [Parameter(Mandatory)] [string] $Frontend,
        [string] $Path = '',
        [string[]] $Extensions = @(),
        [hashtable] $Metadata = @{}
    )
    $entry = [pscustomobject]@{
        System = $System
        Frontend = $Frontend
        Path = $Path
        Extensions = $Extensions
        Roms = @()
        Metadata = $Metadata
    }
    $Catalog.Systems += $entry
    $Catalog
}

function Find-LibraryRoms {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [string[]] $Extensions = @()
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return @() }
    $roms = @(Get-ChildItem -LiteralPath $Path -Recurse -File -ErrorAction SilentlyContinue)
    if ($Extensions.Count) {
        $roms = @($roms | Where-Object { $_.Extension -in $Extensions })
    }
    $roms
}

function Get-LibraryChecksum {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
    (Get-FileHash -Algorithm SHA256 -Path $Path).Hash.ToLower()
}

function Get-LibraryRomMetadata {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [System.IO.FileInfo] $File)
    @{
        Name = $File.BaseName
        Size = $File.Length
        Extension = $File.Extension
        LastModified = $File.LastWriteTime.ToString('o')
        ChecksumSha256 = Get-LibraryChecksum -Path $File.FullName
    }
}