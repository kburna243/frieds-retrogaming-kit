<#
.SYNOPSIS
    Retro Shooter (RS3 Reaper and siblings) adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    The Retro Shooter hub enumerates as VID_16C0 / VID_0079 / VID_2563 with the gun PIDs 0x05E1 and
    0x187C. Detection is read-only and works without the kit module; the other functions need the kit
    context (lightgun\adapters\README.md).
#>

function Test-RetroShooterHardware {
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
        # VID_0079 appears as DolphinBar too (PID 1802/1803): match the hub PIDs, never a bare VID_0079.
        if ($id -like '*VID_16C0&PID_05E1*' -or $id -like '*VID_16C0&PID_187C*' -or $id -like '*VID_0079&PID_187C*' -or $id -like '*VID_2563&*') { return $true }
        $name = ''
        if ($d.PSObject.Properties['FriendlyName']) { $name = [string]$d.FriendlyName }
        if ($name -like '*RetroShooter*' -or $name -like '*Reaper*') { return $true }
    }
    return $false
}

function Get-RetroShooterAdapterInfo {
    @{
        ToolDir    = 'RetroShooter'
        MatchIds   = @('VID_16C0&PID_05E1', 'VID_16C0&PID_187C', 'VID_0079&PID_187C', 'VID_2563&')
        SteamEntries = @('0x16c0/0x05e1', '0x16c0/0x187c', '0x0079/0x187c')
        MameValues = [ordered]@{ lightgun = '1'; lightgun_device = 'rawinput'; dual_lightgun = '1'; offscreen_reload = '1'; output = 'windows' }
        GunsValues = [ordered]@{ EnableLightguns = '1'; Gun1Device = 'RetroShooter'; EnableDemulShooter = '1' }
        DemulDevice = $true
        Links      = @{ 'RS calibration software' = 'https://retroshooter.com' }
    }
}

# The RS calibration tools live on retroshooter.com, not on the core allow-list: hint, portable ZIP
# through -PackagePath. The calibration itself (four screen corners, stored in the hub) stays manual.
function Install-RetroShooterSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-RetroShooterAdapterInfo
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
    if (-not (Test-Path -LiteralPath $targetDir)) { $null = New-Item -ItemType Directory -Path $targetDir -Force }
    Expand-Archive -LiteralPath $PackagePath -DestinationPath $targetDir -Force
    Write-KitLog (Get-KitText 'Lightgun.Adapter.SoftwareInstalled' -f 'Retro Shooter', $targetDir)
    $true
}

function Configure-RetroShooterProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $DetectedDeviceId = '')
    Set-LightgunAdapterConfiguration -Name 'RetroShooter' -RetroBatRoot $RetroBatRoot -DetectedDeviceId $DetectedDeviceId -Confirm:$false
}

function Set-RetroShooterInterferenceShield {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-RetroShooterAdapterInfo
    $steam = Get-LightgunSteamPath
    if (-not $steam) { return }
    $vdf = Join-Path $steam 'config\config.vdf'
    if (Test-Path -LiteralPath $vdf -PathType Leaf) {
        $null = Set-LightgunSteamBlacklist -ConfigVdf $vdf -ExtraEntries @($info['SteamEntries']) -Confirm:$false
    }
}
