<#
.SYNOPSIS
    OpenFIRE / Open-Gun adapter for Fried's Retrogaming Kit.
.DESCRIPTION
    OpenFIRE firmware on RP2040 (USB\VID_2E8A&PID_000A in TinyUSB/bootloader state) or ESP32-S3
    (USB\VID_303A&PID_1001). Detection is read-only and works without the kit module; the other
    functions need the kit context (lightgun\adapters\README.md).
#>

function Test-OpenFIREHardware {
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
        if ($id -like '*VID_2E8A&PID_000A*' -or $id -like '*VID_303A&PID_1001*') { return $true }
        $name = ''
        if ($d.PSObject.Properties['FriendlyName']) { $name = [string]$d.FriendlyName }
        if ($name -like '*OpenFIRE*' -or $name -like '*Picon-AS*') { return $true }
    }
    return $false
}

function Get-OpenFIREAdapterInfo {
    @{
        ToolDir    = 'OpenFIRE'
        MatchIds   = @('VID_2E8A&PID_000A', 'VID_303A&PID_1001')
        SteamEntries = @('0x2e8a/0x000a', '0x303a/0x1001')
        MameValues = [ordered]@{ lightgun = '1'; lightgun_device = 'rawinput'; dual_lightgun = '1'; offscreen_reload = '1'; output = 'windows' }
        GunsValues = [ordered]@{ EnableLightguns = '1'; Gun1Device = 'OpenFIRE' }
        DemulDevice = $true
        Links      = @{ 'OpenFIRE-App (Windows ZIP under Assets)' = 'https://github.com/TeamOpenFIRE/OpenFIRE-App/releases/latest' }
    }
}

# The OpenFIRE-App publishes portable ZIPs on its GitHub releases - official, but the exact release
# folder is not on the core allow-list yet, so the kit points at the releases page and unpacks a
# downloaded ZIP only through -PackagePath (never straight from the network).
function Install-OpenFIRESoftware {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $PackagePath, [switch] $Approved)
    $info = Get-OpenFIREAdapterInfo
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
    Write-KitLog (Get-KitText 'Lightgun.Adapter.SoftwareInstalled' -f 'OpenFIRE', $targetDir)
    $true
}

function Configure-OpenFIREProfile {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [string] $DetectedDeviceId = '')
    Set-LightgunAdapterConfiguration -Name 'OpenFIRE' -RetroBatRoot $RetroBatRoot -DetectedDeviceId $DetectedDeviceId -Confirm:$false
}

function Set-OpenFIREInterferenceShield {
    [CmdletBinding(SupportsShouldProcess)]
    param([string] $RetroBatRoot, [switch] $Disable)
    if ($Disable) { return }
    $info = Get-OpenFIREAdapterInfo
    $steam = Get-LightgunSteamPath
    if (-not $steam) { return }
    $vdf = Join-Path $steam 'config\config.vdf'
    if (Test-Path -LiteralPath $vdf -PathType Leaf) {
        $null = Set-LightgunSteamBlacklist -ConfigVdf $vdf -ExtraEntries @($info['SteamEntries']) -Confirm:$false
    }
}
