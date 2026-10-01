# Library adapter plugins: one <Name>.ps1 per frontend in library\adapters\, five-function shape
# (Test / Get-Info / Install / Configure / Shield). Library adapters detect frontend installations
# and manage ROM libraries — scan, add, remove, media, playlists — across all supported frontends.

function Get-LibraryAdapterCatalog {
    [CmdletBinding()]
    param([string] $Dir = (Get-LibraryAdapterDir))
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) { return @() }
    foreach ($f in @(Get-ChildItem -LiteralPath $Dir -Filter '*.ps1' -File | Sort-Object Name)) {
        if ($f.Name -like '_*') { continue }
        $name = $f.BaseName
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref] $tokens, [ref] $errors)
        $funcs = @(if ($ast) { foreach ($d in $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) { $d.Name } })
        [pscustomobject]@{
            Name         = $name
            Path         = $f.FullName
            HasParseErrors = (@($errors).Count -gt 0)
            HasTest      = [bool]($funcs -contains "Test-${name}Frontend")
            HasInfo      = [bool]($funcs -contains "Get-${name}FrontendInfo")
            HasInstall   = [bool]($funcs -contains "Install-${name}Frontend")
            HasConfigure = [bool]($funcs -contains "Configure-${name}Frontend")
            HasShield    = [bool]($funcs -contains "Set-${name}InterferenceShield")
        }
    }
}

function Invoke-LibraryAdapterFunction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Function,
        [string] $Dir = (Get-LibraryAdapterDir),
        [hashtable] $Parameters = @{}
    )
    if ($Name -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$') { throw (Get-KitText 'Library.Adapter.NotFound' -f $Name) }
    $file = Join-Path $Dir "$Name.ps1"
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { throw (Get-KitText 'Library.Adapter.NotFound' -f $Name) }
    . $file
    if (-not (Get-Command $Function -ErrorAction SilentlyContinue)) { throw (Get-KitText 'Library.Adapter.MissingFunction' -f $Name, $Function) }
    & $Function @Parameters
}

function Get-LibraryAdapterValue($Info, [string] $Key) { if ($Info -and $Info.Contains($Key)) { $Info[$Key] } }

function Get-LibrarySystemSnapshot {
    [CmdletBinding()]
    param([string] $RetroBatRoot = '')
    @{
        Processes = @(Get-Process -ErrorAction SilentlyContinue | ForEach-Object { $_.Name.ToLowerInvariant() })
        Ports     = @(try { @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | ForEach-Object { [int]$_.LocalPort }) } catch { @() })
        Devices   = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue)
        Root      = $RetroBatRoot
    }
}

function Get-LibraryDetectedFrontends {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot = '',
        [hashtable] $Snapshot,
        [string] $Dir = (Get-LibraryAdapterDir)
    )
    $results = @()
    $catalog = Get-LibraryAdapterCatalog -Dir $Dir
    $ctx = if ($Snapshot) { $Snapshot } else { Get-LibrarySystemSnapshot -RetroBatRoot $RetroBatRoot }
    foreach ($adapter in $catalog) {
        try {
            $info = Invoke-LibraryAdapterFunction -Name $adapter.Name -Function "Get-$($adapter.Name)FrontendInfo" -Dir $Dir
            $present = Invoke-LibraryAdapterFunction -Name $adapter.Name -Function "Test-$($adapter.Name)Frontend" -Dir $Dir -Parameters @{ Context = $ctx }
            $results += [pscustomobject]@{
                Name        = $adapter.Name
                Present     = [bool]$present
                DatabaseFormat = if ($info.Contains('DatabaseFormat')) { $info.DatabaseFormat } else { '' }
                Category    = 'library'
            }
        } catch {
            $results += [pscustomobject]@{ Name = $adapter.Name; Present = $false; DatabaseFormat = ''; Category = 'library'; Error = $_.Exception.Message }
        }
    }
    $results
}