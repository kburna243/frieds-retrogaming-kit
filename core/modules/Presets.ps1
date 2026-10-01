# Presets.ps1 -- Named configuration presets for the kit.
# Presets are JSON files in presets/ (user) or core/presets/ (built-in).
# Easy mode uses built-in best-practice presets; Custom lets the user pick;
# NerdExtreme exposes the raw preset JSON for editing.

$script:PresetsDir = ''
$script:BuiltinPresetsDir = ''

function Get-KitPresetsDir {
    if ($script:PresetsDir) { return $script:PresetsDir }
    $script:PresetsDir = Join-Path $env:USERPROFILE 'RetroCabinet\Presets'
    if (-not (Test-Path -LiteralPath $script:PresetsDir)) { $null = New-Item -ItemType Directory -Path $script:PresetsDir -Force }
    $script:PresetsDir
}

function Get-KitBuiltinPresetsDir {
    if ($script:BuiltinPresetsDir) { return $script:BuiltinPresetsDir }
    $script:BuiltinPresetsDir = Join-Path $script:KitRoot 'core\presets'
    $script:BuiltinPresetsDir
}

# List all available presets (built-in + user).
function Get-KitPresetCatalog {
    [CmdletBinding()]
    param([string] $Module = '')
    $presets = @()
    $dirs = @(Get-KitBuiltinPresetsDir)
    $userDir = Get-KitPresetsDir
    if ($userDir -and (Test-Path $userDir)) { $dirs += $userDir }
    foreach ($d in $dirs) {
        if (-not (Test-Path $d)) { continue }
        foreach ($f in Get-ChildItem -LiteralPath $d -Filter '*.json' -File -ErrorAction SilentlyContinue | Sort-Object Name) {
            try {
                $json = Get-Content $f.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($Module -and $json.module -and $json.module -ne $Module) { continue }
                $isBuiltin = $f.DirectoryName -eq (Get-KitBuiltinPresetsDir)
                $presets += [pscustomobject]@{
                    Name        = $f.BaseName
                    Module      = if ($json.module) { $json.module } else { '' }
                    Description = if ($json.description) { $json.description } else { '' }
                    Mode        = if ($json.mode) { $json.mode } else { 'Custom' }
                    Builtin     = $isBuiltin
                    Path        = $f.FullName
                }
            } catch {
                Write-KitLog "Invalid preset file: $($f.Name)" -Level Warn
            }
        }
    }
    $presets
}

# Load a preset by name.
function Get-KitPreset {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Name)
    $dirs = @((Get-KitPresetsDir), (Get-KitBuiltinPresetsDir))
    foreach ($d in $dirs) {
        $path = Join-Path $d "$Name.json"
        if (Test-Path -LiteralPath $path) {
            try {
                Get-Content $path -Raw -Encoding UTF8 | ConvertFrom-Json
                return
            } catch {
                throw "Preset '$Name' is invalid JSON: $($_.Exception.Message)"
            }
        }
    }
    throw "Preset '$Name' not found"
}

# Save a custom preset.
function Set-KitPreset {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [hashtable] $Values,
        [string] $Module = '',
        [string] $Description = '',
        [ValidateSet('Easy', 'Custom', 'NerdExtreme')] [string] $Mode = 'Custom'
    )
    if (-not $PSCmdlet.ShouldProcess($Name, 'save preset')) { return $false }
    $dir = Get-KitPresetsDir
    $path = Join-Path $dir "$Name.json"
    $preset = [ordered]@{
        name        = $Name
        module      = $Module
        description = $Description
        mode        = $Mode
        values      = $Values
        created     = (Get-Date -Format 'o')
    }
    $json = ConvertTo-Json $preset -Depth 5 -Compress
    [IO.File]::WriteAllText($path, $json, [Text.UTF8Encoding]::new($false))
    Write-KitLog "Preset saved: $Name ($Module) -> $path"
    $true
}

# Remove a user preset (never a built-in).
function Remove-KitPreset {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [string] $Name)
    $dir = Get-KitPresetsDir
    $path = Join-Path $dir "$Name.json"
    if (-not (Test-Path $path)) { throw "Preset '$Name' not found" }
    # Safety: refuse to delete built-in presets
    $builtinPath = Join-Path (Get-KitBuiltinPresetsDir) "$Name.json"
    if (Test-Path $builtinPath) { throw "Cannot remove built-in preset '$Name' -- only user presets can be deleted" }
    if (-not $PSCmdlet.ShouldProcess($Name, 'remove preset')) { return $false }
    Remove-Item $path -Force
    Write-KitLog "Preset removed: $Name"
    $true
}

# Apply a preset's values to the current setup context.
function Invoke-KitPreset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [string] $RetroBatRoot = ''
    )
    $preset = Get-KitPreset -Name $Name
    if (-not $preset) { throw "Preset '$Name' not found" }
    if ($preset.mode) { Set-KitSetupMode -Mode $preset.mode }
    if ($preset.module) { $script:SetupTargetModule = $preset.module }
    Write-KitLog "Preset loaded: $Name ($(if ($preset.module) { $preset.module } else { 'global' })) -- mode: $(if ($preset.mode) { $preset.mode } else { 'Custom' })"
    $preset.values
}