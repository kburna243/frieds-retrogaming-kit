$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1') -Force
$newRetroBat = Join-Path $PSScriptRoot 'New-LightgunTestRetroBat.ps1'

# Hardware, services, uninstall entries, tasks and Steam are mocked; the doctor only reads. Mock bodies compute
# their paths from the global $TestDrive: variables of the test scope are not reliably visible inside them.
Describe 'Lightgun doctor' {
    Set-KitCulture -Culture 'en-US'
    $rb = Join-Path $TestDrive 'RetroBat'
    & $newRetroBat -Root $rb
    $state = Join-Path $TestDrive 'install-state.json'
    Set-KitStateValue -Path $state -Key 'RetroBatRoot' -Value $rb
    Set-KitStepStatus -Path $state -Name 'lightgun-1-detect' -Status Done -Message 'ok'

    function Set-HealthyCabinet {
        Mock -ModuleName RetroCabinetKit.Lightgun Get-LightgunDolphinBarState { [pscustomobject]@{ Mode4 = $true; WrongMode = @() } }
        Mock -ModuleName RetroCabinetKit.Lightgun Get-LightgunRefreshReport { [pscustomobject]@{ DeviceName = 'D1'; Width = 1920; Height = 1080; RefreshRate = 60; Level = 'Ok' } }
        Mock -ModuleName RetroCabinetKit.Lightgun Get-LightgunViGEmState { [pscustomobject]@{ Installed = $true; Running = $true; Service = $true; Version = '1.22.0' } }
        Mock -ModuleName RetroCabinetKit.Lightgun Find-LightgunGunmote { $g = Join-Path $TestDrive 'Gunmote'; [pscustomobject]@{ Dir = $g; Exe = "$g\Gunmote.exe"; Version = '1.0'; InProgramFiles = $true } }
        Mock -ModuleName RetroCabinetKit.Lightgun Test-LightgunGunmoteTask { $true }
        Mock -ModuleName RetroCabinetKit.Lightgun Get-LightgunSteamPath { $null }
        Mock -ModuleName RetroCabinetKit.Lightgun Get-LightgunAutomationDir { Join-Path $TestDrive 'no-automation' }
    }
    function Get-Rows([string] $StatePath = $state) { @(Invoke-KitDoctor -Check @(Get-LightgunDoctorCheck -StatePath $StatePath)) }

    It 'a healthy cabinet has no warning and no error' {
        Set-HealthyCabinet
        $rows = Get-Rows
        @($rows | Where-Object { $_.Level -in 'Warn', 'Error' }) | ForEach-Object { "$($_.Name): $($_.Detail)" } | Should BeNullOrEmpty
        ($rows | Where-Object { $_.Name -eq 'RetroBat' }).Level | Should Be 'Ok'
        ($rows | Where-Object { $_.Name -eq 'Gunmote autostart' }).Level | Should Be 'Ok'
    }

    It 'missing ViGEmBus is an error once the setup was started, information before' {
        Set-HealthyCabinet
        Mock -ModuleName RetroCabinetKit.Lightgun Get-LightgunViGEmState { [pscustomobject]@{ Installed = $false; Running = $false; Service = $false; Version = '' } }
        (Get-Rows | Where-Object { $_.Name -eq 'ViGEmBus' }).Level | Should Be 'Error'
        (Get-Rows -StatePath (Join-Path $TestDrive 'never.json') | Where-Object { $_.Name -eq 'ViGEmBus' }).Level | Should Be 'Info'
    }

    It 'wrong DolphinBar mode, a 30 Hz screen and Gunmote outside Program Files are warnings' {
        Set-HealthyCabinet
        Mock -ModuleName RetroCabinetKit.Lightgun Get-LightgunDolphinBarState { [pscustomobject]@{ Mode4 = $false; WrongMode = @('Mode12') } }
        Mock -ModuleName RetroCabinetKit.Lightgun Get-LightgunRefreshReport { [pscustomobject]@{ DeviceName = 'TV'; Width = 3840; Height = 2160; RefreshRate = 30; Level = 'Warn' } }
        Mock -ModuleName RetroCabinetKit.Lightgun Find-LightgunGunmote { $g = Join-Path $TestDrive 'Gunmote'; [pscustomobject]@{ Dir = $g; Exe = "$g\Gunmote.exe"; Version = '1.0'; InProgramFiles = $false } }
        $rows = Get-Rows
        ($rows | Where-Object { $_.Name -eq 'DolphinBar' }).Detail | Should Match 'Mode12.*Mode 4'
        ($rows | Where-Object { $_.Name -eq 'Refresh rate' }).Level | Should Be 'Warn'
        ($rows | Where-Object { $_.Name -eq 'Gunmote' }).Level | Should Be 'Warn'
    }

    It 'a changed or writable automation folder is a security error; hooks are checked with it' {
        Set-HealthyCabinet
        New-Item -ItemType Directory -Path (Join-Path $TestDrive 'automation') -Force | Out-Null
        Mock -ModuleName RetroCabinetKit.Lightgun Get-LightgunAutomationDir { Join-Path $TestDrive 'automation' }
        Mock -ModuleName RetroCabinetKit.Lightgun Test-LightgunAutomationFile { $false }
        $rows = @(Get-Rows | Where-Object { $_.Area -eq 'Security' })
        ($rows | ForEach-Object { '{0}={1}' -f $_.Name, $_.Level }) -join '; ' | Should BeExactly 'Profile automation folder=Error; RetroBat hooks=Warn'
    }

    It 'a failing check does not stop the others' {
        Set-HealthyCabinet
        Mock -ModuleName RetroCabinetKit.Lightgun Get-LightgunDolphinBarState { throw 'PnP not available' }
        $rows = Get-Rows
        ($rows | Where-Object { $_.Name -eq 'DolphinBar' }).Detail | Should Match 'could not run: PnP not available'
        ($rows | Where-Object { $_.Name -eq 'ViGEmBus' }).Level | Should Be 'Ok'
    }
}
