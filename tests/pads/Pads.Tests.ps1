$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
# pads pulls core, lightgun and arcade (without -Force: one shared instance per package is what makes
# the cross-catalog exclusion read the SAME adapters the other two suites use).
Import-Module (Join-Path $kitRoot 'pads\RetroCabinetKit.Pads.psd1') -Force
$newRetroBat = Join-Path $kitRoot 'tests\lightgun\New-LightgunTestRetroBat.ps1'
$steps = Join-Path $kitRoot 'pads\steps'
$padAdapterDir = Join-Path $kitRoot 'pads\adapters'
$utf8 = New-Object Text.UTF8Encoding $false

# PnpDevice-shaped hashtables (InstanceId/Name/Class). Only ever fed in via -Devices: this file must
# never look at the machines' real device list, and never at a real RetroBat or Steam folder.
function New-PadTestDevice {
    param([string] $InstanceId, [string] $Name = '', [string] $Class = 'HIDClass')
    @{ InstanceId = $InstanceId; Name = $Name; Class = $Class }
}

# Write-KitLog goes into the core log file; capturing it is how "logged exactly once" is testable.
# The body's own pipeline output is dropped on purpose: a configuration function returns a change
# count, and that number would otherwise land in front of the log text.
function Use-PadLogFile {
    param([string] $Path, [scriptblock] $Body)
    Start-KitLog -Path $Path -NoTranscript
    try { $null = & $Body } finally { Stop-KitLog }
    if (Test-Path -LiteralPath $Path) { [IO.File]::ReadAllText($Path) } else { '' }
}

Describe 'Pad adapter catalog' {
    Set-KitCulture -Culture 'en-US'

    It 'ships five files and lists four complete adapters (the underscore template never appears)' {
        @(Get-ChildItem -LiteralPath $padAdapterDir -Filter '*.ps1' -File).Count | Should Be 5
        $cat = @(Get-PadAdapterCatalog)
        ($cat | ForEach-Object Name) -join ',' | Should Be 'EightBitDoPad,PlayStationPad,SwitchProPad,XboxPad'
        foreach ($a in $cat) {
            $a.HasParseErrors | Should Be $false
            $a.HasTest | Should Be $true
            $a.HasInfo | Should Be $true
            $a.HasInstall | Should Be $true
            $a.HasConfigure | Should Be $true
            $a.HasShield | Should Be $true
        }
    }

    It 'every adapter is class Gamepad and declares no write target outside [Controllers]' {
        foreach ($a in @(Get-PadAdapterCatalog)) {
            $i = Invoke-PadAdapterFunction -Name $a.Name -Function "Get-$($a.Name)AdapterInfo"
            [string](Get-PadAdapterValue $i 'Class') | Should Be 'Gamepad'
            @(Get-PadAdapterValue $i 'MatchIds').Count | Should BeGreaterThan 0
            # The class decision, as data: a pad that declares Steam entries or emulator tables would
            # re-open a write path this package deliberately does not have.
            @(Get-PadAdapterValue $i 'SteamEntries').Count | Should Be 0
            @(Get-PadAdapterValue $i 'MameValues').Count | Should Be 0
            @(Get-PadAdapterValue $i 'Model2Values').Count | Should Be 0
            @(Get-PadAdapterValue $i 'SupermodelValues').Count | Should Be 0
            (Get-PadAdapterValue $i 'ControllersValues')['Autocontrollers'] | Should Be '1'
        }
    }

    It 'parses clean as data and as script (no AST errors, manifest readable)' {
        $tokens = $null; $errors = $null
        foreach ($file in @(Get-ChildItem -LiteralPath $padAdapterDir -Filter '*.ps1' -File) +
                          @(Get-ChildItem -LiteralPath (Join-Path $kitRoot 'pads\modules') -Filter '*.ps1' -File) +
                          @((Join-Path $kitRoot 'pads\RetroCabinetKit.Pads.psm1'), (Join-Path $kitRoot 'pads\steps\01-Gamepads.ps1'))) {
            $path = if ($file.FullName) { $file.FullName } else { $file }
            $null = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
            @($errors).Count | Should Be 0
        }
        $m = Import-PowerShellDataFile (Join-Path $kitRoot 'pads\RetroCabinetKit.Pads.psd1')
        $m.ModuleVersion | Should Be '0.4.1'
        $m.RootModule | Should Be 'RetroCabinetKit.Pads.psm1'
        $m.FunctionsToExport | Should Be '*-Pad*'
        $m.GUID | Should Match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    }
}

