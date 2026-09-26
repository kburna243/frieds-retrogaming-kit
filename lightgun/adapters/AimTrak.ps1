<#
.SYNOPSIS
    Ultimarc AimTrak adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    AimTrak modules enumerate as USB\VID_D209&PID_1601..1608 (gun 1 to gun 8). Detection is read-only
    and works without the kit module; the other functions need the kit context (lightgun\adapters\README.md).
#>

function Test-AimTrakHardware {
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
        if ($id -like '*VID_D209&PID_160*') { return $true }
        $name = ''
        if ($d.PSObject.Properties['FriendlyName']) { $name = [string]$d.FriendlyName }
        if ($name -like '*AimTrak*') { return $true }
    }
    return $false
}

function Get-AimTrakAdapterInfo {
    @{
        ToolDir    = 'AimTrak'
        MatchIds   = @('VID_D209&PID_1601', 'VID_D209&PID_1602', 'VID_D209&PID_1603', 'VID_D209&PID_1604',
                       'VID_D209&PID_1605', 'VID_D209&PID_1606', 'VID_D209&PID_1607', 'VID_D209&PID_1608')
        # The two player slots a cabinet uses; more guns: append 0xd209/0x1603... here.
        SteamEntries = @('0xd209/0x1601', '0xd209/0x1602')
        MameValues = [ordered]@{ lightgun = '1'; lightgun_device = 'rawinput'; dual_lightgun = '1'; offscreen_reload = '1' }
        GunsValues = [ordered]@{ EnableLightguns = '1'; Gun1Device = 'AimTrak' }
        DemulDevice = $false
        Links      = @{ 'AimTrak control panel and drivers' = 'https://www.ultimarc.com' }
    }
}

# The AimTrak control panel is a classic installer (.exe) from ultimarc.com, which is not on the core
# allow-list. The kit never starts vendor installers itself: it names the source and leaves the manual
# step to the user. A portable ZIP (if the vendor ships one) can go through -PackagePath like the others.
function Install-AimTrakSoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-AimTrakAdapterInfo
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
    Write-KitLog (Get-KitText 'Lightgun.Adapter.SoftwareInstalled' -f 'AimTrak', $targetDir)
    $true
}

function Configure-AimTrakProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $DetectedDeviceId = '')
    Set-LightgunAdapterConfiguration -Name 'AimTrak' -RetroBatRoot $RetroBatRoot -DetectedDeviceId $DetectedDeviceId -Confirm:$false
}

function Set-AimTrakInterferenceShield {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-AimTrakAdapterInfo
    $steam = Get-LightgunSteamPath
    if (-not $steam) { return }
    $vdf = Join-Path $steam 'config\config.vdf'
    if (Test-Path -LiteralPath $vdf -PathType Leaf) {
        $null = Set-LightgunSteamBlacklist -ConfigVdf $vdf -ExtraEntries @($info['SteamEntries']) -Confirm:$false
    }
}
