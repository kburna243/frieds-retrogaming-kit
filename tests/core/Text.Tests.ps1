$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force

function New-TextFile([string] $Name, [string] $Text, [Text.Encoding] $Encoding, [switch] $Bom) {
    $path = Join-Path $TestDrive $Name
    $body = $Encoding.GetBytes($Text)
    $pre  = if ($Bom) { $Encoding.GetPreamble() } else { [byte[]]@() }
    [IO.File]::WriteAllBytes($path, [byte[]]($pre + $body))
    $path
}
function Get-ExpectedBytes([string] $Text, [Text.Encoding] $Encoding, [switch] $Bom) {
    $pre = if ($Bom) { $Encoding.GetPreamble() } else { [byte[]]@() }
    [Convert]::ToBase64String([byte[]]($pre + $Encoding.GetBytes($Text)))
}
function Get-ActualBytes([string] $Path) { [Convert]::ToBase64String([IO.File]::ReadAllBytes($Path)) }

$ansi    = [Text.Encoding]::Default
$utf8    = New-Object Text.UTF8Encoding $false
$utf8bom = New-Object Text.UTF8Encoding $true
$utf16le = [Text.Encoding]::Unicode
$utf16be = [Text.Encoding]::BigEndianUnicode
$source  = "Table=C:\Old\vPinball\Tables`r`nB2S=C:\Old\vPinball\B2S`r`nSteam=C:\Program Files (x86)\Steam`r`n"
$target  = "Table=D:\Neu Ordner ä\vPinball\Tables`r`nB2S=D:\Neu Ordner ä\vPinball\B2S`r`nSteam=C:\Program Files (x86)\Steam`r`n"
$map     = @{ 'C:\Old\vPinball\' = 'D:\Neu Ordner ä\vPinball\' }

Describe 'Get-KitFileEncoding' {
    It 'detects UTF-8 with BOM'  { (Get-KitFileEncoding (New-TextFile 'e1.txt' 'ä' $utf8bom -Bom)).Name | Should Be 'UTF8BOM' }
    It 'detects UTF-16LE'        { (Get-KitFileEncoding (New-TextFile 'e2.txt' 'ä' $utf16le -Bom)).Name | Should Be 'UTF16LE' }
    It 'detects UTF-16BE'        { (Get-KitFileEncoding (New-TextFile 'e3.txt' 'ä' $utf16be -Bom)).Name | Should Be 'UTF16BE' }
    It 'detects UTF-8 without BOM by validation' { (Get-KitFileEncoding (New-TextFile 'e4.txt' 'Tür' $utf8)).Name | Should Be 'UTF8' }
    It 'falls back to ANSI'      { (Get-KitFileEncoding (New-TextFile 'e5.txt' 'Tür' $ansi)).Name | Should Be 'ANSI' }
    It 'treats pure ASCII as ANSI' { (Get-KitFileEncoding (New-TextFile 'e6.txt' 'plain' $utf8)).Name | Should Be 'ANSI' }
}

Describe 'Edit-KitTextFile keeps the original encoding' {
    It 'UTF-16LE with BOM' {
        $p = New-TextFile 'u16.ini' $source $utf16le -Bom
        Edit-KitTextFile -Path $p -Replace $map | Should Be 2
        Get-ActualBytes $p | Should Be (Get-ExpectedBytes $target $utf16le -Bom)
    }
    It 'UTF-8 with BOM' {
        $p = New-TextFile 'u8bom.xml' $source $utf8bom -Bom
        Edit-KitTextFile -Path $p -Replace $map | Should Be 2
        Get-ActualBytes $p | Should Be (Get-ExpectedBytes $target $utf8bom -Bom)
    }
    It 'UTF-8 without BOM' {
        $p = New-TextFile 'u8.txt' ($source + 'Grüße') $utf8
        Edit-KitTextFile -Path $p -Replace $map | Should Be 2
        Get-ActualBytes $p | Should Be (Get-ExpectedBytes ($target + 'Grüße') $utf8)
    }
    It 'ANSI' {
        $p = New-TextFile 'ansi.vbs' $source $ansi
        Edit-KitTextFile -Path $p -Replace $map | Should Be 2
        Get-ActualBytes $p | Should Be (Get-ExpectedBytes $target $ansi)
    }
    It 'handles brackets and spaces in the file name' {
        $p = New-TextFile 'Table (1990) [v2].vbs' $source $ansi
        Edit-KitTextFile -Path $p -Replace $map | Should Be 2
    }
}

Describe 'Edit-KitTextFile behaviour' {
    It 'is case-sensitive by default and case-insensitive on request' {
        $p = New-TextFile 'case.txt' "c:\OLD\VPINBALL\x`r`nC:\Old\vPinball\y" $ansi
        Edit-KitTextFile -Path $p -Replace $map | Should Be 1
        Edit-KitTextFile -Path $p -Replace $map -CaseInsensitive | Should Be 1
        [IO.File]::ReadAllText($p, $ansi) | Should BeExactly "D:\Neu Ordner ä\vPinball\x`r`nD:\Neu Ordner ä\vPinball\y"
    }
    It 'never replaces its own output again (single pass)' {
        $p = New-TextFile 'double.txt' 'C:\A\x' $ansi
        Edit-KitTextFile -Path $p -Replace @{ 'C:\A\' = 'C:\A\B\' } | Should Be 1
        [IO.File]::ReadAllText($p, $ansi) | Should BeExactly 'C:\A\B\x'
    }
    It 'counts but does not write under -WhatIf' {
        $p = New-TextFile 'whatif.txt' $source $utf16le -Bom
        $before = Get-ActualBytes $p
        Edit-KitTextFile -Path $p -Replace $map -WhatIf | Should Be 2
        Get-ActualBytes $p | Should Be $before
    }
    It 'returns 0 and leaves the file untouched without matches' {
        $p = New-TextFile 'nomatch.txt' 'nothing here' $ansi
        $before = Get-ActualBytes $p
        Edit-KitTextFile -Path $p -Replace $map | Should Be 0
        Get-ActualBytes $p | Should Be $before
    }
    It 'refuses a replacement that ANSI cannot represent and keeps the file' {
        $p = New-TextFile 'unrepresentable.txt' $source $ansi
        $before = Get-ActualBytes $p
        { Edit-KitTextFile -Path $p -Replace @{ 'C:\Old\' = ('D:\' + [char]0x0142 + '\') } } | Should Throw
        Get-ActualBytes $p | Should Be $before
    }
}
