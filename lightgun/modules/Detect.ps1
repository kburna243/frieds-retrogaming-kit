# Detect (step 1): a RetroBat installation the user brings along or a fresh one. The kit does not install
# RetroBat in P3a; for a missing or never started RetroBat it only points to the official releases.

$script:LightgunRetroBatReleases = 'https://github.com/RetroBat-Official/retrobat-setup/releases'

function Get-LightgunRetroBatReleaseUrl {
    [CmdletBinding()]
    param()
    $script:LightgunRetroBatReleases
}

# Kind: 'Build' (emulationstation.exe + es_settings.cfg), 'Fresh' (exe, but never started: no es_settings.cfg),
# 'None'. Version from system\version.info when present.
function Get-LightgunRetroBatInfo {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Root)
    $p = Get-LightgunRetroBatPath -Root $Root
    $exe = Test-Path -LiteralPath $p.EsExe -PathType Leaf
    $cfg = Test-Path -LiteralPath $p.EsSettings -PathType Leaf
    $kind = if ($exe -and $cfg) { 'Build' } elseif ($exe) { 'Fresh' } else { 'None' }
    $versionFile = Join-Path $p.Root 'system\version.info'
    $version = if (Test-Path -LiteralPath $versionFile -PathType Leaf) { ([IO.File]::ReadAllText($versionFile)).Trim() } else { '' }
    [pscustomobject]@{ Root = $p.Root; Kind = $kind; Version = $version; Paths = $p }
}
