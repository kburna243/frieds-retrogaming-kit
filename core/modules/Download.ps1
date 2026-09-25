# Download: only HTTPS from allow-listed official hosts (core\download-allowlist.psd1), TLS 1.2,
# BITS when available with Invoke-WebRequest as fallback, Authenticode check with expected publisher.
# ponytail: only the start URL is checked, not redirect targets; Test-KitSignature is the real guard.

function Get-KitAllowedHost {
    [CmdletBinding()]
    param()
    (Import-PowerShellDataFile -LiteralPath (Join-Path $script:KitCoreDir 'download-allowlist.psd1')).Hosts
}

function Get-KitAllowedUrlPrefix {
    [CmdletBinding()]
    param()
    $list = Import-PowerShellDataFile -LiteralPath (Join-Path $script:KitCoreDir 'download-allowlist.psd1')
    if ($list.ContainsKey('UrlPrefixes')) { @($list.UrlPrefixes) }
}

# Allowed: HTTPS, no user info, default port, and either the host is in -AllowedHosts or the normalized URL
# lies below one of -AllowedUrlPrefixes (same host, path starts with the prefix path, no '%' escapes in the
# path so an encoded '..' cannot slip past the normalization).
function Test-KitDownloadUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Uri,
        [string[]] $AllowedHosts = (Get-KitAllowedHost),
        [AllowEmptyCollection()] [string[]] $AllowedUrlPrefixes = @(Get-KitAllowedUrlPrefix)
    )
    $parsed = $null
    if (-not [Uri]::TryCreate($Uri, [UriKind]::Absolute, [ref]$parsed)) { return $false }
    if ($parsed.Scheme -ne 'https' -or $parsed.UserInfo -or -not $parsed.IsDefaultPort) { return $false }
    $hostName = $parsed.Host.ToLowerInvariant()
    if (@($AllowedHosts | Where-Object { $_ -and $_.ToLowerInvariant() -eq $hostName }).Count) { return $true }
    if ($parsed.AbsolutePath.Contains('%')) { return $false }
    foreach ($p in $AllowedUrlPrefixes | Where-Object { $_ }) {
        $prefix = [Uri]$p
        if ($prefix.Host.ToLowerInvariant() -eq $hostName -and
            $parsed.AbsolutePath.StartsWith($prefix.AbsolutePath, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    $false
}

function Save-KitDownload {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Uri,
        [Parameter(Mandatory)] [string] $Destination,
        [string[]] $AllowedHosts = (Get-KitAllowedHost),
        [AllowEmptyCollection()] [string[]] $AllowedUrlPrefixes = @(Get-KitAllowedUrlPrefix)
    )
    if (-not (Test-KitDownloadUrl -Uri $Uri -AllowedHosts $AllowedHosts -AllowedUrlPrefixes $AllowedUrlPrefixes)) { throw (Get-KitText 'Download.HostNotAllowed' -f $Uri) }
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

# Downloads land in %ProgramData%\RetroCabinetKit\downloads, never in a folder the user can change.
function Get-KitDownloadDir {
    [CmdletBinding()]
    param([string] $Base = (Join-Path $env:ProgramData 'RetroCabinetKit'))
    Join-Path $Base 'downloads'
}

# Creates <Base> and <Base>\downloads with an ACL for Administrators and SYSTEM only (inheritance off). As
# administrator the owner becomes Administrators, so a folder a user created there beforehand loses its
# owner rights. Links (junctions) are refused. Returns the downloads folder.
function Initialize-KitDownloadDir {
    [CmdletBinding()]
    param([string] $Base = (Join-Path $env:ProgramData 'RetroCabinetKit'))
    $admin = Test-KitAdmin
    # A fresh object per folder: after one SetAccessControl the object counts as unchanged and writes nothing.
    $newAcl = {
        $acl = New-Object Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($sid in 'S-1-5-32-544', 'S-1-5-18') {
            $id = New-Object Security.Principal.SecurityIdentifier $sid
            $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule ($id, 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow')))
        }
        if ($admin) { $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-544')) }
        $acl
    }
    $full = Resolve-FullPath $Base
    $dirs = @($full, (Get-KitDownloadDir -Base $full))
    foreach ($d in $dirs) {
        if (-not (Test-Path -LiteralPath $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
        if ((Get-Item -LiteralPath $d -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw (Get-KitText 'Path.ReparsePoint' -f $d) }
    }
    # Deepest first: once the base is locked, a non-administrator (tests) could not reach the child any more.
    foreach ($d in $dirs[1], $dirs[0]) { (Get-Item -LiteralPath $d -Force).SetAccessControl((& $newAcl)) }
    $dirs[1]
}

# Common name (SimpleName) and O= of the signer certificate.
function Get-CertificateNames([Security.Cryptography.X509Certificates.X509Certificate2] $Certificate) {
    if (-not $Certificate) { return @('', '') }
    $o = [regex]::Match($Certificate.Subject, '(?:^|,)\s*O=(?:"((?:[^"]|"")*)"|([^,]*))')
    $org = if (-not $o.Success) { '' } elseif ($o.Groups[1].Success) { $o.Groups[1].Value.Replace('""', '"') } else { $o.Groups[2].Value.Trim() }
    @($Certificate.GetNameInfo([Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false), $org)
}

# IsTrusted only when the signature is Valid AND the signer's CN is exactly one of -ExpectedPublisher AND its
# O is exactly -ExpectedOrganization (default: the first expected publisher). Windows' own files are signed
# as CN=Microsoft Windows, O=Microsoft Corporation; redistributables as CN=O=Microsoft Corporation.
function Test-KitSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [string[]] $ExpectedPublisher,
        [string] $ExpectedOrganization
    )
    if (-not $ExpectedOrganization) { $ExpectedOrganization = $ExpectedPublisher[0] }
    $signature = Get-AuthenticodeSignature -LiteralPath (Resolve-FullPath $Path)
    $subject = if ($signature.SignerCertificate) { $signature.SignerCertificate.Subject } else { '' }
    $names   = Get-CertificateNames $signature.SignerCertificate
    $match   = [bool](@($ExpectedPublisher | Where-Object { [string]::Equals($_, $names[0], [StringComparison]::OrdinalIgnoreCase) }).Count) -and
               [string]::Equals($ExpectedOrganization, $names[1], [StringComparison]::OrdinalIgnoreCase)
    $result  = [pscustomobject]@{
        Path           = $signature.Path
        Status         = [string]$signature.Status
        Subject        = $subject
        Publisher      = $names[0]
        Organization   = $names[1]
        PublisherMatch = $match
        IsTrusted      = ($signature.Status -eq 'Valid') -and $match
    }
    if (-not $result.IsTrusted) { Write-KitLog (Get-KitText 'Signature.NotTrusted' -f $result.Path, $result.Status, $subject) -Level Warn }
    $result
}

# One row per file that is about to be run or registered: path, SHA256 and Authenticode status. Read-only.
function Get-KitFilePlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string[]] $Path)
    foreach ($p in $Path) {
        $full = Resolve-FullPath $p
        $signature = Get-AuthenticodeSignature -LiteralPath $full
        [pscustomobject]@{
            Path      = $full
            Sha256    = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
            Signature = [string]$signature.Status
            Signer    = (Get-CertificateNames $signature.SignerCertificate)[0]
        }
    }
}

# $true while the file still has the hash that was shown and confirmed (nothing was swapped in between).
function Test-KitFilePlanHash {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Row)
    (Test-Path -LiteralPath $Row.Path -PathType Leaf) -and (Get-FileHash -LiteralPath $Row.Path -Algorithm SHA256).Hash -eq $Row.Sha256
}

# Shows the plan (log) and asks for confirmation: -Approve { param($text) ... } returns $true/$false (the
# wizard passes its dialog); without -Approve the console asks. There is no silent way around it.
function Confirm-KitPlan {
    [CmdletBinding()]
    param(
        [string[]] $Lines = @(),
        [object[]] $FilePlan = @(),
        [scriptblock] $Approve
    )
    $all = @($Lines)
    if ($FilePlan) {
        $all += Get-KitText 'Plan.Intro'
        $all += @(foreach ($f in $FilePlan) { Get-KitText 'Plan.File' -f $f.Path, $f.Sha256, $f.Signature, $f.Signer })
    }
    foreach ($l in $all) { Write-KitLog $l }
    $text = $all -join [Environment]::NewLine
    if ($Approve) { return [bool](& $Approve $text | Select-Object -Last 1) }
    $PSCmdlet.ShouldContinue($text, (Get-KitText 'Ui.Confirm.Title'))
}
