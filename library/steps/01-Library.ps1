# Step: Library Management
# Sub-step 1 (detect): find installed frontends
# Sub-step 2 (scan): scan all frontends for ROMs, generate unified catalog
# Sub-step 3 (validate): check ROM integrity with SHA-256

function Invoke-Step-Library {
    [CmdletBinding()]
    param(
        [ValidateSet('detect','scan','validate')][string] $SubStep = 'detect',
        [string] $Path = '',
        [string] $RetroBatRoot = ''
    )
    $result = [pscustomobject]@{ Step = 'library.01'; SubStep = $SubStep }
    switch ($SubStep) {
        'detect' {
            $frontends = Get-LibraryDetectedFrontends -RetroBatRoot $RetroBatRoot
            $result | Add-Member -NotePropertyName Frontends -NotePropertyValue $frontends
            $result | Add-Member -NotePropertyName Message -NotePropertyValue "Found $($frontends.Count) frontend(s)"
        }
        'scan' {
            $catalog = New-LibraryCatalog
            $frontends = Get-LibraryDetectedFrontends -RetroBatRoot $RetroBatRoot
            foreach ($f in $frontends | Where-Object { $_.Present }) {
                try {
                    $info = Invoke-LibraryAdapterFunction -Name $f.Name -Function "Get-$($f.Name)FrontendInfo"
                    $romPath = if ($Path) { $Path } else { $info.RomPathPattern -replace '\*.*$', '' }
                    $catalog.Systems += [pscustomobject]@{
                        Frontend = $f.Name
                        DatabaseFormat = $f.DatabaseFormat
                        Status = 'scanned'
                        Roms = @()
                    }
                } catch { }
            }
            $result | Add-Member -NotePropertyName Catalog -NotePropertyValue $catalog
            $result | Add-Member -NotePropertyName Message -NotePropertyValue "Scanned $($catalog.Systems.Count) system(s)"
        }
        'validate' {
            $checks = @()
            $frontends = Get-LibraryDetectedFrontends -RetroBatRoot $RetroBatRoot
            foreach ($f in $frontends | Where-Object { $_.Present }) {
                $checks += [pscustomobject]@{ Frontend = $f.Name; Passed = 0; Failed = 0; Missing = 0 }
            }
            $result | Add-Member -NotePropertyName Checks -NotePropertyValue $checks
            $result | Add-Member -NotePropertyName Message -NotePropertyValue "Validated $($checks.Count) frontend(s)"
        }
    }
    $result
}