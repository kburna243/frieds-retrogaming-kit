# Layouts (step 6): the kit's own Gunmote layouts and the profile selection in Keymaps.json.
#   Menu  (Default)   no pointer: RetroBat reads a deflected stick as a held direction. Trigger (B) -> Xbox A.
#   Pad43             pointer on the left stick, 4:3 (MAME, Model 2/3, Supermodel)
#   TP                pointer on the RIGHT stick (TeknoParrot profiles aim with the right stick)
#   Mouse             lightgun mouse, only for RetroArch and PCSX2 (they only know a pointer)
# Every layout sets ALL keys and the OffScreen state explicitly: Gunmote fills missing entries from the Default
# layout, so a pad layout without its own OffScreen pointer inherited "pointer off" from the menu layout
# (inheritance trap). Home is disabled in every layout (it opened the Xbox Game Bar); holding Home for five
# seconds still opens Gunmote's layout chooser.
# Keymaps.json: LayoutChooser (title -> file; the profile automation selects a layout by its title),
# Applications (file per program path substring), Default (fallback on every window change).
# Mode Keep: an existing entry whose layout already does the right thing (same pointer kind, explicit
# OffScreen, Home off) stays; Replace: the kit's layouts everywhere.
# Gunmote writes its files back when it exits: written only while Gunmote is closed.

$script:LightgunKeyNames = @(
    'A', 'B', 'Home', 'Left', 'Right', 'Up', 'Down', 'Minus', 'Plus', 'One', 'Two', 'Shake',
    'Nunchuk.C', 'Nunchuk.Z', 'Nunchuk.StickDown', 'Nunchuk.StickUp', 'Nunchuk.StickRight', 'Nunchuk.StickLeft', 'Nunchuk.Shake',
    'Pointer', 'PointerX-', 'PointerX+', 'PointerY-', 'PointerY+',
    'AccelX-', 'AccelX+', 'AccelY-', 'AccelY+', 'AccelZ-', 'AccelZ+', 'Extension', 'Nunchuk.Rotation+', 'Nunchuk.Rotation-',
    'Nunchuk.AccelX-', 'Nunchuk.AccelX+', 'Nunchuk.AccelY-', 'Nunchuk.AccelY+', 'Nunchuk.AccelZ-', 'Nunchuk.AccelZ+',
    'Classic.Left', 'Classic.Right', 'Classic.Up', 'Classic.Down',
    'Classic.StickLLeft', 'Classic.StickLRight', 'Classic.StickLUp', 'Classic.StickLDown',
    'Classic.StickRLeft', 'Classic.StickRRight', 'Classic.StickRUp', 'Classic.StickRDown',
    'Classic.Minus', 'Classic.Plus', 'Classic.Home', 'Classic.Y', 'Classic.X', 'Classic.A', 'Classic.B',
    'Classic.TriggerL', 'Classic.TriggerR', 'Classic.L', 'Classic.R', 'Classic.ZL', 'Classic.ZR'
)

$script:LightgunLayouts = [ordered]@{
    Menu  = @{ File = 'rck_menu.json';  Title = 'RCK Menu (no pointer)' }
    Pad43 = @{ File = 'rck_pad43.json'; Title = 'RCK Pad 4:3' }
    TP    = @{ File = 'rck_tp.json';    Title = 'RCK TeknoParrot' }
    Mouse = @{ File = 'rck_mouse.json'; Title = 'RCK Mouse' }
}

# Gunmote's own layouts that the kit recognizes by name without reading them.
$script:LightgunBuiltinLayouts = @{ 'default.json' = 'Mouse'; 'mouse43.json' = 'Mouse' }

# Program (below the RetroBat folder) -> layout kind. DuckStation stays out on purpose: [W6] it is guided only.
$script:LightgunApplications = @(
    @{ Path = 'emulationstation\emulationstation.exe'; Kind = 'Menu' }
    @{ Path = 'emulators\mame\mame.exe'; Kind = 'Pad43' }
    @{ Path = 'emulators\supermodel\supermodel.exe'; Kind = 'Pad43' }
    @{ Path = 'emulators\m2emulator\emulator_multicpu.exe'; Kind = 'Pad43' }
    @{ Path = 'emulators\teknoparrot\TeknoParrotUi.exe'; Kind = 'TP' }
    @{ Path = 'emulators\retroarch\retroarch.exe'; Kind = 'Mouse' }
    @{ Path = 'emulators\pcsx2\pcsx2-qt.exe'; Kind = 'Mouse' }
)

