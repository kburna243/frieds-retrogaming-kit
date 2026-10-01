# Frontend adapter plugins: one <Name>.ps1 per frontend in frontends\adapters\, five-function contract
# (Test / Get-Info / Install / Configure / Shield). Frontend adapters detect frontend installations
# and manage themes, genre routing, library imports, and catalog exports.
# Designed for extensibility: drop a new .ps1 → auto-discovered by Get-FrontendsAdapterCatalog.

function Get-FrontendsAdapterCatalog {
    [CmdletBinding()]
    param([string] $Dir = (Get-FrontendsAdapterDir))
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { return @() }
    foreach ($f in @(Get-ChildItem -LiteralPath $Dir -Filter '*.ps1' -File | Sort-Object Name)) {
        if ($f.Name -like '_*') { continue }
        $name = $f.BaseName
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref] $tokens, [ref] $errors)
        $funcs = @(if ($ast) { foreach ($d in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) { $d.Name } })
        [pscustomobject]@{
            Name           = $name
            Path           = $f.FullName
            HasParseErrors = (@($errors).Count -gt 0)
            HasTest        = [bool]($funcs -contains "Test-${name}Frontend")
            HasInfo        = [bool]($funcs -contains "Get-${name}FrontendInfo")
            HasInstall     = [bool]($funcs -contains "Install-${name}Frontend")
            HasConfigure   = [bool]($funcs -contains "Configure-${name}Frontend")
            HasShield      = [bool]($funcs -contains "Set-${name}InterferenceShield")
        }
    }
}

function Invoke-FrontendsAdapterFunction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Function,
        [string] $Dir = (Get-FrontendsAdapterDir),
        [hashtable] $Parameters = @{}
    )
    if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$') { throw (Get-KitText 'Frontends.Adapter.NotFound' -f $Name) }
    $file = Join-Path $Dir "$Name.ps1"
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw (Get-KitText 'Frontends.Adapter.NotFound' -f $Name) }
    . $file
    if (-not (Get-Command $Function -ErrorAction SilentlyContinue)) { throw (Get-KitText 'Frontends.Adapter.MissingFunction' -f $Name, $Function) }
    & $Function @Parameters
}

function Get-FrontendsAdapterValue($Info, [string] $Key) { if ($Info -and $Info.Contains($Key)) { $Info[$Key] } }

# Detect ALL frontend adapters installed on this system.
function Get-FrontendsDetectedAdapters {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [hashtable] $Snapshot,
        [string] $Dir = (Get-FrontendsAdapterDir),
        [switch] $Quiet
    )
    if (-not $PSBoundParameters.ContainsKey('Snapshot')) { $Snapshot = Get-FrontendSystemSnapshot -RetroBatRoot $RetroBatRoot }
    $errors = New-Object Collections.Generic.List[string]
    $scanned = New-Object Collections.Generic.List[string]
    $detected = New-Object Collections.Generic.List[object]
    foreach ($a in (Get-FrontendsAdapterCatalog -Dir $Dir)) {
        if ($a.HasParseErrors -or -not ($a.HasTest -and $a.HasInfo)) {
            $reason = if ($a.HasParseErrors) { 'syntax' } elseif (-not $a.HasTest) { "Test-$($a.Name)Frontend" } else { "Get-$($a.Name)FrontendInfo" }
            $errors.Add((Get-KitText 'Frontends.Adapter.Incomplete' -f $a.Name, $reason))
            if (-not $Quiet) { Write-KitLog (Get-KitText 'Frontends.Adapter.Incomplete' -f $a.Name, $reason) -Level Warn }
            continue
        }
        $scanned.Add($a.Name)
        try {
            $present = [bool](Invoke-FrontendsAdapterFunction -Name $a.Name -Function "Test-$($a.Name)Frontend" -Parameters @{ RetroBatRoot = $RetroBatRoot; Snapshot = $Snapshot })
            if (-not $present) { continue }
            $info = Invoke-FrontendsAdapterFunction -Name $a.Name -Function "Get-$($a.Name)FrontendInfo" -Parameters @{ RetroBatRoot = $RetroBatRoot }
            $detected.Add([pscustomobject]@{
                Name       = $a.Name
                FrontendType = [string](Get-FrontendsAdapterValue $info 'FrontendType')
                Version    = [string](Get-FrontendsAdapterValue $info 'Version')
                ExePath    = [string](Get-FrontendsAdapterValue $info 'ExePath')
            })
        } catch {
            $errors.Add((Get-KitText 'Frontends.Adapter.Error' -f $a.Name, $_.Exception.Message))
            if (-not $Quiet) { Write-KitLog (Get-KitText 'Frontends.Adapter.Error' -f $a.Name, $_.Exception.Message) -Level Error }
        }
    }
    $names = @($detected | ForEach-Object { $_.Name })
    [pscustomobject]@{
        Success            = ($names.Count -gt 0)
        DetectedFrontends  = $names
        DetectedDetails    = $detected.ToArray()
        ScannedAdapters    = ($scanned -join ',')
        Errors             = @($errors)
    }
}

