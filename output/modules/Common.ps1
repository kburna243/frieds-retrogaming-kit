# Output common: state path, RetroBat root resolution, middleware adapter directory.

function Get-OutputDefaultStatePath {
    [CmdletBinding()]
    param()
    Join-Path $script:OutputDir 'install-state.json'
}

function Get-OutputRetroBatRoot {
    [CmdletBinding()]
    param([string] $StatePath = (Get-OutputDefaultStatePath))
    $root = [string](Get-KitStateValue -Path $StatePath -Key 'RetroBatRoot')
    if (-not $root) { $root = [string](Get-KitStateValue -Path (Get-LightgunDefaultStatePath) -Key 'RetroBatRoot') }
    $root
}

function Get-OutputAdapterDir {
    [CmdletBinding()]
    param()
    Join-Path $script:OutputDir 'adapters'
}
