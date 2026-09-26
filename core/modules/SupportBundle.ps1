# Support bundle: one zip a user can attach to an issue. Everything in it passes ConvertTo-KitSupportText
# (profile path, user and computer name, account SIDs, private IPs, e-mail addresses and other users' profile
# folders are replaced). It contains no ROMs, tables, databases or configuration files, only:
#   summary.json      kit version, time, doctor counts
#   environment.json  Windows build, PowerShell version, culture, 64-bit, elevation
#   doctor.txt/.json  the doctor report (read-only checks)
#   state/<name>.json the install-state.json files of the suites
#   logs/<name>       the newest kit logs

# ConvertTo-KitAnonymousText plus the patterns the depersonalization scan looks for in the repository.
function ConvertTo-KitSupportText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $Text,
        [string] $UserName = $env:USERNAME,
        [string] $ComputerName = $env:COMPUTERNAME,
        [string] $UserProfile = $env:USERPROFILE
    )
    $t = ConvertTo-KitAnonymousText -Text $Text -UserName $UserName -ComputerName $ComputerName -UserProfile $UserProfile
    $octet = '(?:25[0-5]|2[0-4]\d|1?\d?\d)'
    $t = [regex]::Replace($t, "(?<![\d.])(?:10\.$octet|172\.(?:1[6-9]|2\d|3[01])|192\.168|169\.254|100\.(?:6[4-9]|[7-9]\d|1[01]\d|12[0-7]))\.$octet\.$octet(?![\d.])", '<IP>')
    $t = [regex]::Replace($t, '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}\b', '<EMAIL>')
    # Other accounts' profile folders (a second user, an old build's creator): keep the drive, hide the name.
    $t = [regex]::Replace($t, '(?i)\b([A-Z]:\\(?:Users|Dokumente und Einstellungen|Documents and Settings)\\)(?!<USER|Public\\|Default\\|All Users\\)[^\\/:*?"<>|\r\n]+', '$1<OTHERUSER>')
    $t
}

function Add-ZipText($Zip, [string] $Name, [string] $Text) {
    $entry = $Zip.CreateEntry($Name, [IO.Compression.CompressionLevel]::Optimal)
    $writer = New-Object IO.StreamWriter ($entry.Open(), (New-Object Text.UTF8Encoding $false))
    try { $writer.Write($Text) } finally { $writer.Dispose() }
}

function Read-SharedText([string] $Path) {
    $stream = [IO.File]::Open($Path, 'Open', 'Read', 'ReadWrite')
    try { $reader = New-Object IO.StreamReader ($stream, [Text.Encoding]::UTF8, $true); $reader.ReadToEnd() } finally { $stream.Dispose() }
}

# -DoctorResult: rows of Invoke-KitDoctor (the caller runs the checks it has). -StatePath: state files (missing
# ones are left out). -LogDir: the newest -MaxLogs *.log files from there. Returns the zip file.
function Export-KitSupportBundle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Destination,
        [AllowEmptyCollection()] [object[]] $DoctorResult = @(),
        [string[]] $StatePath = @(),
        [string] $LogDir,
        [ValidateRange(0, 50)] [int] $MaxLogs = 5,
        [string] $KitRoot = $script:KitRoot,
        [hashtable] $Environment
    )
    $zipPath = Resolve-FullPath $Destination
    if (Test-Path -LiteralPath $zipPath) { throw (Get-KitText 'Support.Exists' -f $zipPath) }
    $dir = Split-Path -Parent $zipPath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $versionFile = Join-Path $KitRoot 'VERSION'
    $version = if (Test-Path -LiteralPath $versionFile -PathType Leaf) { ([IO.File]::ReadAllText($versionFile)).Trim() } else { '' }
    if (-not $Environment) {
        $os = [Environment]::OSVersion.Version
        $build = [string](Get-KitRegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'CurrentBuildNumber' -ErrorAction SilentlyContinue)
        $Environment = [ordered]@{
            OsVersion  = "$os"
            OsBuild    = $build
            PSVersion  = "$($PSVersionTable.PSVersion)"
            PSEdition  = "$($PSVersionTable.PSEdition)"
            Is64BitOs  = [Environment]::Is64BitOperatingSystem
            Culture    = "$(Get-Culture)"
            UICulture  = "$(Get-UICulture)"
            KitCulture = Get-KitCulture
            Elevated   = [bool](Test-KitAdmin)
        }
    }
    $summary = Get-KitDoctorSummary -Result $DoctorResult
    $manifest = [ordered]@{
        Format   = 1
        Version  = $version
        Created  = (Get-Date).ToString('o')
        Doctor   = [ordered]@{ Ok = $summary.Ok; Info = $summary.Info; Warn = $summary.Warn; Error = $summary.Error }
        Contents = New-Object Collections.Generic.List[string]
    }

    Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::Open($zipPath, [IO.Compression.ZipArchiveMode]::Create)
    try {
        Add-ZipText $zip 'environment.json' (ConvertTo-KitSupportText -Text (ConvertTo-Json -InputObject $Environment -Depth 4))
        $manifest.Contents.Add('environment.json')
        if (@($DoctorResult).Count) {
            Add-ZipText $zip 'doctor.txt' (ConvertTo-KitSupportText -Text ((Format-KitDoctorReport -Result $DoctorResult) -join "`r`n"))
            $rows = @($DoctorResult | ForEach-Object { [ordered]@{ Area = $_.Area; Name = $_.Name; Level = $_.Level; Detail = $_.Detail } })
            Add-ZipText $zip 'doctor.json' (ConvertTo-KitSupportText -Text (ConvertTo-Json -InputObject $rows -Depth 4))
            $manifest.Contents.Add('doctor.txt'); $manifest.Contents.Add('doctor.json')
        }
        $i = 0
        foreach ($s in $StatePath | Where-Object { $_ }) {
            $full = Resolve-FullPath $s
            if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { continue }
            $i++
            $name = 'state/{0}-{1}' -f (Split-Path -Leaf (Split-Path -Parent $full)), (Split-Path -Leaf $full)
            if ($manifest.Contents.Contains($name)) { $name = 'state/{0}-{1}' -f $i, (Split-Path -Leaf $full) }
            Add-ZipText $zip $name (ConvertTo-KitSupportText -Text (Read-SharedText $full))
            $manifest.Contents.Add($name)
        }
        if ($LogDir -and $MaxLogs -gt 0 -and (Test-Path -LiteralPath $LogDir -PathType Container)) {
            foreach ($log in Get-ChildItem -LiteralPath $LogDir -Filter '*.log' -File | Sort-Object LastWriteTime -Descending | Select-Object -First $MaxLogs) {
                $name = "logs/$($log.Name)"
                Add-ZipText $zip $name (ConvertTo-KitSupportText -Text (Read-SharedText $log.FullName))
                $manifest.Contents.Add($name)
            }
        }
        $manifest.Contents = @($manifest.Contents)
        Add-ZipText $zip 'summary.json' (ConvertTo-Json -InputObject $manifest -Depth 4)
        $zip.Dispose(); $zip = $null
    } catch {
        if ($zip) { $zip.Dispose() }
        if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
        throw
    }
    Write-KitLog (Get-KitText 'Support.Created' -f $zipPath)
    Get-Item -LiteralPath $zipPath
}
