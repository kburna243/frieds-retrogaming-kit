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
    Get-ChildItem -LiteralPath $fp -Recurse -File -Filter $script:PinballBamBatName -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}

function Find-PinballInstallGuide {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Root)
    $fp = Join-PinballPath (ConvertTo-PinballRoot $Root) 'vPinball\FuturePinball'
    Get-ChildItem -LiteralPath $fp -Recurse -File -Filter '*.pdf' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'install' -and $_.Name -match 'guide' } |
        Select-Object -First 1 -ExpandProperty FullName
}

function Invoke-PinballBat {
    [CmdletBinding(SupportsShouldProcess)]
    param([Parameter(Mandatory)] [string] $Path)
    $cmd = Get-PinballBatCommand -Path $Path
    if (-not $PSCmdlet.ShouldProcess($Path, 'cmd /c "<bat>" < nul')) { return }
    Assert-PinballProcessesClosed
    Invoke-PinballProcess $cmd.FilePath $cmd.Arguments $cmd.WorkingDirectory
}
