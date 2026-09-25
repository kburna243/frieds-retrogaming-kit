# Register (step 6): COM registration of the build, order and techniques proven on a real cabinet:
#   1. VPinMAME 64/32 (regsvr32)       - VPX needs the controller before a table loads
#   2. B2S Server, FlexDMD 32/64       - RegAsm /codebase; the B2S RegisterApp GUI hangs without a desktop
#   3. PUPDMDControl /regserver
#   4. PuP DllSurrogate                - AppID with an EMPTY DllSurrogate string (reg.exe /d "" swallows it)
#   5. Popper: ForegroundLockTimeout 0, PinUpDOF/PuPServer/PinUpPlayer /regserver, PinUpMenuSetup -setfolders
# Batch files are only ever run as cmd /c "<bat>" < nul in their own folder (no hanging "pause").
# Needs administrator rights; tests only check the plan, they never register anything.

$script:PinballPupSurrogateClsid = '{88919FAC-00B2-4AA8-B1C7-52AD65C476D3}'

# ProgIDs whose server must point into the new root after registration.
$script:PinballComProgIds = @('VPinMAME.Controller', 'B2S.Server', 'FlexDMD.FlexDMD', 'PinUpPlayer.PinUpPlayerX')

function Get-PinballRegisterPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Root,
        [string] $WindowsDir = $env:SystemRoot
    )
    $v      = Join-PinballPath (ConvertTo-PinballRoot $Root) 'vPinball'
    $vpm    = Join-Path $v 'VisualPinball\VPinMAME'
    $tables = Join-Path $v 'VisualPinball\Tables'
    $pup    = Join-Path $v 'PinUPSystem'
    $reg64  = Join-Path $WindowsDir 'System32\regsvr32.exe'
    $reg32  = Join-Path $WindowsDir 'SysWOW64\regsvr32.exe'
    $asm32  = Join-Path $WindowsDir 'Microsoft.NET\Framework\v4.0.30319\RegAsm.exe'
    $asm64  = Join-Path $WindowsDir 'Microsoft.NET\Framework64\v4.0.30319\RegAsm.exe'
    $q = { param($p) '"' + $p + '"' }

    $plan = New-Object Collections.Generic.List[object]
    $add = { param($title, $file, $arguments, $dir, $requires, [bool] $optional = $false)
        $plan.Add([pscustomobject]@{ Title = $title; Kind = 'Process'; FilePath = $file; Arguments = $arguments
                                     WorkingDirectory = $dir; Requires = $requires; Optional = $optional }) }

    & $add 'VPinMAME 64-bit' $reg64 ('/s ' + (& $q "$vpm\VPinMAME64.dll")) $vpm "$vpm\VPinMAME64.dll"
    & $add 'VPinMAME 32-bit' $reg32 ('/s ' + (& $q "$vpm\VPinMAME.dll"))   $vpm "$vpm\VPinMAME.dll"
    foreach ($dll in @(@{ T = 'B2S Server'; P = "$tables\B2SBackglassServer.dll"; O = $false },
                       @{ T = 'FlexDMD';    P = "$vpm\FlexDMD.dll";                O = $false },
                       @{ T = 'FlexUDMD';   P = "$vpm\FlexUDMD.dll";               O = $true })) {
        & $add "$($dll.T) 32-bit" $asm32 ((& $q $dll.P) + ' /codebase /silent') (Split-Path $dll.P) $dll.P $dll.O
        & $add "$($dll.T) 64-bit" $asm64 ((& $q $dll.P) + ' /codebase /silent') (Split-Path $dll.P) $dll.P $dll.O
    }
    & $add 'PUPDMDControl' "$vpm\PUPDMDControl.exe" '/regserver' $vpm "$vpm\PUPDMDControl.exe"

    $clsid = $script:PinballPupSurrogateClsid
    $plan.Add([pscustomobject]@{ Title = 'PuP DllSurrogate'; Kind = 'Registry'; Optional = $false; Requires = $null
        Values = @(
            @{ Path = "Registry::HKEY_CLASSES_ROOT\WOW6432Node\CLSID\$clsid"; Name = 'AppID'; Value = $clsid; Type = 'String' }
            @{ Path = "Registry::HKEY_CLASSES_ROOT\WOW6432Node\AppID\$clsid"; Name = 'DllSurrogate'; Value = ''; Type = 'String' }
        ) })
    $plan.Add([pscustomobject]@{ Title = 'ForegroundLockTimeout 0'; Kind = 'Registry'; Optional = $false; Requires = $null
        Values = @(@{ Path = 'HKCU:\Control Panel\Desktop'; Name = 'ForegroundLockTimeout'; Value = 0; Type = 'DWord' }) })

    foreach ($exe in 'PinUpDOF.exe', 'PuPServer.exe', 'PinUpPlayer.exe') { & $add $exe "$pup\$exe" '/regserver' $pup "$pup\$exe" }
    & $add 'PinUpMenuSetup -setfolders' "$pup\PinUpMenuSetup.exe" '-setfolders' $pup "$pup\PinUpMenuSetup.exe"
    $plan.ToArray()
}

