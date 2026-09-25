# Steam (step 5, interference): Steam Input grabs every ViGEm pad, and even with Steam Input off Steam keeps
# reading the DolphinBar. Fix: "controller_blacklist" in config\config.vdf (DolphinBar in every mode), written
# only while Steam is closed (Steam writes the file back on exit). The Steam Input Xbox setting in
# userdata\<id>\config\localconfig.vdf is only reported: it is switched off in Steam's own settings.
# Plus the GunmoteVMultiGuard task, which can loop forever and block the DolphinBar: disabled after a
# confirmation, reversible (Enable-ScheduledTask).
#
# VDF (Valve KeyValues) is edited as text: only the one value is replaced or one line inserted, everything
# else (order, comments, tabs, conditionals) stays byte for byte.

$script:LightgunSteamBlacklist = @('0x0079/0x1802', '0x0079/0x1803', '0x057e/0x0306')

function Get-LightgunSteamBlacklistEntry {
    [CmdletBinding()]
    param()
    $script:LightgunSteamBlacklist
}

# Tokens: @{ Type = 'String' | 'Open' | 'Close'; Value; Start; End } (End exclusive). Quoted strings keep
# their escapes in Value decoded (\" \\ \n \t); unquoted words count as strings; // comments and
# [$CONDITION] markers are skipped.
# One regex pass (localconfig.vdf can be megabytes; a character loop in PowerShell would take seconds).
$script:VdfTokenPattern = New-Object regex ('\s+|//[^\n]*|(?<open>\{)|(?<close>\})|\[[^\]\r\n]*\]|"(?<q>(?:[^"\\]|\\.)*)"|(?<bad>")|(?<w>[^\s{}"]+)', 'Compiled')

function Get-VdfToken([string] $Text) {
    foreach ($m in $script:VdfTokenPattern.Matches($Text)) {
        if ($m.Groups['open'].Success) { @{ Type = 'Open'; Start = $m.Index; End = $m.Index + 1 } }
        elseif ($m.Groups['close'].Success) { @{ Type = 'Close'; Start = $m.Index; End = $m.Index + 1 } }
        elseif ($m.Groups['q'].Success) {
            $v = [regex]::Replace($m.Groups['q'].Value, '\\(.)', { param($e) switch -CaseSensitive ($e.Groups[1].Value) { 'n' { "`n" } 't' { "`t" } default { $_ } } })
            @{ Type = 'String'; Value = $v; Start = $m.Index; End = $m.Index + $m.Length }
        }
        elseif ($m.Groups['w'].Success) { @{ Type = 'String'; Value = $m.Value; Start = $m.Index; End = $m.Index + $m.Length } }
        elseif ($m.Groups['bad'].Success) { throw 'VDF: unterminated string' }
    }
}

# Tree of the VDF: every node @{ Key; KeyToken; Value (string) | Children (list) ; ValueToken | Open/Close tokens }.
function ConvertFrom-Vdf([string] $Text) {
    $tokens = @(Get-VdfToken $Text)
    $root = @{ Key = ''; Children = (New-Object Collections.ArrayList); Close = $null }
    $stack = New-Object Collections.Stack
    $stack.Push($root)
    for ($k = 0; $k -lt $tokens.Count; $k++) {
        $t = $tokens[$k]
        if ($t.Type -eq 'Close') {
            if ($stack.Count -le 1) { throw 'VDF: unexpected }' }
            $node = $stack.Pop(); $node.Close = $t; continue
        }
        if ($t.Type -ne 'String') { throw 'VDF: unexpected {' }
        $next = if ($k + 1 -lt $tokens.Count) { $tokens[$k + 1] } else { $null }
        if (-not $next) { throw "VDF: key without value: $($t.Value)" }
        if ($next.Type -eq 'Open') {
            $node = @{ Key = $t.Value; KeyToken = $t; Children = (New-Object Collections.ArrayList); Open = $next; Close = $null }
            $null = $stack.Peek().Children.Add($node); $stack.Push($node); $k++
        } elseif ($next.Type -eq 'String') {
            $null = $stack.Peek().Children.Add(@{ Key = $t.Value; KeyToken = $t; Value = $next.Value; ValueToken = $next }); $k++
        } else { throw "VDF: unexpected } after key $($t.Value)" }
    }
    if ($stack.Count -ne 1) { throw 'VDF: missing }' }
    $root
}

