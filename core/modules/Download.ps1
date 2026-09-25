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

# Creates the folder, or accepts an existing one only when its owner is one of -TrustedOwner (default:
# Administrators, SYSTEM). Below ProgramData every user may create folders: one created beforehand stays under
# the user's control (the owner can always rewrite the ACL), so the kit stops instead of using it. A folder
# created right here (New-Item fails if someone was faster) needs no check. Links (junctions) are refused.
# Returns the full path.
function Initialize-KitTrustedFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [string[]] $TrustedOwner = @('S-1-5-32-544', 'S-1-5-18')
    )
    $full = Resolve-FullPath $Path
    $created = $false
    if (-not (Test-Path -LiteralPath $full)) {
        try { $null = New-Item -ItemType Directory -Path $full -ErrorAction Stop; $created = $true }
        catch { if (-not (Test-Path -LiteralPath $full)) { throw } }
    }
    if ((Get-Item -LiteralPath $full -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw (Get-KitText 'Path.ReparsePoint' -f $full) }
    if (-not $created) {
        $owner = [IO.Directory]::GetAccessControl($full).GetOwner([Security.Principal.SecurityIdentifier]).Value
        if ($TrustedOwner -notcontains $owner) { throw (Get-KitText 'Path.UntrustedOwner' -f $full, $owner) }
    }
    $full
}

# Creates <Base> and <Base>\downloads (existing ones only with a trusted owner) with an ACL for Administrators
# and SYSTEM only (inheritance off); -TrustedOwner SIDs get full control too (tests in TEMP add their own SID,
# the default adds nothing). As administrator the owner becomes Administrators. Returns the downloads folder.
function Initialize-KitDownloadDir {
    [CmdletBinding()]
    param(
        [string] $Base = (Join-Path $env:ProgramData 'RetroCabinetKit'),
        [string[]] $TrustedOwner = @('S-1-5-32-544', 'S-1-5-18')
    )
    $admin = Test-KitAdmin
    # A fresh object per folder: after one SetAccessControl the object counts as unchanged and writes nothing.
    $newAcl = {
        $acl = New-Object Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true, $false)
        foreach ($sid in (@('S-1-5-32-544', 'S-1-5-18') + $TrustedOwner | Select-Object -Unique)) {
            $id = New-Object Security.Principal.SecurityIdentifier $sid
            $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule ($id, 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow')))
        }
        if ($admin) { $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier 'S-1-5-32-544')) }
        $acl
    }
    $full = Initialize-KitTrustedFolder -Path $Base -TrustedOwner $TrustedOwner
    $dl = Initialize-KitTrustedFolder -Path (Get-KitDownloadDir -Base $full) -TrustedOwner $TrustedOwner
    # Deepest first: once the base is locked, a non-administrator (tests) could not reach the child any more.
    foreach ($d in $dl, $full) { (Get-Item -LiteralPath $d -Force).SetAccessControl((& $newAcl)) }
    $dl
}

# A fresh folder per run (GUID) below the locked downloads folder, created only AFTER the lock: it inherits the
# admin-only ACL and nobody else can have put a file into it.
function New-KitWorkDir {
    [CmdletBinding()]
    param(
        [string] $Base = (Join-Path $env:ProgramData 'RetroCabinetKit'),
        [string[]] $TrustedOwner = @('S-1-5-32-544', 'S-1-5-18')
    )
    $dl = Initialize-KitDownloadDir -Base $Base -TrustedOwner $TrustedOwner
    (New-Item -ItemType Directory -Path (Join-Path $dl ([guid]::NewGuid().ToString('N'))) -ErrorAction Stop).FullName
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

# Opens the file of a plan row read-only with FileShare.Read and checks the hash read THROUGH that handle:
# while the returned stream is open nobody can change, replace or delete the file, and it is the confirmed
# one. Programs may still read and run it. $null (nothing held) when it is missing, locked or changed.
function Open-KitFilePlanFile {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [psobject] $Row)
    try { $fs = [IO.File]::Open($Row.Path, 'Open', 'Read', 'Read') } catch { return $null }
    $ok = $false
    try { $ok = (Get-Sha256Hex $fs) -eq $Row.Sha256 } finally { if (-not $ok) { $fs.Dispose() } }
    if ($ok) { $fs }
}

