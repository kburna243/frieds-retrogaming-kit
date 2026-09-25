<#
.SYNOPSIS
    Pinball step 4: copy vPinball and the detected sibling folders from the source root to the target root
    with robocopy (exit codes 0-7 ok, >= 8 error) and check file count and size afterwards.
    -WhatIf runs robocopy /L. After step 5 a full copy is locked; -Update copies only newer files and never
    overwrites the files the relocation rewrote.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [switch] $Update,
    [ValidateRange(1, 128)] [int] $Threads = 8,
    [string] $LogPath,
    [string] $StatePath,
    [string] $Culture
)
$ErrorActionPreference = 'Stop'
$kitRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Import-Module (Join-Path $kitRoot 'core\RetroCabinetKit.Core.psd1')
Import-Module (Join-Path $kitRoot 'pinball\RetroCabinetKit.Pinball.psd1')
if ($Culture) { Set-KitCulture -Culture $Culture }
if (-not $StatePath) { $StatePath = Get-PinballDefaultStatePath }

$sourceRoot = Get-KitStateValue -Path $StatePath -Key 'SourceRoot'
$targetRoot = Get-KitStateValue -Path $StatePath -Key 'TargetRoot'
$siblings   = @(Get-KitStateValue -Path $StatePath -Key 'Siblings' | Where-Object { $_ })
$locked     = [bool](Get-KitStateValue -Path $StatePath -Key 'RelocateDone') -and -not $Update
$exclude    = @(if ($Update) { Get-PinballCopyExclusion -StatePath $StatePath })
if (-not ($sourceRoot -and $targetRoot)) { Write-KitLog (Get-KitText 'Pinball.Step.RunTargetFirst') -Level Warn }
# The state file is only a hint: the target must still be a local drive (the source may be a network share).
$rootProblem = if ($targetRoot) { Get-PinballRootProblem -Root $targetRoot -NoDatabase }
if ($rootProblem) { Write-KitLog $rootProblem -Level Warn }
if ($locked) { Write-KitLog (Get-KitText 'Pinball.Copy.Locked') -Level Warn }

if ($WhatIfPreference -and $sourceRoot -and $targetRoot -and -not $locked -and -not $rootProblem) {
    foreach ($r in Invoke-PinballCopy -SourceRoot $sourceRoot -TargetRoot $targetRoot -Siblings $siblings -StatePath $StatePath -Update:$Update -ListOnly) {
        Write-KitLog (Get-KitText 'Pinball.Copy.ListOnly' -f $r.Folder, $r.ExitCode, $r.FilesCopied)
    }
}

$step = New-KitStep -Name 'pinball-4-copy' `
    -Test { [bool]($sourceRoot -and $targetRoot) -and -not $locked -and -not $rootProblem } `
    -Invoke {
        $rows = @(Invoke-PinballCopy -SourceRoot $sourceRoot -TargetRoot $targetRoot -Siblings $siblings -StatePath $StatePath -Update:$Update -Threads $Threads -LogPath $LogPath)
        $bad = @($rows | Where-Object { -not $_.Ok })
        if ($bad) { throw (Get-KitText 'Pinball.Copy.Failed' -f $bad[0].Folder, $bad[0].ExitCode) }
    } `
    -Verify {
        if (-not ($sourceRoot -and $targetRoot) -or $rootProblem) { return $false }
        $rows = @(Test-PinballCopy -SourceRoot $sourceRoot -TargetRoot $targetRoot -Siblings $siblings -Update:$Update -ExcludeFiles $exclude)
        foreach ($r in $rows) { Write-KitLog (Get-KitText 'Pinball.Copy.Check' -f $r.Folder, $r.SourceFiles, $r.TargetFiles, $r.SourceBytes, $r.TargetBytes) }
        -not @($rows | Where-Object { -not $_.Complete }).Count
    }

Invoke-KitStep -Step $step -StatePath $StatePath -WhatIf:$WhatIfPreference
