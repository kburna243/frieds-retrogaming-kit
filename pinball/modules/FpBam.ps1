# FpBam (step 7): Future Pinball + BAM first-time setup.
#   - AppCompat "disable fullscreen optimizations" (~ DISABLEDXMAXIMIZEDWINDOWEDMODE) for FPLoader.exe and
#     Future Pinball.exe below the NEW root (HKCU ...\AppCompatFlags\Layers, value NAME = program path).
#     Existing flags of the value are kept. Entries of the old root are only reported (outdated).
#   - "BAM settings - Cabinet - Reset and Install.bat" via cmd /c "<bat>" < nul.
#   - "Start FPLoader.exe once as administrator" cannot be automated: it stays NeedsUser until confirmed.

$script:PinballLayersKey = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\AppCompatFlags\Layers'
$script:PinballFsoFlag = 'DISABLEDXMAXIMIZEDWINDOWEDMODE'
$script:PinballBamBatName = 'BAM settings - Cabinet - Reset and Install.bat'

function Get-PinballFpExecutable {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Root)
    $fp = Join-PinballPath (ConvertTo-PinballRoot $Root) 'vPinball\FuturePinball'
    "$fp\BAM\FPLoader.exe"
    "$fp\Future Pinball.exe"
}

# '~ RUNASADMIN' + flag -> '~ RUNASADMIN DISABLEDXMAXIMIZEDWINDOWEDMODE'; already present -> unchanged.
function Add-PinballLayerFlag {
    [CmdletBinding()]
    param(
        [AllowEmptyString()] [AllowNull()] [string] $Data,
        [Parameter(Mandatory)] [string] $Flag
    )
    $tokens = @(([string]$Data).Split(' ', [StringSplitOptions]::RemoveEmptyEntries) | Where-Object { $_ -ne '~' })
    if (-not ($tokens | Where-Object { $_ -eq $Flag })) { $tokens += $Flag }
    '~ ' + ($tokens -join ' ')
}

function Test-PinballFullscreenOptimizationOff {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string[]] $Executable,
        [string] $LayersKey = $script:PinballLayersKey
    )
    foreach ($exe in $Executable) {
        if ((-split (Get-KitRegistryValue -Path $LayersKey -Name $exe)) -notcontains $script:PinballFsoFlag) { return $false }
    }
    $true
}

function Set-PinballFullscreenOptimizationOff {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string[]] $Executable,
        [string] $LayersKey = $script:PinballLayersKey
    )
    foreach ($exe in $Executable) {
        $old = [string](Get-KitRegistryValue -Path $LayersKey -Name $exe)
        $new = Add-PinballLayerFlag -Data $old -Flag $script:PinballFsoFlag
        if ($new -eq $old) { continue }
        if ($PSCmdlet.ShouldProcess("$LayersKey\$exe", "Set '$new'")) {
            Assert-PinballProcessesClosed
            Set-KitRegistryValue -Path $LayersKey -Name $exe -Value $new -Confirm:$false
        }
        [pscustomobject]@{ Name = $exe; Old = $old; New = $new }
    }
}

function Find-PinballBamBat {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Root)
    $fp = Join-PinballPath (ConvertTo-PinballRoot $Root) 'vPinball\FuturePinball'
    Get-KitFileTree -Path $fp -Filter $script:PinballBamBatName -SkipReparseFiles | Select-Object -First 1 -ExpandProperty FullName
}

function Find-PinballInstallGuide {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Root)
    $fp = Join-PinballPath (ConvertTo-PinballRoot $Root) 'vPinball\FuturePinball'
    Get-KitFileTree -Path $fp -Filter '*.pdf' |
        Where-Object { $_.Name -match 'install' -and $_.Name -match 'guide' } |
        Select-Object -First 1 -ExpandProperty FullName
}

# A batch file of the build (BAM setup, Popper autostart) runs only after its plan (path, SHA256, signature
# status; -Lines on top, -ShowLines: its first lines) was confirmed, and only while it is held read-only with
# the confirmed hash (N5). Declined -> throws.
function Invoke-PinballBat {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [string[]] $Lines = @(),
        [int] $ShowLines = 0,
        [scriptblock] $Approve
    )
    $cmd = Get-PinballBatCommand -Path $Path
    if (-not $PSCmdlet.ShouldProcess($Path, 'cmd /c "<bat>" < nul')) { return }
    $plan = Get-KitFilePlan -Path $Path
    if ($ShowLines -gt 0) {
        $bytes = [IO.File]::ReadAllBytes($Path)
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))) -replace '-', '' } finally { $sha.Dispose() }
        if ($hash -ne $plan.Sha256) { throw (Get-KitText 'Plan.Changed' -f $Path) } # the shown text is the planned file
        $content = @([Text.Encoding]::Default.GetString($bytes).TrimEnd("`r", "`n") -split '\r?\n')
        $Lines += Get-KitText 'Pinball.Bat.Content' -f $Path, ([math]::Min($ShowLines, $content.Count)), $content.Count
        $Lines += @($content | Select-Object -First $ShowLines | ForEach-Object { '    ' + ($_ -replace '[\x00-\x08\x0B-\x1F\x7F]', '?') })
    }
    if (-not (Confirm-KitPlan -Lines $Lines -FilePlan @($plan) -Approve $Approve)) { throw (Get-KitText 'Plan.Declined') }
    Assert-PinballProcessesClosed
    $handle = Open-KitFilePlanFile -Row $plan
    if (-not $handle) { throw (Get-KitText 'Plan.Changed' -f $Path) }
    try { Invoke-PinballProcess $cmd.FilePath $cmd.Arguments $cmd.WorkingDirectory } finally { $handle.Dispose() }
}
