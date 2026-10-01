# IniParser.ps1 -- Structured INI file handling with shadow override support.
# Reads INI files into nested hashtables: @{ Section = @{ Key = Value } }.
# Supports .override.ini files: user values always win over kit defaults.
# This is the foundation for the Shadow Override pattern: kit updates never
# overwrite user customizations.

# Convert an INI file into a nested hashtable: Section -> Key -> Value.
# Keys before any [Section] header go into the '' (global) section.
function ConvertFrom-Ini {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)] [string] $Path,
        [switch] $AsOrdered
    )
    process {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
            Write-Error "INI file not found: $Path"
            return @{}
        }
        $ini = if ($AsOrdered) { [ordered]@{} } else { @{} }
        $currentSection = ''
        if (-not $ini.ContainsKey($currentSection)) { $ini[$currentSection] = if ($AsOrdered) { [ordered]@{} } else { @{} } }

        foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
            # Section header
            if ($line -match '^\s*\[([^\]]+)\]\s*$') {
                $currentSection = $matches[1].Trim()
                if (-not $ini.ContainsKey($currentSection)) {
                    $ini[$currentSection] = if ($AsOrdered) { [ordered]@{} } else { @{} }
                }
                continue
            }
            # Skip comments and blanks
            if ($line -match '^\s*[#;]' -or $line -match '^\s*$') { continue }
            # Key = Value (or Key: Value)
            if ($line -match '^\s*([^=:]+?)\s*[=:]\s*(.*)') {
                $key = $matches[1].Trim()
                $value = $matches[2].Trim()
                # Remove trailing inline comments (but keep ; inside quotes)
                if ($value -match '^(.*?)\s*[#;]') { $value = $matches[1].Trim() }
                if (-not $ini.ContainsKey($currentSection)) {
                    $ini[$currentSection] = if ($AsOrdered) { [ordered]@{} } else { @{} }
                }
                $ini[$currentSection][$key] = $value
            }
        }
        $ini
    }
}

# Convert a nested hashtable back to INI text and write to file.
# Preserves section order when AsOrdered hashtables are used internally.
function ConvertTo-Ini {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [hashtable] $IniData,
        [Parameter(Mandatory)] [string] $Path
    )
    if (-not $PSCmdlet.ShouldProcess($Path, 'write INI file')) { return }

    $sb = [Text.StringBuilder]::new()
    $firstSection = $true

    # Global section first (keys before any [header])
    if ($IniData.ContainsKey('') -and $IniData[''].Count) {
        foreach ($key in $IniData[''].Keys) {
            $null = $sb.AppendLine("$key = $($IniData[''][$key])")
        }
        $firstSection = $false
    }

    # Named sections
    foreach ($section in $IniData.Keys) {
        if ($section -eq '') { continue }
        if (-not $firstSection) { $null = $sb.AppendLine() }
        $null = $sb.AppendLine("[$section]")
        foreach ($key in $IniData[$section].Keys) {
            $null = $sb.AppendLine("$key = $($IniData[$section][$key])")
        }
        $firstSection = $false
    }

    # Backup before writing
    if (Test-Path -LiteralPath $Path) {
        $backup = "$Path.bak_$(Get-Date -Format 'yyyyMMddHHmmss')"
        Copy-Item -LiteralPath $Path -Destination $backup -ErrorAction SilentlyContinue
    }

    $text = $sb.ToString().TrimEnd("`r`n")
    [IO.File]::WriteAllText($Path, $text, [Text.UTF8Encoding]::new($false))
    Write-Verbose "INI written: $Path ($($IniData.Keys.Count) section(s))"
}

# Deep-merge: OverrideData values win over BaseData values (per-section, per-key).
# Sections and keys only in BaseData are preserved.
function Merge-IniData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable] $BaseData,
        [Parameter(Mandatory)] [hashtable] $OverrideData
    )
    $merged = @{}
    # Copy base data (shallow clone sections, but deep enough for our use case)
    foreach ($section in $BaseData.Keys) {
        $merged[$section] = @{}
        foreach ($key in $BaseData[$section].Keys) {
            $merged[$section][$key] = $BaseData[$section][$key]
        }
    }
    # Apply overrides
    foreach ($section in $OverrideData.Keys) {
        if (-not $merged.ContainsKey($section)) {
            $merged[$section] = @{}
        }
        foreach ($key in $OverrideData[$section].Keys) {
            $merged[$section][$key] = $OverrideData[$section][$key]
        }
    }
    $merged
}

# Get the override path for a given INI file.
function Get-IniOverridePath {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $IniPath)
    $IniPath -replace '\.ini$', '.override.ini'
}

# Test whether a specific key is managed by a user override.
function Test-IniIsOverridden {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $IniPath,
        [Parameter(Mandatory)] [string] $Section,
        [Parameter(Mandatory)] [string] $Key
    )
    $overridePath = Get-IniOverridePath $IniPath
    if (-not (Test-Path -LiteralPath $overridePath -PathType Leaf)) { return $false }
    $override = ConvertFrom-Ini -Path $overridePath
    $override.ContainsKey($Section) -and $override[$Section].ContainsKey($Key)
}

# Load the union: base INI merged with its override (if any).
function Get-IniEffectiveConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $IniPath)
    $base = ConvertFrom-Ini -Path $IniPath
    $overridePath = Get-IniOverridePath $IniPath
    if (Test-Path -LiteralPath $overridePath -PathType Leaf) {
        $override = ConvertFrom-Ini -Path $overridePath
        return Merge-IniData -BaseData $base -OverrideData $override
    }
    $base
}