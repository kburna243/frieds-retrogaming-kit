# Dependencies (step 3): detect VC++ 2005-2022 x86/x64, .NET 3.5, .NET 4.8, DirectX 9 legacy (d3dx9_43.dll,
# needed by Future Pinball) and the Windows version; install from the build first
# (2-Programs\All In One Runtimes, Installer\directx9), official Microsoft downloads only as fallback
# (allow-listed hosts + Authenticode "Microsoft Corporation"), .NET 3.5 via DISM only after confirmation.
# Silent switches are the ones proven on a real cabinet (see project history).

$script:PinballUninstallKeys = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall'
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
)

# Year, arch, installer file in "All In One Runtimes", silent switches, optional official fallback URL.
$script:PinballVcPackages = @(
    @{ Year = '2005';      Arch = 'x86'; File = 'vcredist2005_x86.exe';                Args = '/q' }
    @{ Year = '2005';      Arch = 'x64'; File = 'vcredist2005_x64.exe';                Args = '/q' }
    @{ Year = '2008';      Arch = 'x86'; File = 'vcredist2008_x86.exe';                Args = '/qb' }
    @{ Year = '2008';      Arch = 'x64'; File = 'vcredist2008_x64.exe';                Args = '/qb' }
    @{ Year = '2010';      Arch = 'x86'; File = 'vcredist2010_x86.exe';                Args = '/passive /norestart' }
    @{ Year = '2010';      Arch = 'x64'; File = 'vcredist2010_x64.exe';                Args = '/passive /norestart' }
    @{ Year = '2012';      Arch = 'x86'; File = 'vcredist2012_x86.exe';                Args = '/passive /norestart' }
    @{ Year = '2012';      Arch = 'x64'; File = 'vcredist2012_x64.exe';                Args = '/passive /norestart' }
    @{ Year = '2013';      Arch = 'x86'; File = 'vcredist2013_x86.exe';                Args = '/passive /norestart'; Url = 'https://aka.ms/highdpimfc2013x86enu' }
    @{ Year = '2013';      Arch = 'x64'; File = 'vcredist2013_x64.exe';                Args = '/passive /norestart'; Url = 'https://aka.ms/highdpimfc2013x64enu' }
    @{ Year = '2015-2022'; Arch = 'x86'; File = 'vcredist2015_2017_2019_2022_x86.exe'; Args = '/passive /norestart'; Url = 'https://aka.ms/vs/17/release/vc_redist.x86.exe' }
    @{ Year = '2015-2022'; Arch = 'x64'; File = 'vcredist2015_2017_2019_2022_x64.exe'; Args = '/passive /norestart'; Url = 'https://aka.ms/vs/17/release/vc_redist.x64.exe' }
)
$script:PinballDirectXUrl = 'https://download.microsoft.com/download/1/7/1/1718CCC4-6315-4D8E-9543-8E28A4E18C4C/dxwebsetup.exe'

# Installed VC++ runtimes from the uninstall keys (both registry views) as Year/Arch pairs.
# The 2005 x86 package has no architecture in its name; its uninstall key lives under WOW6432Node.
function Get-PinballVcRedist {
    [CmdletBinding()]
    param([string[]] $UninstallKeys = $script:PinballUninstallKeys)
    foreach ($root in $UninstallKeys) {
        foreach ($key in Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue) {
            $name = [string]$key.GetValue('DisplayName')
            $m = [regex]::Match($name, 'Visual C\+\+ (\d{4})(?:-\d{4})?\b.*Redistributable')
            if (-not $m.Success) { continue }
            $year = $m.Groups[1].Value
            if ([int]$year -ge 2015) { $year = '2015-2022' }
            $arch = if ($name -match 'x64|amd64') { 'x64' } elseif ($name -match 'x86') { 'x86' }
                    elseif ($root -match 'WOW6432Node') { 'x86' } else { 'x64' }
            [pscustomobject]@{ Year = $year; Arch = $arch; Name = $name }
        }
    }
}

# The v14 runtime key (2015-2022) is the documented detection for the current redistributable.
function Test-PinballVc14Runtime {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [ValidateSet('x86', 'x64')] [string] $Arch)
    $key = if ($Arch -eq 'x64') { 'HKLM:\SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64' }
           else { 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio\14.0\VC\Runtimes\x86' }
    [int](Get-KitRegistryValue -Path $key -Name 'Installed') -eq 1
}

