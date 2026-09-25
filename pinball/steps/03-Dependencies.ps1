<#
.SYNOPSIS
    Pinball step 3: detect VC++ 2005-2022 x86/x64, .NET 3.5/4.8, DirectX 9 (d3dx9_43.dll) and the Windows
    version; install what is missing, from the build first (2-Programs\All In One Runtimes, Installer\directx9).
.PARAMETER AllowDownload
    Permit the official Microsoft fallback downloads (allow-listed hosts, Microsoft signature required)
    for runtimes the build does not contain.
.PARAMETER AllowDism
    Permit enabling .NET Framework 3.5 through DISM (Windows feature, may take minutes).
.PARAMETER Root
    Build root to install from. Default: SourceRoot from step 1. Installers of a build on a network path are
    not used (downloads only); a local root must contain the build database.
.PARAMETER Approve
    { param($text) ... } returning $true to run the shown plan (files, SHA256, signature). The wizard passes
    its dialog; without it the console asks. Every file must carry a valid Microsoft signature.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch] $AllowDownload,
    [switch] $AllowDism,
    [string] $Root,
    [scriptblock] $Approve,
    [string] $StatePath,
    [string] $Culture
)
$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1')
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1')
if ($Culture) { Set-KitCulture -Culture $Culture }
if (-not $StatePath) { $StatePath = Get-PinballDefaultStatePath }
if (-not $Root) { $Root = Get-KitStateValue -Path $StatePath -Key 'SourceRoot' }
if (-not $Root) { Write-KitLog (Get-KitText 'Pinball.Step.RunDetectFirst') -Level Warn }
# A local root must really be a build; a root on the network is allowed, its installers are just not used.
$rootProblem = if ($Root -and -not (Get-PinballRootProblem -Root $Root -NoDatabase)) { Get-PinballRootProblem -Root $Root }
if ($rootProblem) { Write-KitLog $rootProblem -Level Warn }
elseif ($Root -and (Get-PinballRootProblem -Root $Root -NoDatabase)) { Write-KitLog (Get-KitText 'Pinball.Deps.NoLocalBuild' -f $Root) -Level Warn }

$status = @(Get-PinballDependencyStatus)
foreach ($s in $status) {
    Write-KitLog (Get-KitText $(if ($s.Present) { 'Pinball.Deps.Present' } else { 'Pinball.Deps.Missing' }) -f $s.Name, $s.Detail)
}
$plan = @(if ($Root) { Get-PinballDependencyPlan -Root $Root -Status $status })
foreach ($p in $plan) { Write-KitLog (Get-KitText 'Pinball.Deps.Plan' -f $p.Name, $p.Source, $(if ($p.FilePath) { $p.FilePath } else { $p.Url })) }

# Items the kit may not handle on its own stop the step with NeedsUser and say why.
$blocked = @($plan | Where-Object {
    $_.Source -eq 'User' -or ($_.Source -eq 'Dism' -and -not $AllowDism) -or ($_.Source -eq 'Download' -and -not $AllowDownload)
})
foreach ($b in $blocked) { Write-KitLog (Get-KitText "Pinball.Deps.NeedsUser.$($b.Source)" -f $b.Name) -Level Warn }
if ($plan.Count -and -not (Test-KitAdmin)) { Write-KitLog (Get-KitText 'Pinball.Step.NeedsAdmin') -Level Warn }

$step = New-KitStep -Name 'pinball-3-dependencies' `
    -Test { [bool]$Root -and -not $rootProblem -and (Test-KitAdmin) -and -not $blocked.Count } `
    -Invoke {
        $rows = @(Invoke-PinballDependencyPlan -Plan $plan -AllowDism:$AllowDism -Approve $Approve)
        foreach ($r in $rows | Where-Object { $_.Result -eq 'NeedsUser' }) { Write-KitLog ('{0}: {1}' -f $r.Id, $r.Message) -Level Warn }
        $reboot = @($rows | Where-Object { $_.Result -eq 'RebootRequired' } | ForEach-Object { $_.Id })
        if ($reboot) {
            Set-KitStateValue -Path $StatePath -Key 'RebootRequired' -Value $reboot
            Write-KitLog (Get-KitText 'Pinball.Deps.Reboot' -f ($reboot -join ', ')) -Level Warn
        }
        foreach ($r in $rows | Where-Object { $_.Result -notin 'Ok', 'RebootRequired', 'NeedsUser' }) {
            Write-KitLog ('{0}: {1} {2} {3}' -f $r.Id, $r.Result, $r.ExitCode, $r.Message) -Level Error
        }
    } `
    -Verify { -not @(Get-PinballDependencyStatus | Where-Object { -not $_.Present }).Count }

Invoke-KitStep -Step $step -StatePath $StatePath -WhatIf:$WhatIfPreference
