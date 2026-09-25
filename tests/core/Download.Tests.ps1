$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force

# No real download happens in these tests.
Describe 'Download allow list' {
    It 'loads the configured hosts' {
        @(Get-KitAllowedHost) -contains 'github.com' | Should Be $true
    }

    It 'accepts HTTPS URLs on allowed hosts' {
        Test-KitDownloadUrl 'https://github.com/nefarius/ViGEmBus/releases' | Should Be $true
        Test-KitDownloadUrl 'https://GitHub.com/x' | Should Be $true
    }

    It 'rejects HTTP, look-alike hosts, subdomains and garbage' {
        Test-KitDownloadUrl 'http://github.com/x' | Should Be $false
        Test-KitDownloadUrl 'https://evilgithub.com/x' | Should Be $false
        Test-KitDownloadUrl 'https://github.com.evil.example/x' | Should Be $false
        Test-KitDownloadUrl 'https://gist.github.com/x' | Should Be $false
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
        Save-KitDownload -Uri 'https://github.com/x.exe' -Destination $dest -WhatIf
        $dest | Should Not Exist
        Assert-MockCalled -ModuleName 'RetroCabinetKit.Core' Invoke-WebRequest -Times 0
    }
}

Describe 'Test-KitSignature' {
    $notepad = Join-Path $env:SystemRoot 'System32\notepad.exe'

    It 'trusts a validly signed Windows binary from the expected publisher' {
        $r = Test-KitSignature -Path $notepad -ExpectedPublisher 'Microsoft'
        $r.Status | Should Be 'Valid'
        $r.IsTrusted | Should Be $true
    }

    It 'does not trust a valid signature from another publisher' {
        $r = Test-KitSignature -Path $notepad -ExpectedPublisher 'Some Other Vendor'
        $r.PublisherMatch | Should Be $false
        $r.IsTrusted | Should Be $false
    }

    It 'reports an unsigned file as not trusted' {
        $f = Join-Path $TestDrive 'unsigned.ps1'
        Set-Content -LiteralPath $f -Value 'Write-Output 1'
        $r = Test-KitSignature -Path $f -ExpectedPublisher 'Microsoft'
        $r.Status | Should Be 'NotSigned'
        $r.IsTrusted | Should Be $false
    }
}
