<#
.SYNOPSIS
    Kit API for other processes (API.md): runs one operation and writes exactly one JSON document to standard
    output. No network port; log lines never go to standard output.
.PARAMETER Operation
    Operation name (see -List or API.md), e.g. status, backups.list, step.lightgun.07-retrobatsettings.
.PARAMETER ParametersJson
    The operation's parameters as a JSON object, e.g. {"Path":"..."}.
.PARAMETER Apply
    Allow changes. Without it every change operation is a dry run.
.PARAMETER Approved
    A person approved the plans the operation asks for (see Approvals in the result of the dry run).
.PARAMETER Anonymize
    Replace profile paths, user and computer names, SIDs, private IPs and e-mail addresses (for cloud models).
.PARAMETER List
    Write the operation catalog instead.
.OUTPUTS
    Exit code 0 = success, 1 = the operation did not succeed, 2 = the request was refused.
#>
[CmdletBinding()]
param(
    [string] $Operation,
    [string] $ParametersJson,
    [switch] $Apply,
    [switch] $Approved,
    [switch] $Anonymize,
    [switch] $List,
    [string] $Culture = 'en-US'
)
$ErrorActionPreference = 'Stop'
# Nothing but the JSON document may reach standard output: host output of the engine is dropped here.
Import-Module (Join-Path $PSScriptRoot 'RetroCabinetKit.Api.psd1') 6>$null
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'core\RetroCabinetKit.Core.psd1') 6>$null
Set-KitCulture -Culture $Culture

if ($List) { $Operation = 'operations' }
$parameters = @{}
$refused = $null
if (-not $Operation) { $refused = 'No -Operation given (use -List for the catalog).' }
elseif ($ParametersJson) {
    try {
        $obj = ConvertFrom-Json -InputObject $ParametersJson
        if ($obj -isnot [psobject] -or $obj -is [array]) { throw 'not a JSON object' }
        foreach ($p in $obj.PSObject.Properties) {
            $v = $p.Value
            if ($v -is [array]) { $v = [string[]]@($v) }
            elseif ($v -is [psobject] -and $v -isnot [string] -and $v -isnot [ValueType]) { throw "parameter '$($p.Name)' is not a plain value" }
            $parameters[$p.Name] = $v
        }
    } catch { $refused = "-ParametersJson: $($_.Exception.Message)" }
}

if ($refused) {
    $result = New-KitOperationResult -Operation ([string]$Operation) -Status Failed -Message $refused -Errors @($refused)
    ConvertTo-KitApiJson -Result $result -Anonymize:$Anonymize
    exit 2
}
# Runs without a console host, so "What if:" lines cannot reach standard output (see Invoke-KitOperationIsolated).
$result = Invoke-KitOperationIsolated -Name $Operation -Parameters $parameters -Apply:$Apply -Approved:$Approved -Culture $Culture
ConvertTo-KitApiJson -Result $result -Anonymize:$Anonymize
if ($result.Status -eq 'NotAvailable' -or ($result.Status -eq 'Failed' -and @($result.Errors) -match '^(Unknown|Missing) parameter')) { exit 2 }
if ($result.Success) { exit 0 }
exit 1
