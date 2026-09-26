# Doctor checks of the lightgun package (read-only). A missing part is an error only when the lightgun setup
# was started on this machine (install-state.json exists); otherwise it is information.

function Get-LightgunDoctorCheck {
    [CmdletBinding()]
    param([string] $StatePath = (Get-LightgunDefaultStatePath))
    $area = Get-KitText 'Doctor.Area.Lightgun'
    $security = Get-KitText 'Doctor.Area.Security'
    $configured = Test-Path -LiteralPath $StatePath -PathType Leaf
    $root = if ($configured) { [string](Get-KitStateValue -Path $StatePath -Key 'RetroBatRoot') } else { '' }
    $d = @{ Configured = $configured; Root = $root; Missing = $(if ($configured) { 'Error' } else { 'Info' }) }

    Get-KitStateCheck -Area $area -StatePath $StatePath

    New-KitCheck -Area $area -Name (Get-KitText 'Doctor.Lg.RetroBat') -Data $d -Script {
        param($d)
        if (-not $d.Root) { return @{ Level = 'Info'; Detail = (Get-KitText 'Doctor.Lg.NoRoot') } }
        $problem = Get-LightgunRetroBatProblem -Root $d.Root
        if ($problem) { return @{ Level = 'Error'; Detail = $problem } }
        $info = Get-LightgunRetroBatInfo -Root $d.Root
        @{ Level = 'Ok'; Detail = (Get-KitText 'Doctor.Lg.RetroBatOk' -f $d.Root, $(if ($info.Version) { $info.Version } else { '?' })) }
    }

    New-KitCheck -Area $area -Name (Get-KitText 'Doctor.Lg.DolphinBar') -Data $d -Script {
        param($d)
        $bar = Get-LightgunDolphinBarState
        if ($bar.Mode4) { @{ Level = 'Ok'; Detail = (Get-KitText 'Doctor.Lg.DolphinBarOk') } }
        elseif (@($bar.WrongMode).Count) { @{ Level = 'Warn'; Detail = (Get-KitText 'Doctor.Lg.DolphinBarWrong' -f (@($bar.WrongMode) -join ', ')) } }
        else { @{ Level = $(if ($d.Configured) { 'Warn' } else { 'Info' }); Detail = (Get-KitText 'Doctor.Lg.DolphinBarMissing') } }
    }

    New-KitCheck -Area $area -Name (Get-KitText 'Doctor.Lg.Display') -Data $d -Script {
        param($d)
        foreach ($m in Get-LightgunRefreshReport) {
            $level = if ($m.Level -eq 'Warn') { 'Warn' } elseif ($m.Level -eq 'Ok') { 'Ok' } else { 'Info' }
            $key = if ($level -eq 'Warn') { 'Doctor.Lg.DisplayLow' } else { 'Doctor.Lg.DisplayRow' }
            @{ Level = $level; Detail = (Get-KitText $key -f $m.DeviceName, $m.Width, $m.Height, $m.RefreshRate) }
        }
    }

    New-KitCheck -Area $area -Name (Get-KitText 'Doctor.Lg.ViGEm') -Data $d -Script {
        param($d)
        $v = Get-LightgunViGEmState
        if ($v.Installed -and $v.Running) { @{ Level = 'Ok'; Detail = (Get-KitText 'Doctor.Lg.ViGEmOk' -f $v.Version) } }
        elseif ($v.Service) { @{ Level = 'Warn'; Detail = (Get-KitText 'Doctor.Lg.ViGEmStopped') } }
        else { @{ Level = $d.Missing; Detail = (Get-KitText 'Doctor.Lg.ViGEmMissing') } }
    }

    New-KitCheck -Area $area -Name (Get-KitText 'Doctor.Lg.Gunmote') -Data $d -Script {
        param($d)
        $g = Find-LightgunGunmote
        if (-not $g) { return @{ Level = $d.Missing; Detail = (Get-KitText 'Doctor.Lg.GunmoteMissing') } }
        if ($g.InProgramFiles) { @{ Level = 'Ok'; Detail = (Get-KitText 'Doctor.Lg.GunmoteOk' -f $g.Dir, $g.Version) } }
        else { @{ Level = 'Warn'; Detail = (Get-KitText 'Doctor.Lg.GunmoteOutside' -f $g.Dir) } }
        if (Test-LightgunGunmoteTask -Exe $g.Exe) { @{ Name = (Get-KitText 'Doctor.Lg.GunmoteTask'); Level = 'Ok'; Detail = (Get-KitText 'Doctor.Lg.GunmoteTaskOk') } }
        else { @{ Name = (Get-KitText 'Doctor.Lg.GunmoteTask'); Level = 'Info'; Detail = (Get-KitText 'Doctor.Lg.GunmoteTaskMissing') } }
    }

    New-KitCheck -Area $area -Name (Get-KitText 'Doctor.Lg.Steam') -Data $d -Script {
        param($d)
        $steam = Get-LightgunSteamPath
        $config = if ($steam) { Join-Path $steam 'config\config.vdf' } else { '' }
        if (-not $config -or -not (Test-Path -LiteralPath $config -PathType Leaf)) { return @{ Level = 'Info'; Detail = (Get-KitText 'Doctor.Lg.SteamNone') } }
        if (Test-LightgunSteamBlacklist -ConfigVdf $config) { @{ Level = 'Ok'; Detail = (Get-KitText 'Doctor.Lg.SteamOk') } }
        else { @{ Level = $(if ($d.Configured) { 'Warn' } else { 'Info' }); Detail = (Get-KitText 'Doctor.Lg.SteamBad') } }
    }

    # The automation runs with highest rights: a writable folder or a changed watcher is a security finding.
    New-KitCheck -Area $security -Name (Get-KitText 'Doctor.Lg.Automation') -Data $d -Script {
        param($d)
        $dir = Get-LightgunAutomationDir
        if (-not (Test-Path -LiteralPath $dir -PathType Container)) { return @{ Level = 'Info'; Detail = (Get-KitText 'Doctor.Lg.AutomationNone') } }
        if (Test-LightgunAutomationFile -AutomationDir $dir) { @{ Level = 'Ok'; Detail = (Get-KitText 'Doctor.Lg.AutomationOk') } }
        else { @{ Level = 'Error'; Detail = (Get-KitText 'Doctor.Lg.AutomationBad' -f $dir) } }
        if ($d.Root -and -not (Get-LightgunRetroBatProblem -Root $d.Root)) {
            if (Test-LightgunHook -RetroBatRoot $d.Root) { @{ Name = (Get-KitText 'Doctor.Lg.Hooks'); Level = 'Ok'; Detail = (Get-KitText 'Doctor.Lg.HooksOk') } }
            else { @{ Name = (Get-KitText 'Doctor.Lg.Hooks'); Level = 'Warn'; Detail = (Get-KitText 'Doctor.Lg.HooksBad') } }
        }
    }
}