Describe 'Device class rule: lightgun > arcade > pads' {
    Set-KitCulture -Culture 'en-US'
    # 045E:028E is the shared id of this whole problem: Xbox 360 pad, GP2040-CE board and 8BitDo X-mode.
    $gp2040    = New-PadTestDevice 'USB\VID_045E&PID_028E\7&GP2040BOARD&0&0' 'GP2040-CE USB Arcade Stick'
    $aimtrak   = New-PadTestDevice 'USB\VID_D209&PID_1602\0&0001' 'AimTrak Gun'
    $madcatz   = New-PadTestDevice 'USB\VID_0738&PID_4718\2&0002' 'Mad Catz FightStick TE'
    $receiver  = New-PadTestDevice 'USB\VID_045E&PID_0719\3&0003' 'Xbox 360 Wireless Receiver for Windows'
    $xboxPad   = New-PadTestDevice 'USB\VID_045E&PID_028E\6&11A3B2C1&0&0' 'Xbox 360 Wired Controller'
    $eightBit  = New-PadTestDevice 'USB\VID_2DC8&PID_3106\6&22A1B2C3&0&0' '8BitDo 2.4G Receiver'
    $btDs4     = New-PadTestDevice 'BTHENUM\{00001124-0000-1000-8000-00805F9B34FB}_VID&0002054C_PID&09CC\8&155D1B1&0&C0' 'Wireless Controller for Windows' 'Bluetooth'
    $bleSeries = New-PadTestDevice 'BTHLE\DEV_A4C138980A1D&0000' 'Xbox Wireless Controller' 'BluetoothLEDevices'

    It 'leaves a GP2040-CE board to arcade although it reports the Xbox pad id' {
        $r = Get-PadDetectedGamepad -Devices @($gp2040) -Quiet
        @($r.DetectedPads).Count | Should Be 0
        @($r.Excluded).Count | Should Be 1
        $r.Excluded[0].Class | Should Be 'Arcade'
        $r.Excluded[0].DeviceId | Should Be 'USB\VID_045E&PID_028E\7&GP2040BOARD&0&0'
    }

    It 'leaves an AimTrak to lightgun and a MadCatz stick plus the 360 receiver to arcade' {
        $r = Get-PadDetectedGamepad -Devices @($aimtrak, $madcatz, $receiver) -Quiet
        @($r.DetectedPads).Count | Should Be 0
        (($r.Excluded | ForEach-Object Class) -join ',') | Should Be 'Lightgun,Arcade,Arcade'
    }

    It 'logs every excluded device exactly once' {
        $log = Join-Path $TestDrive 'excluded.log'
        $text = Use-PadLogFile -Path $log -Body {
            $null = Get-PadDetectedGamepad -Devices @($gp2040, $aimtrak, $xboxPad)
        }
        @(([regex]::Matches($text, 'belongs to class'))).Count | Should Be 2
        ($text -split "`n" | Where-Object { $_ -match 'VID_D209' }).Count | Should Be 1
        ($text | Should Match 'class Arcade')
    }

    It 'detects a bare 045E:028E and an 8BitDo receiver as pads - pads are multiple by nature' {
        $r = Get-PadDetectedGamepad -Devices @($xboxPad, $eightBit) -Quiet
        @($r.DetectedPads).Count | Should Be 2
        (($r.DetectedPads | ForEach-Object Name) -join '+') | Should Be 'EightBitDoPad+XboxPad'
        (($r.DetectedPads | ForEach-Object Class) -join ',') | Should Be 'Gamepad,Gamepad'
        $r.Success | Should Be $true
        # NextStep is a pasteable command per family: the writer's parameter is -Name (singular, like
        # the guide shows it), so a hint such as "-Names (A+B)" would tell an agent to type something
        # that does not exist. Multi-detection stays visible because every family gets its own call.
        $r.NextStep | Should Be "Set-PadGamepadConfiguration -Name 'EightBitDoPad'; Set-PadGamepadConfiguration -Name 'XboxPad'"
    }

    It 'finds a paired DualShock 4 through the BTHENUM spelling of the same signature' {
        $r = Get-PadDetectedGamepad -Devices @($btDs4) -Quiet
        @($r.DetectedPads).Count | Should Be 1
        $r.DetectedPads[0].Name | Should Be 'PlayStationPad'
        $r.DetectedPads[0].DeviceId | Should Match 'VID&0002054C_PID&09CC'
    }

    It 'cannot see a Bluetooth-LE pad and says so instead of guessing (documented blind spot)' {
        # BTHLE\Dev_<mac> carries no VID/PID. adapters\README.md documents this as the v1 blind spot.
        $r = Get-PadDetectedGamepad -Devices @($bleSeries) -Quiet
        @($r.DetectedPads).Count | Should Be 0
        @($r.Excluded).Count | Should Be 0
        $r.Success | Should Be $true
    }

    It 'never reads the live PnP list when -Devices is bound' {
        # An unbound call is the only allowed live scan; a bound empty list must stay empty.
        Mock -ModuleName 'RetroCabinetKit.Pads' Get-PnpDevice { throw 'pad detection scanned the machine' }
        { Get-PadDetectedGamepad -Devices @($xboxPad) -Quiet } | Should Not Throw
        { Get-PadDetectedGamepad -Devices @() -Quiet } | Should Not Throw
        @((Get-PadDetectedGamepad -Devices @() -Quiet).DetectedPads).Count | Should Be 0
    }

    It 'reports quirks as codes in the result, and the BLE firmware quirk in prose from the shield' {
        $blePad = New-PadTestDevice 'USB\VID_045E&PID_0B13\9&BLE13&0&0' 'Xbox Wireless Controller' 'Bluetooth'
        $r = Get-PadDetectedGamepad -Devices @($blePad, $eightBit) -Quiet
        (($r.Quirks | ForEach-Object { $_ }) -join ',') | Should Match 'ble-0b13-firmware'
        # Adapter functions live in the module session, not in this one: Invoke-PadAdapterFunction is
        # the only sanctioned route into them (same rule as the arcade suite).
        $shield = { Invoke-PadAdapterFunction -Name 'XboxPad' -Function 'Set-XboxPadInterferenceShield' -Parameters @{ RetroBatRoot = ''; Devices = @($blePad) } }
        $text = Use-PadLogFile -Path (Join-Path $TestDrive 'quirks.log') -Body $shield
        ($text | Should Match 'BLE mode')
        $eightShield = { Invoke-PadAdapterFunction -Name 'EightBitDoPad' -Function 'Set-EightBitDoPadInterferenceShield' -Parameters @{ RetroBatRoot = ''; Devices = @($eightBit) } }
        $clean = Use-PadLogFile -Path (Join-Path $TestDrive 'clean.log') -Body $eightShield
        ($clean | Should Not Match 'BLE mode')
        # 8BitDo's masquerade is explained in its own file, with the vendor id it borrows.
        ($clean | Should Match 'PlayStation')
        ($clean | Should Match 'deliberately NOT')
    }
}

