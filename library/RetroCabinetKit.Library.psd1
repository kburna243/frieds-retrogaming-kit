@{
    # Module manifest for RetroCabinetKit.Library
    
    RootModule = 'RetroCabinetKit.Library.psm1'
    ModuleVersion = '0.8.0'
    
    # Author and company information
    Author = 'Fried'
    CompanyName = 'Dehl und Börner Systems GbR'
    
    # Description of the module's functionality
    Description = 'Library management module for RetroCabinetKit v0.8.0 - Handles ROM cataloging, frontend adapters, and library operations'
    
    # PowerShell version requirements
    PowerShellVersion = '5.1'
    # CompatiblePSEditions = @('Desktop')
    
    # Modules to import
    RequiredModules = @(
        @{ ModuleName = 'RetroCabinetKit.Core'; ModuleVersion = '0.8.0' }
    )
    
    # Functions to export (all *-Library* functions)
    FunctionsToExport = @(
        'Get-LibraryAdapterDir'
        'New-LibraryCatalog'
        'Add-LibrarySystemEntry'
        'Find-LibraryRoms'
        'Get-LibraryChecksum'
        'Get-LibraryAdapterCatalog'
        'Invoke-LibraryAdapterFunction'
        'Get-LibrarySystemSnapshot'
        '*-Library*'
    )
    
    # Variables to export
    VariablesToExport = @(
        'LibraryDir'
    )
    
    # Aliases to export
    AliasesToExport = @()
    
    # Private data
    PrivateData = @{
        PSData = @{
            # Tags applied to this module. Help in module discovery in online galleries.
            Tags = @('RetroCabinetKit', 'Library', 'Gaming', 'ROM Management')
            
            # A URL to the license for this module.
            LicenseUri = 'https://github.com/dehl-boerner/retro-cabinet-kit/blob/main/LICENSE'
            
            # A URL to the main website for this project.
            ProjectUri = 'https://github.com/dehl-boerner/retro-cabinet-kit'
            
            # ReleaseNotes of this module
            ReleaseNotes = @(
                'Version 0.8.0: Initial library management scaffolding'
            )
        }
    }
    
    # HelpInfo URI of this module
    HelpInfoURI = 'https://github.com/dehl-boerner/retro-cabinet-kit/wiki/RetroCabinetKit.Library'
    
    # Default command prefix for exported commands
    DefaultCommandPrefix = 'Library'
}