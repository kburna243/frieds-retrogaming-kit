@{
    RootModule        = 'RetroCabinetKit.Displays.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'f2a28165-a849-4f13-8e26-b3427567b1c3'
    Author            = 'Fried'
    Description       = 'Display package of retro-cabinet-kit: monitors, DMD, backglass, topper detection and configuration via EDID and adapter plugins.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('*-Displays*')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{ PSData = @{ Tags = @('retrobat', 'display', 'monitor', 'dmd', 'edid') } }
}

