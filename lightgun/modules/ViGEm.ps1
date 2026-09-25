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

# Downloads (or takes -InstallerPath) into a fresh admin-only work folder and hands it to
# Invoke-KitVerifiedExecutable: copied into its own work folder, signature (CN and O) checked, plan confirmed,
# started from the copy with a held read handle, /qn. Returns the exit code (0, 3010 = restart needed,
# 1638 = already installed). Declined, changed or untrusted -> throws. -DownloadBase / -TrustedOwner: kit data
# folder and its trusted owners (tests).
function Install-LightgunViGEm {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [scriptblock] $Approve,
        [string] $InstallerPath,
        [string] $DownloadBase,
        [string[]] $TrustedOwner
    )
    $release = Get-LightgunViGEmRelease
    if (-not $PSCmdlet.ShouldProcess($release.Url, 'Download, check signature, install /qn')) { return }
    $dirArgs = @{}
    if ($DownloadBase) { $dirArgs.Base = $DownloadBase }
    if ($TrustedOwner) { $dirArgs.TrustedOwner = $TrustedOwner }
    $dl = $null
    try {
        if (-not $InstallerPath) {
            $dl = New-KitWorkDir @dirArgs
            $InstallerPath = Join-Path $dl ([IO.Path]::GetFileName(([Uri]$release.Url).AbsolutePath))
            $null = Save-KitDownload -Uri $release.Url -Destination $InstallerPath -Confirm:$false
        }
        $lines = @((Get-KitText 'Lightgun.ViGEm.Plan' -f $release.Version), (Get-KitText 'Lightgun.ViGEm.Archived'))
        $item = @{ Name = 'ViGEmBus'; Path = $InstallerPath; Arguments = '/qn'; Publisher = @($release.Publisher) }
        $r = Invoke-KitVerifiedExecutable -Item $item -Lines $lines -Approve $Approve @dirArgs
    } finally { if ($dl) { Remove-Item -LiteralPath $dl -Recurse -Force -ErrorAction SilentlyContinue } }
    switch ($r.Result) {
        'Untrusted' { throw (Get-KitText 'Lightgun.ViGEm.Untrusted' -f $r.File, $r.Signature.Status, $r.Signature.Subject) }
        'Declined'  { throw (Get-KitText 'Plan.Declined') }
        'Changed'   { throw (Get-KitText 'Plan.Changed' -f $InstallerPath) }
    }
    if ($r.ExitCode -notin 0, 1638, 3010) { throw (Get-KitText 'Lightgun.ViGEm.Failed' -f $r.ExitCode) }
    if ($r.ExitCode -eq 3010) { Write-KitLog (Get-KitText 'Lightgun.ViGEm.Restart') -Level Warn }
    $r.ExitCode
}
