# Text: detect a file's encoding and replace strings while keeping that exact encoding.
# Detection: BOM (UTF-8, UTF-16LE, UTF-16BE); otherwise strict UTF-8 validation for files with
# non-ASCII bytes; everything else (including pure ASCII) is treated as ANSI, the default of the
# Windows tools whose files the kit edits. Edits refuse to run when the file would not survive a
# decode/encode round trip or when a replacement cannot be represented in the file's encoding.

function Get-KitFileEncoding {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    $bytes = [IO.File]::ReadAllBytes((Resolve-FullPath $Path))
    Get-BytesEncoding $bytes
}

function Get-BytesEncoding([byte[]] $Bytes) {
    $n = $Bytes.Length
    if ($n -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        return [pscustomobject]@{ Name = 'UTF8BOM'; CodePage = 65001; BomLength = 3 }
    }
    if ($n -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) {
        return [pscustomobject]@{ Name = 'UTF16LE'; CodePage = 1200; BomLength = 2 }
    }
    if ($n -ge 2 -and $Bytes[0] -eq 0xFE -and $Bytes[1] -eq 0xFF) {
        return [pscustomobject]@{ Name = 'UTF16BE'; CodePage = 1201; BomLength = 2 }
    }
    $hasHighByte = $false
    foreach ($b in $Bytes) { if ($b -ge 0x80) { $hasHighByte = $true; break } }
    if ($hasHighByte) {
        try {
            $null = (New-Object Text.UTF8Encoding($false, $true)).GetString($Bytes)
            return [pscustomobject]@{ Name = 'UTF8'; CodePage = 65001; BomLength = 0 }
        } catch [Text.DecoderFallbackException] { }
    }
    [pscustomobject]@{ Name = 'ANSI'; CodePage = [Text.Encoding]::Default.CodePage; BomLength = 0 }
}

# Returns the number of replaced occurrences. All keys are matched in ONE pass (longest first),
# so a replacement is never matched again by another key (no double replacement).
function Edit-KitTextFile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory, ParameterSetName = 'Replace')] [System.Collections.IDictionary] $Replace,
        [Parameter(ParameterSetName = 'Replace')] [switch] $CaseInsensitive,
        # { param($Text) ... } returning @{ Text = <new text>; Count = <replacements> } for rules that a
        # literal map cannot express (e.g. path boundaries). Same encoding guarantees as -Replace.
        [Parameter(Mandatory, ParameterSetName = 'Rewrite')] [scriptblock] $Rewrite
    )
    $full  = Resolve-FullPath $Path
    $bytes = [IO.File]::ReadAllBytes($full)
    $info  = Get-BytesEncoding $bytes
    $encoding = [Text.Encoding]::GetEncoding($info.CodePage, [Text.EncoderFallback]::ExceptionFallback, [Text.DecoderFallback]::ReplacementFallback)
    $body = $encoding.GetString($bytes, $info.BomLength, $bytes.Length - $info.BomLength)

    $roundTrip = $encoding.GetBytes($body)
    if ([Convert]::ToBase64String($roundTrip) -ne [Convert]::ToBase64String($bytes, $info.BomLength, $bytes.Length - $info.BomLength)) {
        throw "File does not round-trip in its encoding ($($info.Name)), refusing to edit: $full"
    }

    if ($Rewrite) {
        $rewritten = & $Rewrite $body
        return Write-EditedText $PSCmdlet $full $bytes $info $encoding ([string]$rewritten.Text) ([int]$rewritten.Count)
    }

    $keys = @($Replace.Keys | ForEach-Object { [string]$_ } | Where-Object { $_ } | Sort-Object { $_.Length } -Descending)
    if (-not $keys) { return 0 }
    $options = [Text.RegularExpressions.RegexOptions]::CultureInvariant
    if ($CaseInsensitive) { $options = $options -bor [Text.RegularExpressions.RegexOptions]::IgnoreCase }
    $pattern = ($keys | ForEach-Object { [regex]::Escape($_) }) -join '|'

    $hits = @{ Count = 0 }
    $evaluator = [Text.RegularExpressions.MatchEvaluator] {
        param($match)
        $hits.Count++
        foreach ($k in $keys) {
            $same = if ($CaseInsensitive) { [string]::Equals($k, $match.Value, [StringComparison]::OrdinalIgnoreCase) }
                    else { [string]::Equals($k, $match.Value, [StringComparison]::Ordinal) }
            if ($same) { return [string]$Replace[$k] }
        }
        $match.Value
    }.GetNewClosure()
    $newBody = [regex]::Replace($body, $pattern, $evaluator, $options)
    Write-EditedText $PSCmdlet $full $bytes $info $encoding $newBody $hits.Count
}

function Write-EditedText($cmdlet, [string] $full, [byte[]] $bytes, $info, [Text.Encoding] $encoding, [string] $newBody, [int] $count) {
    if ($count -eq 0) { return 0 }

    $encoded = $encoding.GetBytes($newBody) # throws if a replacement is not representable
    $buffer  = New-Object IO.MemoryStream
    $buffer.Write($bytes, 0, $info.BomLength)
    $buffer.Write($encoded, 0, $encoded.Length)
    $newBytes = $buffer.ToArray()
    if ($cmdlet.ShouldProcess($full, "Replace $count occurrence(s)")) {
        $tmp = "$full.tmp"
        [IO.File]::WriteAllBytes($tmp, $newBytes)
        [IO.File]::Replace($tmp, $full, [NullString]::Value)
        Add-KitStepChange -Kind File -Target $full -Detail "$count replacement(s)"
    }
    $count
}
