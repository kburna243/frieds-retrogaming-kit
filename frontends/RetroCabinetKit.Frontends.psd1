@{
    RootModule        = 'RetroCabinetKit.Frontends.psm1'
    ModuleVersion     = '1.3.2'
    GUID              = 'f1a2b3c4-d5e6-7890-abcd-ef1234567890'
    Author            = 'Fried'
    Description       = 'Frontend package of retro-cabinet-kit: detect, install, theme, and configure game frontends for retro gaming cabinets. Covers RetroBat, PinballY, Playnite, LaunchBox, PinUP and more via extensible adapter plugins.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @('*-Frontends*', '*-Frontend*')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData       = @{ PSData = @{ Tags = @('retrobat', 'frontend', 'pinbally', 'playnite', 'launchbox', 'pinup', 'emulationstation') } }
}

