$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force

# No real download happens in these tests.
Describe 'Download allow list' {
    It 'loads the configured hosts: only Microsoft as whole hosts, GitHub never as a whole host' {
        @(Get-KitAllowedHost) -contains 'aka.ms' | Should Be $true
        @(Get-KitAllowedHost | Where-Object { $_ -match 'github' }).Count | Should Be 0
        Test-KitDownloadUrl 'https://github.com/nefarius/ViGEmBus/releases' | Should Be $false
        Test-KitDownloadUrl 'https://objects.githubusercontent.com/x' | Should Be $false
    }

    It 'allows exactly the ViGEmBus release folder on GitHub, nothing else there' {
        Test-KitDownloadUrl 'https://github.com/nefarius/ViGEmBus/releases/download/v1.22.0/ViGEmBus_1.22.0_x64_x86_arm64.exe' | Should Be $true
        Test-KitDownloadUrl 'https://github.com/nefarius/ViGEmBus/releases/download/../../../evil/x/releases/download/a.exe' | Should Be $false
        Test-KitDownloadUrl 'https://github.com/nefarius/ViGEmBus/releases/download/%2e%2e/%2e%2e/x.exe' | Should Be $false
        Test-KitDownloadUrl 'https://github.com/nefarius/ViGEmBusEvil/releases/download/x.exe' | Should Be $false
        Test-KitDownloadUrl 'https://github.com@evil.example/nefarius/ViGEmBus/releases/download/x.exe' | Should Be $false
        Test-KitDownloadUrl 'https://github.com:8443/nefarius/ViGEmBus/releases/download/x.exe' | Should Be $false
        Test-KitDownloadUrl 'http://github.com/nefarius/ViGEmBus/releases/download/x.exe' | Should Be $false
        Test-KitDownloadUrl 'https://github.com/someone/else/releases/download/x.exe' | Should Be $false
    }

    It 'accepts HTTPS URLs on allowed hosts' {
        Test-KitDownloadUrl 'https://aka.ms/vs/17/release/vc_redist.x64.exe' | Should Be $true
        Test-KitDownloadUrl 'https://Download.Microsoft.com/x' | Should Be $true
    }

    It 'rejects HTTP, look-alike hosts, subdomains and garbage' {
        Test-KitDownloadUrl 'http://aka.ms/x' | Should Be $false
        Test-KitDownloadUrl 'https://evilaka.ms/x' | Should Be $false
        Test-KitDownloadUrl 'https://aka.ms.evil.example/x' | Should Be $false
        Test-KitDownloadUrl 'https://x.download.microsoft.com/x' | Should Be $false
        Test-KitDownloadUrl 'not a url' | Should Be $false
    }

    It 'refuses a download from a host that is not allowed before touching the network' {
        $dest = Join-Path $TestDrive 'x.exe'
        { Save-KitDownload -Uri 'https://example.com/x.exe' -Destination $dest } | Should Throw
        $dest | Should Not Exist
    }

    It 'downloads nothing under -WhatIf' {
        $dest = Join-Path $TestDrive 'y.exe'
        Mock -ModuleName 'RetroCabinetKit.Core' Invoke-WebRequest { throw 'network must not be used' }
        Mock -ModuleName 'RetroCabinetKit.Core' Start-BitsTransfer { throw 'network must not be used' }
        Save-KitDownload -Uri 'https://aka.ms/x.exe' -Destination $dest -WhatIf
        $dest | Should Not Exist
        Assert-MockCalled -ModuleName 'RetroCabinetKit.Core' Invoke-WebRequest -Times 0
    }
}

