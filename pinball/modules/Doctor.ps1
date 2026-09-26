# Doctor checks of the pinball package (read-only). A missing part is an error only when the pinball setup
# was started on this machine (install-state.json exists); otherwise it is information.

function Get-PinballDoctorCheck {
    [CmdletBinding()]
    param([string] $StatePath = (Get-PinballDefaultStatePath))
    $area = Get-KitText 'Doctor.Area.Pinball'
    $security = Get-KitText 'Doctor.Area.Security'
    $configured = Test-Path -LiteralPath $StatePath -PathType Leaf
    $root = ''
    $comDone = $false
    if ($configured) {
        $state = Read-KitState -Path $StatePath
        foreach ($key in 'TargetRoot', 'SourceRoot') {
            $p = $state.Values.PSObject.Properties[$key]
            if ($p -and $p.Value) { $root = [string]$p.Value; break }
        }
        $s = $state.Steps.PSObject.Properties['pinball-6-register']
        $comDone = [bool]($s -and $s.Value.Status -in 'Done', 'Skipped')
    }
    $d = @{ StatePath = $StatePath; Configured = $configured; Root = $root; ComDone = $comDone }

    Get-KitStateCheck -Area $area -StatePath $StatePath

    New-KitCheck -Area $area -Name (Get-KitText 'Doctor.Pb.Build') -Data $d -Script {
        param($d)
        if (-not $d.Root) { return @{ Level = 'Info'; Detail = (Get-KitText 'Doctor.Pb.NoRoot') } }
        $problem = Get-PinballRootProblem -Root $d.Root
        if ($problem) { @{ Level = 'Error'; Detail = $problem } } else { @{ Level = 'Ok'; Detail = $d.Root } }
    }

    New-KitCheck -Area $area -Name (Get-KitText 'Doctor.Pb.Deps') -Data $d -Script {
        param($d)
        $rows = @(Get-PinballDependencyStatus)
        $missing = @($rows | Where-Object { -not $_.Present } | ForEach-Object { $_.Name })
        if (-not $missing.Count) { return @{ Level = 'Ok'; Detail = (Get-KitText 'Doctor.Pb.DepsOk' -f $rows.Count) } }
        $level = if ($d.Configured) { 'Warn' } else { 'Info' }
        @{ Level = $level; Detail = (Get-KitText 'Doctor.Pb.DepsMissing' -f ($missing -join ', ')) }
    }

    New-KitCheck -Area $area -Name (Get-KitText 'Doctor.Pb.Com') -Data $d -Script {
        param($d)
        if (-not $d.Root -or (Get-PinballRootProblem -Root $d.Root)) { return @{ Level = 'Info'; Detail = (Get-KitText 'Doctor.Pb.ComNotYet') } }
        $bad = @(Test-PinballComRegistration -Root $d.Root | Where-Object { -not $_.Ok } | ForEach-Object { $_.Name })
        if (-not $bad.Count) { return @{ Level = 'Ok'; Detail = (Get-KitText 'Doctor.Pb.ComOk' -f $d.Root) } }
        if (-not $d.ComDone) { return @{ Level = 'Info'; Detail = (Get-KitText 'Doctor.Pb.ComNotYet') } }
        @{ Level = 'Error'; Detail = (Get-KitText 'Doctor.Pb.ComBad' -f ($bad -join ', ')) }
    }

    New-KitCheck -Area $security -Name (Get-KitText 'Doctor.Pb.Acl') -Data $d -Script {
        param($d)
        if (-not $d.Root -or (Get-PinballRootProblem -Root $d.Root)) { return }
        $risks = @(Get-PinballFolderAclRisk -Path $d.Root)
        if (-not $risks.Count) { return @{ Level = 'Ok'; Detail = (Get-KitText 'Doctor.Pb.AclOk' -f $d.Root) } }
        @{ Level = 'Warn'; Detail = (Get-KitText 'Doctor.Pb.AclRisk' -f (@($risks | ForEach-Object { $_.Name } | Select-Object -Unique) -join ', ')) }
    }
}
