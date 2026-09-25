$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1') -Force

# Only the command plan and the verification are tested; nothing is registered.
$testKey = 'HKCU:\Software\retro-cabinet-kit-test-pinball-com'
$classes = "$testKey\Classes"
# Default values (empty name) are set with Set-Item; New-ItemProperty refuses an empty name.
function Set-Default([string] $Path, [string] $Value) { if (-not (Test-Path -LiteralPath $Path)) { New-Item -Path $Path -Force | Out-Null }; Set-Item -LiteralPath $Path -Value $Value }

Describe 'Register plan (step 6)' {
    $plan = @(Get-PinballRegisterPlan -Root 'E:\Games' -WindowsDir 'C:\Windows')

    It 'keeps the proven order' {
        ($plan | ForEach-Object { $_.Title }) -join ' | ' | Should BeExactly (
            'VPinMAME 64-bit | VPinMAME 32-bit | B2S Server 32-bit | B2S Server 64-bit | FlexDMD 32-bit | FlexDMD 64-bit | ' +
            'FlexUDMD 32-bit | FlexUDMD 64-bit | PUPDMDControl | PuP DllSurrogate | ForegroundLockTimeout 0 | ' +
            'PinUpDOF.exe | PuPServer.exe | PinUpPlayer.exe | PinUpMenuSetup -setfolders')
    }

    It 'uses regsvr32 64/32 and RegAsm /codebase instead of the RegisterApp GUI' {
        $plan[0].FilePath | Should BeExactly 'C:\Windows\System32\regsvr32.exe'
        $plan[0].Arguments | Should BeExactly '/s "E:\Games\vPinball\VisualPinball\VPinMAME\VPinMAME64.dll"'
        $plan[1].FilePath | Should BeExactly 'C:\Windows\SysWOW64\regsvr32.exe'
        $plan[2].FilePath | Should BeExactly 'C:\Windows\Microsoft.NET\Framework\v4.0.30319\RegAsm.exe'
        $plan[2].Arguments | Should BeExactly '"E:\Games\vPinball\VisualPinball\Tables\B2SBackglassServer.dll" /codebase /silent'
        $plan[3].FilePath | Should BeExactly 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\RegAsm.exe'
        @($plan | Where-Object { $_.FilePath -like '*RegisterApp*' -or $_.FilePath -like '*FlexDMDUI*' }).Count | Should Be 0
        ($plan | Where-Object { $_.Title -like 'FlexUDMD*' } | ForEach-Object { $_.Optional }) -join ',' | Should Be 'True,True'
    }

    It 'registers the Popper servers in their own folder' {
        $p = $plan | Where-Object { $_.Title -eq 'PinUpPlayer.exe' }
        $p.Arguments | Should BeExactly '/regserver'
        $p.WorkingDirectory | Should BeExactly 'E:\Games\vPinball\PinUPSystem'
        ($plan | Where-Object { $_.Title -eq 'PUPDMDControl' }).WorkingDirectory | Should BeExactly 'E:\Games\vPinball\VisualPinball\VPinMAME'
        $plan[-1].Arguments | Should BeExactly '-setfolders'
    }

    It 'sets the DllSurrogate as an empty string through the registry cmdlet' {
        $s = $plan | Where-Object { $_.Title -eq 'PuP DllSurrogate' }
        $s.Kind | Should Be 'Registry'
        $v = $s.Values | Where-Object { $_.Name -eq 'DllSurrogate' }
        $v.Value | Should BeExactly ''
        $v.Path | Should BeExactly 'Registry::HKEY_CLASSES_ROOT\WOW6432Node\AppID\{88919FAC-00B2-4AA8-B1C7-52AD65C476D3}'
    }

    It 'runs batch files with stdin from nul in their own folder' {
        $c = Get-PinballBatCommand -Path 'E:\Games\vPinball\Installer\Pu P Register.bat'
        $c.FilePath | Should BeExactly (Join-Path $env:SystemRoot 'System32\cmd.exe')
        $c.Arguments | Should BeExactly '/c ""E:\Games\vPinball\Installer\Pu P Register.bat" < nul"'
        $c.WorkingDirectory | Should BeExactly 'E:\Games\vPinball\Installer'
    }

    It 'reports missing files and registers nothing under -WhatIf' {
        Mock -ModuleName 'RetroCabinetKit.Pinball' Start-Process { throw 'must not start' }
        Mock -ModuleName 'RetroCabinetKit.Pinball' Set-KitRegistryValue { throw 'must not write' }
        $rows = @(Invoke-PinballRegisterPlan -Root $TestDrive -Plan (Get-PinballRegisterPlan -Root $TestDrive) -WhatIf)
        ($rows | Where-Object { $_.Title -eq 'VPinMAME 64-bit' }).Result | Should Be 'Missing'
        ($rows | Where-Object { $_.Title -eq 'FlexUDMD 32-bit' }).Result | Should Be 'NotPresent'
        ($rows | Where-Object { $_.Title -eq 'PuP DllSurrogate' }).Result | Should Be 'Skipped'
        Assert-MockCalled -ModuleName 'RetroCabinetKit.Pinball' Start-Process -Times 0
    }
}