Describe 'Test-KitSignature' {
    $notepad = Join-Path $env:SystemRoot 'System32\notepad.exe'

    It 'trusts a validly signed Windows binary when CN and O match exactly' {
        $r = Test-KitSignature -Path $notepad -ExpectedPublisher 'Microsoft Windows' -ExpectedOrganization 'Microsoft Corporation'
        $r.Status | Should Be 'Valid'
        $r.Publisher | Should BeExactly 'Microsoft Windows'
        $r.Organization | Should BeExactly 'Microsoft Corporation'
        $r.IsTrusted | Should Be $true
    }

    It 'accepts one of several expected CNs' {
        (Test-KitSignature -Path $notepad -ExpectedPublisher 'Microsoft Corporation', 'Microsoft Windows' -ExpectedOrganization 'Microsoft Corporation').IsTrusted | Should Be $true
    }

    It 'no longer trusts a partial name: CN and O are compared exactly' {
        (Test-KitSignature -Path $notepad -ExpectedPublisher 'Microsoft').IsTrusted | Should Be $false
        (Test-KitSignature -Path $notepad -ExpectedPublisher 'Microsoft Win' -ExpectedOrganization 'Microsoft Corporation').IsTrusted | Should Be $false
        (Test-KitSignature -Path $notepad -ExpectedPublisher 'Microsoft Windows' -ExpectedOrganization 'Microsoft').IsTrusted | Should Be $false
        # CN right, O defaults to the CN: "Microsoft Windows" is not the organization.
        (Test-KitSignature -Path $notepad -ExpectedPublisher 'Microsoft Windows').IsTrusted | Should Be $false
    }

    It 'does not trust a valid signature from another publisher' {
        $r = Test-KitSignature -Path $notepad -ExpectedPublisher 'Some Other Vendor'
        $r.PublisherMatch | Should Be $false
        $r.IsTrusted | Should Be $false
    }

    It 'reports an unsigned file as not trusted' {
        $f = Join-Path $TestDrive 'unsigned.ps1'
        Set-Content -LiteralPath $f -Value 'Write-Output 1'
        $r = Test-KitSignature -Path $f -ExpectedPublisher 'Microsoft Windows' -ExpectedOrganization 'Microsoft Corporation'
        $r.Status | Should Be 'NotSigned'
        $r.IsTrusted | Should Be $false
    }
}

Describe 'File plan and confirmation' {
    $notepad = Join-Path $env:SystemRoot 'System32\notepad.exe'

    It 'lists path, SHA256 and signature of a system file' {
        $p = Get-KitFilePlan -Path $notepad
        $p.Path | Should BeExactly $notepad
        $p.Sha256 | Should Be (Get-FileHash -LiteralPath $notepad -Algorithm SHA256).Hash
        $p.Signature | Should Be 'Valid'
        $p.Signer | Should BeExactly 'Microsoft Windows'
        Test-KitFilePlanHash -Row $p | Should Be $true
    }

    It 'notices a file that changed after the plan was made' {
        $f = Join-Path $TestDrive 'setup.exe'
        [IO.File]::WriteAllBytes($f, [byte[]](1, 2, 3))
        $p = Get-KitFilePlan -Path $f
        $p.Signature | Should Not Be 'Valid'
        [IO.File]::WriteAllBytes($f, [byte[]](1, 2, 4))
        Test-KitFilePlanHash -Row $p | Should Be $false
    }

    It 'passes the plan text to -Approve and returns its answer' {
        $script:shown = $null
        Confirm-KitPlan -FilePlan @(Get-KitFilePlan -Path $notepad) -Approve { param($t) $script:shown = $t; $false } | Should Be $false
        $script:shown | Should Match ([regex]::Escape($notepad))
        $script:shown | Should Match (Get-FileHash -LiteralPath $notepad -Algorithm SHA256).Hash
        Confirm-KitPlan -Lines 'x' -Approve { $true } | Should Be $true
    }
}