function Find-VdfNode($Node, [string[]] $Path) {
    foreach ($p in $Path) {
        $Node = @($Node.Children | Where-Object { $_.ContainsKey('Children') -and [string]::Equals($_.Key, $p, [StringComparison]::OrdinalIgnoreCase) }) | Select-Object -First 1
        if (-not $Node) { return $null }
    }
    $Node
}

function ConvertTo-VdfQuoted([string] $Value) { '"' + ($Value -replace '\\', '\\' -replace '"', '\"') + '"' }

# Value of Key inside the block Path (e.g. 'InstallConfigStore','Software','Valve','Steam'); $null if missing.
function Get-LightgunVdfValue {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Text, [Parameter(Mandatory)] [string[]] $Path, [Parameter(Mandatory)] [string] $Key)
    $block = Find-VdfNode (ConvertFrom-Vdf $Text) $Path
    if (-not $block) { return $null }
    $hit = @($block.Children | Where-Object { $_.ContainsKey('Value') -and [string]::Equals($_.Key, $Key, [StringComparison]::OrdinalIgnoreCase) }) | Select-Object -First 1
    if ($hit) { $hit.Value }
}

# Returns @{ Text; Count } for Edit-KitTextFile -Rewrite: the value is replaced in place, or a new line
# "<indent>"Key"<tab><tab>"Value"" is inserted before the closing brace of the block (indent and line break
# taken from the file). The block itself must exist.
function Set-LightgunVdfValue {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [AllowEmptyString()] [string] $Text, [Parameter(Mandatory)] [string[]] $Path,
          [Parameter(Mandatory)] [string] $Key, [Parameter(Mandatory)] [AllowEmptyString()] [string] $Value)
    $block = Find-VdfNode (ConvertFrom-Vdf $Text) $Path
    if (-not $block -or -not $block.Close) { throw (Get-KitText 'Lightgun.Steam.NoBlock' -f ($Path -join '\')) }
    $hit = @($block.Children | Where-Object { $_.ContainsKey('Value') -and [string]::Equals($_.Key, $Key, [StringComparison]::OrdinalIgnoreCase) }) | Select-Object -First 1
    if ($hit) {
        if ($hit.Value -ceq $Value) { return @{ Text = $Text; Count = 0 } }
        $t = $hit.ValueToken
        return @{ Text = $Text.Substring(0, $t.Start) + (ConvertTo-VdfQuoted $Value) + $Text.Substring($t.End); Count = 1 }
    }
    $close = $block.Close.Start
    $lineStart = $Text.LastIndexOf("`n", [math]::Max(0, $close - 1)) + 1
    $indent = $Text.Substring($lineStart, $close - $lineStart)
    $nl = if ($Text.Contains("`r`n")) { "`r`n" } else { "`n" }
    if ($indent.Trim()) { # closing brace shares its line with other text: put the pair on a line of its own
        $line = $nl + "`t" + (ConvertTo-VdfQuoted $Key) + "`t`t" + (ConvertTo-VdfQuoted $Value) + $nl
        return @{ Text = $Text.Substring(0, $close) + $line + $Text.Substring($close); Count = 1 }
    }
    $line = $indent + "`t" + (ConvertTo-VdfQuoted $Key) + "`t`t" + (ConvertTo-VdfQuoted $Value) + $nl
    @{ Text = $Text.Substring(0, $lineStart) + $line + $Text.Substring($lineStart); Count = 1 }
}

# 'a,b' + required entries -> entries missing are appended, existing ones (any case) and foreign ones stay.
function Merge-LightgunBlacklist {
    [CmdletBinding()]
    param([AllowEmptyString()] [AllowNull()] [string] $Current, [string[]] $Required = $script:LightgunSteamBlacklist)
    $list = New-Object Collections.Generic.List[string]
    foreach ($e in ([string]$Current).Split(',')) { if ($e.Trim()) { $list.Add($e.Trim()) } }
    foreach ($r in $Required) { if (-not @($list | Where-Object { [string]::Equals($_, $r, [StringComparison]::OrdinalIgnoreCase) }).Count) { $list.Add($r) } }
    $list -join ','
}

function Get-LightgunSteamPath {
    [CmdletBinding()]
    param()
    $p = Get-KitRegistryValue -Path 'HKCU:\Software\Valve\Steam' -Name 'SteamPath'
    if ($p) { ([string]$p).Replace('/', '\') }
}

$script:LightgunSteamConfigPath = @('InstallConfigStore', 'Software', 'Valve', 'Steam')

function Test-LightgunSteamBlacklist {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $ConfigVdf)
    $text = [IO.File]::ReadAllText($ConfigVdf)
    $current = Get-LightgunVdfValue -Text $text -Path $script:LightgunSteamConfigPath -Key 'controller_blacklist'
    [string]$current -ceq (Merge-LightgunBlacklist -Current $current)
}

# Writes the missing blacklist entries (backup first, Steam and the other guarded programs must be closed).
# Returns the number of changed values (0 or 1).
function Set-LightgunSteamBlacklist {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [string] $ConfigVdf)
    $text = [IO.File]::ReadAllText($ConfigVdf)
    $current = Get-LightgunVdfValue -Text $text -Path $script:LightgunSteamConfigPath -Key 'controller_blacklist'
    $wanted = Merge-LightgunBlacklist -Current $current
    if ([string]$current -ceq $wanted) { return 0 }
    Write-KitLog (Get-KitText 'Lightgun.Steam.Blacklist' -f $(if ($null -eq $current) { '-' } else { $current }), $wanted)
    if (-not $PSCmdlet.ShouldProcess($ConfigVdf, "controller_blacklist = $wanted")) { return 0 }
    Assert-LightgunProcessesClosed
    $null = Backup-LightgunFile -Path $ConfigVdf
    $path = $script:LightgunSteamConfigPath
    Edit-KitTextFile -Path $ConfigVdf -Rewrite { param($t) Set-LightgunVdfValue -Text $t -Path $path -Key 'controller_blacklist' -Value $wanted } -Confirm:$false
}

# Steam Input Xbox values of every Steam user (read-only): File, Key, Value for keys containing "xbox".
function Get-LightgunSteamInputReport {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $SteamPath)
    foreach ($f in Get-ChildItem -Path (Join-Path $SteamPath 'userdata\*\config\localconfig.vdf') -ErrorAction SilentlyContinue) {
        try { $tree = ConvertFrom-Vdf ([IO.File]::ReadAllText($f.FullName)) } catch { Write-KitLog "$($f.FullName): $($_.Exception.Message)" -Level Warn; continue }
        $queue = New-Object Collections.Queue
        $queue.Enqueue($tree)
        while ($queue.Count) {
            $node = $queue.Dequeue()
            foreach ($c in $node.Children) {
                if ($c.ContainsKey('Children')) { $queue.Enqueue($c) }
                elseif ($c.Key -match 'xbox') { [pscustomobject]@{ File = $f.FullName; Key = $c.Key; Value = $c.Value } }
            }
        }
    }
}

# GunmoteVMultiGuard ("\EmuMote\Gunmote Vmulti Guard"). Only visible with administrator rights.
function Get-LightgunVMultiGuardTask {
    [CmdletBinding()]
    param([object[]] $Tasks)
    if (-not $PSBoundParameters.ContainsKey('Tasks')) { $Tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue) }
    foreach ($t in $Tasks) {
        if (($t.TaskName -replace '\s', '') -match 'VMultiGuard') {
            [pscustomobject]@{ TaskName = $t.TaskName; TaskPath = $t.TaskPath; Enabled = [string]$t.State -ne 'Disabled' }
        }
    }
}

# Disables the guard task after a confirmation that names the way back.
function Disable-LightgunVMultiGuardTask {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [psobject] $Task, [scriptblock] $Approve)
    $undo = "Enable-ScheduledTask -TaskPath '$($Task.TaskPath)' -TaskName '$($Task.TaskName)'"
    if (-not $PSCmdlet.ShouldProcess("$($Task.TaskPath)$($Task.TaskName)", 'Disable task')) { return }
    $lines = @((Get-KitText 'Lightgun.Guard.Plan' -f "$($Task.TaskPath)$($Task.TaskName)"), (Get-KitText 'Lightgun.Guard.Undo' -f $undo))
    if (-not (Confirm-KitPlan -Lines $lines -Approve $Approve)) { throw (Get-KitText 'Plan.Declined') }
    $null = Disable-ScheduledTask -TaskPath $Task.TaskPath -TaskName $Task.TaskName
    Write-KitLog (Get-KitText 'Lightgun.Guard.Disabled' -f "$($Task.TaskPath)$($Task.TaskName)", $undo)
}