Describe 'Register plan confirmation and unblocking (nothing is registered)' {
    Set-KitCulture -Culture 'en-US'
    $dir = Join-Path $TestDrive 'Build'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $inPlan = Join-Path $dir 'InPlan.dll'
    $other = Join-Path $dir 'Other.dll'
    function New-Blocked([string] $Path) { [IO.File]::WriteAllBytes($Path, [byte[]](1, 2, 3)); Set-Content -LiteralPath $Path -Stream 'Zone.Identifier' -Value "[ZoneTransfer]`r`nZoneId=3" }
    function Test-Blocked([string] $Path) { [bool](Get-Item -LiteralPath $Path -Stream * | Where-Object { $_.Stream -eq 'Zone.Identifier' }) }
    New-Blocked $inPlan
    New-Blocked $other
    $plan = @([pscustomobject]@{ Title = 'Test DLL'; Kind = 'Process'; FilePath = (Join-Path $env:SystemRoot 'System32\regsvr32.exe'); Arguments = "/s `"$inPlan`""
                                 WorkingDirectory = $dir; Requires = $inPlan; Optional = $false })

    It 'shows path and SHA256 of the build file and registers nothing when declined' {
        Mock -ModuleName 'RetroCabinetKit.Pinball' Start-Process { throw 'must not start' }
        $script:shown = $null
        { Invoke-PinballRegisterPlan -Root $TestDrive -Plan $plan -Approve { param($t) $script:shown = $t; $false } } | Should Throw
        $script:shown | Should Match ([regex]::Escape($inPlan))
        $script:shown | Should Match (Get-FileHash -LiteralPath $inPlan -Algorithm SHA256).Hash
        $script:shown | Should Match 'signature: \w+'
        Test-Blocked $inPlan | Should Be $true
        Assert-MockCalled -ModuleName 'RetroCabinetKit.Pinball' Start-Process -Times 0
    }

    It 'after confirmation unblocks only the files of the plan' {
        Mock -ModuleName 'RetroCabinetKit.Pinball' Start-Process { [pscustomobject]@{ ExitCode = 0 } }
        $rows = @(Invoke-PinballRegisterPlan -Root $TestDrive -Plan $plan -Approve { $true })
        $rows[0].Result | Should Be 'Ok'
        Test-Blocked $inPlan | Should Be $false
        Test-Blocked $other | Should Be $true
        Assert-MockCalled -ModuleName 'RetroCabinetKit.Pinball' Start-Process -Times 1
    }

    It 'holds the confirmed file read-only while the registration runs, and refuses a changed one (N5)' {
        $global:RckProbe = $null
        Mock -ModuleName 'RetroCabinetKit.Pinball' Start-Process {
            $w = $true
            try { [IO.File]::Open($inPlan, 'Open', 'ReadWrite', 'ReadWrite').Dispose() } catch { $w = $false }
            $global:RckProbe = $w
            [pscustomobject]@{ ExitCode = 0 }
        }
        (@(Invoke-PinballRegisterPlan -Root $TestDrive -Plan $plan -Approve { $true }))[0].Result | Should Be 'Ok'
        $global:RckProbe | Should Be $false
        # Changed between confirmation and start: nothing runs.
        $rows = @(Invoke-PinballRegisterPlan -Root $TestDrive -Plan $plan -Approve { [IO.File]::WriteAllBytes($inPlan, [byte[]](9)); $true })
        $rows[0].Result | Should Be 'Failed'
        Assert-MockCalled -ModuleName 'RetroCabinetKit.Pinball' Start-Process -Times 1 -Exactly -Scope It
        Remove-Variable -Name RckProbe -Scope Global
    }
}

Describe 'Folder rights of the build (analysis on a TEMP folder only)' {
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().User
    function New-AclFolder([string] $Name, [hashtable] $Extra = @{}) {
        $d = Join-Path $TestDrive $Name
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        $acl = New-Object Security.AccessControl.DirectorySecurity
        $acl.SetAccessRuleProtection($true, $false)
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule ($me, 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow')))
        foreach ($sid in $Extra.Keys) {
            $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule ((New-Object Security.Principal.SecurityIdentifier $sid), $Extra[$sid], 'ContainerInherit, ObjectInherit', 'None', 'Allow')))
        }
        (Get-Item -LiteralPath $d).SetAccessControl($acl)
        $d
    }

    It 'finds no risk when only the owner has access and when Users may only read' {
        @(Get-PinballFolderAclRisk -Path (New-AclFolder 'own')).Count | Should Be 0
        @(Get-PinballFolderAclRisk -Path (New-AclFolder 'read' @{ 'S-1-5-32-545' = 'ReadAndExecute'; 'S-1-5-11' = 'Read' })).Count | Should Be 0
    }

    It 'warns about Everyone, Users and Authenticated Users with write or modify rights' {
        $r = @(Get-PinballFolderAclRisk -Path (New-AclFolder 'open' @{ 'S-1-1-0' = 'Modify'; 'S-1-5-32-545' = 'Write'; 'S-1-5-11' = 'AppendData' }))
        ($r | ForEach-Object { $_.Sid } | Sort-Object) -join ',' | Should Be 'S-1-1-0,S-1-5-11,S-1-5-32-545'
    }

    It 'reports a FAT/exFAT drive as a risk: it has no rights at all (N9)' {
        Set-KitCulture -Culture 'en-US'
        foreach ($fs in 'FAT32', 'exFAT') {
            $r = @(Get-PinballFolderAclRisk -Path (New-AclFolder 'own') -FileSystem $fs)
            $r.Count | Should Be 1
            $r[0].Sid | Should Be 'S-1-1-0'
            $r[0].Name | Should Match $fs
        }
        @(Get-PinballFolderAclRisk -Path (New-AclFolder 'own') -FileSystem 'NTFS').Count | Should Be 0
    }

    It 'accepts an Entra ID account SID (S-1-12-1-...) for the hardening' {
        (Get-PinballHardeningArgument -Path 'E:\x' -UserSid 'S-1-12-1-1111111111-2222222222-3333333333-4444444444') -join ' ' | Should Match '\*S-1-12-1-1111111111-2222222222-3333333333-4444444444:\(OI\)\(CI\)M'
        { Get-PinballHardeningArgument -Path 'E:\x' -UserSid 'S-1-12-2-1-2-3-4' } | Should Throw
    }

    It 'builds the icacls hardening command and refuses anything but a user SID' {
        $sid = $me.Value
        (Get-PinballHardeningArgument -Path 'E:\Games\vPinball' -UserSid $sid) -join ' ' |
            Should BeExactly "E:\Games\vPinball /inheritance:r /grant:r *S-1-5-32-544:(OI)(CI)F *S-1-5-18:(OI)(CI)F *${sid}:(OI)(CI)M *S-1-5-32-545:(OI)(CI)RX /C /Q"
        { Get-PinballHardeningArgument -Path 'E:\x' -UserSid 'S-1-1-0' } | Should Throw
        { Get-PinballHardeningArgument -Path 'E:\x' -UserSid "$sid /grant *S-1-1-0:F" } | Should Throw
    }

    It 'hardens only as administrator on a real build, never without asking' {
        # Without administrator rights (or, elevated, without a build) it stops before asking or running icacls.
        Set-KitCulture -Culture 'en-US'
        { Protect-PinballBuildFolder -Root (Join-Path $TestDrive 'NoBuild') -UserSid $me.Value -Approve { throw 'must not ask' } } |
            Should Throw $(if (Test-KitAdmin) { 'No build found' } else { 'administrator rights' })
    }
}

Describe 'COM verification against a test classes key' {
    BeforeAll {
        if (Test-Path -LiteralPath $testKey) { Remove-Item -LiteralPath $testKey -Recurse -Force }
        $ids = @{ 'VPinMAME.Controller' = '{00000000-0000-0000-0000-00000000000A}'; 'B2S.Server' = '{00000000-0000-0000-0000-00000000000B}'
                  'FlexDMD.FlexDMD' = '{00000000-0000-0000-0000-00000000000C}'; 'PinUpPlayer.PinUpPlayerX' = '{00000000-0000-0000-0000-00000000000D}' }
        foreach ($p in $ids.Keys) { Set-Default "$classes\$p\CLSID" $ids[$p] }
        Set-Default "$classes\CLSID\$($ids['VPinMAME.Controller'])\InprocServer32" 'E:\Games\vPinball\VisualPinball\VPinMAME\VPinMAME64.dll'
        Set-Default "$classes\WOW6432Node\CLSID\$($ids['B2S.Server'])\InprocServer32" 'mscoree.dll'
        Set-KitRegistryValue -Path "$classes\WOW6432Node\CLSID\$($ids['B2S.Server'])\InprocServer32" -Name 'CodeBase' -Value 'file:///E:/Games/vPinball/VisualPinball/Tables/B2SBackglassServer.dll'
        Set-KitRegistryValue -Path "$classes\CLSID\$($ids['FlexDMD.FlexDMD'])\InprocServer32" -Name 'CodeBase' -Value 'file:///D:/Old/vPinball/VisualPinball/VPinMAME/FlexDMD.dll'
        Set-Default "$classes\CLSID\$($ids['PinUpPlayer.PinUpPlayerX'])\LocalServer32" '"E:\Games\vPinball\PinUPSystem\PinUpPlayer.exe" /automation'
        Set-KitRegistryValue -Path "$classes\WOW6432Node\AppID\{88919FAC-00B2-4AA8-B1C7-52AD65C476D3}" -Name 'DllSurrogate' -Value ''
    }
    AfterAll { if (Test-Path -LiteralPath $testKey) { Remove-Item -LiteralPath $testKey -Recurse -Force } }

    It 'accepts servers below the new root and flags one still pointing to the old root' {
        $r = @(Test-PinballComRegistration -Root 'E:\Games' -ClassesRoot $classes)
        ($r | Where-Object { $_.Ok } | ForEach-Object { $_.Name }) -join ',' | Should Be 'VPinMAME.Controller,B2S.Server,PinUpPlayer.PinUpPlayerX,PuP DllSurrogate'
        $flex = $r | Where-Object { $_.Name -eq 'FlexDMD.FlexDMD' }
        $flex.Ok | Should Be $false
        $flex.Paths[0] | Should BeExactly 'D:\Old\vPinball\VisualPinball\VPinMAME\FlexDMD.dll'
        ($r | Where-Object { $_.Name -eq 'PinUpPlayer.PinUpPlayerX' }).Paths[0] | Should BeExactly 'E:\Games\vPinball\PinUPSystem\PinUpPlayer.exe'
    }
}