Describe 'Download folder (simulated in TEMP, never ProgramData)' {
    Set-KitCulture -Culture 'en-US'
    It 'defaults to ProgramData\RetroCabinetKit\downloads' {
        Get-KitDownloadDir | Should BeExactly (Join-Path $env:ProgramData 'RetroCabinetKit\downloads')
    }

    It 'refuses an existing folder that is not owned by Administrators or SYSTEM (a user created it beforehand)' {
        $base = Join-Path $TestDrive 'precreated'
        New-Item -ItemType Directory -Path $base | Out-Null
        # Owned by the current user, like a folder a user created beforehand (an elevated run would create it
        # owned by the Administrators group). Only the owner section is written.
        $owner = New-Object Security.AccessControl.DirectorySecurity
        $owner.SetOwner([Security.Principal.WindowsIdentity]::GetCurrent().User)
        [IO.Directory]::SetAccessControl($base, $owner)
        { Initialize-KitDownloadDir -Base $base } | Should Throw 'not owned by Administrators or SYSTEM'
        (Get-Acl -LiteralPath $base).AreAccessRulesProtected | Should Be $false # refused before any ACL change
        Join-Path $base 'downloads' | Should Not Exist
    }

    It 'gives every run a fresh GUID work folder below the locked downloads folder, created after the lock' {
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $base = Join-Path $TestDrive 'workbase'
        $owners = 'S-1-5-32-544', 'S-1-5-18', $me
        $a = New-KitWorkDir -Base $base -TrustedOwner $owners
        $b = New-KitWorkDir -Base $base -TrustedOwner $owners
        $a | Should Not Be $b
        (Split-Path -Leaf $a) | Should Match '^[0-9a-f]{32}$'
        Split-Path -Parent $a | Should BeExactly (Join-Path $base 'downloads')
        # Inherits the protected ACL of the downloads folder (no rules of its own, nothing from outside).
        $acl = [IO.Directory]::GetAccessControl($a)
        @($acl.GetAccessRules($true, $false, [Security.Principal.SecurityIdentifier])).Count | Should Be 0
        (@($acl.GetAccessRules($false, $true, [Security.Principal.SecurityIdentifier]) | ForEach-Object { $_.IdentityReference.Value } | Sort-Object -Unique) -join ',') |
            Should Be ((@($owners | Sort-Object -Unique)) -join ',')
    }

    It 'gives base and downloads folder an ACL for Administrators and SYSTEM only' {
        $base = Join-Path $TestDrive 'kitdata'
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $dir = Initialize-KitDownloadDir -Base $base
        try {
            $dir | Should BeExactly (Join-Path $base 'downloads')
            foreach ($d in $base, $dir) {
                # .NET directly: the provider would list the locked base first.
                $acl = [IO.Directory]::GetAccessControl($d)
                $acl.AreAccessRulesProtected | Should Be $true
                $sids = @($acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) | ForEach-Object { $_.IdentityReference.Value } | Sort-Object -Unique)
                $sids -join ',' | Should Be 'S-1-5-18,S-1-5-32-544'
            }
        } finally {
            # Own TEMP test folder: give the rights back so it can be removed.
            foreach ($d in $base, $dir) {
                $acl = New-Object Security.AccessControl.DirectorySecurity
                $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule ($me, 'FullControl', 'ContainerInherit, ObjectInherit', 'None', 'Allow')))
                [IO.Directory]::SetAccessControl($d, $acl)
            }
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'refuses a junction as download folder' {
        $base = Join-Path $TestDrive 'junctionbase'
        $elsewhere = Join-Path $TestDrive 'elsewhere'
        New-Item -ItemType Directory -Path $base, $elsewhere -Force | Out-Null
        $null = cmd /c mklink /J "$base\downloads" "$elsewhere"
        try {
            { Initialize-KitDownloadDir -Base $base } | Should Throw
            # Refused before any ACL was changed.
            (Get-Acl -LiteralPath $base).AreAccessRulesProtected | Should Be $false
            (Get-Acl -LiteralPath $elsewhere).AreAccessRulesProtected | Should Be $false
        } finally { cmd /c rmdir "$base\downloads" }
    }
}