# The program whose entry decides which existing layout counts for a kind (mode Keep).
$script:LightgunKindAnchor = @{ Pad43 = 'emulators\mame\mame.exe'; TP = 'emulators\teknoparrot\TeknoParrotUi.exe'; Mouse = 'emulators\retroarch\retroarch.exe' }

function Get-LightgunLayoutKind {
    [CmdletBinding()]
    param()
    @($script:LightgunLayouts.Keys)
}

# The kit's layout as an ordered dictionary (Title, All.OnScreen, All.OffScreen).
function New-LightgunLayout {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [ValidateSet('Menu', 'Pad43', 'TP', 'Mouse')] [string] $Kind)
    $on = [ordered]@{}
    foreach ($k in $script:LightgunKeyNames) { $on[$k] = 'disable' }
    $pad = [ordered]@{
        'Left' = '360.left'; 'Right' = '360.right'; 'Up' = '360.up'; 'Down' = '360.down'
        'Minus' = '360.back'; 'Plus' = '360.start'; 'One' = '360.x'; 'Two' = '360.y'
        'Nunchuk.C' = '360.triggerr'; 'Nunchuk.Z' = '360.bumperr'; 'Nunchuk.Shake' = '360.bumperl'
    }
    switch ($Kind) {
        'Menu' {
            foreach ($k in $pad.Keys) { $on[$k] = $pad[$k] }
            $on['A'] = '360.b'; $on['B'] = '360.a'
            $off = [ordered]@{ 'A' = '360.b'; 'B' = '360.a'; 'Pointer' = 'disable'; 'Home' = 'disable' }
        }
        { $_ -in 'Pad43', 'TP' } {
            foreach ($k in $pad.Keys) { $on[$k] = $pad[$k] }
            $on['A'] = '360.a'; $on['B'] = '360.b'
            if ($Kind -eq 'Pad43') {
                $on['Pointer'] = '360.stickl-light-4:3'
                foreach ($d in 'Up', 'Down', 'Left', 'Right') { $on["Nunchuk.Stick$d"] = "360.stickr$($d.ToLowerInvariant())" }
            } else { $on['Pointer'] = '360.stickr-light' } # the Nunchuk stick stays off: the right stick aims
            $off = [ordered]@{ 'A' = '360.a'; 'B' = '360.b'; 'Pointer' = $on['Pointer']; 'Home' = 'disable' }
        }
        'Mouse' {
            $on['Pointer'] = 'lightgunmouse'; $on['A'] = 'mouseright'; $on['B'] = 'mouseleft'
            $on['Left'] = 'left'; $on['Right'] = 'right'; $on['Up'] = 'up'; $on['Down'] = 'down'
            $on['Plus'] = 'vk_1'; $on['Minus'] = 'vk_5'; $on['One'] = 'mousemiddle'
            $off = [ordered]@{ 'A' = 'mouseright'; 'B' = 'mouseright'; 'Pointer' = 'lightgunmouse'; 'Home' = 'disable' }
        }
    }
    [ordered]@{ Title = $script:LightgunLayouts[$Kind].Title; All = [ordered]@{ OnScreen = $on; OffScreen = $off } }
}

function Read-LightgunJson([string] $Path) {
    [IO.File]::ReadAllText($Path) | ConvertFrom-Json
}

function Get-JsonProperty($Object, [string] $Name) {
    if ($null -eq $Object) { return $null }
    $p = $Object.PSObject.Properties[$Name]
    if ($p) { $p.Value }
}