# Install a frontend (link only; user supplies package with -Approved).
function Install-FrontendsAdapter {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $RetroBatRoot,
        [string] $PackagePath,
        [switch] $Approved
    )
    $params = @{ RetroBatRoot = $RetroBatRoot }
    if ($PackagePath) { $params.PackagePath = $PackagePath }
    if ($Approved.IsPresent) { $params.Approved = $true }
    Invoke-FrontendsAdapterFunction -Name $Name -Function "Install-$($Name)Frontend" -Parameters $params
}

# Apply configuration to detected frontend adapters.
function Set-FrontendsAdapterConfiguration {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string[]] $Names,
        [Parameter(Mandatory)] [string] $RetroBatRoot
    )
    if (-not $PSCmdlet.ShouldProcess(($Names -join ', '), 'configure frontend adapters')) { return 0 }
    $changes = 0
    foreach ($n in $Names) {
        $info = Invoke-FrontendsAdapterFunction -Name $n -Function "Get-$($n)FrontendInfo" -Parameters @{ RetroBatRoot = $RetroBatRoot }
        foreach ($t in @(Get-FrontendsAdapterValue $info 'SettingsTargets')) {
            $path = if ($t.Contains('Path')) { [string]$t.Path }
                    else {
                        $toolDir = [string](Get-FrontendsAdapterValue $info 'ToolDir')
                        Join-Path $RetroBatRoot ('frontends\' + $toolDir + '\' + [string]$t.File)
                    }
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
                Write-KitLog "Frontend config not found: $path" -Level Warn
                continue
            }
            $values = @{}
            if ($t.Contains('Values')) { foreach ($k in $t.Values.Keys) { $values[$k] = $t.Values[$k] } }
            if ($values.Count) {
                $section = if ($t.Contains('Section')) { [string]$t.Section } else { '' }
                $changes += Set-FrontendsIniValue -Path $path -Section $section -Values $values -Confirm:$false
            }
        }
    }
    Write-KitLog "Frontend configuration: $($Names -join ', ') -- $changes value(s) set"
    $changes
}

function Test-FrontendsAdapterConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string[]] $Names, [Parameter(Mandatory)] [string] $RetroBatRoot)
    foreach ($n in $Names) {
        $info = Invoke-FrontendsAdapterFunction -Name $n -Function "Get-$($n)FrontendInfo" -Parameters @{ RetroBatRoot = $RetroBatRoot }
        foreach ($t in @(Get-FrontendsAdapterValue $info 'SettingsTargets')) {
            $path = if ($t.Contains('Path')) { [string]$t.Path }
                    else {
                        $toolDir = [string](Get-FrontendsAdapterValue $info 'ToolDir')
                        Join-Path $RetroBatRoot ('frontends\' + $toolDir + '\' + [string]$t.File)
                    }
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $false }
            $values = @{}
            if ($t.Contains('Values')) { foreach ($k in $t.Values.Keys) { $values[$k] = $t.Values[$k] } }
            if ($values.Count -and @(Get-FrontendsIniPlan -Path $path -Section $([string]$(if ($t.Contains('Section')) { $t.Section } else { '' })) -Values $values).Count) { return $false }
        }
    }
    $true
}

# INI helpers for frontend config files
function Get-FrontendsIniPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [string] $Section = '',
        [hashtable] $Values = @{}
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8)
    $plan = @()
    foreach ($key in $Values.Keys) {
        $found = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match "^\s*$key\s*[=:]\s*(.*)") {
                $oldVal = $matches[1].Trim()
                if ($oldVal -ne [string]$Values[$key]) {
                    $plan += [pscustomobject]@{ Key = $key; Old = $oldVal; New = [string]$Values[$key]; Line = $i }
                }
                $found = $true
                break
            }
        }
        if (-not $found) {
            $plan += [pscustomobject]@{ Key = $key; Old = $null; New = [string]$Values[$key]; Line = -1 }
        }
    }
    $plan
}

