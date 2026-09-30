@{
    RootModule        = 'RetroCabinetKit.Pads.psm1'
    ModuleVersion     = '0.6.0'
    GUID              = '36d324e0-9d4b-4060-b1dc-76971b7e490f'
    Author            = 'Fried'
    Description       = 'Pads package of retro-cabinet-kit: USB/Bluetooth gamepads (8BitDo, Xbox, PlayStation, Switch Pro) as the third input class, detected by tight VID/PID signatures plus the BTHENUM classic encoding, always behind lightgun and arcade. Writes only retrobat.ini [Controllers] through lightgun''s audited INI writer and never puts a pad on the Steam controller_blacklist.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('*-Pad*')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{ PSData = @{ Tags = @('retrobat', 'gamepad', '8bitdo', 'xbox', 'playstation', 'switch') } }
}
