function Get-DisplaysAdapterDir {
    Join-Path $script:DisplaysDir 'adapters'
}

function Get-DisplayMonitorEdid {
    [CmdletBinding()]
    param()
    # Returns array of monitor info with EDID-derived keys (Manufacturer, ProductCode, SerialNumber)
    Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorID -ErrorAction SilentlyContinue |
        ForEach-Object {
            $mfr = if ($_.ManufacturerName) { [string]::Join('', ($_.ManufacturerName | ForEach-Object { [char]$_ })) } else { '' }
            $prod = if ($_.ProductCodeID) { [string]::Join('', ($_.ProductCodeID | ForEach-Object { [char]$_ })) } else { '' }
            $ser = if ($_.SerialNumberID) { [string]::Join('', ($_.SerialNumberID | ForEach-Object { [char]$_ })) } else { '' }
            [pscustomobject]@{ Manufacturer = $mfr; ProductCode = $prod; SerialNumber = $ser; InstanceName = $_.InstanceName }
        }
}