Describe 'Pad configuration writes only retrobat.ini [Controllers]' {
    Set-KitCulture -Culture 'en-US'
    # The dev machine runs Gunmote: every real writer would hit the process guard and throw.
    Mock -ModuleName 'RetroCabinetKit.Lightgun' Test-KitProcessesClosed { }
    $rb = Join-Path $TestDrive 'RetroBat'
    & $newRetroBat -Root $rb
    [IO.File]::WriteAllText((Join-Path $rb 'retrobat.ini'), "[Controllers]`r`nAutocontrollers=0`r`n", $utf8)

    It 'turns Autocontrollers on once, then changes nothing' {
        $ini = Join-Path $rb 'retrobat.ini'
        Set-PadGamepadConfiguration -Name 'XboxPad' -RetroBatRoot $rb -Confirm:$false | Should Be 1
        [IO.File]::ReadAllText($ini) | Should Match 'Autocontrollers\s*=\s*1'
        Set-PadGamepadConfiguration -Name 'XboxPad' -RetroBatRoot $rb -Confirm:$false | Should Be 0
        Test-PadGamepadConfiguration -Name 'XboxPad' -RetroBatRoot $rb | Should Be $true
    }

    It 'keeps the rest of the cabinet file intact while editing the section' {
        [IO.File]::WriteAllText((Join-Path $rb 'retrobat.ini'), "[Guns]`r`nEnableLightguns=1`r`n`r`n[Controllers]`r`nAutocontrollers=0`r`n", $utf8)
        Set-PadGamepadConfiguration -Name 'EightBitDoPad' -RetroBatRoot $rb -Confirm:$false | Should Be 1
        $text = [IO.File]::ReadAllText((Join-Path $rb 'retrobat.ini'))
        ($text | Should Match '\[Guns\]')
        ($text | Should Match 'EnableLightguns\s*=\s*1')
        ($text | Should Match 'Autocontrollers\s*=\s*1')
    }

    It 'warns and writes nothing when retrobat.ini is absent - the kit does not invent cabinet files' {
        $bare = Join-Path $TestDrive 'NoIniCabinet'
        & $newRetroBat -Root $bare
        $log = Join-Path $TestDrive 'noini.log'
        $text = Use-PadLogFile -Path $log -Body { Set-PadGamepadConfiguration -Name 'XboxPad' -RetroBatRoot $bare -Confirm:$false }
        ($text | Should Match 'retrobat.ini not found')
        (Join-Path $bare 'retrobat.ini') | Should Not Exist
        # "nothing to verify" counts as verified, so the step reports Skipped instead of Failed.
        Test-PadGamepadConfiguration -Name 'XboxPad' -RetroBatRoot $bare | Should Be $true
    }

    It 'gates on the detected list: a family that is not plugged in is never configured' {
        $detected = @((Get-PadDetectedGamepad -Devices @((New-PadTestDevice 'USB\VID_2DC8&PID_3106\6&1' '8BitDo Pad')) -Quiet).DetectedPads)
        @($detected).Count | Should Be 1
        $ini = Join-Path $rb 'retrobat.ini'
        [IO.File]::WriteAllText($ini, "[Controllers]`r`nAutocontrollers=0`r`n", $utf8)
        # Configure-<Name>Profile is an adapter function: reachable through the sanctioned route only.
        Invoke-PadAdapterFunction -Name 'XboxPad' -Function 'Configure-XboxPadProfile' -Parameters @{ RetroBatRoot = $rb; DetectedPads = $detected } | Should Be 0
        Invoke-PadAdapterFunction -Name 'EightBitDoPad' -Function 'Configure-EightBitDoPadProfile' -Parameters @{ RetroBatRoot = $rb; DetectedPads = $detected } | Should Be 1
        [IO.File]::ReadAllText((Join-Path $rb 'retrobat.ini')) | Should Match 'Autocontrollers\s*=\s*1'
        [IO.File]::WriteAllText((Join-Path $rb 'retrobat.ini'), "[Controllers]`r`nAutocontrollers=0`r`n", $utf8)
        # Same adapter, now absent from the list: zero changes, and the cabinet file stays dirty.
        Invoke-PadAdapterFunction -Name 'EightBitDoPad' -Function 'Configure-EightBitDoPadProfile' -Parameters @{ RetroBatRoot = $rb; DetectedPads = @() } | Should Be 0
        [IO.File]::ReadAllText((Join-Path $rb 'retrobat.ini')) | Should Match 'Autocontrollers=0'
    }

    It 'installs nothing without a package and nothing without -Approved' {
        Install-PadAdapter -Name 'XboxPad' -RetroBatRoot $rb -Confirm:$false | Should Be $false
        Test-Path (Join-Path $rb 'tools') | Should Be $false
        $src = Join-Path $TestDrive 'payload'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $src 'firmware.bin'), 'fake')
        $zip = Join-Path $TestDrive 'pad.zip'
        Compress-Archive -Path (Join-Path $src 'firmware.bin') -DestinationPath $zip -Force
        Install-PadAdapter -Name 'EightBitDoPad' -RetroBatRoot $rb -PackagePath $zip -Confirm:$false | Should Be $false
        Test-Path (Join-Path $rb 'tools\8BitDo') | Should Be $false
        # No pad family declares a tool folder in v1, so even an approved ZIP stays out of tools\.
        Install-PadAdapter -Name 'EightBitDoPad' -RetroBatRoot $rb -PackagePath $zip -Approved -Confirm:$false | Should Be $false
        Test-Path (Join-Path $rb 'tools') | Should Be $false
    }

    It 'never reaches Steam: no backup, no blacklist entry, no Steam writer in these files' {
        $fakeSteam = Join-Path $TestDrive 'FakeSteam'
        & (Join-Path $kitRoot 'tests\lightgun\New-LightgunTestGunmote.ps1') -Gunmote (Join-Path $TestDrive 'Gunmote') -Steam $fakeSteam
        $vdf = Join-Path $fakeSteam 'config\config.vdf'
        $steamMock = ({ $fakeSteam }.GetNewClosure())
        # The fallback resolves inside whichever session asks; Pester patches per session, so both
        # Lightgun and Pads must be mocked or a real registry lookup could answer.
        Mock -ModuleName 'RetroCabinetKit.Lightgun' Get-LightgunSteamPath $steamMock
        Mock -ModuleName 'RetroCabinetKit.Pads' Get-LightgunSteamPath $steamMock
        [IO.File]::WriteAllText((Join-Path $rb 'retrobat.ini'), "[Controllers]`r`nAutocontrollers=0`r`n", $utf8)
        Set-PadGamepadConfiguration -Name 'XboxPad' -RetroBatRoot $rb -Confirm:$false | Should Be 1
        @(Get-ChildItem (Join-Path $fakeSteam 'config') -Filter '*.bak_lightgun*').Count | Should Be 0
        # The synthetic config.vdf ships with one unrelated blacklist entry; a pad run must leave it
        # exactly as it found it - no new vendor id, no rewrite, therefore no backup file either.
        $vdfText = [IO.File]::ReadAllText($vdf)
        ($vdfText | Should Match '0x1234/0x5678')
        ($vdfText | Should Not Match '0x045e')
        ($vdfText | Should Not Match '0x2dc8')
        ($vdfText | Should Not Match '0x054c')
        ($vdfText | Should Not Match '0x057e')
        # Static half of the guard: this package must not even contain the Steam writer or a kill.
        $sources = @(Get-ChildItem -LiteralPath (Join-Path $kitRoot 'pads') -Recurse -Include '*.ps1', '*.psm1', '*.psd1' -File)
        foreach ($f in $sources) {
            $code = [IO.File]::ReadAllText($f.FullName)
            ($code | Should Not Match 'SteamBlacklist')
            ($code | Should Not Match 'Stop-Process')
            ($code | Should Not Match 'Invoke-WebRequest')
            ($code | Should Not Match 'Set-ItemProperty')
        }
    }
}

