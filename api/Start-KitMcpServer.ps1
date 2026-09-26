<#
.SYNOPSIS
    MCP server over stdio for the Kit API (API.md): lets an agent (the separate harness, or any MCP client) use the
    kit's operations as tools. No network port: JSON-RPC 2.0 messages, one per line, on standard input and output.
.DESCRIPTION
    Tools come from the API catalog (Get-KitOperation); interactive and not yet available operations are not listed.
    Every change tool takes "apply" (without it: dry run, nothing is changed) and "approved" (a person approved the
    plans listed in "Approvals" of the dry run; the model must never set it on its own). Results are the API's
    OperationResult as JSON text, anonymized by default because the server cannot know whether the client forwards
    them to a cloud model.
.PARAMETER ReadOnly
    Offer only the read tools (status, components, backups, check).
.PARAMETER NoAnonymize
    Return results with real paths and names (only for a local model on this PC).
.PARAMETER Culture
    Language of the messages in the results (en-US, de-DE).
.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File api\Start-KitMcpServer.ps1 -ReadOnly
#>
[CmdletBinding()]
param(
    [switch] $ReadOnly,
    [switch] $NoAnonymize,
    [string] $Culture = 'en-US'
)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
# Standard output belongs to the protocol: engine host output is dropped here, operations run hostless.
Import-Module (Join-Path (Split-Path -Parent $PSScriptRoot) 'core\RetroCabinetKit.Core.psd1') 6>$null
Import-Module (Join-Path $PSScriptRoot 'RetroCabinetKit.Api.psd1') 6>$null
Set-KitCulture -Culture $Culture

$protocolVersions = @('2025-06-18', '2025-03-26', '2024-11-05')
$kitVersion = Get-KitVersion
$utf8 = New-Object Text.UTF8Encoding $false
$reader = New-Object IO.StreamReader ([Console]::OpenStandardInput(), $utf8)
$writer = New-Object IO.StreamWriter ([Console]::OpenStandardOutput(), $utf8)
$writer.AutoFlush = $true
$writer.NewLine = "`n"

function Send-Message($Message) { $writer.WriteLine((ConvertTo-Json -InputObject $Message -Depth 30 -Compress)) }
function Send-Result($Id, $Result) { Send-Message ([ordered]@{ jsonrpc = '2.0'; id = $Id; result = $Result }) }
function Send-Error($Id, [int] $Code, [string] $Text) { Send-Message ([ordered]@{ jsonrpc = '2.0'; id = $Id; error = [ordered]@{ code = $Code; message = $Text } }) }
function Write-Log([string] $Text) { [Console]::Error.WriteLine("[kit-mcp] $Text") }

# --- tools from the API catalog ------------------------------------------------------------------------------
$tools = [ordered]@{}
foreach ($op in Get-KitOperation) {
    if (-not $op.Available -or $op.Name -eq 'operations') { continue }
    if ($ReadOnly -and $op.Kind -ne 'Read') { continue }
    $properties = [ordered]@{}
    $required = New-Object Collections.Generic.List[string]
    foreach ($p in @($op.Parameters)) {
        $schema = switch ($p.Type) {
            'String[]' { [ordered]@{ type = 'array'; items = [ordered]@{ type = 'string' } } }
            'Int32'    { [ordered]@{ type = 'integer' } }
            'Int64'    { [ordered]@{ type = 'integer' } }
            'Boolean'  { [ordered]@{ type = 'boolean' } }
            'switch'   { [ordered]@{ type = 'boolean' } }
            default    { [ordered]@{ type = 'string' } }
        }
        $properties[$p.Name] = $schema
        if ($p.Mandatory) { $required.Add($p.Name) }
    }
    if ($op.Kind -eq 'Change') {
        $properties['apply'] = [ordered]@{ type = 'boolean'; description = 'Apply the change. Without it the call is a dry run: nothing is changed and the plan is returned. Only after the user saw the plan and said yes.' }
        $properties['approved'] = [ordered]@{ type = 'boolean'; description = 'The user approved the plans listed in Approvals of the dry run. Never set this without the user''s explicit yes to exactly these plans.' }
    }
    $name = $op.Name -replace '[^A-Za-z0-9_-]', '_'
    $description = $op.Description
    if ($op.Kind -eq 'Change') { $description += ' Changes the cabinet: dry run unless apply=true.' }
    $tools[$name] = [pscustomobject]@{
        Operation = $op.Name
        Kind      = $op.Kind
        Schema    = [ordered]@{
            name        = $name
            title       = $op.Name
            description = $description
            inputSchema = [ordered]@{ type = 'object'; properties = $properties; required = $required.ToArray(); additionalProperties = $false }
            annotations = [ordered]@{ readOnlyHint = ($op.Kind -eq 'Read'); destructiveHint = ($op.Kind -eq 'Change'); idempotentHint = $false; openWorldHint = $false }
        }
    }
}
Write-Log ("{0} tools, read-only={1}, anonymize={2}" -f $tools.Count, [bool]$ReadOnly, -not $NoAnonymize)