# cmd /c with more than two quotes strips the outer pair: ""<bat>" < nul" -> "<bat>" < nul
function Get-PinballBatCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path)
    [pscustomobject]@{
        FilePath         = Join-Path $env:SystemRoot 'System32\cmd.exe'
        Arguments        = '/c ""' + $Path + '" < nul"'
        WorkingDirectory = Split-Path -Parent $Path
    }
}

function Invoke-PinballProcess([string] $FilePath, [string] $Arguments, [string] $WorkingDirectory) {
    $opt = @{ FilePath = $FilePath; WorkingDirectory = $WorkingDirectory; Wait = $true; PassThru = $true; WindowStyle = 'Hidden' }
    if ($Arguments) { $opt.ArgumentList = $Arguments } # -ArgumentList refuses empty values
    (Start-Process @opt).ExitCode
}

# The build files that get registered or run (DLLs, Popper servers) are shown first as one plan (path,
# SHA256, signature status; the build's files are usually unsigned, so the status is information, the
# confirmation is the gate). Declined -> throws, nothing registered. Only the files of the plan lose their
# download mark, and each one is used only while its hash is still the confirmed one.
function Invoke-PinballRegisterPlan {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Root,
        [Parameter(Mandatory)] [object[]] $Plan,
        [scriptblock] $Approve
    )
    $queued = New-Object Collections.Generic.List[object]
    $rows = @(foreach ($item in $Plan) {
        $row = [pscustomobject]@{ Title = $item.Title; Result = 'Skipped'; ExitCode = $null }
        $row
        if ($item.Requires -and -not (Test-Path -LiteralPath $item.Requires)) {
            $row.Result = if ($item.Optional) { 'NotPresent' } else { 'Missing' }
        } elseif ($PSCmdlet.ShouldProcess($item.Title, 'Register')) {
            $queued.Add([pscustomobject]@{ Row = $row; Item = $item })
        }
    })
    $files = @($queued | ForEach-Object { $_.Item.Requires } | Where-Object { $_ } | Sort-Object -Unique)
    $filePlan = @{}
    if ($files) {
        foreach ($f in $files) { $filePlan[$f] = Get-KitFilePlan -Path $f }
        if (-not (Confirm-KitPlan -FilePlan @($files | ForEach-Object { $filePlan[$_] }) -Approve $Approve)) { throw (Get-KitText 'Plan.Declined') }
        Unblock-File -LiteralPath $files
    }
    foreach ($t in $queued) {
        $item = $t.Item; $row = $t.Row
        Assert-PinballProcessesClosed
        try {
            if ($item.Kind -eq 'Registry') {
                foreach ($val in $item.Values) { Set-KitRegistryValue -Path $val.Path -Name $val.Name -Value $val.Value -Type $val.Type -Confirm:$false }
                $row.Result = 'Ok'
            } else {
                # Held read-only (hash read through the handle) while the process uses it (N5).
                $handle = if ($item.Requires) { Open-KitFilePlanFile -Row $filePlan[$item.Requires] }
                if ($item.Requires -and -not $handle) {
                    $row.Result = 'Failed'; Write-KitLog (Get-KitText 'Plan.Changed' -f $item.Requires) -Level Error
                } else {
                    try { $row.ExitCode = Invoke-PinballProcess $item.FilePath $item.Arguments $item.WorkingDirectory }
                    finally { if ($handle) { $handle.Dispose() } }
                    $row.Result = if ($row.ExitCode -eq 0) { 'Ok' } else { 'Failed' }
                }
            }
        } catch { $row.Result = 'Failed'; Write-KitLog $_.Exception.Message -Level Error }
    }
    $rows
}