# Kind of an existing layout file by what it does: 'Menu', 'Pad43', 'Pad', 'TP', 'Mouse' or '' (unknown).
# Correct = the OffScreen pointer and B are set explicitly and Home is off (Mouse: pointer only).
function Get-LightgunLayoutInfo {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $KeymapsDir, [Parameter(Mandatory)] [string] $File)
    $name = [IO.Path]::GetFileName($File)
    if ($script:LightgunBuiltinLayouts.ContainsKey($name.ToLowerInvariant())) { return [pscustomobject]@{ Kind = $script:LightgunBuiltinLayouts[$name.ToLowerInvariant()]; Correct = $true } }
    $path = Join-Path $KeymapsDir $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return [pscustomobject]@{ Kind = ''; Correct = $false } }
    try { $j = Read-LightgunJson $path } catch { return [pscustomobject]@{ Kind = ''; Correct = $false } }
    $all = Get-JsonProperty $j 'All'
    $on = Get-JsonProperty $all 'OnScreen'
    $off = Get-JsonProperty $all 'OffScreen'
    $pointer = [string](Get-JsonProperty $on 'Pointer')
    $kind = if ($pointer -eq 'disable') { 'Menu' }
            elseif ($pointer -like 'lightgunmouse*') { 'Mouse' }
            elseif ($pointer -like '360.stickr-light*') { 'TP' }
            elseif ($pointer -eq '360.stickl-light-4:3') { 'Pad43' }
            elseif ($pointer -like '360.stickl-light*') { 'Pad' }
            else { '' }
    $offPointer = [string](Get-JsonProperty $off 'Pointer')
    $b = [string](Get-JsonProperty $on 'B')
    $wantB = if ($kind -eq 'Menu') { '360.a' } else { '360.b' }
    $correct = if ($kind -eq 'Mouse') { $true } else {
        $kind -and $offPointer -eq $pointer -and $b -eq $wantB -and [string](Get-JsonProperty $off 'B') -eq $wantB -and [string](Get-JsonProperty $on 'Home') -eq 'disable'
    }
    [pscustomobject]@{ Kind = $kind; Correct = [bool]$correct }
}

# Everything step 6 would change, without writing: @{ Files = [{ Path; Json }]; Keymaps = <object>; Changes = [text];
# Titles = @{ Kind = LayoutChooser title }; Count }. -Mode Keep keeps existing correct choices.
function Get-LightgunLayoutPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $KeymapsDir,
        [Parameter(Mandatory)] [string] $RetroBatRoot,
        [ValidateSet('Keep', 'Replace')] [string] $Mode = 'Keep'
    )
    $keymapsJson = Join-Path $KeymapsDir 'Keymaps.json'
    if (-not (Test-Path -LiteralPath $keymapsJson -PathType Leaf)) { throw (Get-KitText 'Lightgun.Layouts.NoKeymaps' -f $keymapsJson) }
    $km = Read-LightgunJson $keymapsJson
    $root = (Resolve-LightgunFullPath $RetroBatRoot).TrimEnd('\')
    foreach ($p in 'LayoutChooser', 'Applications') { if (-not (Get-JsonProperty $km $p)) { $km | Add-Member -NotePropertyName $p -NotePropertyValue @() -Force } }
    $chooser = New-Object Collections.ArrayList (, @($km.LayoutChooser))
    $apps = New-Object Collections.ArrayList (, @($km.Applications))
    $changes = New-Object Collections.ArrayList
    $files = New-Object Collections.ArrayList

    # 1. Which file serves each kind.
    $chosen = @{}
    $kept = @{}
    foreach ($kind in $script:LightgunLayouts.Keys) {
        $current = if ($kind -eq 'Menu') { [string](Get-JsonProperty $km 'Default') } else {
            $anchor = "$root\$($script:LightgunKindAnchor[$kind])"
            $hit = @($apps | Where-Object { [string]::Equals([string]$_.Search, $anchor, [StringComparison]::OrdinalIgnoreCase) }) | Select-Object -First 1
            if ($hit) { [string]$hit.Keymap } else { '' }
        }
        $keep = $false
        if ($Mode -eq 'Keep' -and $current) {
            $info = Get-LightgunLayoutInfo -KeymapsDir $KeymapsDir -File $current
            $keep = $info.Kind -eq $kind -and $info.Correct
        }
        $chosen[$kind] = if ($keep) { $current } else { $script:LightgunLayouts[$kind].File }
        $kept[$kind] = $keep
    }

    # 2. Kit layout files that are used and missing or different (Keep: a correct kit file the user adjusted stays).
    foreach ($kind in $script:LightgunLayouts.Keys) {
        $file = $script:LightgunLayouts[$kind].File
        if ($chosen[$kind] -ne $file -or $kept[$kind]) { continue }
        $json = ConvertTo-Json -InputObject (New-LightgunLayout -Kind $kind) -Depth 5
        $path = Join-Path $KeymapsDir $file
        $same = (Test-Path -LiteralPath $path -PathType Leaf) -and ([IO.File]::ReadAllText($path) -ceq $json)
        if (-not $same) { $null = $files.Add([pscustomobject]@{ Path = $path; Json = $json }); $null = $changes.Add((Get-KitText 'Lightgun.Layouts.WriteFile' -f $file)) }
    }

    # 3. LayoutChooser: a title for every chosen file (the automation selects layouts by title).
    $titles = @{}
    foreach ($kind in $script:LightgunLayouts.Keys) {
        $file = $chosen[$kind]
        $entry = @($chooser | Where-Object { [string]::Equals([string]$_.Keymap, $file, [StringComparison]::OrdinalIgnoreCase) }) | Select-Object -First 1
        if (-not $entry) {
            $title = if ($file -eq $script:LightgunLayouts[$kind].File) { $script:LightgunLayouts[$kind].Title } else { [IO.Path]::GetFileNameWithoutExtension($file) }
            $entry = [pscustomobject]@{ Title = $title; Keymap = $file }
            $null = $chooser.Add($entry)
            $null = $changes.Add((Get-KitText 'Lightgun.Layouts.AddChooser' -f $title, $file))
        }
        $titles[$kind] = [string]$entry.Title
    }

    # 4. Default and Applications.
    if ([string](Get-JsonProperty $km 'Default') -ne $chosen['Menu']) {
        $null = $changes.Add((Get-KitText 'Lightgun.Layouts.SetDefault' -f ([string](Get-JsonProperty $km 'Default')), $chosen['Menu']))
        $km | Add-Member -NotePropertyName 'Default' -NotePropertyValue $chosen['Menu'] -Force
    }
    foreach ($a in $script:LightgunApplications) {
        $search = "$root\$($a.Path)"
        $want = $chosen[$a.Kind]
        $hit = @($apps | Where-Object { [string]::Equals([string]$_.Search, $search, [StringComparison]::OrdinalIgnoreCase) }) | Select-Object -First 1
        if (-not $hit) {
            $null = $apps.Add([pscustomobject]@{ Keymap = $want; Search = $search })
            $null = $changes.Add((Get-KitText 'Lightgun.Layouts.AddApp' -f $search, $want))
            continue
        }
        if ([string]$hit.Keymap -eq $want) { continue }
        $info = Get-LightgunLayoutInfo -KeymapsDir $KeymapsDir -File ([string]$hit.Keymap)
        if ($Mode -eq 'Keep' -and $info.Kind -eq $a.Kind -and $info.Correct) { continue }
        $null = $changes.Add((Get-KitText 'Lightgun.Layouts.SetApp' -f $search, $hit.Keymap, $want))
        $hit.Keymap = $want
    }
    $km.LayoutChooser = @($chooser)
    $km.Applications = @($apps)
    $count = $changes.Count
    [pscustomobject]@{ KeymapsJson = $keymapsJson; Keymaps = $km; Files = @($files); Changes = @($changes); Titles = $titles; Count = $count; KeymapsChanged = ($count - $files.Count) -gt 0 }
}

