# Enhancements step: detect, recommend, configure
# This step file is called by the main kit workflow.

# Sub-step 1: Detect GPU and active adapters
Write-KitLog (Get-KitText 'Enhancements.Step.Detecting') -Level Info
$snapshot = Get-EnhancementsSystemSnapshot
$detectionResult = Get-EnhancementsDetectedAdapters -Snapshot $snapshot
if (-not $detectionResult.Success) {
    Write-KitLog (Get-KitText 'Enhancements.Step.NoAdaptersDetected') -Level Warn
} else {
    Write-KitLog (Get-KitText 'Enhancements.Step.DetectedAdapters' -f ($detectionResult.DetectedAdapters -join ', ')) -Level Info
}

# Sub-step 2: Recommend profile based on GPU power
# We'll use a simple heuristic: if GPU VRAM > 4GB, suggest BestLook; else if > 2GB, suggest Balanced; else Performance.
$gpuInfo = $snapshot.GpuInfo
if ($gpuInfo) {
    # Assuming we have at least one GPU, take the first one's VRAM
    $vramMB = $gpuInfo[0].VRAM_MB
    if ($vramMB -gt 4096) {
        $recommendedProfile = 'BestLook'
    } elseif ($vramMB -gt 2048) {
        $recommendedProfile = 'Balanced'
    } else {
        $recommendedProfile = 'Performance'
    }
    Write-KitLog (Get-KitText 'Enhancements.Step.RecommendedProfile' -f $recommendedProfile) -Level Info
} else {
    $recommendedProfile = 'Performance'  # fallback
    Write-KitLog (Get-KitText 'Enhancements.Step.NoGPUInfo') -Level Warn
}

# Sub-step 3: Configure selected profile (for now, we just log; in reality, we would apply the profile to each adapter)
# We'll get the profile details and then for each detected adapter, call Configure-<Name>Profile
$profile = Get-EnhancementProfile -Name $recommendedProfile
Write-KitLog (Get-KitText 'Enhancements.Step.ApplyingProfile' -f $profile.Label) -Level Info

# For each detected adapter, we would call Configure-<Name>Profile with the recommended profile.
# However, note that the adapter's Configure function expects the profile name.
# We'll loop through the detected adapters and call their configure function.
if ($detectionResult.Success) {
    foreach ($adapterName in $detectionResult.DetectedAdapters) {
        try {
            Invoke-EnhancementsAdapterFunction -Name $adapterName -Function "Configure-$($adapterName)Profile" -Parameters @{ RetroBatRoot = $snapshot.Root; Profile = $recommendedProfile; Snapshot = $snapshot }
            Write-KitLog (Get-KitText 'Enhancements.Step.AdapterConfigured' -f $adapterName, $recommendedProfile) -Level Info
        } catch {
            Write-KitLog (Get-KitText 'Enhancements.Step.AdapterConfigurationFailed' -f $adapterName, $_.Exception.Message) -Level Error
        }
    }
}

# Note: We are not actually applying any settings to files in this step file because the Configure function
# in the adapter is expected to do that. We are just calling the adapter's configure function.
# In a real implementation, the adapter's Configure function would write to the appropriate config files.

# We return success if we at least detected adapters and attempted to configure them.
# However, note that the step file doesn't return a value to the caller in the same way as a function.
# Instead, we rely on logging and the NextStep in the detection result.
# For the step file, we can set a variable or just let the logging indicate progress.

# We'll set a variable for the next step to use? Not required by the pattern, but we can.
# The pattern in displays\steps\01-Displays.ps1 doesn't return a value, it just logs and sets the next step in the detection result.
# We'll follow the same pattern: we don't return anything, but we have logged and done the work.

# End of step file