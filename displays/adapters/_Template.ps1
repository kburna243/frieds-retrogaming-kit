function Test-<Name>Hardware {
    [CmdletBinding()]
    param(
        [string] $RetroBatRoot,
        [hashtable] $Snapshot
    )
    # Return $true if the hardware for this adapter is detected, otherwise $false.
    # Example: check for a process, port, or device signature.
    $false
}

function Get-<Name>AdapterInfo {
    [CmdletBinding()]
    param()
    # Return a hashtable with adapter-specific information.
    # Common keys for display adapters:
    #   AdapterType   - e.g., 'Monitor', 'DMD', 'Backglass', 'Topper'
    #   EdidSignature - a hash of Manufacturer+ProductCode+SerialNumber (or similar unique ID)
    #   DetectPorts   - array of TCP/UDP ports to listen on for detection
    #   ToolDir       - folder name under tools\ where this adapter's settings live
    #   SettingsTargets - array of objects describing where to write settings (see Get-OutputAdapterInfo for structure)
    @{
        AdapterType   = '<Name>'
        EdidSignature = ''
        DetectPorts   = @()
        ToolDir       = '<Name>'
        SettingsTargets = @()
    }
}

function Install-<Name>Software {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string] $RetroBatRoot,
        [string] $PackagePath,
        [bool] $Approved
    )
    # Install the software for this adapter.
    # If $PackagePath is provided, install from that local file or URL.
    # If $Approved is $true, skip interactive confirmation.
    # This function should not perform any configuration; only install.
    Write-KitLog "Installing <Name> software (stub)."
}

function Configure-<Name>Profile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string] $RetroBatRoot,
        [hashtable] $Snapshot
    )
    # Configure the adapter's profile based on the current snapshot.
    # This function should write configuration files but not touch the system otherwise.
    Write-KitLog "Configuring <Name> profile (stub)."
}

function Set-<Name>InterferenceShield {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string] $RetroBatRoot,
        [hashtable] $Snapshot
    )
    # Apply interference shielding (e.g., solenoid protection) if needed for this adapter.
    # For display adapters, this might be backlight timeout or DMD blanking.
    Write-KitLog "Setting interference shield for <Name> (stub)."
}