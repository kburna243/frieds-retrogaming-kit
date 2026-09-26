$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1') -Force

# Build check, prerequisites, COM registration and ACLs are mocked; the doctor only reads.
Describe 'Pinball doctor' {
    Set-KitCulture -Culture 'en-US'
    $state = Join-Path $TestDrive 'install-state.json'
    Set-KitStateValue -Path $state -Key 'SourceRoot' -Value 'E:\Old Build'
    Set-KitStateValue -Path $state -Key 'TargetRoot' -Value 'D:\Pinball'

    function Set-HealthyBuild {
        Mock -ModuleName RetroCabinetKit.Pinball Get-PinballRootProblem { $null }
        Mock -ModuleName RetroCabinetKit.Pinball Get-PinballDependencyStatus {
            [pscustomobject]@{ Id = 'VC'; Name = 'Visual C++ 2015-2022 x64'; Present = $true; Detail = '' }
            [pscustomobject]@{ Id = 'NetFx35'; Name = '.NET Framework 3.5'; Present = $true; Detail = '' }
        }
        Mock -ModuleName RetroCabinetKit.Pinball Test-PinballComRegistration { [pscustomobject]@{ Name = 'VPinMAME.Controller'; Paths = @(); Ok = $true } }
        Mock -ModuleName RetroCabinetKit.Pinball Get-PinballFolderAclRisk { }
    }
    function Get-Rows([string] $StatePath = $state) { @(Invoke-KitDoctor -Check @(Get-PinballDoctorCheck -StatePath $StatePath)) }

    It 'a healthy build is green and uses the target root' {
        Set-HealthyBuild
        $rows = Get-Rows
        @($rows | Where-Object { $_.Level -in 'Warn', 'Error' }).Count | Should Be 0
        ($rows | Where-Object { $_.Name -eq 'Build' }).Detail | Should BeExactly 'D:\Pinball'
        ($rows | Where-Object { $_.Name -eq 'Rights on the build folder' }).Area | Should Be 'Security'
    }

    It 'without state everything is information' {
        Set-HealthyBuild
        Mock -ModuleName RetroCabinetKit.Pinball Get-PinballDependencyStatus { [pscustomobject]@{ Id = 'NetFx35'; Name = '.NET Framework 3.5'; Present = $false; Detail = '' } }
        $rows = Get-Rows -StatePath (Join-Path $TestDrive 'never.json')
        @($rows | Where-Object { $_.Level -ne 'Info' }).Count | Should Be 0
    }

    It 'a missing prerequisite is a warning; a broken build folder an error' {
        Set-HealthyBuild
        Mock -ModuleName RetroCabinetKit.Pinball Get-PinballDependencyStatus { [pscustomobject]@{ Id = 'NetFx35'; Name = '.NET Framework 3.5'; Present = $false; Detail = '' } }
        Mock -ModuleName RetroCabinetKit.Pinball Get-PinballRootProblem { 'The build database is missing.' }
        $rows = Get-Rows
        ($rows | Where-Object { $_.Name -eq 'Prerequisites' }).Detail | Should BeExactly 'Missing: .NET Framework 3.5 (step 3).'
        ($rows | Where-Object { $_.Name -eq 'Build' }).Level | Should Be 'Error'
        ($rows | Where-Object { $_.Name -eq 'COM registration' }).Level | Should Be 'Info'
    }

    It 'COM pointing elsewhere is an error only after step 6 ran' {
        Set-HealthyBuild
        Mock -ModuleName RetroCabinetKit.Pinball Test-PinballComRegistration { [pscustomobject]@{ Name = 'B2S.Server'; Paths = @('E:\Old Build\x.dll'); Ok = $false } }
        ($(Get-Rows) | Where-Object { $_.Name -eq 'COM registration' }).Level | Should Be 'Info'
        Set-KitStepStatus -Path $state -Name 'pinball-6-register' -Status Done -Message 'ok'
        $com = Get-Rows | Where-Object { $_.Name -eq 'COM registration' }
        $com.Level | Should Be 'Error'
        $com.Detail | Should Match 'B2S.Server'
    }

    It 'broad write rights on the build folder are a security warning' {
        Set-HealthyBuild
        Mock -ModuleName RetroCabinetKit.Pinball Get-PinballFolderAclRisk { [pscustomobject]@{ Path = 'D:\Pinball'; Sid = 'S-1-5-11'; Name = 'Authenticated Users'; Rights = 'Modify'; Inherited = $true } }
        $acl = Get-Rows | Where-Object { $_.Name -eq 'Rights on the build folder' }
        $acl.Level | Should Be 'Warn'
        $acl.Detail | Should Match 'Authenticated Users'
    }
}
