$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# A distribution such as hotwm ships the kit without pinball\. The API must still load, keep every other operation and
# say plainly that the pinball ones are not part of this kit. The copy runs in its own PowerShell process, so no module
# of the full kit loaded by other test files can stand in for the missing package.
Describe 'Kit API without the pinball package' {
    $copy = Join-Path $TestDrive 'kit'
    New-Item -ItemType Directory -Path $copy | Out-Null
    foreach ($d in 'api', 'core', 'lightgun', 'arcade', 'pads', 'output', 'displays', 'enhancements', 'library', 'emulators', 'frontends', 'i18n') {
        Copy-Item -LiteralPath (Join-Path $kitRoot $d) -Destination $copy -Recurse
    }
    Copy-Item -LiteralPath (Join-Path $kitRoot 'VERSION') -Destination $copy
    $probe = Join-Path $TestDrive 'probe.ps1'
    Set-Content -LiteralPath $probe -Encoding UTF8 -Value @"
Import-Module '$copy\core\RetroCabinetKit.Core.psd1'
Import-Module '$copy\api\RetroCabinetKit.Api.psd1'
Set-KitCulture -Culture 'en-US'
`$ops = @(Get-KitOperation)
[pscustomobject]@{
    Hook       = Invoke-KitOperation -Name 'outputs.wiimote_hook'
    Components = Invoke-KitOperation -Name 'components'
    Status     = Invoke-KitOperation -Name 'status'
    PinballY   = Invoke-KitOperation -Name 'pinbally.detect' -Parameters @{ Path = 'C:\nowhere' }
    Unavailable = @(`$ops | Where-Object { -not `$_.Available -and -not `$_.Interactive } | ForEach-Object { `$_.Name })
    PinballSteps = @(`$ops | Where-Object { `$_.Name -like 'step.pinball.*' }).Count
    LightgunSteps = @(`$ops | Where-Object { `$_.Name -like 'step.lightgun.*' }).Count
} | ConvertTo-Json -Depth 6 -Compress
"@
    $json = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $probe
    $r = ($json -join '') | ConvertFrom-Json

    It 'the API loads and a lightgun/output operation succeeds' {
        $r.Hook.Operation | Should Be 'outputs.wiimote_hook'
        $r.Hook.Errors.Count | Should Be 0
        $r.Hook.Message | Should Not Match 'Pinball'
    }
    It 'components and status run without pinball rows or pinball errors' {
        $r.Components.Success | Should Be $true
        @($r.Components.Data.Components | Where-Object { $_.Name -like 'Pinball*' }).Count | Should Be 0
        $r.Status.Success | Should Be $true
    }
    It 'pinball operations are listed as not available and say why' {
        $r.Unavailable -contains 'pinbally.detect' | Should Be $true
        $r.Unavailable -contains 'pinbally.retarget' | Should Be $true
        $r.PinballY.Status | Should Be 'NotAvailable'
        $r.PinballY.Message | Should Match 'package pinball'
    }
    It 'lists no pinball steps but every lightgun step' {
        $r.PinballSteps | Should Be 0
        $r.LightgunSteps | Should Be @(Get-ChildItem (Join-Path $kitRoot 'lightgun\steps') -Filter *.ps1).Count
    }
}
