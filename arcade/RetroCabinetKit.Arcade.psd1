@{
    RootModule        = 'RetroCabinetKit.Arcade.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '7c2f60d3-5b41-4f8a-9d26-3a1e88bf4c57'
    Author            = 'Fried'
    Description       = 'Arcade package of retro-cabinet-kit: USB fightsticks, arcade encoders and steering wheels as plugins in arcade\adapters\, detected by VID/PID and configured through lightgun''s proven INI writers (mame.ini, retrobat.ini [Controllers], Supermodel.ini, EMULATOR.INI, Steam controller_blacklist).'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('*-Arcade*')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{ PSData = @{ Tags = @('retrobat', 'arcade', 'fightstick', 'wheel', 'mame') } }
}


