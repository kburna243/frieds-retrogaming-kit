@{
    RootModule        = 'RetroCabinetKit.Library.psm1'
    ModuleVersion     = '1.3.0'
    GUID              = '995ce767-9ac3-4c05-b0c8-65030ac21c84'
    Author            = 'retro-cabinet-kit contributors'
    Description       = 'Library management module for retro-cabinet-kit: Handles ROM cataloging, frontend adapters, and library operations.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('*-Library*')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{ PSData = @{ Tags = @('retrobat', 'library', 'roms', 'catalog') } }
}

