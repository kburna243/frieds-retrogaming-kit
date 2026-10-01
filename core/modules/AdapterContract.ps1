# AdapterContract.ps1 -- Formal contract for all adapter plugins in the kit.
# Every adapter (.ps1 in adapters/) must satisfy this contract, verified by Test-AdapterContract.
# This replaces the AST-based Has* boolean checks with a declarative Capabilities model.

# Canonical adapter capability set. Adapters declare which operations they support.
$script:AdapterCapabilities = @('Detect', 'GetInfo', 'Install', 'Configure', 'Shield')

# Contract verification: checks that an adapter file exports the five canonical functions
# and that its Get-*Info hashtable includes a Capabilities key.
function Test-AdapterContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $AdapterPath,
        [ValidateSet('Emulator', 'Frontend', 'Library', 'Enhancement', 'Display', 'Output', 'Lightgun', 'Arcade', 'Pad')]
        [string] $AdapterKind = 'Emulator'
    )
    $result = [pscustomobject]@{
        Path           = $AdapterPath
        Name           = (Split-Path -Leaf $AdapterPath).Replace('.ps1', '')
        Kind           = $AdapterKind
        Valid          = $true
        MissingFuncs   = @()
        CapabilitiesOk = $false
        ParseErrors    = @()
        Warnings       = @()
    }

    # 1. Syntax check
    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($AdapterPath, [ref]$tokens, [ref]$errors)
    if ($errors.Count) {
        $result.ParseErrors = @($errors | ForEach-Object { $_.Message })
        $result.Valid = $false
        return $result
    }

    # 2. Required functions based on adapter kind
    $funcPrefix = $result.Name
    $requiredFuncs = @()
    switch ($AdapterKind) {
        'Emulator'    { $requiredFuncs = @("Test-${funcPrefix}Emulator", "Get-${funcPrefix}EmulatorInfo", "Install-${funcPrefix}Emulator", "Configure-${funcPrefix}Emulator", "Set-${funcPrefix}InterferenceShield") }
        'Frontend'    { $requiredFuncs = @("Test-${funcPrefix}Frontend", "Get-${funcPrefix}FrontendInfo", "Install-${funcPrefix}Frontend", "Configure-${funcPrefix}Frontend", "Set-${funcPrefix}InterferenceShield") }
        'Library'     { $requiredFuncs = @("Test-${funcPrefix}Frontend", "Get-${funcPrefix}FrontendInfo", "Install-${funcPrefix}Frontend", "Configure-${funcPrefix}Frontend", "Set-${funcPrefix}InterferenceShield") }
        'Enhancement' { $requiredFuncs = @("Test-${funcPrefix}Hardware", "Get-${funcPrefix}AdapterInfo", "Install-${funcPrefix}Software", "Configure-${funcPrefix}Profile", "Set-${funcPrefix}InterferenceShield") }
        'Display'     { $requiredFuncs = @("Test-${funcPrefix}Hardware", "Get-${funcPrefix}AdapterInfo", "Install-${funcPrefix}Software", "Configure-${funcPrefix}Profile", "Set-${funcPrefix}InterferenceShield") }
        'Output'      { $requiredFuncs = @("Test-${funcPrefix}Hardware", "Get-${funcPrefix}AdapterInfo", "Install-${funcPrefix}Software", "Configure-${funcPrefix}Profile", "Set-${funcPrefix}InterferenceShield") }
        'Lightgun'    { $requiredFuncs = @("Test-${funcPrefix}Adapter", "Get-${funcPrefix}AdapterInfo", "Configure-${funcPrefix}Adapter", "Set-${funcPrefix}InterferenceShield") }
        'Arcade'      { $requiredFuncs = @("Test-${funcPrefix}Adapter", "Get-${funcPrefix}AdapterInfo", "Set-${funcPrefix}InterferenceShield") }
        'Pad'         { $requiredFuncs = @("Test-${funcPrefix}Adapter", "Get-${funcPrefix}AdapterInfo", "Set-${funcPrefix}InterferenceShield") }
    }

    $funcs = @(if ($ast) { foreach ($d in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) { $d.Name } })
    $result.MissingFuncs = @($requiredFuncs | Where-Object { $_ -notin $funcs })
    if ($result.MissingFuncs.Count) {
        $result.Valid = $false
        $result.Warnings += "Missing functions: $($result.MissingFuncs -join ', ')"
    }

    # 3. Capabilities check: Get-*Info must return a Capabilities key
    if ($result.Valid) {
        $infoFuncName = $requiredFuncs | Where-Object { $_ -like 'Get-*Info' } | Select-Object -First 1
        if ($infoFuncName) {
            # Search AST for the Get-*Info function's return statement for Capabilities hint
            $infoFunc = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq $infoFuncName }, $true)
            if ($infoFunc) {
                # Check the hashtable keys in the return statement for 'Capabilities'
                $hashtableKeys = @()
                $infoFunc[0].FindAll({ $args[0] -is [System.Management.Automation.Language.HashtableAst] }, $true) |
                    ForEach-Object {
                        foreach ($kv in $_.KeyValuePairs) {
                            $keyStr = if ($kv.Item1 -is [System.Management.Automation.Language.StringConstantExpressionAst]) { $kv.Item1.Value } else { '' }
                            $hashtableKeys += $keyStr
                        }
                    }
                $result.CapabilitiesOk = 'Capabilities' -in $hashtableKeys
                if (-not $result.CapabilitiesOk) {
                    $result.Warnings += "Get-*Info should declare a Capabilities hashtable (Detect, GetInfo, Install, Configure, Shield)"
                }
            }
        }
    }

    $result
}

# Batch-contract check for all adapters in a directory.
function Test-AdapterContractBatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $AdapterDir,
        [string] $AdapterKind = 'Emulator'
    )
    if (-not (Test-Path -LiteralPath $AdapterDir -PathType Container)) { return @() }
    @(Get-ChildItem -LiteralPath $AdapterDir -Filter '*.ps1' -File |
        Where-Object { $_.Name -notlike '_*' } |
        Sort-Object Name |
        ForEach-Object { Test-AdapterContract -AdapterPath $_.FullName -AdapterKind $AdapterKind })
}