$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1') -Force
$newBuild = Join-Path $PSScriptRoot 'New-PinballTestBuild.ps1'

Describe 'Robocopy arguments and exit codes' {
    It 'builds the planned command line' {
        $a = Get-PinballRobocopyArgument -Source 'S:\B\vPinball' -Destination 'T:\N\vPinball'
        $a -join ' ' | Should BeExactly 'S:\B\vPinball T:\N\vPinball /E /COPY:DAT /DCOPY:T /R:2 /W:5 /MT:8 /XJ /XD @eaDir @tmp System Volume Information $RECYCLE.BIN /NP /NFL /NDL /NJH /NJS'
        $a -contains 'System Volume Information' | Should Be $true
    }

    It 'uses /L for a dry run and /XO + /XF for an update' {
        $a = Get-PinballRobocopyArgument -Source 'S:\x' -Destination 'T:\x' -ListOnly -Update -ExcludeFiles 'PUPDatabase.db', 'a b.ini' -LogPath 'C:\l.log'
        $a -contains '/L' | Should Be $true
        $a -contains '/XO' | Should Be $true
        ($a -join '|') | Should Match ([regex]::Escape('/XF|PUPDatabase.db|a b.ini'))
        $a -contains '/LOG+:C:\l.log' | Should Be $true
        $a -contains '/NFL' | Should Be $false
    }

    It 'refuses exclusion names that are no plain file names (they come from the state file)' {
        foreach ($bad in '/MOV', 'a"b', 'sub\x.ini', 'C:x', '*.ini', 'a|b') {
            { Get-PinballRobocopyArgument -Source 'S:\x' -Destination 'T:\x' -Update -ExcludeFiles $bad } | Should Throw
        }
        { Get-PinballRobocopyArgument -Source 'S:\x' -Destination 'T:\x' -Update -ExcludeFiles 'Table (1990) [v2].ini', 'PUPDatabase.db' } | Should Not Throw
    }

    It 'maps exit codes 0-7 to ok and 8+ to failure' {
        foreach ($c in 0..7) { (Get-PinballRobocopyResult $c).Ok | Should Be $true }
        foreach ($c in 8, 9, 16) { (Get-PinballRobocopyResult $c).Ok | Should Be $false }
        (Get-PinballRobocopyResult 1).FilesCopied | Should Be $true
        (Get-PinballRobocopyResult 2).FilesCopied | Should Be $false
    }
}

Describe 'Copy a synthetic build (real robocopy inside TEMP)' {
    Set-KitCulture -Culture 'en-US'
    $src = Join-Path $TestDrive 'Src'
    $dst = Join-Path $TestDrive 'Dst'
    & $newBuild -Root $src -OldRoot 'D:\Old'
    New-Item -ItemType Directory -Path (Join-Path $src 'vPinball\@eaDir') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $src 'vPinball\@eaDir\thumb') -Value 'nas'
    $state = Join-Path $TestDrive 'state.json'

    It 'lists without copying (-ListOnly)' {
        $r = @(Invoke-PinballCopy -SourceRoot $src -TargetRoot $dst -Siblings 'DOFLinx' -ListOnly)
        $r.Count | Should Be 2
        $r[0].FilesCopied | Should Be $true
        Join-Path $dst 'vPinball' | Should Not Exist
    }

    It 'copies and verifies count and size' {
        $r = @(Invoke-PinballCopy -SourceRoot $src -TargetRoot $dst -Siblings 'DOFLinx' -StatePath $state)
        @($r | Where-Object { -not $_.Ok }).Count | Should Be 0
        $check = @(Test-PinballCopy -SourceRoot $src -TargetRoot $dst -Siblings 'DOFLinx')
        @($check | Where-Object { -not $_.Complete }).Count | Should Be 0
        $check[0].TargetFiles | Should Be $check[0].SourceFiles
        Join-Path $dst 'vPinball\@eaDir' | Should Not Exist
    }

    It 'notices a missing file' {
        Remove-Item -LiteralPath (Join-Path $dst 'vPinball\Deluxe\Arcade.exe')
        (@(Test-PinballCopy -SourceRoot $src -TargetRoot $dst))[0].Complete | Should Be $false
    }

    It 'locks a full copy after relocation and only updates without the rewritten files' {
        Set-KitStateValue -Path $state -Key 'RelocateDone' -Value $true
        Set-KitStateValue -Path $state -Key 'RelocatedFiles' -Value @((Join-Path $dst 'vPinball\VisualPinball\Tables\script.vbs'))
        Set-Content -LiteralPath (Join-Path $dst 'vPinball\VisualPinball\Tables\script.vbs') -Value 'rewritten'
        { Invoke-PinballCopy -SourceRoot $src -TargetRoot $dst -StatePath $state } | Should Throw 'locked'
        (Get-Item -LiteralPath (Join-Path $dst 'vPinball\VisualPinball\Tables\script.vbs')).LastWriteTime = (Get-Date).AddYears(-5)
        $r = @(Invoke-PinballCopy -SourceRoot $src -TargetRoot $dst -StatePath $state -Update)
        $r[0].Ok | Should Be $true
        Get-Content -LiteralPath (Join-Path $dst 'vPinball\VisualPinball\Tables\script.vbs') | Should Be 'rewritten'
        Join-Path $dst 'vPinball\Deluxe\Arcade.exe' | Should Exist
    }
}
