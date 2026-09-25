# Gunmote (step 4): guided. The user downloads and installs Gunmote from the official repository himself;
# the kit finds the installation (uninstall entry or Program Files), shows the version and makes sure Gunmote
# starts at logon as a task with highest rights (its pipe and the driver need them). Gunmote writes all its
# files back when it exits: the kit changes them only while Gunmote is closed and with administrator rights.

$script:LightgunGunmoteReleases = 'https://github.com/gunmotelabs/Gunmote/releases'
$script:LightgunGunmoteTaskName = 'RetroCabinetKit Gunmote'

function Get-LightgunGunmoteReleaseUrl {
    [CmdletBinding()]
    param()
    $script:LightgunGunmoteReleases
}

# -Entries injects uninstall entries, -Path forces a folder (tests, portable copies). $null = not found.
function Find-LightgunGunmote {
    [CmdletBinding()]
    param([object[]] $Entries, [string] $Path)
    $dir = $Path
    $version = ''
    if (-not $dir) {
        if (-not $PSBoundParameters.ContainsKey('Entries')) { $Entries = @(Get-LightgunUninstallEntry -Pattern '^Gunmote\b') }
        $entry = @($Entries | Where-Object { $_.InstallLocation }) | Select-Object -First 1
        if ($entry) { $dir = $entry.InstallLocation; $version = $entry.DisplayVersion }
        elseif ($env:ProgramFiles) { $dir = Join-Path $env:ProgramFiles 'Gunmote' }
    }
    if (-not $dir) { return $null }
    $dir = (Resolve-LightgunFullPath $dir).TrimEnd('\')
    $exe = Join-Path $dir 'Gunmote.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { return $null }
    if (-not $version) { $version = [string](Get-Item -LiteralPath $exe).VersionInfo.ProductVersion }
    [pscustomobject]@{
        Dir            = $dir
        Exe            = $exe
        Version        = $version
        Keymaps        = Join-Path $dir 'Keymaps'
        KeymapsJson    = Join-Path $dir 'Keymaps\Keymaps.json'
        InProgramFiles = Test-LightgunUnderProgramFiles -Path $dir
    }
}

function Get-LightgunGunmoteTaskName {
    [CmdletBinding()]
    param()
    $script:LightgunGunmoteTaskName
}

# $true when a task starts this Gunmote.exe with highest rights (the kit's own or one the user made).
function Test-LightgunGunmoteTask {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Exe, [object[]] $Tasks)
    $a = @{ Execute = $Exe }; if ($PSBoundParameters.ContainsKey('Tasks')) { $a.Tasks = $Tasks }
    [bool](@(Get-LightgunTaskByProgram @a | Where-Object { $_.RunLevel -eq 'Highest' }).Count)
}

# Registers "RetroCabinetKit Gunmote" (logon, highest rights, the starting user). Only for a Gunmote below
# Program Files: a task with highest rights must never start a program that a normal user could replace.
function Register-LightgunGunmoteTask {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [psobject] $Gunmote,
        [Parameter(Mandatory)] [string] $UserSid,
        [string] $TaskName = $script:LightgunGunmoteTaskName
    )
    if (-not $Gunmote.InProgramFiles) { throw (Get-KitText 'Lightgun.Gunmote.NotProgramFiles' -f $Gunmote.Dir) }
    Register-LightgunTask -TaskName $TaskName -Execute $Gunmote.Exe -UserSid $UserSid -AtLogOn -WhatIf:$WhatIfPreference -Confirm:$false
}
