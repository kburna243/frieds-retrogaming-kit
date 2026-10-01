@{
    RootModule        = 'RetroCabinetKit.Output.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = 'e58b1f04-9d27-4c6a-8b35-70f2ad49e1c6'
    Author            = 'Fried'
    Description       = 'Output package of retro-cabinet-kit: haptic middleware (MAMEHooker, qMameHook, Hook of the Reaper) as plugins in output\adapters\, detected by process, port and supported boards; configures mame.ini output=, the middleware settings files and the solenoid protection - never installs services and never kills processes.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('*-Output*')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{ PSData = @{ Tags = @('retrobat', 'output', 'rumble', 'mamehooker', 'solenoid') } }
}


