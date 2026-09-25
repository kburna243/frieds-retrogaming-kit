# ViGEm (step 3): the virtual Xbox 360 pad bus Gunmote feeds. Detected by service, driver and uninstall
# entry; installed only from the official signed release of nefarius/ViGEmBus (archived since 2023, still the
# driver Gunmote uses): allow-listed URL prefix, download into the admin-only ProgramData folder, signer CN
# and O compared exactly, plan with SHA256 confirmed, hash checked again, silent install with /qn.

$script:LightgunViGEm = @{
    Version   = '1.22.0'
    Url       = 'https://github.com/nefarius/ViGEmBus/releases/download/v1.22.0/ViGEmBus_1.22.0_x64_x86_arm64.exe'
    Publisher = 'Nefarius Software Solutions e.U.'
    Releases  = 'https://github.com/nefarius/ViGEmBus/releases'
}

function Get-LightgunViGEmRelease {
    [CmdletBinding()]
    param()
    [pscustomobject]$script:LightgunViGEm
}

# -Service / -Entries inject the service object and uninstall entries (tests).
function Get-LightgunViGEmState {
    [CmdletBinding()]
    param([object] $Service, [object[]] $Entries)
    if (-not $PSBoundParameters.ContainsKey('Service')) { $Service = Get-Service -Name 'ViGEmBus' -ErrorAction SilentlyContinue }
    if (-not $PSBoundParameters.ContainsKey('Entries')) { $Entries = @(Get-LightgunUninstallEntry -Pattern '^ViGEm Bus Driver') }
    $entry = @($Entries) | Select-Object -First 1
    [pscustomobject]@{
        Installed = [bool]$Service -and [bool]$entry
        Running   = [bool]$Service -and [string]$Service.Status -eq 'Running'
        Service   = [bool]$Service
        Version   = if ($entry) { $entry.DisplayVersion } else { '' }
    }
}

# Downloads (or takes -InstallerPath), checks the signature, shows the plan and installs with /qn.
# Returns the exit code (0, 3010 = restart needed, 1638 = already installed). Declined or untrusted -> throws.
function Install-LightgunViGEm {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [scriptblock] $Approve,
        [string] $InstallerPath,
        [string] $DownloadBase
    )
    $release = Get-LightgunViGEmRelease
    if (-not $PSCmdlet.ShouldProcess($release.Url, 'Download, check signature, install /qn')) { return }
    if (-not $InstallerPath) {
        $dirArgs = @{}; if ($DownloadBase) { $dirArgs.Base = $DownloadBase }
        $dir = Initialize-KitDownloadDir @dirArgs
        $InstallerPath = Join-Path $dir ([IO.Path]::GetFileName(([Uri]$release.Url).AbsolutePath))
        if (-not (Test-Path -LiteralPath $InstallerPath)) { $null = Save-KitDownload -Uri $release.Url -Destination $InstallerPath -Confirm:$false }
    }
    $signature = Test-KitSignature -Path $InstallerPath -ExpectedPublisher $release.Publisher
    if (-not $signature.IsTrusted) { throw (Get-KitText 'Lightgun.ViGEm.Untrusted' -f $InstallerPath, $signature.Status, $signature.Subject) }
    $plan = Get-KitFilePlan -Path $InstallerPath
    $lines = @((Get-KitText 'Lightgun.ViGEm.Plan' -f $release.Version), (Get-KitText 'Lightgun.ViGEm.Archived'))
    if (-not (Confirm-KitPlan -Lines $lines -FilePlan @($plan) -Approve $Approve)) { throw (Get-KitText 'Plan.Declined') }
    if (-not (Test-KitFilePlanHash -Row $plan)) { throw (Get-KitText 'Plan.Changed' -f $InstallerPath) }
    $p = Start-Process -FilePath $plan.Path -ArgumentList '/qn' -Wait -PassThru
    if ($p.ExitCode -notin 0, 1638, 3010) { throw (Get-KitText 'Lightgun.ViGEm.Failed' -f $p.ExitCode) }
    if ($p.ExitCode -eq 3010) { Write-KitLog (Get-KitText 'Lightgun.ViGEm.Restart') -Level Warn }
    $p.ExitCode
}