# An installer never runs where it was found (N1): next to it in the build or download folder a planted DLL
# would be loaded, and the file could be swapped between check and start. Each item is copied into a fresh
# admin-only work folder (New-KitWorkDir): the file, or with Folder = $true everything below its folder (links
# skipped). EVERY .exe/.dll there must carry a valid signature with the expected CN (Publisher) and O
# (Organization, default: the first CN). The PE files of all trusted items are confirmed as ONE plan with
# SHA256 (-Lines on top; -Approve, else the console asks). Right before the start the work folder must hold
# exactly the copied files, and every PE file is held open with FileShare.Read after its hash was read through
# that handle. The copy starts with the work folder as working directory; the folder is removed afterwards.
# Windows' own programs below System32 (DISM) run in place: only administrators can change that folder and a
# copy would miss their components. Item: @{ Name; Path; Arguments; Publisher; Organization; Folder }.
# Returns one row per item: Name, Result (Ok | Untrusted | Declined | Changed), ExitCode, File, Signature.
function Invoke-KitVerifiedExecutable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [hashtable[]] $Item,
        [string[]] $Lines = @(),
        [scriptblock] $Approve,
        [string] $Base = (Join-Path $env:ProgramData 'RetroCabinetKit'),
        [string[]] $TrustedOwner = @('S-1-5-32-544', 'S-1-5-18')
    )
    $rows = New-Object Collections.Generic.List[object]
    $ready = New-Object Collections.Generic.List[object]
    $system32 = Join-Path $env:SystemRoot 'System32'
    try {
        foreach ($it in $Item) {
            $row = [pscustomobject]@{ Name = $it.Name; Result = 'Untrusted'; ExitCode = $null; File = $null; Signature = $null }
            $rows.Add($row)
            $src = Resolve-FullPath $it.Path
            $srcDir = Split-Path -Parent $src
            $job = [pscustomobject]@{ Row = $row; Item = $it; Work = $srcDir; Exe = $src; Expected = $null; Plan = @(); Temp = $false }
            if (-not (Test-KitPathUnder -Path $src -Root $system32)) {
                $job.Work = New-KitWorkDir -Base $Base -TrustedOwner $TrustedOwner
                $job.Temp = $true
                $files = if ($it['Folder']) { @(Get-KitFileTree -Path $srcDir -SkipReparseFiles) } else { @(Get-Item -LiteralPath $src -Force) }
                $job.Expected = @(foreach ($f in $files) {
                    $rel = $f.FullName.Substring($srcDir.Length).TrimStart('\')
                    $dest = Join-Path $job.Work $rel
                    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force
                    Copy-Item -LiteralPath $f.FullName -Destination $dest
                    $rel
                })
                $job.Exe = Join-Path $job.Work (Split-Path -Leaf $src)
                $pe = @($job.Expected | Where-Object { [IO.Path]::GetExtension($_) -in '.exe', '.dll' } | ForEach-Object { Join-Path $job.Work $_ })
            } else { $pe = @($src) }
            $bad = $null
            foreach ($p in $pe) {
                $sig = Test-KitSignature -Path $p -ExpectedPublisher $it.Publisher -ExpectedOrganization $it['Organization']
                if (-not $sig.IsTrusted) { $bad = $sig; break }
            }
            if ($bad) {
                $row.File = $bad.Path; $row.Signature = $bad
                if ($job.Temp) { Remove-Item -LiteralPath $job.Work -Recurse -Force -ErrorAction SilentlyContinue }
                continue
            }
            $job.Plan = @(Get-KitFilePlan -Path $pe)
            $ready.Add($job)
        }
        $ok = $ready.Count -and (Confirm-KitPlan -Lines $Lines -FilePlan @($ready | ForEach-Object { $_.Plan }) -Approve $Approve)
        foreach ($job in $ready) {
            if (-not $ok) { $job.Row.Result = 'Declined'; continue }
            $handles = New-Object Collections.Generic.List[object]
            try {
                $job.Row.Result = 'Changed'
                if ($job.Temp) {
                    $present = @(Get-ChildItem -LiteralPath $job.Work -Recurse -Force | Where-Object { -not $_.PSIsContainer } |
                        ForEach-Object { $_.FullName.Substring($job.Work.Length).TrimStart('\') })
                    if ((@($present | Sort-Object) -join '|') -ne (@($job.Expected | Sort-Object) -join '|')) { continue }
                }
                foreach ($p in $job.Plan) {
                    $h = Open-KitFilePlanFile -Row $p
                    if (-not $h) { break }
                    $handles.Add($h)
                }
                if ($handles.Count -ne $job.Plan.Count) { continue }
                $opt = @{ FilePath = $job.Exe; WorkingDirectory = $job.Work; Wait = $true; PassThru = $true; WindowStyle = 'Hidden' }
                if ($job.Item['Arguments']) { $opt.ArgumentList = $job.Item['Arguments'] } # -ArgumentList refuses empty values
                $job.Row.ExitCode = (Start-Process @opt).ExitCode
                $job.Row.Result = 'Ok'
            } finally { foreach ($h in $handles) { $h.Dispose() } }
        }
    } finally {
        foreach ($job in $ready | Where-Object { $_.Temp }) { Remove-Item -LiteralPath $job.Work -Recurse -Force -ErrorAction SilentlyContinue }
    }
    foreach ($r in $rows | Where-Object { $_.Result -eq 'Changed' }) { Write-KitLog (Get-KitText 'Plan.Changed' -f $r.Name) -Level Error }
    $rows.ToArray()
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
