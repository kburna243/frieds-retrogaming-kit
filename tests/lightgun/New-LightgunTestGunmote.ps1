<#
.SYNOPSIS
    Builds a synthetic Gunmote folder (Gunmote.exe empty, Keymaps\Keymaps.json like a fresh installation with
    only the mouse layout) and a synthetic Steam folder (config\config.vdf, userdata\1\config\localconfig.vdf).
    Generic values only.
#>
param([Parameter(Mandatory)] [string] $Gunmote, [string] $Steam)
$utf8 = New-Object Text.UTF8Encoding $false
New-Item -ItemType Directory -Path "$Gunmote\Keymaps" -Force | Out-Null
[IO.File]::WriteAllBytes("$Gunmote\Gunmote.exe", [byte[]]@())
$keymaps = @'
{
  "LayoutChooser": [
    {
      "Title": "Default (Mouse)",
      "Keymap": "default.json"
    }
  ],
  "Applications": [],
  "Default": "default.json",
  "Calibration": "Calibration.json"
}
'@
[IO.File]::WriteAllText("$Gunmote\Keymaps\Keymaps.json", $keymaps, $utf8)

if (-not $Steam) { return }
New-Item -ItemType Directory -Path "$Steam\config", "$Steam\userdata\1\config" -Force | Out-Null
$config = @'
"InstallConfigStore"
{
	"Software"
	{
		// a comment the kit keeps
		"Valve"
		{
			"Steam"
			{
				"AutoUpdateWindowEnabled"		"0"
				"controller_blacklist"		"0x1234/0x5678"
			}
		}
	}
	"Music"
	{
		"LocalLibraryRoots"		"C:\\Music \"x\""
	}
}
'@
[IO.File]::WriteAllText("$Steam\config\config.vdf", ($config -replace "`r?`n", "`n"), $utf8)
$local = @'
"UserLocalConfigStore"
{
	"Software"
	{
		"Valve"
		{
			"Steam"
			{
				"SteamController_XBoxSupport"		"1"
			}
		}
	}
}
'@
[IO.File]::WriteAllText("$Steam\userdata\1\config\localconfig.vdf", ($local -replace "`r?`n", "`n"), $utf8)
