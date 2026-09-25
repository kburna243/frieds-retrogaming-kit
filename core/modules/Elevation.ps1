# Elevation: admin check, relaunch elevated, mapped drive -> UNC, same-user check.
# Mapped drives belong to the logon session and are missing in the elevated session,
# so script paths are converted to UNC before relaunching. When the elevated process
# runs as a different account (over-the-shoulder UAC), HKCU would be the wrong profile:
# callers pass the original SID and lock registry steps if Test-KitSameUser is $false.

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