# Writes the plan: layout files, then Keymaps.json (backup first). Gunmote and the other guarded programs
# must be closed; checked again right before every file. Returns the number of changes.
function Invoke-LightgunLayoutPlan {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [psobject] $Plan)
    foreach ($c in $Plan.Changes) { Write-KitLog $c }
    if (-not $Plan.Count) { return 0 }
    if (-not $PSCmdlet.ShouldProcess($Plan.KeymapsJson, "$($Plan.Count) change(s)")) { return 0 }
    $utf8 = New-Object Text.UTF8Encoding $false
    foreach ($f in $Plan.Files) {
        Assert-LightgunProcessesClosed
        if (Test-Path -LiteralPath $f.Path) { $null = Backup-LightgunFile -Path $f.Path }
        [IO.File]::WriteAllText($f.Path, $f.Json, $utf8)
    }
    if ($Plan.KeymapsChanged) {
        Assert-LightgunProcessesClosed
        $null = Backup-LightgunFile -Path $Plan.KeymapsJson
        $tmp = "$($Plan.KeymapsJson).tmp"
        [IO.File]::WriteAllText($tmp, (ConvertTo-Json -InputObject $Plan.Keymaps -Depth 10), $utf8)
        [IO.File]::Replace($tmp, $Plan.KeymapsJson, [NullString]::Value)
    }
    $Plan.Count
}

# Layout titles go into task arguments: only plain characters are accepted.
function Test-LightgunLayoutTitle {
    [CmdletBinding()]
    param([AllowEmptyString()] [string] $Title)
    $Title -match '^[\p{L}\p{N} _\-\.:,\(\)\+]{1,64}$'
}
