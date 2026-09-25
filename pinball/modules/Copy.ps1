# Copy (step 4): robocopy vPinball and the detected sibling folders from the source root to the target root.
# Exit codes 0-7 = ok, >= 8 = error. Once paths were relocated, a new full copy would overwrite the rewritten
# files, so it is locked (state value RelocateDone); -Update only copies newer files (/XO) and excludes every
# file name the relocation rewrote. -ListOnly (= -WhatIf of the step) is robocopy /L.

function Get-PinballRobocopyArgument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Source,
        [Parameter(Mandatory)] [string] $Destination,
        [ValidateRange(1, 128)] [int] $Threads = 8,
        [switch] $ListOnly,
        [switch] $Update,
        [string[]] $ExcludeFiles = @(),
        [string] $LogPath
    )
    $a = @($Source, $Destination, '/E', '/COPY:DAT', '/DCOPY:T', '/R:2', '/W:5', "/MT:$Threads", '/XJ',
           '/XD', '@eaDir', '@tmp', 'System Volume Information', '$RECYCLE.BIN', '/NP')
    if ($Update) {
        $a += '/XO'
        if ($ExcludeFiles) { $a += '/XF'; $a += $ExcludeFiles }
    }
    if ($ListOnly) { $a += '/L' }
    if ($LogPath) { $a += "/LOG+:$LogPath" } else { $a += @('/NFL', '/NDL', '/NJH', '/NJS') }
    $a
}

# Bit 0 (1) = files copied or, with /L, files that would be copied; bits >= 8 = failures.
function Get-PinballRobocopyResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [int] $ExitCode)
    [pscustomobject]@{
        ExitCode    = $ExitCode
        Ok          = ($ExitCode -ge 0 -and $ExitCode -lt 8)
        FilesCopied = [bool]($ExitCode -band 1)
    }
}

# File names rewritten by the relocation; an update copy must never overwrite them.
# ponytail: by name, so same-named files elsewhere in the build are skipped too (safe side).
function Get-PinballCopyExclusion {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $StatePath)
    @(Get-KitStateValue -Path $StatePath -Key 'RelocatedFiles') | Where-Object { $_ } |
        ForEach-Object { Split-Path -Leaf $_ } | Sort-Object -Unique
}

function Invoke-PinballRobocopy([string[]] $Arguments) {
    $null = & (Join-Path $env:SystemRoot 'System32\robocopy.exe') @Arguments
    Get-PinballRobocopyResult -ExitCode $LASTEXITCODE
}

function Invoke-PinballCopy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $SourceRoot,
        [Parameter(Mandatory)] [string] $TargetRoot,
        [string[]] $Siblings = @(),
        [string] $StatePath,
        [switch] $ListOnly,
        [switch] $Update,
        [int] $Threads = 8,
        [string] $LogPath
    )
    $exclude = @()
    if ($StatePath -and (Get-KitStateValue -Path $StatePath -Key 'RelocateDone')) {
        if (-not $Update) { throw (Get-KitText 'Pinball.Copy.Locked') }
        $exclude = @(Get-PinballCopyExclusion -StatePath $StatePath)
    }
    if (-not $ListOnly) { Assert-PinballProcessesClosed }
    $src = ConvertTo-PinballRoot $SourceRoot
    $dst = ConvertTo-PinballRoot $TargetRoot
    foreach ($name in @('vPinball') + @($Siblings)) {
        $arguments = Get-PinballRobocopyArgument -Source (Join-PinballPath $src $name) -Destination (Join-PinballPath $dst $name) `
            -Threads $Threads -ListOnly:$ListOnly -Update:$Update -ExcludeFiles $exclude -LogPath $LogPath
        $r = Invoke-PinballRobocopy $arguments
        $r | Add-Member -NotePropertyName Folder -NotePropertyValue $name -PassThru
        if (-not $r.Ok) { Write-KitLog (Get-KitText 'Pinball.Copy.Failed' -f $name, $r.ExitCode) -Level Error }
    }
}

# Verify: robocopy /L finds nothing left to copy (exit code without bit 0 and < 8) and the target holds
# at least as many files and bytes as the source for every folder.
function Test-PinballCopy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $SourceRoot,
        [Parameter(Mandatory)] [string] $TargetRoot,
        [string[]] $Siblings = @(),
        # After relocation: same /XO + /XF rules as the update copy; rewritten files may be smaller.
        [switch] $Update,
        [string[]] $ExcludeFiles = @()
    )
    $src = ConvertTo-PinballRoot $SourceRoot
    $dst = ConvertTo-PinballRoot $TargetRoot
    foreach ($name in @('vPinball') + @($Siblings)) {
        $from = Join-PinballPath $src $name
        $to   = Join-PinballPath $dst $name
        $list = if (Test-Path -LiteralPath $to) {
            Invoke-PinballRobocopy (Get-PinballRobocopyArgument -Source $from -Destination $to -ListOnly -Update:$Update -ExcludeFiles $ExcludeFiles)
        } else { $null }
        $a = Measure-PinballFolder -Path $from
        $b = if (Test-Path -LiteralPath $to) { Measure-PinballFolder -Path $to } else { [pscustomobject]@{ Files = 0; Bytes = 0 } }
        [pscustomobject]@{
            Folder      = $name
            SourceFiles = $a.Files; SourceBytes = $a.Bytes
            TargetFiles = $b.Files; TargetBytes = $b.Bytes
            Complete    = [bool]($list -and $list.Ok -and -not $list.FilesCopied -and $b.Files -ge $a.Files -and ($Update -or $b.Bytes -ge $a.Bytes))
        }
    }
}