function Set-FrontendsIniValue {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [string] $Section = '',
        [hashtable] $Values = @{}
    )
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 0 }
    if (-not $PSCmdlet.ShouldProcess($Path, "set $($Values.Count) INI value(s)")) { return 0 }
    $plan = Get-FrontendsIniPlan -Path $Path -Section $Section -Values $Values
    if (-not $plan.Count) { return 0 }
    $lines = [Collections.Generic.List[string]](@(Get-Content -LiteralPath $Path -Encoding UTF8))
    foreach ($p in $plan) {
        if ($p.Line -ge 0) {
            $lines[$p.Line] = "$($p.Key) = $($p.New)"
        } else {
            $lines.Add("$($p.Key) = $($p.New)")
        }
    }
    $backup = "$Path.bak_$(Get-Date -Format 'yyyyMMddHHmmss')"
    Copy-Item -LiteralPath $Path -Destination $backup
    [IO.File]::WriteAllLines($Path, $lines, [Text.UTF8Encoding]::new($false))
    $plan.Count
}

# Set theme for a frontend
function Set-FrontendsTheme {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $FrontendName,
        [Parameter(Mandatory)] [string] $RetroBatRoot,
        [Parameter(Mandatory)] [string] $ThemeName
    )
    $info = Invoke-FrontendsAdapterFunction -Name $FrontendName -Function "Get-$($FrontendName)FrontendInfo" -Parameters @{ RetroBatRoot = $RetroBatRoot }
    $themeTarget = if ($info.Contains('ThemeTarget')) { $info.ThemeTarget } else { '' }
    if (-not $themeTarget) {
        return @{ Success = $false; Message = "Theme support not available for $FrontendName" }
    }
    $cfgPath = Join-Path $RetroBatRoot $themeTarget
    if (-not (Test-Path -LiteralPath $cfgPath -PathType Leaf)) {
        return @{ Success = $false; Message = "Theme config not found: $cfgPath" }
    }
    Set-FrontendsIniValue -Path $cfgPath -Values @{ 'theme' = $ThemeName }
    @{ Success = $true; Theme = $ThemeName; Frontend = $FrontendName }
}

# Configure genre routing (which emulator for which system)
function Set-FrontendsGenreRouting {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $FrontendName,
        [Parameter(Mandatory)] [string] $RetroBatRoot,
        [hashtable] $Routing = @{}
    )
    $defaultRouting = Get-FrontendGenreRouting -FrontendName $FrontendName -RetroBatRoot $RetroBatRoot
    $merged = @{} + $defaultRouting
    foreach ($k in $Routing.Keys) { $merged[$k] = $Routing[$k] }
    @{ Success = $true; Frontend = $FrontendName; Systems = $merged.Count }
}

# Import library from a frontend's database into the unified catalog format
function Import-FrontendsLibrary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $FrontendName,
        [Parameter(Mandatory)] [string] $RetroBatRoot
    )
    $info = Invoke-FrontendsAdapterFunction -Name $FrontendName -Function "Get-$($FrontendName)FrontendInfo" -Parameters @{ RetroBatRoot = $RetroBatRoot }
    [pscustomobject]@{
        Frontend = $FrontendName
        Format   = [string](Get-FrontendsAdapterValue $info 'DatabaseFormat')
        Systems  = @()
        Imported = (Get-Date -Format 'o')
    }
}

# Export unified catalog to a frontend-specific format
function Export-FrontendsCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $FrontendName,
        [Parameter(Mandatory)] [string] $RetroBatRoot,
        [Parameter(Mandatory)] [string] $Destination
    )
    $catalog = Import-FrontendsLibrary -FrontendName $FrontendName -RetroBatRoot $RetroBatRoot
    $json = ConvertTo-Json -InputObject $catalog -Depth 5 -Compress
    [IO.File]::WriteAllText($Destination, $json, [Text.UTF8Encoding]::new($false))
    @{ Success = $true; Path = $Destination; Size = (Get-Item -LiteralPath $Destination).Length }
}