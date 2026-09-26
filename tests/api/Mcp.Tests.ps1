$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$server = Join-Path $kitRoot 'api\Start-KitMcpServer.ps1'
$exe = if ($env:SystemRoot) { Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' } else { 'pwsh' }

# Runs the server as a child process like an MCP client does: one JSON-RPC message per line on standard input,
# standard input closed at the end, every line of standard output parsed as one message.
function Invoke-McpSession([object[]] $Messages, [string[]] $Arguments = @(), [string[]] $RawLines = @()) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.Arguments = (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$server`"") + $Arguments) -join ' '
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.StandardOutputEncoding = New-Object Text.UTF8Encoding $false
    $p = [Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    foreach ($m in $Messages) { $p.StandardInput.WriteLine((ConvertTo-Json -InputObject $m -Depth 10 -Compress)) }
    foreach ($l in $RawLines) { $p.StandardInput.WriteLine($l) }
    $p.StandardInput.Close()
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    $null = $errTask.Result
    @($out -split "`n" | Where-Object { $_.Trim() } | ForEach-Object { ConvertFrom-Json -InputObject $_ })
}

function New-McpCall([int] $Id, [string] $Tool, [hashtable] $Arguments = @{}) {
    @{ jsonrpc = '2.0'; id = $Id; method = 'tools/call'; params = @{ name = $Tool; arguments = $Arguments } }
}

$init = @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = @{ protocolVersion = '2025-03-26'; capabilities = @{}; clientInfo = @{ name = 'test'; version = '1' } } }
$initialized = @{ jsonrpc = '2.0'; method = 'notifications/initialized' }

Describe 'MCP server over stdio' {
    It 'initializes with the asked protocol version and the kit version; answers nothing to notifications' {
        $r = Invoke-McpSession -Messages @($init, $initialized, @{ jsonrpc = '2.0'; id = 2; method = 'ping' })
        $r.Count | Should Be 2
        $r[0].id | Should Be 1
        $r[0].result.protocolVersion | Should BeExactly '2025-03-26'
        $r[0].result.serverInfo.name | Should BeExactly 'frieds-retrogaming-kit'
        $r[0].result.serverInfo.version | Should BeExactly ([IO.File]::ReadAllText((Join-Path $kitRoot 'VERSION')).Trim())
        $r[0].result.capabilities.tools | Should Not BeNullOrEmpty
        $r[1].id | Should Be 2
    }

    It 'offers the newest protocol version it knows for an unknown one' {
        $old = @{ jsonrpc = '2.0'; id = 1; method = 'initialize'; params = @{ protocolVersion = '1999-01-01' } }
        (Invoke-McpSession -Messages @($old))[0].result.protocolVersion | Should BeExactly '2025-06-18'
    }

    It 'lists the API catalog as tools: valid names, no interactive steps, apply/approved only on change tools' {
        $tools = @((Invoke-McpSession -Messages @($init, @{ jsonrpc = '2.0'; id = 2; method = 'tools/list' }))[1].result.tools)
        $names = @($tools | ForEach-Object { $_.name })
        foreach ($n in 'status', 'components', 'backups_list', 'backup_check', 'backup_restore', 'backup_remove') { $names -contains $n | Should Be $true }
        $names -contains 'operations' | Should Be $false
        $names -contains 'step_lightgun_09-verify' | Should Be $false
        $names -contains 'step_pinball_08-screens' | Should Be $false
        foreach ($t in $tools) {
            $t.name | Should Match '^[A-Za-z0-9_-]{1,64}$'
            $t.inputSchema.type | Should Be 'object'
            $hasApply = [bool]$t.inputSchema.properties.PSObject.Properties['apply']
            $hasApply | Should Be (-not $t.annotations.readOnlyHint)
        }
    }

    It '-ReadOnly offers only read tools and refuses a change tool' {
        $r = Invoke-McpSession -Arguments @('-ReadOnly') -Messages @($init, @{ jsonrpc = '2.0'; id = 2; method = 'tools/list' }, (New-McpCall 3 'backup_remove' @{ Path = 'x' }))
        @($r[1].result.tools | Where-Object { -not $_.annotations.readOnlyHint }).Count | Should Be 0
        @($r[1].result.tools).Count | Should BeGreaterThan 2
        $r[2].error.code | Should Be -32602
    }

    It 'a change tool is a dry run without apply and changes with apply; results are anonymized' {
        $f = Join-Path $TestDrive 'mcp\es.cfg'
        New-Item -ItemType Directory -Path (Split-Path -Parent $f) -Force | Out-Null
        [IO.File]::WriteAllText($f, 'current')
        $bak = "$f.bak_lightgun_20260101-100000-000"
        [IO.File]::WriteAllText($bak, 'older')

        $r = Invoke-McpSession -Messages @($init, (New-McpCall 2 'backup_restore' @{ Path = $bak }))
        $r[1].result.isError | Should Be $false
        $dry = $r[1].result.content[0].text | ConvertFrom-Json
        $dry.Status | Should Be 'WhatIf'
        $dry.Applied | Should Be $false
        [IO.File]::ReadAllText($f) | Should BeExactly 'current'
        if ($env:USERPROFILE -and $TestDrive.StartsWith($env:USERPROFILE)) {
            $r[1].result.content[0].text | Should Not Match ([regex]::Escape($env:USERPROFILE))
        }

        $r = Invoke-McpSession -Messages @($init, (New-McpCall 2 'backup_restore' @{ Path = $bak; apply = $true }))
        ($r[1].result.content[0].text | ConvertFrom-Json).Status | Should Be 'Done'
        [IO.File]::ReadAllText($f) | Should BeExactly 'older'
    }

    It 'reports a failed or refused operation as a tool error, not a protocol error' {
        $r = Invoke-McpSession -Messages @($init, (New-McpCall 2 'backup_check' @{ Path = (Join-Path $TestDrive 'nothing.txt') }), (New-McpCall 3 'status' @{ Unknown = 'x' }))
        $r[1].result.isError | Should Be $true
        ($r[1].result.content[0].text | ConvertFrom-Json).Status | Should Be 'Failed'
        $r[2].result.isError | Should Be $true
    }

    It 'answers protocol errors: unknown method, unknown tool, unreadable line' {
        $r = Invoke-McpSession -Messages @($init, @{ jsonrpc = '2.0'; id = 2; method = 'resources/list' }, (New-McpCall 3 'no_such_tool')) -RawLines @('not json')
        $r[1].error.code | Should Be -32601
        $r[2].error.code | Should Be -32602
        $r[3].error.code | Should Be -32700
    }
}
