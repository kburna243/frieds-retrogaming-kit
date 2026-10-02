# Stand-ins for the four pinball functions the API and the kit tools call outside pinball operations, for a kit
# built without pinball\ (a distribution such as hotwm: core + lightgun + output). Dot-sourced only when
# pinball\RetroCabinetKit.Pinball.psd1 is missing; they report nothing, so doctor, backups and restores cover the
# packages that are there. Pinball operations themselves are marked unavailable in the API catalog.
# ponytail: only pinball is optional; make another package optional the same way when a distribution leaves it out.

function Get-PinballDefaultStatePath { '' }
function Get-PinballDoctorCheck { param([string] $StatePath) }
function Get-PinballBackupRoot { param([string] $StatePath) }
function Assert-PinballProcessesClosed { }
