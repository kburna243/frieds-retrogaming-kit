<#
.SYNOPSIS
    Lightgun step 3: ViGEmBus (virtual Xbox 360 pads). Detected by service and uninstall entry. When missing and
    confirmed with -AllowInstall: official signed installer of nefarius/ViGEmBus (archived since 2023) is
    downloaded into the admin-only ProgramData folder, its signer (CN and O) is compared exactly, the plan with
    SHA256 is confirmed, then it installs silently (/qn). Needs administrator rights.
.PARAMETER AllowInstall
    Allows the download and installation.
.PARAMETER Approve
    { param($text) ... } returning $true to run the installer shown with SHA256 and signature.
.PARAMETER Service
    Injected service object (tests). $null = service missing.
.PARAMETER Entries
    Injected uninstall entries (tests).
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch] $AllowInstall,
    [scriptblock] $Approve,
    [object] $Service,
    [object[]] $Entries,
    [string] $StatePath,
    [string] $Culture
)
$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1')
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1')
if ($Culture) { Set-KitCulture -Culture $Culture }
if (-not $StatePath) { $StatePath = Get-LightgunDefaultStatePath }

$probe = @{}
if ($PSBoundParameters.ContainsKey('Service')) { $probe.Service = $Service }
if ($PSBoundParameters.ContainsKey('Entries')) { $probe.Entries = $Entries }
$state = Get-LightgunViGEmState @probe
$release = Get-LightgunViGEmRelease
if ($state.Installed) { Write-KitLog (Get-KitText 'Lightgun.ViGEm.Present' -f $state.Version, $state.Running) }
else {
    Write-KitLog (Get-KitText 'Lightgun.ViGEm.Missing' -f $release.Releases) -Level Warn
    Write-KitLog (Get-KitText 'Lightgun.ViGEm.Archived')
    if (-not $AllowInstall) { Write-KitLog (Get-KitText 'Lightgun.ViGEm.NeedsAllow') -Level Warn }
    elseif (-not (Test-KitAdmin)) { Write-KitLog (Get-KitText 'Lightgun.Step.NeedsAdmin') -Level Warn }
}

$step = New-KitStep -Name 'lightgun-3-vigembus' `
    -Test { [bool]$AllowInstall -and (Test-KitAdmin) } `
    -Invoke {
        $code = Install-LightgunViGEm -Approve $Approve -Confirm:$false
        Set-KitStateValue -Path $StatePath -Key 'ViGEmExitCode' -Value $code
    } `
    -Verify { (Get-LightgunViGEmState @probe).Installed }
Invoke-KitStep -Step $step -StatePath $StatePath -WhatIf:$WhatIfPreference