# --- folder rights (M1) ---------------------------------------------------------------------------------------

# Authenticated Users, Users, Everyone. Rights that let them change files: write, append, attributes,
# delete, change permissions, take ownership, generic write/all.
$script:PinballBroadSids = @('S-1-5-11', 'S-1-5-32-545', 'S-1-1-0')
$script:PinballWriteMask = [int64][Security.AccessControl.FileSystemRights]'WriteData, AppendData, WriteExtendedAttributes, WriteAttributes, Delete, DeleteSubdirectoriesAndFiles, ChangePermissions, TakeOwnership' -bor 0x10000000 -bor 0x40000000

# Registered COM servers run inside every program that uses them, elevated ones too: a folder that broad
# groups may change is a way to administrator rights. Read-only; one row per risky Allow entry. A FAT/exFAT
# drive has no rights at all (N9): one row for everyone. -FileSystem overrides the detection (tests).
function Get-PinballFolderAclRisk {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path, [string] $FileSystem)
    if (-not $FileSystem) { $FileSystem = try { (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot((Resolve-PinballFullPath $Path)))).DriveFormat } catch { '' } }
    if ($FileSystem -in 'FAT', 'FAT32', 'exFAT') {
        return [pscustomobject]@{ Path = $Path; Sid = 'S-1-1-0'; Name = (Get-KitText 'Pinball.Acl.NoAclName' -f $FileSystem); Rights = 'FullControl'; Inherited = $false }
    }
    $acl = Get-Acl -LiteralPath $Path
    foreach ($rule in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
        $sid = $rule.IdentityReference.Value
        if ($rule.AccessControlType -ne 'Allow' -or $script:PinballBroadSids -notcontains $sid) { continue }
        if (-not ([int64]$rule.FileSystemRights -band $script:PinballWriteMask)) { continue }
        $name = try { $rule.IdentityReference.Translate([Security.Principal.NTAccount]).Value } catch { $sid }
        [pscustomobject]@{ Path = $Path; Sid = $sid; Name = $name; Rights = [string]$rule.FileSystemRights; Inherited = $rule.IsInherited }
    }
}

# icacls arguments for the optional hardening: inheritance off, Administrators and SYSTEM full control, the
# cabinet user modify, Users read/execute; the broad write entries are gone.
# ponytail: the cabinet user keeps write access, Popper, VPX and VPinMAME write into the build at runtime.
function Get-PinballHardeningArgument {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Path, [Parameter(Mandatory)] [string] $UserSid)
    # Local/domain (S-1-5-21) or Entra ID (S-1-12-1) account (N9).
    if ($UserSid -notmatch '^S-1-(5-21|12-1)(-\d+){3,4}$') { throw (Get-KitText 'Pinball.Acl.BadSid' -f $UserSid) }
    @($Path, '/inheritance:r', '/grant:r', '*S-1-5-32-544:(OI)(CI)F', '*S-1-5-18:(OI)(CI)F', "*${UserSid}:(OI)(CI)M", '*S-1-5-32-545:(OI)(CI)RX', '/C', '/Q')
}