Describe 'Invoke-KitVerifiedExecutable (copies of signed Windows files, work folder in TEMP)' {
    Set-KitCulture -Culture 'en-US'
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $dir = @{ Base = (Join-Path $TestDrive 'KitData'); TrustedOwner = @('S-1-5-32-544', 'S-1-5-18', $me) }
    $work = Join-Path $TestDrive 'KitData\downloads'
    $src = Join-Path $TestDrive 'Build\setup'
    New-Item -ItemType Directory -Path $src -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\cmd.exe') -Destination "$src\setup.exe"
    $ms = @{ Publisher = 'Microsoft Windows'; Organization = 'Microsoft Corporation' }

    It 'runs a copy in a fresh work folder (working directory = that folder), returns the exit code, removes it' {
        [IO.File]::WriteAllBytes("$src\evil.dll", [byte[]](77, 90, 0, 0)) # not copied without Folder
        try {
            $r = Invoke-KitVerifiedExecutable -Item (@{ Name = 'Setup'; Path = "$src\setup.exe"; Arguments = '/d /c exit 3' } + $ms) -Approve { $true } @dir
        } finally { Remove-Item -LiteralPath "$src\evil.dll" }
        $r.Result | Should Be 'Ok'
        $r.ExitCode | Should Be 3
        @(Get-ChildItem -LiteralPath $work -Force).Count | Should Be 0
    }

    It 'holds every PE file read-only while the program runs (Start-Process mocked)' {
        $global:RckProbe = $null
        Mock -ModuleName 'RetroCabinetKit.Core' Start-Process {
            $p = @{ FilePath = $FilePath; WorkingDirectory = $WorkingDirectory; Writable = $true; Deletable = $true }
            try { [IO.File]::Open($FilePath, 'Open', 'ReadWrite', 'ReadWrite').Dispose() } catch { $p.Writable = $false }
            try { Remove-Item -LiteralPath $FilePath -Force -ErrorAction Stop } catch { $p.Deletable = $false }
            $global:RckProbe = $p
            [pscustomobject]@{ ExitCode = 0 }
        }
        (Invoke-KitVerifiedExecutable -Item (@{ Name = 'Setup'; Path = "$src\setup.exe" } + $ms) -Approve { $true } @dir).Result | Should Be 'Ok'
        $global:RckProbe.FilePath | Should BeLike "$work\*\setup.exe"
        $global:RckProbe.WorkingDirectory | Should BeExactly (Split-Path -Parent $global:RckProbe.FilePath)
        $global:RckProbe.Writable | Should Be $false
        $global:RckProbe.Deletable | Should Be $false
        Remove-Variable -Name RckProbe -Scope Global
    }

    It 'with Folder copies the whole folder and refuses an unsigned DLL next to the installer' {
        [IO.File]::WriteAllBytes("$src\dsetup.dll", [byte[]](77, 90, 0, 0))
        Mock -ModuleName 'RetroCabinetKit.Core' Start-Process { throw 'must not start' }
        try {
            $r = Invoke-KitVerifiedExecutable -Item (@{ Name = 'DX'; Path = "$src\setup.exe"; Folder = $true } + $ms) -Approve { throw 'must not ask' } @dir
        } finally { Remove-Item -LiteralPath "$src\dsetup.dll" }
        $r.Result | Should Be 'Untrusted'
        $r.File | Should BeLike '*\dsetup.dll'
        @(Get-ChildItem -LiteralPath $work -Force).Count | Should Be 0
    }

    It 'with Folder shows every PE file in the plan and copies the other files too' {
        Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\version.dll') -Destination "$src\dsetup.dll"
        [IO.File]::WriteAllText("$src\data.cab", 'cab')
        Mock -ModuleName 'RetroCabinetKit.Core' Start-Process {
            $global:RckFiles = @(Get-ChildItem -LiteralPath $WorkingDirectory -Force | ForEach-Object { $_.Name } | Sort-Object)
            [pscustomobject]@{ ExitCode = 0 }
        }
        $script:shown = $null
        try {
            $r = Invoke-KitVerifiedExecutable -Item (@{ Name = 'DX'; Path = "$src\setup.exe"; Folder = $true } + $ms) -Approve { param($t) $script:shown = $t; $true } @dir
        } finally { Remove-Item -LiteralPath "$src\dsetup.dll", "$src\data.cab" }
        $r.Result | Should Be 'Ok'
        $script:shown | Should Match 'setup\.exe'
        $script:shown | Should Match 'dsetup\.dll'
        $global:RckFiles -join ',' | Should Be 'data.cab,dsetup.dll,setup.exe'
        Remove-Variable -Name RckFiles -Scope Global
    }

    It 'does not start when a file appeared in the work folder after the confirmation (planted DLL)' {
        Mock -ModuleName 'RetroCabinetKit.Core' Start-Process { throw 'must not start' }
        $r = Invoke-KitVerifiedExecutable -Item (@{ Name = 'Setup'; Path = "$src\setup.exe" } + $ms) @dir -Approve {
            $w = Get-ChildItem -LiteralPath $work -Directory | Select-Object -First 1
            [IO.File]::WriteAllBytes((Join-Path $w.FullName 'version.dll'), [byte[]](77, 90))
            $true
        }
        $r.Result | Should Be 'Changed'
        @(Get-ChildItem -LiteralPath $work -Force).Count | Should Be 0
    }

    It 'does not start when the copy was changed after the confirmation' {
        Mock -ModuleName 'RetroCabinetKit.Core' Start-Process { throw 'must not start' }
        $r = Invoke-KitVerifiedExecutable -Item (@{ Name = 'Setup'; Path = "$src\setup.exe" } + $ms) @dir -Approve {
            $w = Get-ChildItem -LiteralPath $work -Directory | Select-Object -First 1
            [IO.File]::AppendAllText((Join-Path $w.FullName 'setup.exe'), 'x')
            $true
        }
        $r.Result | Should Be 'Changed'
    }

    It 'runs nothing when declined' {
        Mock -ModuleName 'RetroCabinetKit.Core' Start-Process { throw 'must not start' }
        (Invoke-KitVerifiedExecutable -Item (@{ Name = 'Setup'; Path = "$src\setup.exe" } + $ms) -Approve { $false } @dir).Result | Should Be 'Declined'
        @(Get-ChildItem -LiteralPath $work -Force).Count | Should Be 0
    }
}
