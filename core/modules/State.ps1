# State: install-state.json with step status and arbitrary values. Writes are atomic
# (write <file>.tmp, then File.Replace/Move), so a crash never leaves a half-written state.

function New-StateObject {
    [pscustomobject]@{ Version = 1; Steps = [pscustomobject]@{}; Values = [pscustomobject]@{} }
}

function Read-KitState {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $full = Resolve-FullPath $Path
    if (-not (Test-Path -LiteralPath $full)) { return New-StateObject }
    $state = [IO.File]::ReadAllText($full) | ConvertFrom-Json
    foreach ($p in 'Steps', 'Values') {
        if (-not $state.PSObject.Properties[$p]) { $state | Add-Member -NotePropertyName $p -NotePropertyValue ([pscustomobject]@{}) }
    }
    $state
}

function Save-KitState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [psobject] $State
    )
    $full = Resolve-FullPath $Path
    $tmp  = "$full.tmp"
    $json = ConvertTo-Json -InputObject $State -Depth 10
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding $false))
    if (Test-Path -LiteralPath $full) { [IO.File]::Replace($tmp, $full, [NullString]::Value) }
    else { [IO.File]::Move($tmp, $full) }
}

function Set-KitStateValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Key,
        [AllowNull()] [AllowEmptyString()] [object] $Value
    )
    $state = Read-KitState $Path
    $state.Values | Add-Member -NotePropertyName $Key -NotePropertyValue $Value -Force
    Save-KitState -Path $Path -State $state
}

function Get-KitStateValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Key
    )
    $prop = (Read-KitState $Path).Values.PSObject.Properties[$Key]
    if ($prop) { $prop.Value }
}

function Set-KitStepStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [ValidateSet('Skipped', 'Done', 'Failed', 'NeedsUser')] [string] $Status,
        [string] $Message
    )
    $state = Read-KitState $Path
    $entry = [pscustomobject]@{ Status = $Status; Message = $Message; Time = (Get-Date).ToString('o') }
    $state.Steps | Add-Member -NotePropertyName $Name -NotePropertyValue $entry -Force
    Save-KitState -Path $Path -State $state
}

function Get-KitStepStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $Name
    )
    $prop = (Read-KitState $Path).Steps.PSObject.Properties[$Name]
    if ($prop) { $prop.Value.Status }
}