$instructions = 'Local tools of Fried''s Retrogaming Kit for this Windows cabinet (pinball and lightgun). Read tools only look. ' +
    'Change tools are dry runs unless apply=true: always call without apply first, show the plan and any Approvals to the user, ' +
    'and only after an explicit yes call again with apply=true (and approved=true only for the approvals the user accepted). ' +
    'Steps that need a person at the cabinet are not offered; tell the user to run them in the wizard.'

# --- request loop ------------------------------------------------------------------------------------------------
while ($null -ne ($line = $reader.ReadLine())) {
    if (-not $line.Trim()) { continue }
    try { $msg = ConvertFrom-Json -InputObject $line }
    catch { Send-Error $null -32700 'Parse error'; continue }
    $hasId = [bool]$msg.PSObject.Properties['id']
    $id = if ($hasId) { $msg.id } else { $null }
    $method = [string]$msg.method
    if (-not $hasId) { continue } # notifications (initialized, cancelled): nothing to answer
    try {
        switch ($method) {
            'initialize' {
                $asked = if ($msg.params -and $msg.params.PSObject.Properties['protocolVersion']) { [string]$msg.params.protocolVersion } else { '' }
                $version = if ($protocolVersions -contains $asked) { $asked } else { $protocolVersions[0] }
                Send-Result $id ([ordered]@{
                    protocolVersion = $version
                    capabilities    = [ordered]@{ tools = [ordered]@{ listChanged = $false } }
                    serverInfo      = [ordered]@{ name = 'frieds-retrogaming-kit'; title = 'Fried''s Retrogaming Kit'; version = $kitVersion }
                    instructions    = $instructions
                })
            }
            'ping' { Send-Result $id ([ordered]@{}) }
            'tools/list' { Send-Result $id ([ordered]@{ tools = @($tools.Values | ForEach-Object { $_.Schema }) }) }
            'tools/call' {
                $toolName = [string]$msg.params.name
                if (-not $tools.Contains($toolName)) { Send-Error $id -32602 "Unknown tool: $toolName"; break }
                $tool = $tools[$toolName]
                $parameters = @{}; $apply = $false; $approved = $false
                if ($msg.params.PSObject.Properties['arguments'] -and $msg.params.arguments) {
                    foreach ($a in $msg.params.arguments.PSObject.Properties) {
                        if ($a.Name -eq 'apply') { $apply = [bool]$a.Value; continue }
                        if ($a.Name -eq 'approved') { $approved = [bool]$a.Value; continue }
                        $v = $a.Value
                        if ($v -is [array]) { $v = [string[]]@($v) }
                        $parameters[$a.Name] = $v
                    }
                }
                if ($tool.Kind -ne 'Change') { $apply = $false; $approved = $false }
                Write-Log ("call {0} apply={1} approved={2}" -f $tool.Operation, $apply, $approved)
                $result = Invoke-KitOperationIsolated -Name $tool.Operation -Parameters $parameters -Apply:$apply -Approved:$approved -Culture $Culture
                $text = ConvertTo-KitApiJson -Result $result -Anonymize:(-not $NoAnonymize)
                Send-Result $id ([ordered]@{ content = @([ordered]@{ type = 'text'; text = $text }); isError = (-not $result.Success) })
            }
            default { Send-Error $id -32601 "Method not found: $method" }
        }
    } catch {
        Write-Log $_.Exception.Message
        Send-Error $id -32603 $_.Exception.Message
    }
}
