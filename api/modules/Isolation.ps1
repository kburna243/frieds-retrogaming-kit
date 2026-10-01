# Isolation.ps1 -- Runs one operation in its own PowerShell instance without a console host.
# "What if:" lines and host output of the engine go nowhere, only the result object comes back.
# For every client that owns standard output (the JSON command, the MCP server).
# Extracted from api/RetroCabinetKit.Api.psm1.

function Invoke-KitOperationIsolated {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [hashtable] $Parameters = @{},
        [switch] $Apply,
        [switch] $Approved,
        [string] $Culture = (Get-KitCulture)
    )
    $ps = [PowerShell]::Create()
    try {
        $null = $ps.AddScript({
            param($KitRoot, $Culture, $Name, $Parameters, $Apply, $Approved)
            Import-Module (Join-Path $KitRoot 'core\RetroCabinetKit.Core.psd1')
            Import-Module (Join-Path $KitRoot 'api\RetroCabinetKit.Api.psd1')
            Set-KitCulture -Culture $Culture
            Invoke-KitOperation -Name $Name -Parameters $Parameters -Apply:$Apply -Approved:$Approved
        }).AddArgument($script:KitRoot).AddArgument($Culture).AddArgument($Name).AddArgument($Parameters).AddArgument([bool]$Apply).AddArgument([bool]$Approved)
        $result = @($ps.Invoke() | Where-Object { $_ -and $_.PSObject.TypeNames -contains 'RetroCabinetKit.OperationResult' }) | Select-Object -Last 1
        if (-not $result) {
            $why = @($ps.Streams.Error | ForEach-Object { $_.Exception.Message }) -join ' '
            $result = New-KitOperationResult -Operation $Name -Status Failed -Message "No result. $why" -Errors @($why)
        }
        $result
    } finally { $ps.Dispose() }
}