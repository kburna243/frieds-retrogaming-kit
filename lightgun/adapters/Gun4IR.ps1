<#
.SYNOPSIS
    Gun4IR lightgun adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    Gun4IR on an Arduino Leonardo (runtime VID_2341&PID_8036) or on the ATmega32U4/Caterina bootloader
    (VID_1B4F&PID_9206). Detection is read-only and works without the kit module; the other functions
    use the kit helpers and need the module context (see lightgun\adapters\README.md).
#>

function Test-Gun4IRHardware {
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
        if ($id -like '*VID_2341&PID_8036*' -or $id -like '*VID_1B4F&PID_9206*') { return $true }
        $name = ''
        if ($d.PSObject.Properties['FriendlyName']) { $name = [string]$d.FriendlyName }
        if ($name -like '*Gun4IR*') { return $true }
    }
    return $false
}

function Get-Gun4IRAdapterInfo {
    @{
        ToolDir    = 'Gun4IR'
        MatchIds   = @('VID_2341&PID_8036', 'VID_1B4F&PID_9206')
        SteamEntries = @('0x2341/0x8036', '0x1b4f/0x9206')
        MameValues = [ordered]@{ lightgun = '1'; lightgun_device = 'rawinput'; dual_lightgun = '1'; offscreen_reload = '1'; output = 'windows' }
        GunsValues = [ordered]@{ EnableLightguns = '1'; Gun1Device = 'Gun4IR'; EnableDemulShooter = '1' }
        DemulDevice = $true
        Links      = @{ 'Gun4IR firmware and PC tools' = 'https://github.com/gun4ir/Gun4IR/releases' }
    }
}

# Deliberately does NOT download: the Gun4IR package is not on the core allow-list, so the kit only names
# the official source. The user fetches the ZIP and passes it as -PackagePath; with -Approved the kit
# unpacks it into tools\Gun4IR. Without a package nothing happens beyond the hint.
function Install-Gun4IRSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-Gun4IRAdapterInfo
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
    Write-KitLog (Get-KitText 'Lightgun.Adapter.SoftwareInstalled' -f 'Gun4IR', $targetDir)
    $true
}

function Configure-Gun4IRProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $DetectedDeviceId = '')
    Set-LightgunAdapterConfiguration -Name 'Gun4IR' -RetroBatRoot $RetroBatRoot -DetectedDeviceId $DetectedDeviceId -Confirm:$false
}

# Interference shield, kit style: Steam Input is blocked from grabbing the gun via controller_blacklist.
# The downloaded draft killed Steam and touched HKLM - the kit never does either.
function Set-Gun4IRInterferenceShield {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-Gun4IRAdapterInfo
    $steam = Get-LightgunSteamPath
    if (-not $steam) { return }
    $vdf = Join-Path $steam 'config\config.vdf'
    if (Test-Path -LiteralPath $vdf -PathType Leaf) {
        $null = Set-LightgunSteamBlacklist -ConfigVdf $vdf -ExtraEntries @($info['SteamEntries'])
    }
}
