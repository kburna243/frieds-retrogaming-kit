# Result.ps1 -- Operation result types. Every API call returns a RetroCabinetKit.OperationResult.
# Extracted from api/RetroCabinetKit.Api.psm1 to keep the API facade lean.

function New-KitOperationResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Operation,
        [ValidateSet('Read', 'Change')] [string] $Kind = 'Read',
        [Parameter(Mandatory)] [ValidateSet('Ok', 'Done', 'Skipped', 'WhatIf', 'NeedsUser', 'Failed', 'NotAvailable')] [string] $Status,
        [string] $Message = '',
        [bool] $Applied = $false,
        [string[]] $Warnings = @(),
        [string[]] $Errors = @(),
        [object[]] $Changes = @(),
        [string[]] $Backups = @(),
        [string[]] $Approvals = @(),
        [double] $Duration = 0,
        [datetime] $StartedAt = (Get-Date),
        [object] $Data = $null
    )
    [pscustomobject]@{
        PSTypeName = 'RetroCabinetKit.OperationResult'
        ApiVersion = $script:ApiVersion
        KitVersion = $script:KitVersion
        Operation  = $Operation
        Kind       = $Kind
        Success    = $Status -in 'Ok', 'Done', 'Skipped', 'WhatIf'
        Status     = $Status
        Applied    = $Applied
        Message    = $Message
        Warnings   = @($Warnings | Where-Object { $_ })
        Errors     = @($Errors | Where-Object { $_ })
        Changes    = @($Changes | Where-Object { $_ })
        Backups    = @($Backups | Where-Object { $_ })
        Approvals  = @($Approvals | Where-Object { $_ })
        Duration   = [math]::Round($Duration, 3)
        StartedAt  = $StartedAt.ToString('o')
        Data       = $Data
    }
}

# Every string inside a result, anonymized (same rules as the support bundle); names and structure stay.
function ConvertTo-AnonymousValue($Value) {
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) { return (ConvertTo-KitSupportText -Text $Value) }
    if ($Value -is [ValueType]) { return $Value }
    if ($Value -is [Collections.IEnumerable] -and $Value -isnot [Collections.IDictionary]) { return ,@($Value | ForEach-Object { ConvertTo-AnonymousValue $_ }) }
    $copy = [ordered]@{}
    if ($Value -is [Collections.IDictionary]) { foreach ($k in $Value.Keys) { $copy[[string]$k] = ConvertTo-AnonymousValue $Value[$k] } }
    else { foreach ($prop in $Value.PSObject.Properties) { $copy[$prop.Name] = ConvertTo-AnonymousValue $prop.Value } }
    [pscustomobject]$copy
}

# JSON for other processes. -Anonymize for anything that leaves this PC (e.g. to a cloud model).
function ConvertTo-KitApiJson {
    [CmdletBinding()]
    param([Parameter(Mandatory, ValueFromPipeline)] [psobject] $Result, [switch] $Anonymize)
    process {
        $plain = ConvertTo-Json -InputObject $Result -Depth 10 | ConvertFrom-Json
        if ($Anonymize) { $plain = ConvertTo-AnonymousValue $plain }
        ConvertTo-Json -InputObject $plain -Depth 10 -Compress
    }
}