Describe 'Broken pad adapters are reported, never executed' {
    Set-KitCulture -Culture 'en-US'
    $dir = Join-Path $TestDrive 'brokenAdapters'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $dir 'NoTest.ps1'), 'function Get-NoTestAdapterInfo { @{ Class = "Gamepad" } }', $utf8)
    [IO.File]::WriteAllText((Join-Path $dir 'Boom.ps1'), "function Test-BoomHardware { param(`$RetroBatRoot, `$Devices) `$true }`nfunction Get-BoomAdapterInfo { throw 'usb stack exploded' }", $utf8)

    It 'refuses an unknown adapter and a missing function by name' {
        { Invoke-PadAdapterFunction -Name 'DoesNotExist' -Function 'Get-DoesNotExistAdapterInfo' } | Should Throw 'No pad adapter DoesNotExist found'
        { Invoke-PadAdapterFunction -Name 'NoTest' -Function 'Configure-NoTestProfile' -Dir $dir } | Should Throw 'lacks function'
        { Invoke-PadAdapterFunction -Name '..\core' -Function 'Get-KitCulture' } | Should Throw 'No pad adapter'
    }

    It 'lists an incomplete adapter as an error instead of pretending the scan was clean' {
        $r = Get-PadDetectedGamepad -Devices @() -Dir $dir -Quiet
        $r.Success | Should Be $false
        @($r.DetectedPads).Count | Should Be 0
        ($r.ScannedAdapters -join ',') | Should Be 'Boom'
        @($r.Errors).Count | Should Be 2
        ($r.Errors -join ';') | Should Match 'incomplete'
        $r.NextStep | Should Be ''
    }

    It 'unpacks an approved local ZIP where a family does declare a tool folder' {
        # No shipped pad family has a portable tool in v1 (all four declare ToolDir = ''), so the one
        # audited package route is exercised with a synthetic adapter - the ZIP branch is real code and
        # must not rest untested.
        $src = Join-Path $TestDrive 'toolAdapter'
        New-Item -ItemType Directory -Path $src -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $src 'SyntheticPad.ps1'), (@'
function Test-SyntheticPadHardware { [CmdletBinding()] param([string] $RetroBatRoot, [object[]] $Devices) $false }
function Get-SyntheticPadAdapterInfo { @{ Class = 'Gamepad'; ToolDir = 'SyntheticTool'; MatchIds = @('USB\VID_9999&PID_0001*'); NameHints = @(); Quirks = @(); SteamEntries = @(); MameValues = @(); ControllersValues = @{ Autocontrollers = '1' }; Model2Values = @(); SupermodelValues = @(); Links = @{ 'Synthetic' = 'https://example.invalid/tool' }; Notes = 'test fixture' } }
'@), $utf8)
        $payload = Join-Path $TestDrive 'toolpayload'
        New-Item -ItemType Directory -Path $payload -Force | Out-Null
        [IO.File]::WriteAllText((Join-Path $payload 'tool.exe'), 'fake')
        $zip = Join-Path $TestDrive 'synthetic.zip'
        Compress-Archive -Path (Join-Path $payload 'tool.exe') -DestinationPath $zip -Force
        $root = Join-Path $TestDrive 'ToolRetroBat'
        Install-PadAdapterPackage -Name 'SyntheticPad' -RetroBatRoot $root -PackagePath $zip -Dir $src -Confirm:$false | Should Be $false
        Test-Path (Join-Path $root 'tools\SyntheticTool') | Should Be $false
        Install-PadAdapterPackage -Name 'SyntheticPad' -RetroBatRoot $root -PackagePath $zip -Dir $src -Approved -Confirm:$false | Should Be $true
        Join-Path $root 'tools\SyntheticTool\tool.exe' | Should Exist
        # Without a package the route only names the source, and writes nothing at all.
        Install-PadAdapterPackage -Name 'SyntheticPad' -RetroBatRoot $root -Dir $src -Confirm:$false | Should Be $false
    }
}

