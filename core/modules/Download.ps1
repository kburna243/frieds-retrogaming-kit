# Download: only HTTPS from allow-listed official hosts (core\download-allowlist.psd1), TLS 1.2,
# BITS when available with Invoke-WebRequest as fallback, Authenticode check with expected publisher.
# ponytail: only the start URL is checked, not redirect targets; Test-KitSignature is the real guard.

function Get-KitAllowedHost {
    [CmdletBinding()]
    param()
    (Import-PowerShellDataFile -LiteralPath (Join-Path $script:KitCoreDir 'download-allowlist.psd1')).Hosts
}

function Test-KitDownloadUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Uri,
        [string[]] $AllowedHosts = (Get-KitAllowedHost)
    )
    $parsed = $null
    if (-not [Uri]::TryCreate($Uri, [UriKind]::Absolute, [ref]$parsed)) { return $false }
    if ($parsed.Scheme -ne 'https') { return $false }
    $hostName = $parsed.Host.ToLowerInvariant()
    [bool](@($AllowedHosts | Where-Object { $_.ToLowerInvariant() -eq $hostName }).Count)
}

function Save-KitDownload {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Uri,
        [Parameter(Mandatory)] [string] $Destination,
        [string[]] $AllowedHosts = (Get-KitAllowedHost)
    )
    if (-not (Test-KitDownloadUrl -Uri $Uri -AllowedHosts $AllowedHosts)) { throw (Get-KitText 'Download.HostNotAllowed' -f $Uri) }
    $dest = Resolve-FullPath $Destination
    if (-not $PSCmdlet.ShouldProcess($dest, "Download $Uri")) { return }

    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    $partial = "$dest.partial"
    try {
        $done = $false
        if (Get-Command Start-BitsTransfer -ErrorAction SilentlyContinue) {
            try { Start-BitsTransfer -Source $Uri -Destination $partial -ErrorAction Stop; $done = $true }
            catch { Write-KitLog (Get-KitText 'Download.Fallback' -f $_.Exception.Message) -Level Warn }
        }
        if (-not $done) { Invoke-WebRequest -Uri $Uri -OutFile $partial -UseBasicParsing -ErrorAction Stop }
        Move-Item -LiteralPath $partial -Destination $dest -Force
    } catch {
        if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
        throw
    }
    Get-Item -LiteralPath $dest
}

# IsTrusted only when the signature is Valid AND the signer subject contains the expected publisher.
function Test-KitSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string] $ExpectedPublisher
    )
    $signature = Get-AuthenticodeSignature -LiteralPath (Resolve-FullPath $Path)
    $subject = if ($signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { '' }
    $match   = $subject.IndexOf($ExpectedPublisher, [StringComparison]::OrdinalIgnoreCase) -ge 0
    $result  = [pscustomobject]@{
        Path           = $signature.Path
        Status         = [string]$signature.Status
        Subject        = $subject
        PublisherMatch = $match
        IsTrusted      = ($signature.Status -eq 'Valid') -and $match
    }
    if (-not $result.IsTrusted) { Write-KitLog (Get-KitText 'Signature.NotTrusted' -f $result.Path, $result.Status, $subject) -Level Warn }
    $result
}
