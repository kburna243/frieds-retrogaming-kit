$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1') -Force
Import-Module (Join-Path $kitRoot 'lightgun\RetroCabinetKit.Lightgun.psd1') -Force

# Runs only with tests\Run-Tests.ps1 -Local. Works on COPIES (TestDrive) of the real RetroBat and Gunmote files in
# tests\fixtures-local\retrobat\. No real value is written into this file; the RetroBat folder the real
# Keymaps.json points to is derived at runtime. Expectation: mode Keep changes nothing where the real setup
# already does the right thing; every difference to the kit's target is listed (Write-Host), nothing real is
# ever written.
$fixtures = Join-Path $kitRoot 'tests\fixtures-local\retrobat'

function Get-Hash([string] $Path) { (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash }

Describe 'Lightgun on a real setup (local fixture, copies only)' {
    Set-KitCulture -Culture 'en-US'
    Mock -ModuleName 'RetroCabinetKit.Lightgun' Test-KitProcessesClosed { }

    It 'has the local fixtures' {
        foreach ($f in 'es_settings.cfg', 'es_input.cfg', 'Keymaps.json') { Join-Path $fixtures $f | Should Exist }
    }

    $cfg = Join-Path $TestDrive 'RetroBat\emulationstation\.emulationstation'
    New-Item -ItemType Directory -Path $cfg -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $fixtures 'es_settings.cfg'), (Join-Path $fixtures 'es_input.cfg') -Destination $cfg
    $keymaps = Join-Path $TestDrive 'Gunmote\Keymaps'
    New-Item -ItemType Directory -Path $keymaps -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $fixtures 'Keymaps.json') -Destination $keymaps
    Get-ChildItem -LiteralPath (Join-Path $fixtures 'gunmote-keymaps') -Filter '*.json' | Copy-Item -Destination $keymaps
    $settings = Join-Path $cfg 'es_settings.cfg'
    $inputCfg = Join-Path $cfg 'es_input.cfg'

    It 'reads and writes the real XML files byte for byte (round trip without changes)' {
        $m = Get-Module 'RetroCabinetKit.Lightgun'
        foreach ($f in $settings, $inputCfg) {
            $copy = "$f.roundtrip"
            Copy-Item -LiteralPath $f -Destination $copy
            & $m { param($p) Save-LightgunXml (Read-LightgunXml $p) $p } $copy
            Get-Hash $copy | Should Be (Get-Hash $f)
        }
    }

    It 'Gunmote layouts, mode Keep: the real layouts already do the right thing -> 0 changes' {
        $km = [IO.File]::ReadAllText((Join-Path $keymaps 'Keymaps.json')) | ConvertFrom-Json
        $es = @($km.Applications | Where-Object { $_.Search -match '\\emulationstation\\emulationstation\.exe$' }) | Select-Object -First 1
        $es | Should Not BeNullOrEmpty
        $root = $es.Search -replace '\\emulationstation\\emulationstation\.exe$', ''
        $plan = Get-LightgunLayoutPlan -KeymapsDir $keymaps -RetroBatRoot $root -Mode Keep
        foreach ($c in $plan.Changes) { Write-Host "  layouts (Keep): $c" }
        foreach ($k in $plan.Titles.Keys) { Write-Host "  profile $k -> layout title '$($plan.Titles[$k])'" }
        foreach ($t in $plan.Titles.Values) { Test-LightgunLayoutTitle $t | Should Be $true }
        $plan.Count | Should Be 0
        $replace = Get-LightgunLayoutPlan -KeymapsDir $keymaps -RetroBatRoot $root -Mode Replace
        Write-Host "  layouts (Replace) would change $($replace.Count) thing(s)"
    }

    It 'RetroBat settings: lists every difference to the kit target (nothing real is written)' {
        $before = Get-Hash (Join-Path $fixtures 'es_settings.cfg')
        $plan = @(Get-LightgunEsSettingsPlan -Path $settings) + @(Get-LightgunEsInputPlan -Path $inputCfg)
        foreach ($c in $plan) { Write-Host ('  differs: {0}: {1}: {2} -> {3}' -f (Split-Path -Leaf $c.File), $c.Name, $(if ($null -eq $c.Old) { '(missing)' } else { $c.Old }), $c.New) }
        foreach ($o in Get-LightgunEsOverride -Path $settings) { Write-Host "  override (reported only): $($o.System)[`"$($o.Game)`"].$($o.Key) = $($o.Value)" }
        $target = Get-LightgunEsSettingsTarget
        $correct = @($target.Keys | Where-Object { $n = $_; -not @($plan | Where-Object { $_.Name -eq $n }).Count })
        Write-Host "  already correct: $($correct.Count) of $($target.Count) es_settings keys"
        Get-Hash (Join-Path $fixtures 'es_settings.cfg') | Should Be $before
    }

    It 'applied to the copy: only the planned keys change, all other lines stay, a second run changes nothing' {
        $orig = [IO.File]::ReadAllLines($settings)
        $plan = @(Get-LightgunEsSettingsPlan -Path $settings)
        Set-LightgunEsSettings -Path $settings -Confirm:$false | Should Be $plan.Count
        $new = [IO.File]::ReadAllLines($settings)
        $changedNames = @($plan | ForEach-Object { $_.Name })
        $kept = @($orig | Where-Object { $l = $_; -not @($changedNames | Where-Object { $l -match ('name="' + [regex]::Escape($_) + '"') }).Count })
        @($kept | Where-Object { $new -notcontains $_ }).Count | Should Be 0
        $new.Count | Should Be ($orig.Count + @($plan | Where-Object { $_.Action -eq 'Add' }).Count)
        Set-LightgunEsSettings -Path $settings -Confirm:$false | Should Be 0
        $null = Set-LightgunEsInput -Path $inputCfg -Confirm:$false
        Set-LightgunEsInput -Path $inputCfg -Confirm:$false | Should Be 0
    }
}
