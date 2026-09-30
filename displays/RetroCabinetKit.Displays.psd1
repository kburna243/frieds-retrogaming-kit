@{
    RootModule        = 'RetroCabinetKit.Displays.psm1'
    ModuleVersion     = '0.6.0'
    GUID              = 'a1b2c3d4-e5f6-7890-g1h2-i3j4k5l6m7n8'
    Author            = 'Fried'
    Description       = 'Display package of retro-cabinet-kit: monitors, DMD, backglass, topper detection and configuration via EDID and adapter plugins.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('*-Displays*')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{ PSData = @{ Tags = @('retrobat', 'display', 'monitor', 'dmd', 'edid') } }
}