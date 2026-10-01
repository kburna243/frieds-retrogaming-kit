# Step: Enhancement Settings
# Sub-step 1 (detect): scan all enhancement adapters + GPU info
# Sub-step 2 (recommend): suggest a profile (Performance/Balanced/BestLook) based on GPU VRAM
# Sub-step 3 (configure): apply the selected profile across all adapters

function Invoke-Step-Enhancements {
    [CmdletBinding()]
    param(
        [ValidateSet('detect','recommend','configure')][string] $SubStep = 'detect',
        [ValidateSet('Performance','Balanced','BestLook')][string] $Profile = '',
        [string] $RetroBatRoot = ''
    )
    $result = [pscustomobject]@{ Step = 'enhancements.01'; SubStep = $SubStep }
    switch ($SubStep) {
        'detect' {
            $gpu = Get-EnhancementGpuInfo
            $detected = Get-EnhancementsDetectedAdapters -RetroBatRoot $RetroBatRoot
            $result | Add-Member -NotePropertyName Gpu -NotePropertyValue $gpu
            $result | Add-Member -NotePropertyName Adapters -NotePropertyValue $detected
            $result | Add-Member -NotePropertyName Message -NotePropertyValue "Found $($gpu.Count) GPU(s), $($detected.Count) enhancement adapter(s)"
        }
        'recommend' {
            $gpu = Get-EnhancementGpuInfo
            $vramGB = 2
            if ($gpu.Count) { try { $vramGB = [math]::Round($gpu[0].VRAM_MB/1024, 1) } catch { } }
            $suggested = if ($vramGB -ge 6) { 'BestLook' } elseif ($vramGB -ge 3) { 'Balanced' } else { 'Performance' }
            $profiles = @('Performance','Balanced','BestLook')
            $result | Add-Member -NotePropertyName VramGB -NotePropertyValue $vramGB
            $result | Add-Member -NotePropertyName Suggested -NotePropertyValue $suggested
            $result | Add-Member -NotePropertyName Profiles -NotePropertyValue $profiles
            $result | Add-Member -NotePropertyName Message -NotePropertyValue "GPU VRAM: ${vramGB}GB, suggested: $suggested"
        }
        'configure' {
            if (-not $Profile) { $Profile = 'Balanced' }
            $applied = @{}
            $catalog = Get-EnhancementsAdapterCatalog
            foreach ($adapter in $catalog) {
                try {
                    $r = Invoke-EnhancementsAdapterFunction -Name $adapter.Name -Function "Configure-$($adapter.Name)Profile" -Parameters @{ Profile = $Profile }
                    $applied[$adapter.Name] = $r
                } catch {
                    $applied[$adapter.Name] = @{ Success = $false; Message = $_.Exception.Message }
                }
            }
            $result | Add-Member -NotePropertyName Profile -NotePropertyValue $Profile
            $result | Add-Member -NotePropertyName Applied -NotePropertyValue $applied
            $result | Add-Member -NotePropertyName Message -NotePropertyValue "Profile '$Profile' applied to $($catalog.Count) adapter(s)"
        }
    }
    $result
}