Describe 'Step pads-1-gamepad as stand-alone script' {
    Set-KitCulture -Culture 'en-US'
    Mock -ModuleName 'RetroCabinetKit.Lightgun' Test-KitProcessesClosed { }
    $rb = Join-Path $TestDrive 'RetroBat'
    & $newRetroBat -Root $rb
    [IO.File]::WriteAllText((Join-Path $rb 'retrobat.ini'), "[Controllers]`r`nAutocontrollers=0`r`n", $utf8)
    $state = Join-Path $TestDrive 'install-state.json'
    $common = @{ StatePath = $state; Culture = 'en-US' }
    Set-KitStateValue -Path $state -Key 'RetroBatRoot' -Value $rb
    $xboxPad  = New-PadTestDevice 'USB\VID_045E&PID_028E\6&11A3B2C1&0&0' 'Xbox 360 Wired Controller'
    $gp2040   = New-PadTestDevice 'USB\VID_045E&PID_028E\7&GP2040BOARD&0&0' 'GP2040-CE USB Arcade Stick'
    $stepPath = Join-Path $steps '01-Gamepads.ps1'

    It 'takes the documented parameters and no Steam parameter' {
        $p = (Get-Command $stepPath).Parameters.Keys
        foreach ($needed in 'RetroBatRoot', 'Devices', 'Install', 'Name', 'PackagePath', 'Approved', 'StatePath', 'Culture') {
            (@($p) -contains $needed) | Should Be $true
        }
        (@($p) -contains 'SteamConfigVdf') | Should Be $false
    }

    It 'dry run: both steps Skipped, nothing persisted, cabinet file untouched' {
        $before = [IO.File]::ReadAllText((Join-Path $rb 'retrobat.ini'))
        $r = @(& $stepPath @common -Devices @($xboxPad) -WhatIf)
        ($r | ForEach-Object { $_.Status }) -join ',' | Should Be 'Skipped,Skipped'
        Get-KitStateValue -Path $state -Key 'PadsDetected' | Should BeNullOrEmpty
        [IO.File]::ReadAllText((Join-Path $rb 'retrobat.ini')) | Should BeExactly $before
    }

    It 'reports NeedsUser without pads and stores None' {
        $r = @(& $stepPath @common -Devices @($gp2040))
        ($r | ForEach-Object { "$($_.Name)=$($_.Status)" }) -join ',' | Should Be 'pads-1-gamepad-detect=Done,pads-1-gamepad-configure=NeedsUser'
        Get-KitStateValue -Path $state -Key 'PadsDetected' | Should Be 'None'
        Get-KitStateValue -Path $state -Key 'PadsExcluded' | Should Be 1
        [IO.File]::ReadAllText((Join-Path $rb 'retrobat.ini')) | Should Match 'Autocontrollers=0'
    }

    It 'detects the pad, configures it, and skips on the second run' {
        $r = @(& $stepPath @common -Devices @($xboxPad))
        ($r | ForEach-Object { "$($_.Name)=$($_.Status)" }) -join ',' | Should Be 'pads-1-gamepad-detect=Done,pads-1-gamepad-configure=Done'
        Get-KitStateValue -Path $state -Key 'PadsDetected' | Should Be 'XboxPad'
        [IO.File]::ReadAllText((Join-Path $rb 'retrobat.ini')) | Should Match 'Autocontrollers\s*=\s*1'
        $r = @(& $stepPath @common -Devices @($xboxPad))
        ($r | ForEach-Object { $_.Status }) -join ',' | Should Be 'Skipped,Skipped'
        Get-KitStepStatus -Path $state -Name 'pads-1-gamepad-configure' | Should Be 'Skipped'
    }

    It 'names every pad family it found in one state value (multi-player cabinet)' {
        # Dirty start: three families share the one [Controllers] key, so only the first may change it.
        [IO.File]::WriteAllText((Join-Path $rb 'retrobat.ini'), "[Controllers]`r`nAutocontrollers=0`r`n", $utf8)
        $multi = @($xboxPad, (New-PadTestDevice 'USB\VID_2DC8&PID_3106\6&2' '8BitDo Ultimate'),
                   (New-PadTestDevice 'HID\VID_057E&PID_2009&MI_00\7&3' 'Pro Controller'))
        $r = @(& $stepPath @common -Devices $multi)
        Get-KitStateValue -Path $state -Key 'PadsDetected' | Should Be 'EightBitDoPad+SwitchProPad+XboxPad'
        ($r | ForEach-Object { $_.Status }) -join ',' | Should Be 'Done,Done'
        [IO.File]::ReadAllText((Join-Path $rb 'retrobat.ini')) | Should Match 'Autocontrollers\s*=\s*1'
    }

    It 'reads the RetroBat root from the lightgun state when its own state is empty' {
        $ownState = Join-Path $TestDrive 'pads-state.json'
        $lightgunState = Join-Path $TestDrive 'gun-state.json'
        Set-KitStateValue -Path $lightgunState -Key 'RetroBatRoot' -Value $rb
        # One cabinet, one RetroBat: the fallback reads the LIGHTGUN state file, so that path is what a
        # test has to redirect - inside the Pads session, where the fallback is resolved.
        Mock -ModuleName 'RetroCabinetKit.Pads' Get-LightgunDefaultStatePath ({ $lightgunState }.GetNewClosure())
        Get-PadRetroBatRoot -StatePath $ownState | Should Be $rb
        Set-KitStateValue -Path $ownState -Key 'RetroBatRoot' -Value 'X:\OwnPadsCabinet'
        Get-PadRetroBatRoot -StatePath $ownState | Should Be 'X:\OwnPadsCabinet'
    }
}
