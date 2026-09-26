<#
.SYNOPSIS
    Adapter template - copy to <YourGun>.ps1 and fill in the five functions.
.DESCRIPTION
    A community adapter is one file in lightgun\adapters\ named <Name>.ps1. Discovery executes only
    Test-<Name>Hardware (read-only, no kit module needed). The other four functions run in the kit
    module scope, so Write-KitLog, Get-KitText, Set-LightgunIniValue, Set-LightgunSteamBlacklist and
    Save-KitDownload are available there. Files starting with '_' are never executed.

    Contract (names are mandatory, <Name> = file name without extension):
      Test-<Name>Hardware  -RetroBatRoot <string> [-Devices <object[]>]  -> $true/$false
      Get-<Name>AdapterInfo                                             -> hashtable (keys below)
      Install-<Name>Software -RetroBatRoot -PackagePath -Approved      -> $true when something was unpacked
      Configure-<Name>Profile -RetroBatRoot [-DetectedDeviceId]        -> number of file changes
      Set-<Name>InterferenceShield -RetroBatRoot [-Disable]            -> no return contract

    Get-<Name>AdapterInfo keys (all optional except MatchIds):
      ToolDir       folder name under <RetroBatRoot>\tools\
      MatchIds      PnP instance-id substrings identifying the hardware (the VID/PID signatures)
      SteamEntries  '0xVVVV/0xPPPP' strings added to Steam's controller_blacklist
      MameValues    key/value pairs for emulators\mame\mame.ini (space-separated MAME format)
      GunsValues    key/value pairs for retrobat.ini [Guns]
      DemulDevice   $true: write the detected instance id into DemulShooter.ini [Player1] Device
      Links         label -> official download page (informational only, never auto-fetched)

    Rules: detection reads only; writing functions must honour -WhatIf via SupportsShouldProcess;
    nothing is downloaded from a host outside core\download-allowlist.psd1 (name it in Links and
    unpack a user-supplied -PackagePath instead); no process is ever killed - Steam interference is
    handled with controller_blacklist entries.
#>

function Test-_TemplateNameHardware {
    [CmdletBinding()]
    param([string] $RetroBatRoot, [object[]] $Devices)
    if (-not $PSBoundParameters.ContainsKey('Devices')) { $Devices = @(Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue) }
    foreach ($d in $Devices) {
        $id = ''
        if ($d -is [string]) { $id = $d }
        else {
            if ($d.PSObject.Properties['InstanceId']) { $id = [string]$d.InstanceId }
            if (-not $id -and $d.PSObject.Properties['DeviceID']) { $id = [string]$d.DeviceID }
        }
        # TODO: the real VID/PID signature of the hardware, e.g. $id -like '*VID_1234&PID_5678*'
        if ($false) { return $true }
        # TODO: a distinctive friendly name is a second signal, e.g. $name -like '*YourGun*'
    }
    return $false
}

function Get-_TemplateNameAdapterInfo {
    @{
        ToolDir      = '_TemplateName'    # TODO
        MatchIds     = @()                # TODO: at least one VID/PID substring
        SteamEntries = @()                # TODO: 0xVVVV/0xPPPP entries
        MameValues   = [ordered]@{}       # TODO: MAME ini values (or leave empty)
        GunsValues   = [ordered]@{}       # TODO: retrobat.ini [Guns] values (or leave empty)
        DemulDevice  = $false
        Links        = @{ 'TODO official page' = 'https://TODO' }
    }
}

function Install-_TemplateNameSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-_TemplateNameAdapterInfo
    $targetDir = Join-Path $RetroBatRoot ('tools\' + $info['ToolDir'])
    if (-not $PackagePath) {
        foreach ($k in $info['Links'].Keys) { Write-KitLog (Get-KitText 'Lightgun.Adapter.SoftwareLink' -f $k, $info['Links'][$k]) }
        return $false
    }
    if (-not $Approved) { Write-KitLog (Get-KitText 'Lightgun.Adapter.NeedsApproval') -Level Warn; return $false }
    if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) { throw (Get-KitText 'Lightgun.Adapter.PackageMissing' -f $PackagePath) }
    $hash = (Get-FileHash -LiteralPath $PackagePath -Algorithm SHA256).Hash
    Write-KitLog (Get-KitText 'Lightgun.Adapter.PackageHash' -f (Split-Path -Leaf $PackagePath), $hash)
    if (-not $PSCmdlet.ShouldProcess($targetDir, 'unpack adapter package')) { return $false }
    # TODO: unpack (Expand-Archive) or copy the vendor tool into $targetDir
    Write-KitLog (Get-KitText 'Lightgun.Adapter.SoftwareInstalled' -f '_TemplateName', $targetDir)
    $true
}

function Configure-_TemplateNameProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $DetectedDeviceId = '')
    Set-LightgunAdapterConfiguration -Name '_TemplateName' -RetroBatRoot $RetroBatRoot -DetectedDeviceId $DetectedDeviceId -Confirm:$false
}

function Set-_TemplateNameInterferenceShield {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-_TemplateNameAdapterInfo
    $steam = Get-LightgunSteamPath
    if (-not $steam) { return }
    $vdf = Join-Path $steam 'config\config.vdf'
    if (@($info['SteamEntries']).Count -and $vdf -and (Test-Path -LiteralPath $vdf -PathType Leaf)) {
        $null = Set-LightgunSteamBlacklist -ConfigVdf $vdf -ExtraEntries @($info['SteamEntries'])
    }
}
