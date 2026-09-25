# Elevation: admin check, relaunch elevated, mapped drive -> UNC, same-user check.
# Mapped drives belong to the logon session and are missing in the elevated session,
# so script paths are converted to UNC before relaunching. When the elevated process
# runs as a different account (over-the-shoulder UAC), HKCU would be the wrong profile:
# callers pass the original SID and lock registry steps if Test-KitSameUser is $false. Started directly
# "as administrator" (no SID), the interactively logged-on user decides (Get-KitInteractiveUserSid).

function Test-KitAdmin {
    [CmdletBinding()]
    param()
    $principal = New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-KitUserSid {
    [CmdletBinding()]
    param()
    [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
}

function Test-KitSameUser {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $OriginalSid)
    $OriginalSid -eq (Get-KitUserSid)
}

# SID of the user logged on interactively in this session: owner of explorer.exe in the current session,
# otherwise Win32_ComputerSystem.UserName (console user). $null when nobody can be determined.
function Get-KitInteractiveUserSid {
    [CmdletBinding()]
    param()
    $session = [Diagnostics.Process]::GetCurrentProcess().SessionId
    foreach ($p in @(Get-CimInstance -ClassName Win32_Process -Filter "Name='explorer.exe' AND SessionId=$session" -ErrorAction SilentlyContinue)) {
        $owner = Invoke-CimMethod -InputObject $p -MethodName GetOwnerSid -ErrorAction SilentlyContinue
        if ($owner -and $owner.Sid) { return [string]$owner.Sid }
    }
    $name = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue).UserName
    if (-not $name) { return $null }
    try { (New-Object Security.Principal.NTAccount $name).Translate([Security.Principal.SecurityIdentifier]).Value } catch { $null }
}

# SID of the user whose HKCU the kit may write: the SID passed by the elevation; not elevated: the current
# user; elevated directly ("Run as administrator", no SID): the current user only when the interactively
# logged-on user is the same account, otherwise $null. -InteractiveSid injects the query result (tests).
function Get-KitStartUserSid {
    [CmdletBinding()]
    param(
        [AllowEmptyString()] [string] $OriginalSid,
        [bool] $IsAdmin = (Test-KitAdmin),
        [AllowEmptyString()] [AllowNull()] [string] $InteractiveSid
    )
    if ($OriginalSid) { return $OriginalSid }
    $current = Get-KitUserSid
    if (-not $IsAdmin) { return $current }
    if (-not $PSBoundParameters.ContainsKey('InteractiveSid')) { $InteractiveSid = Get-KitInteractiveUserSid }
    if ($InteractiveSid -and $InteractiveSid -eq $current) { return $current }
    $null
}

# Registry steps write to HKCU. Elevated as a DIFFERENT account than the one logged on (over-the-shoulder UAC)
# HKCU is the wrong profile, so they are locked; the same when nobody can tell who is logged on.
# Returns $null (go ahead) or the reason for NeedsUser.
function Get-KitRegistryUserLock {
    [CmdletBinding()]
    param(
        [AllowEmptyString()] [string] $OriginalSid,
        [bool] $IsAdmin = (Test-KitAdmin),
        [AllowEmptyString()] [AllowNull()] [string] $InteractiveSid
    )
    if ($OriginalSid) {
        if (Test-KitSameUser -OriginalSid $OriginalSid) { return $null }
        return Get-KitText 'Elevation.DifferentUser'
    }
    if (-not $IsAdmin) { return $null }
    if (-not $PSBoundParameters.ContainsKey('InteractiveSid')) { $InteractiveSid = Get-KitInteractiveUserSid }
    if (-not $InteractiveSid) { return Get-KitText 'Elevation.NoSid' }
    if ($InteractiveSid -eq (Get-KitUserSid)) { return $null }
    Get-KitText 'Elevation.DifferentUser'
}

function Convert-KitMappedDriveToUnc {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    if ($Path -notmatch '^([A-Za-z]):(.*)$') { return $Path }
    $drive = $Matches[1].ToUpperInvariant() + ':'
    $rest  = $Matches[2]

    $provider = $null
    $disk = Get-CimInstance -ClassName Win32_MappedLogicalDisk -Filter "DeviceID='$drive'" -ErrorAction SilentlyContinue
    if ($disk -and $disk.ProviderName) { $provider = $disk.ProviderName }
    else {
        $disk = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$drive' AND DriveType=4" -ErrorAction SilentlyContinue
        if ($disk -and $disk.ProviderName) { $provider = $disk.ProviderName }
    }
    if (-not $provider) { return $Path }
    if ($rest -and -not $rest.StartsWith('\')) { $rest = '\' + $rest }
    $provider.TrimEnd('\') + $rest
}

# CommandLineToArgvW quoting: backslashes before a quote are doubled, quotes escaped.
function ConvertTo-CommandLineArgument([string] $Value) {
    if ($Value -eq '') { return '""' }
    if ($Value -notmatch '[\s"]') { return $Value }
    $escaped = ($Value -replace '(\\*)"', '$1$1\"') -replace '(\\+)$', '$1$1'
    '"' + $escaped + '"'
}

function Get-KitElevationCommandLine {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ScriptPath,
        [string[]] $ArgumentList = @(),
        [switch] $PassUserSid
    )
    $script = Convert-KitMappedDriveToUnc (Resolve-FullPath $ScriptPath)
    $parts  = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (ConvertTo-CommandLineArgument $script))
    foreach ($a in $ArgumentList) { $parts += ConvertTo-CommandLineArgument $a }
    if ($PassUserSid) { $parts += '-KitUserSid'; $parts += (Get-KitUserSid) }
    $parts -join ' '
}

function Start-KitElevated {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $ScriptPath,
        [string[]] $ArgumentList = @(),
        [switch] $PassUserSid,
        [switch] $Wait
    )
    $commandLine = Get-KitElevationCommandLine -ScriptPath $ScriptPath -ArgumentList $ArgumentList -PassUserSid:$PassUserSid
    if (-not $PSCmdlet.ShouldProcess($ScriptPath, 'Start elevated')) { return }
    $process = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $commandLine -Verb RunAs -PassThru -Wait:$Wait
    if ($Wait) { $process.ExitCode }
}