# One row per dependency: Id, Name, Present, Detail. Read-only.
function Get-PinballDependencyStatus {
    [CmdletBinding()]
    param()
    $installed = @(Get-PinballVcRedist)
    foreach ($p in $script:PinballVcPackages) {
        $hit = @($installed | Where-Object { $_.Year -eq $p.Year -and $_.Arch -eq $p.Arch })
        $present = [bool]$hit.Count
        if (-not $present -and $p.Year -eq '2015-2022') { $present = Test-PinballVc14Runtime -Arch $p.Arch }
        [pscustomobject]@{ Id = "VC$($p.Year)-$($p.Arch)"; Name = "Visual C++ $($p.Year) $($p.Arch)"; Present = $present
                           Detail = (@($hit | ForEach-Object { $_.Name }) -join '; ') }
    }

    $ndp = 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP'
    [pscustomobject]@{ Id = 'NetFx35'; Name = '.NET Framework 3.5'; Present = ([int](Get-KitRegistryValue -Path "$ndp\v3.5" -Name 'Install') -eq 1); Detail = '' }
    $release = [int](Get-KitRegistryValue -Path "$ndp\v4\Full" -Name 'Release')
    [pscustomobject]@{ Id = 'NetFx48'; Name = '.NET Framework 4.8'; Present = ($release -ge 528040); Detail = "Release $release" }

    $d3dx = Join-Path $env:SystemRoot 'SysWOW64\d3dx9_43.dll'
    [pscustomobject]@{ Id = 'DirectX9'; Name = 'DirectX 9 (d3dx9_43.dll)'; Present = (Test-Path -LiteralPath $d3dx); Detail = $d3dx }

    $os = [Environment]::OSVersion.Version
    $build = [int](Get-KitRegistryValue -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -Name 'CurrentBuildNumber')
    [pscustomobject]@{ Id = 'Windows'; Name = 'Windows 10/11'; Present = ($os.Major -ge 10 -and $build -ge 10240); Detail = "$($os.Major).$($os.Minor) build $build" }
}

# What would be done for the missing dependencies. Source = Build | Download | Dism | User.
function Get-PinballDependencyPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string] $Root,
        [Parameter(Mandatory)] [object[]] $Status
    )
    $v = Join-PinballPath (ConvertTo-PinballRoot $Root) 'vPinball'
    $aio = Join-Path $v '2-Programs\All In One Runtimes'
    foreach ($s in $Status | Where-Object { -not $_.Present }) {
        $item = [pscustomobject]@{ Id = $s.Id; Name = $s.Name; Source = 'User'; FilePath = $null; Arguments = $null; Url = $null }
        if ($s.Id -like 'VC*') {
            $p = $script:PinballVcPackages | Where-Object { "VC$($_.Year)-$($_.Arch)" -eq $s.Id }
            $local = Join-Path $aio $p.File
            if (Test-Path -LiteralPath $local) { $item.Source = 'Build'; $item.FilePath = $local; $item.Arguments = $p.Args }
            elseif ($p.ContainsKey('Url')) { $item.Source = 'Download'; $item.Url = $p.Url; $item.Arguments = '/install /quiet /norestart' }
        } elseif ($s.Id -eq 'DirectX9') {
            $local = Join-Path $v 'Installer\directx9\DXSETUP.exe'
            if (Test-Path -LiteralPath $local) { $item.Source = 'Build'; $item.FilePath = $local; $item.Arguments = '/silent' }
            else { $item.Source = 'Download'; $item.Url = $script:PinballDirectXUrl; $item.Arguments = '/Q' }
        } elseif ($s.Id -eq 'NetFx35') {
            $item.Source = 'Dism'; $item.FilePath = Join-Path $env:SystemRoot 'System32\dism.exe'
            $item.Arguments = '/Online /Enable-Feature /FeatureName:NetFx3 /All /NoRestart'
        }
        $item
    }
}

# 0 = ok, 1638 = a newer version is already installed, 3010 = ok but a restart is required.
function Get-PinballInstallerResult {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [int] $ExitCode)
    switch ($ExitCode) { 0 { 'Ok' } 1638 { 'Ok' } 3010 { 'RebootRequired' } default { 'Failed' } }
}

# Runs the plan. Downloads go through the core Download module and must carry a valid Microsoft signature.
# Returns one row per item; RebootRequired rows are collected by the caller.
function Invoke-PinballDependencyPlan {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)] [object[]] $Plan,
        [switch] $AllowDism,
        [string] $DownloadDir = (Join-Path $env:TEMP 'retro-cabinet-kit\downloads')
    )
    foreach ($item in $Plan) {
        $row = [pscustomobject]@{ Id = $item.Id; Result = 'Skipped'; ExitCode = $null; Message = '' }
        if ($item.Source -eq 'User' -or ($item.Source -eq 'Dism' -and -not $AllowDism)) {
            $row.Result = 'NeedsUser'; $row.Message = Get-KitText "Pinball.Deps.NeedsUser.$($item.Source)" -f $item.Name
            $row; continue
        }
        if (-not $PSCmdlet.ShouldProcess($item.Name, "Install ($($item.Source))")) { $row; continue }

        $file = $item.FilePath
        if ($item.Source -eq 'Download') {
            if (-not (Test-Path -LiteralPath $DownloadDir)) { New-Item -ItemType Directory -Path $DownloadDir -Force | Out-Null }
            $file = Join-Path $DownloadDir ("{0}.exe" -f $item.Id)
            $null = Save-KitDownload -Uri $item.Url -Destination $file -Confirm:$false
            if (-not (Test-KitSignature -Path $file -ExpectedPublisher 'Microsoft Corporation').IsTrusted) {
                Remove-Item -LiteralPath $file -Force
                $row.Result = 'Failed'; $row.Message = Get-KitText 'Pinball.Deps.BadSignature' -f $item.Url
                $row; continue
            }
        }
        $process = Start-Process -FilePath $file -ArgumentList $item.Arguments -Wait -PassThru -WindowStyle Hidden
        $row.ExitCode = $process.ExitCode
        $row.Result = Get-PinballInstallerResult -ExitCode $process.ExitCode
        $row
    }
}