# Own command, never part of a step: administrator only, after confirmation. Returns the risks left.
function Protect-PinballBuildFolder {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [string] $Root,
        [Parameter(Mandatory)] [string] $UserSid,
        [scriptblock] $Approve
    )
    if (-not (Test-KitAdmin)) { throw (Get-KitText 'Pinball.Step.NeedsAdmin') }
    $problem = Get-PinballRootProblem -Root $Root
    if ($problem) { throw $problem }
    $v = Join-PinballPath (ConvertTo-PinballRoot $Root) 'vPinball'
    $arguments = Get-PinballHardeningArgument -Path $v -UserSid $UserSid
    if (-not $PSCmdlet.ShouldProcess($v, 'icacls ' + ($arguments -join ' '))) { return }
    if (-not (Confirm-KitPlan -Lines (Get-KitText 'Pinball.Acl.HardenConfirm' -f $v, ($arguments -join ' ')) -Approve $Approve)) { return }
    $ErrorActionPreference = 'Continue' # icacls writes to stderr; judge by exit code only
    $out = & (Join-Path $env:SystemRoot 'System32\icacls.exe') @arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) { throw "icacls failed ($LASTEXITCODE): $($out.Trim())" }
    Write-KitLog (Get-KitText 'Pinball.Acl.Hardened' -f $v)
    Get-PinballFolderAclRisk -Path $v
}

# Server file of a COM class: LocalServer32 or InprocServer32 default value; for .NET classes (mscoree.dll)
# the CodeBase value (file:/// URI). Quotes and arguments are removed.
function Get-PinballComServerPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $ClsidKey
    )
    foreach ($sub in 'LocalServer32', 'InprocServer32') {
        $key = "$ClsidKey\$sub"
        if (-not (Test-Path -LiteralPath $key)) { continue }
        $codeBase = Get-KitRegistryValue -Path $key -Name 'CodeBase'
        if ($codeBase) { return ([Uri]$codeBase).LocalPath }
        $default = [string](Get-KitRegistryValue -Path $key -Name '')
        if ($default -match '^\s*"([^"]+)"') { return $Matches[1] }
        if ($default) { return ($default -replace '\s+/\S+.*$', '').Trim() }
    }
}

# Verify: every ProgID resolves (64- or 32-bit view) to a server below the new root, and the PuP surrogate exists.
function Test-PinballComRegistration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Root,
        [string] $ClassesRoot = 'Registry::HKEY_CLASSES_ROOT',
        [string[]] $ProgIds = $script:PinballComProgIds
    )
    $prefix = (ConvertTo-PinballRoot $Root) + '\'
    foreach ($progId in $ProgIds) {
        $clsid = Get-KitRegistryValue -Path "$ClassesRoot\$progId\CLSID" -Name ''
        $paths = @(if ($clsid) {
            foreach ($view in "$ClassesRoot\CLSID\$clsid", "$ClassesRoot\WOW6432Node\CLSID\$clsid") { Get-PinballComServerPath -ClsidKey $view }
        })
        [pscustomobject]@{
            Name  = $progId
            Paths = $paths
            Ok    = [bool]($paths.Count -and -not @($paths | Where-Object { -not $_.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) }).Count)
        }
    }
    $surrogate = Get-Item -LiteralPath "$ClassesRoot\WOW6432Node\AppID\$($script:PinballPupSurrogateClsid)" -ErrorAction SilentlyContinue
    [pscustomobject]@{
        Name  = 'PuP DllSurrogate'
        Paths = @()
        Ok    = [bool]($surrogate -and ($surrogate.GetValueNames() -contains 'DllSurrogate') -and $surrogate.GetValue('DllSurrogate') -eq '')
    }
}
